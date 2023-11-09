module Analysis.DefinitionPropagator exposing (DeclarationName(..), Definition(..), DefinitionPropagator, Error(..), Unfinished, empty_definition_propogator, from_definitions_and_declarations, to_full_scope)

import Analysis.Scope as Scope
import Language.Language as Language exposing (TypeName(..))
import Language.Syntax as Syntax exposing (Node, node_get, node_location)
import List.Extra
import ListDict exposing (ListDict)
import ListSet exposing (ListSet)
import Time exposing (Month(..))


type DeclarationName
    = TypeDeclaration TypeName


type Definition
    = TypeDef Language.TypeDefinition


type alias DefinitionPropagator =
    { complete : ListDict (Node DeclarationName) Definition
    , incomplete : List Unfinished
    , weak_needs : ListSet DeclarationName
    }


type alias Unfinished =
    { name : Syntax.Node DeclarationName
    , needs : ListDict DeclarationName (Maybe Definition)
    , weak : ListSet DeclarationName
    , finalize : List ( DeclarationName, Definition ) -> Result Error Definition
    }


type alias RecursiveDef =
    List DeclarationName


type Error
    = DuplicateDefinition { first : Syntax.SourceView, second : Syntax.SourceView }
    | StillHaveIncompletes (List ( DeclarationName, List DeclarationName ))
    | WeakNeedsUnfulfilled (List DeclarationName)
    | TypePromisedButNotFound TypeName
    | DefinitionPromisedButNotFound DeclarationName
    | RecursiveDefinition (List DeclarationName)
    | MultipleErrs (List Error)


from_definitions_and_declarations : List ( Syntax.Node DeclarationName, Definition ) -> List Unfinished -> Result Error DefinitionPropagator
from_definitions_and_declarations defs decls =
    add_definitions defs empty_definition_propogator
        |> Result.andThen (catch_duplicates_of_external decls)
        |> Result.andThen
            (\dp ->
                catch_duplicates_and_circular decls
                    |> Result.andThen (\good_decls -> add_incompletes good_decls dp)
            )
        |> Result.andThen insure_weak_needs_completed


extract_typedef : ( Node TypeName, Language.TypeDefinition ) -> Node (Language.Named Language.TypeDefinition)
extract_typedef ( tn, td ) =
    case node_get tn of
        CustomTypeName s ->
            Language.Named s td
                |> (\td2 -> Syntax.Node td2 (node_location tn))

        _ ->
            Debug.todo "Something, im not reallu sure"


to_full_scope : DefinitionPropagator -> Result Error Scope.FullScope
to_full_scope dp =
    let
        initial_state =
            { values = [], types = [] }

        update ( k, v ) state =
            case node_get k of
                TypeDeclaration tn ->
                    case v of
                        TypeDef td ->
                            { state | types = List.append state.types [ ( Node tn (node_location k), td ) ] }

        separated =
            dp.complete |> ListDict.to_list |> List.foldl update initial_state
    in
    Scope.FullScope
        (separated.types |> List.map extract_typedef)
        []
        []
        |> Ok


empty_definition_propogator : DefinitionPropagator
empty_definition_propogator =
    { complete = ListDict.empty
    , incomplete = []
    , weak_needs = ListSet.empty
    }


add_definitions : List ( Node DeclarationName, Definition ) -> DefinitionPropagator -> Result Error DefinitionPropagator
add_definitions defs dp =
    List.foldl (\dd res -> res |> Result.andThen (add_definition_simple dd)) (Ok dp) defs


catch_duplicates_of_external : List Unfinished -> DefinitionPropagator -> Result Error DefinitionPropagator
catch_duplicates_of_external ufs dp =
    let
        dupes : List { first : Node DeclarationName, second : Node DeclarationName }
        dupes =
            List.foldl
                (\uf l ->
                    case definition_of dp (node_get uf.name) of
                        Just first ->
                            List.append l [ { first = first, second = uf.name } ]

                        Nothing ->
                            l
                )
                []
                ufs
    in
    if List.length dupes > 0 then
        Err
            (dupes
                |> List.map (\dd -> { first = node_location dd.first, second = node_location dd.second })
                |> List.map DuplicateDefinition
                |> MultipleErrs
            )

    else
        Ok dp


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

        find_duplicates_this_module : List Unfinished -> Result Error (List Unfinished)
        find_duplicates_this_module luf =
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
                    ListDict.from_list (luf |> List.map stuff_from_unfinished)
            in
            List.map
                (\uf ->
                    check_recursive (stuff_from_unfinished uf) d ListSet.empty
                )
                luf
                |> collapse_recursive_errs ufs
    in
    ufs
        |> find_duplicates_this_module
        |> Result.andThen find_recursives


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
    let
        folder : Maybe a -> Maybe (List a) -> Maybe (List a)
        folder mstuff mstate =
            case mstuff of
                Just stuff ->
                    case mstate of
                        Just state ->
                            List.append state [ stuff ] |> Just

                        Nothing ->
                            Just [ stuff ]

                Nothing ->
                    mstate
    in
    List.foldl
        folder
        (Just [])


check_recursive : ( DeclarationName, List DeclarationName ) -> ListDict DeclarationName (List DeclarationName) -> ListSet DeclarationName -> Maybe RecursiveDef
check_recursive ( me, my_dependents ) others off_the_table =
    let
        new_off_the_table =
            ListSet.insert me off_the_table

        im_problematic : Maybe RecursiveDef
        im_problematic =
            List.Extra.find (\dn -> ListSet.member dn new_off_the_table) my_dependents
                |> Maybe.map (\problem -> [ me, problem ])

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
        Just rdef ->
            Just rdef

        Nothing ->
            children_problematic my_dependents |> Maybe.map (\l -> List.append [ me ] l)


insure_weak_needs_completed : DefinitionPropagator -> Result Error DefinitionPropagator
insure_weak_needs_completed dp =
    let
        completed_set =
            ListDict.keys dp.complete |> List.map node_get |> ListSet.from_list

        unfinished_err =
            if List.length dp.incomplete == 0 then
                Nothing

            else
                Just
                    (StillHaveIncompletes
                        (dp.incomplete
                            |> List.map
                                (\inc ->
                                    ( node_get inc.name
                                    , inc.needs
                                        |> ListDict.to_list
                                        |> List.filter
                                            (\( _, mdef ) -> not (maybe_is_just mdef))
                                        |> List.map Tuple.first
                                    )
                                )
                        )
                    )

        has_incomplete dn =
            List.any (\inc -> (inc.name |> node_get) == dn) dp.incomplete

        unfulfilled_err =
            ListSet.filter (\wn -> not (ListSet.member wn completed_set)) dp.weak_needs
                |> ListSet.filter (not << has_incomplete)
                |> (\unfs ->
                        if ListSet.size unfs > 0 then
                            Just (WeakNeedsUnfulfilled (ListSet.to_list unfs))

                        else
                            Nothing
                   )

        errs =
            [] |> maybe_append unfinished_err |> maybe_append unfulfilled_err
    in
    if List.length errs > 0 then
        errs |> MultipleErrs |> Err

    else
        Ok dp


add_def_to_uf : ( DeclarationName, Definition ) -> Unfinished -> Unfinished
add_def_to_uf ( dname, def ) u =
    if ListDict.has_key dname u.needs then
        { u | needs = ListDict.insert dname (Just def) u.needs }

    else
        u


try_to_complete_incomplete : Unfinished -> List ( DeclarationName, Definition ) -> ( Bool, Unfinished )
try_to_complete_incomplete uf defs =
    List.foldl add_def_to_uf uf defs
        |> (\uf2 -> ( all_needs_met uf2, uf2 ))


add_definition_apply : ( Node DeclarationName, Definition ) -> DefinitionPropagator -> Result Error DefinitionPropagator
add_definition_apply ( dname, ddef ) dp =
    let
        make_just_definitions : List ( a, Maybe b ) -> List ( a, b )
        make_just_definitions =
            List.foldl
                (\( next_name, next_def ) l ->
                    next_def
                        |> Maybe.map (\def_def -> List.append l [ ( next_name, def_def ) ])
                        |> Maybe.withDefault l
                )
                []

        dp_with =
            { dp | complete = ListDict.insert dname ddef dp.complete }

        maybe_finished =
            dp.incomplete |> List.map (add_def_to_uf ( node_get dname, ddef )) |> List.map (\uf2 -> ( all_needs_met uf2, uf2 ))

        still_unfinished =
            maybe_finished |> List.filter (\( complete, _ ) -> not complete) |> List.map Tuple.second

        dp_with_unfinished =
            { dp_with | incomplete = still_unfinished }

        newly_finished =
            maybe_finished
                |> List.filter (\( complete, _ ) -> complete)
                |> List.map Tuple.second
                |> List.map (\uf -> uf.finalize (make_just_definitions (uf.needs |> ListDict.to_list)) |> Result.map (\def -> ( uf.name, def )))

        foldf : Result Error ( Node DeclarationName, Definition ) -> Result Error DefinitionPropagator -> Result Error DefinitionPropagator
        foldf resdef rdp =
            Result.map2 (\a b -> ( a, b )) resdef rdp |> Result.andThen (\( def, dp2 ) -> add_definition_apply def dp2)
    in
    List.foldl foldf (Ok dp_with_unfinished) newly_finished
        |> Result.map
            (\dp2 ->
                { dp2 | weak_needs = ListSet.remove (node_get dname) dp2.weak_needs }
            )


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


definition_of : DefinitionPropagator -> DeclarationName -> Maybe (Node DeclarationName)
definition_of dp dn =
    List.Extra.find (\el -> node_get el == dn) (dp.complete |> ListDict.keys)


add_incomplete : DefinitionPropagator -> Unfinished -> Result Error DefinitionPropagator
add_incomplete dp uf =
    let
        ( finished, nuf ) =
            try_to_complete_incomplete uf (ListDict.to_list dp.complete |> List.map (\( nk, v ) -> ( node_get nk, v )))

        make_just_definitions : List ( a, Maybe b ) -> List ( a, b )
        make_just_definitions =
            List.foldl
                (\( next_name, next_def ) l ->
                    next_def
                        |> Maybe.map (\def_def -> List.append l [ ( next_name, def_def ) ])
                        |> Maybe.withDefault l
                )
                []

        still_unfinished_weak_needs =
            uf.weak |> ListSet.filter (not << maybe_is_just << definition_of dp)
    in
    if finished then
        ListDict.to_list nuf.needs
            |> make_just_definitions
            |> nuf.finalize
            |> Result.andThen
                (\newdef ->
                    add_definition_apply ( uf.name, newdef )
                        { dp | weak_needs = ListSet.merge still_unfinished_weak_needs dp.weak_needs }
                )

    else
        Ok
            { dp
                | incomplete = List.append dp.incomplete [ nuf ]
                , weak_needs = ListSet.merge still_unfinished_weak_needs dp.weak_needs
            }


add_incompletes : List Unfinished -> DefinitionPropagator -> Result Error DefinitionPropagator
add_incompletes incos dp =
    incos
        |> List.foldl
            (\dd res -> res |> Result.andThen (\a -> add_incomplete a dd))
            (Ok dp)


add_definition_simple : ( Syntax.Node DeclarationName, Definition ) -> DefinitionPropagator -> Result Error DefinitionPropagator
add_definition_simple ( decl, def ) old_dp =
    Ok
        { old_dp | complete = ListDict.insert decl def old_dp.complete }


maybe_append : Maybe a -> List a -> List a
maybe_append m l =
    case m of
        Just el ->
            List.append l [ el ]

        Nothing ->
            l


maybe_is_just : Maybe a -> Bool
maybe_is_just m =
    case m of
        Just _ ->
            True

        _ ->
            False


this_or_err : a -> Maybe err -> Result err a
this_or_err this maybe_err =
    case maybe_err of
        Just err ->
            Err err

        Nothing ->
            Ok this
