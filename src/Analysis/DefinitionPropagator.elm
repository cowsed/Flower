module Analysis.DefinitionPropagator exposing (DeclarationName(..), Definition(..), DefinitionPropagator, Dependence(..), Error(..), Unfinished, empty_definition_propogator, from_definitions_and_declarations, to_full_scope)

import Analysis.Scope as Scope
import Language.Language as Language exposing (TypeName(..))
import Language.Syntax as Syntax exposing (Node, node_get, node_location, node_map)
import List.Extra
import ListDict exposing (ListDict)
import ListSet exposing (ListSet)


type DeclarationName
    = TypeDeclaration TypeName


type Dependence
    = Weak DeclarationName
    | Strong DeclarationName


type Definition
    = TypeDef Language.TypeDefinition


type alias DefinitionPropagator =
    { complete : ListDict (Node DeclarationName) Definition
    , incomplete : List Unfinished
    }


type alias Unfinished =
    { name : Syntax.Node DeclarationName
    , needs : ListDict DeclarationName (Maybe Definition)
    , finalize : List ( DeclarationName, Definition ) -> Result Error Definition
    }


type Error
    = DuplicateDefinition { first : Syntax.SourceView, second : Syntax.SourceView }
    | StillHaveIncompletes (List ( DeclarationName, List DeclarationName ))
    | TypePromisedButNotFound TypeName
    | RecursiveDefinition (List DeclarationName)
    | MultipleErrs (List Error)


to_full_scope : DefinitionPropagator -> Result Error Scope.FullScope
to_full_scope dp =
    if List.length dp.incomplete > 0 then
        Err
            (StillHaveIncompletes
                (dp.incomplete
                    |> List.map (\inc -> ( node_get inc.name, inc.needs |> ListSet.to_list |> List.map Tuple.first ))
                 --                    |> List.map node_get
                )
            )

    else
        dp.complete
            |> ListDict.to_list
            |> List.map
                (\( k, v ) ->
                    case v of
                        TypeDef t ->
                            case node_get k of
                                TypeDeclaration tn ->
                                    case tn of
                                        CustomTypeName s ->
                                            Language.Named s t |> (\td -> Syntax.Node td (node_location k))

                                        _ ->
                                            Debug.todo "Something, im not reallu sure"
                )
            |> (\ts -> Scope.FullScope ts [] [])
            |> Ok


empty_definition_propogator : DefinitionPropagator
empty_definition_propogator =
    { complete = ListDict.empty
    , incomplete = []
    }


add_definitions : List ( Node DeclarationName, Definition ) -> DefinitionPropagator -> Result Error DefinitionPropagator
add_definitions defs dp =
    List.foldl (\dd res -> res |> Result.andThen (add_definition_simple dd)) (Ok dp) defs


catch_duplicates_and_circular : List Unfinished -> Result Error (List Unfinished)
catch_duplicates_and_circular ufs =
    let
        try_add : Unfinished -> ListDict DeclarationName Unfinished -> Result Error (ListDict DeclarationName Unfinished)
        try_add uf set =
            case ListDict.get uf.name.thing set of
                Nothing ->
                    ListDict.insert uf.name.thing uf set |> Ok

                Just other ->
                    DuplicateDefinition { first = node_location other.name, second = node_location uf.name } |> Err

        find_duplicates : List Unfinished -> Result Error (List Unfinished)
        find_duplicates luf =
            List.foldl
                (\uf resset ->
                    resset
                        |> Result.andThen (try_add uf)
                )
                (Ok ListDict.empty)
                luf
                |> Result.map ListDict.values

        find_recursives : List Unfinished -> Result Error (List Unfinished)
        find_recursives luf =
            let
                d : ListDict DeclarationName (List DeclarationName)
                d =
                    ListDict.from_list (luf |> List.map (\uf -> ( node_get uf.name, ListDict.keys uf.needs )))
            in
            List.map (\uf -> check_recursive (stuff_from_unfinished uf) d ListSet.empty |> Maybe.map ((::) (uf.name |> node_get))) luf
                |> (\t -> t)
                |> collapse_recursive_errs ufs
    in
    ufs |> find_duplicates |> Result.andThen find_recursives


type alias RecursiveDef =
    List DeclarationName


collapse_recursive_errs : List Unfinished -> List (Maybe RecursiveDef) -> Result Error (List Unfinished)
collapse_recursive_errs if_good ls =
    let
        f : Maybe RecursiveDef -> List RecursiveDef -> List RecursiveDef
        f m state =
            case m of
                Just err ->
                    List.append state [ err ]

                Nothing ->
                    state
    in
    List.foldl f [] ls
        |> (\l ->
                if List.length l > 0 then
                    l |> List.map RecursiveDefinition |> MultipleErrs |> Just

                else
                    Nothing
           )
        |> this_or_err if_good


stuff_from_unfinished : Unfinished -> ( DeclarationName, List DeclarationName )
stuff_from_unfinished uf =
    ( node_get uf.name, ListDict.keys uf.needs )


list_of_maybes_to_maybe_of_list : List (Maybe a) -> Maybe (List a)
list_of_maybes_to_maybe_of_list =
    List.foldl (\mstuff mstate -> Maybe.map2 (\m l -> List.append l [ m ]) mstuff mstate) (Just [])


check_recursive : ( DeclarationName, List DeclarationName ) -> ListDict DeclarationName (List DeclarationName) -> ListSet DeclarationName -> Maybe RecursiveDef
check_recursive ( me, my_dependents ) others off_the_table =
    let
        new_off_the_table =
            ListSet.insert me off_the_table

        im_problematic : Maybe RecursiveDef
        im_problematic =
            List.Extra.find (\dn -> ListSet.member dn new_off_the_table) my_dependents |> Maybe.map List.singleton |> Maybe.map (Debug.log "Me being problematic")

        children_problematic : List DeclarationName -> Maybe RecursiveDef
        children_problematic deps =
            deps
                |> List.map (\m -> ListDict.get m others |> Maybe.map (\def -> ( m, def )))
                |> list_of_maybes_to_maybe_of_list
                |> Maybe.map (List.map (\m -> check_recursive m others (new_off_the_table |> ListSet.insert (m |> Tuple.first))))
                |> Maybe.andThen list_of_maybes_to_maybe_of_list
                |> Maybe.andThen List.head
    in
    case im_problematic of
        Just err ->
            Just err

        Nothing ->
            children_problematic my_dependents |> Maybe.map (\l -> List.append l [ me ])


this_or_err : a -> Maybe err -> Result err a
this_or_err this maybe_err =
    case maybe_err of
        Just err ->
            Err err

        Nothing ->
            Ok this


from_definitions_and_declarations : List ( Syntax.Node DeclarationName, Definition ) -> List Unfinished -> Result Error DefinitionPropagator
from_definitions_and_declarations defs decls =
    add_definitions defs empty_definition_propogator
        |> Result.andThen (\dp -> catch_duplicates_and_circular decls |> Result.andThen (\good_decls -> add_incompletes good_decls dp))


try_to_complete_incomplete : Unfinished -> List ( DeclarationName, Definition ) -> ( Bool, Unfinished )
try_to_complete_incomplete uf defs =
    let
        add_def_to_uf : ( DeclarationName, Definition ) -> Unfinished -> Unfinished
        add_def_to_uf ( dname, def ) u =
            if ListDict.has_key dname u.needs then
                { uf | needs = ListDict.insert (Debug.log "adding dname" dname) (Just def) u.needs }

            else
                u |> Debug.log ("not adding" ++ Debug.toString dname ++ " to u")
    in
    List.foldl add_def_to_uf uf defs
        |> (\uf2 -> ( all_needs_met uf2, uf2 )) |> Debug.log "Ufs"


all_needs_met : Unfinished -> Bool
all_needs_met uf =
    List.foldl
        (\md b ->
            case md of
                Nothing ->
                    False

                Just _ ->
                    b
        )
        True
        (ListDict.values uf.needs)


add_incomplete_ : Unfinished -> DefinitionPropagator -> Result Error DefinitionPropagator
add_incomplete_ uf dp =
    let
        ( finished, nuf ) =
            try_to_complete_incomplete uf (ListDict.to_list dp.complete |> List.map (\( nk, v ) -> ( node_get nk, v )))
    in
    if finished then
        ListDict.to_list nuf.needs
            |> List.foldl
                (\( next_name, next_def ) l ->
                    next_def
                        |> Maybe.map (\def_def -> List.append l [ ( next_name, def_def ) ])
                        |> Maybe.withDefault l
                )
                []
            |> nuf.finalize
            |> Result.map (\newdef -> { dp | complete = ListDict.insert uf.name newdef dp.complete })

    else
        Ok { dp | incomplete = List.append dp.incomplete [ nuf ] }


add_incompletes : List Unfinished -> DefinitionPropagator -> Result Error DefinitionPropagator
add_incompletes incos dp =
    incos |> List.foldl (\dd res -> res |> Result.andThen (add_incomplete_ dd)) (Ok dp)


add_definition_simple : ( Syntax.Node DeclarationName, Definition ) -> DefinitionPropagator -> Result Error DefinitionPropagator
add_definition_simple ( decl, def ) old_dp =
    Ok
        { old_dp | complete = ListDict.insert decl def old_dp.complete }
