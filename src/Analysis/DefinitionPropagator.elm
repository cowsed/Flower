module Analysis.DefinitionPropagator exposing (DefinitionPropagator, DeclarationName(..), Dependence(..), Definition(..), Output(..), Unfinished, Error(..), to_full_scope, empty_definition_propogator, from_definitions_and_declarations)

import Analysis.Scope as Scope
import Language.Language as Language exposing (TypeName(..))
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
    { complete : ListDict DeclarationName Definition
    , incomplete : List Unfinished
    }


to_full_scope : DefinitionPropagator -> Result Error Scope.FullScope
to_full_scope dp =
    if List.length dp.incomplete > 0 then
        Err StillHaveIncompleteTypes

    else
        dp.complete
            |> ListDict.to_list
            |> List.map
                (\( k, v ) ->
                    case v of
                        TypeDef t ->
                            case k of
                                TypeDeclaration tn ->
                                    case tn of
                                        CustomTypeName s ->
                                            Language.Named s t

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


from_definitions_and_declarations : List ( DeclarationName, Definition ) -> List Unfinished -> Result Error DefinitionPropagator
from_definitions_and_declarations defs decls =
    List.foldl (\dd res -> res |> Result.andThen (add_definition dd)) (Ok empty_definition_propogator) defs
        |> (\dp ->
                List.foldl (\dd res -> res |> Result.andThen (add_incomplete_internal dd)) dp decls
           )


remove_incomplete : Unfinished -> DefinitionPropagator -> DefinitionPropagator
remove_incomplete uf dp =
    { dp | incomplete = List.filter (\ic -> ic /= uf) dp.incomplete }


add_incomplete_internal : Unfinished -> DefinitionPropagator -> Result Error DefinitionPropagator
add_incomplete_internal uf dp =
    if List.any (\ic -> ic.name == uf.name) dp.incomplete then
        Err DuplicateDeclaration

    else
        Ok { dp | incomplete = List.append dp.incomplete [ uf ] }





type Output
    = Complete Definition
    | Incomplete Unfinished


type alias Unfinished =
    { name : DeclarationName
    , needs : ListSet DeclarationName
    , add_data : ( DeclarationName, Definition ) -> Output
    }


add_definition : ( DeclarationName, Definition ) -> DefinitionPropagator -> Result Error DefinitionPropagator
add_definition ( decl, def ) old_dp =
    let
        try_add : Unfinished -> Result Error DefinitionPropagator -> Result Error DefinitionPropagator
        try_add uf res_dp =
            case res_dp of
                Err e ->
                    Err e |> Debug.log "add def err"

                Ok dp -> 
                    if ListSet.member decl uf.needs then
                        -- this definition needed the newly added definition
                        case uf.add_data ( decl, def ) of
                            Complete new_def ->
                                remove_incomplete uf dp |> add_definition ( uf.name, new_def ) |> Debug.log "added"

                            Incomplete still_incomplete ->
                                dp |> remove_incomplete uf |> add_incomplete_internal still_incomplete |> Debug.log "still incomplete"

                    else
                        dp |> Ok |> Debug.log "no change"

        -- dont need to do anything
    in
    List.foldl try_add
        (Ok
            { old_dp | complete = ListDict.insert decl def old_dp.complete }
        )
        old_dp.incomplete
        |> Debug.log "add definition call"



-- (dp.incompletes
-- |> List.map
-- (\incomplete ->
-- if List.member decl incomplete.needs then
-- (decl, def) |> incomplete.add_data
--
-- else
-- Incomplete incomplete
-- )
-- )
--
-- |> (\is -> { dp | incompletes = is })
-- |> Ok


type Error
    = DuplicateDeclaration
    | DuplicateDefinition
    | StillHaveIncompleteTypes
