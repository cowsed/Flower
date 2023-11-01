module Analysis.DefinitionPropagator exposing (DeclarationName(..), Definition(..), DefinitionPropagator, Dependence(..), Error(..), Output(..), Unfinished, empty_definition_propogator, from_definitions_and_declarations, to_full_scope)

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


to_full_scope : DefinitionPropagator -> Result Error Scope.FullScope
to_full_scope dp =
    if List.length dp.incomplete > 0 then
        Err
            (StillHaveIncompleteTypes
                (dp.incomplete
                    |> List.map .name
                    |> List.map node_get
                    |> List.map
                        (\decl ->
                            case decl of
                                TypeDeclaration tn ->
                                    tn
                        )
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
    List.foldl (\dd res -> res |> Result.andThen (add_definition dd)) (Ok dp) defs


add_incompletes : List Unfinished -> DefinitionPropagator -> Result Error DefinitionPropagator
add_incompletes incos dp =
    incos  |> List.foldl (\dd res -> res |> Result.andThen (add_incomplete_internal dd)) (Ok dp)


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
    in
    find_duplicates ufs 


from_definitions_and_declarations : List ( Syntax.Node DeclarationName, Definition ) -> List Unfinished -> Result Error DefinitionPropagator
from_definitions_and_declarations defs decls =
    add_definitions defs empty_definition_propogator
        |> Result.andThen (\dp -> catch_duplicates_and_circular decls |> Result.andThen (\good_decls -> add_incompletes good_decls dp))


remove_incomplete : Unfinished -> DefinitionPropagator -> DefinitionPropagator
remove_incomplete uf dp =
    { dp | incomplete = List.filter (\ic -> ic /= uf) dp.incomplete }


add_incomplete_internal : Unfinished -> DefinitionPropagator -> Result Error DefinitionPropagator
add_incomplete_internal uf dp =
    Ok { dp | incomplete = List.append dp.incomplete [ uf ] }



type Output
    = Complete Definition
    | Incomplete Unfinished


type alias Unfinished =
    { name : Syntax.Node DeclarationName
    , needs : ListSet DeclarationName
    , add_data : ( DeclarationName, Definition ) -> Output
    }


add_definition : ( Syntax.Node DeclarationName, Definition ) -> DefinitionPropagator -> Result Error DefinitionPropagator
add_definition ( decl, def ) old_dp =
    let
        try_add : Unfinished -> Result Error DefinitionPropagator -> Result Error DefinitionPropagator
        try_add uf res_dp =
            case res_dp of
                Err e ->
                    Err e

                Ok dp ->
                    if ListSet.member (Syntax.node_get decl) uf.needs then
                        -- this definition needed the newly added definition
                        case uf.add_data ( Syntax.node_get decl, def ) of
                            Complete new_def ->
                                remove_incomplete uf dp |> add_definition ( uf.name, new_def )

                            Incomplete still_incomplete ->
                                dp |> remove_incomplete uf |> add_incomplete_internal still_incomplete

                    else
                        dp |> Ok

        -- dont need to do anything
    in
    List.foldl try_add
        (Ok
            { old_dp | complete = ListDict.insert decl def old_dp.complete }
        )
        old_dp.incomplete


type Error
    = DuplicateDefinition { first : Syntax.SourceView, second : Syntax.SourceView }
    | StillHaveIncompleteTypes (List TypeName)
