module Analysis.Struct exposing (..)

import Analysis.DefinitionPropagator as DefinitionPropagator
import Analysis.Util exposing (AnalysisError(..), AnalysisRes, analyze_typename, ar_foldN, ar_map2)
import Json.Decode exposing (field)
import Language.Language as Language exposing (Identifier(..), SimpleNamed, TypeDefinition(..), TypeName(..))
import Language.Syntax exposing (Node, node_get)
import List.Extra
import ListDict exposing (ListDict)
import ListSet exposing (..)
import Parser.AST as AST


finalize : List (SimpleNamed TypeName) -> List ( DefinitionPropagator.DeclarationName, DefinitionPropagator.Definition ) -> Result DefinitionPropagator.Error DefinitionPropagator.Definition
finalize field_decls ts =
    let
        get_typename : TypeName -> Maybe TypeName
        get_typename tn =
            List.Extra.find
                (\( decl, _ ) ->
                    case decl of
                        DefinitionPropagator.TypeDeclaration tn2 ->
                            tn == tn2
                )
                ts
                |> Maybe.andThen
                    (\( dname, _ ) ->
                        case dname of
                            DefinitionPropagator.TypeDeclaration tn2 ->
                                Just tn2
                     -- _ ->
                     -- Nothing
                    )

        get_add : SimpleNamed TypeName -> List (SimpleNamed Language.TypeName) -> Result DefinitionPropagator.Error (List (SimpleNamed Language.TypeName))
        get_add field l =
            get_typename field.value
                |> Maybe.map (\tdef -> List.append l [ SimpleNamed field.name tdef ])
                |> Result.fromMaybe (DefinitionPropagator.TypePromisedButNotFound field.value)
    in
    List.foldl (Result.andThen << get_add) (Ok []) field_decls
        |> Result.map (DefinitionPropagator.TypeDef << Language.StructDefinitionType << Language.StructDefinition)


is_type_weak_need : TypeName -> Bool
is_type_weak_need tn =
    case tn of
        ReferenceType _ ->
            True

        _ ->
            False


maybe_finish_weak_type: TypeName -> Maybe  DefinitionPropagator.Definition
maybe_finish_weak_type tn = 
    case tn of 
        ReferenceType refto -> Just (DefinitionPropagator.TypeDef (Language.ReferenceDefinitionType refto))
        _ -> Nothing

get_unfinished_struct : Node Identifier -> List AST.UnqualifiedTypeWithName -> AnalysisRes DefinitionPropagator.Unfinished
get_unfinished_struct s ast_fields =
    let
        name =
            node_get s |> CustomTypeName |> DefinitionPropagator.TypeDeclaration

        good_fields : AnalysisRes (List (SimpleNamed TypeName))
        good_fields =
            ast_fields |> List.map ensure_good_struct_field |> ar_foldN (::) []

        all_types fs =
            List.foldl (\nt l -> List.append l [ nt.value ]) [] fs |> List.Extra.unique

        types_needed : List (SimpleNamed TypeName) -> ListDict DefinitionPropagator.DeclarationName (Maybe DefinitionPropagator.Definition)
        types_needed fs =
            all_types fs
                |> List.map (\n -> ( n, maybe_finish_weak_type n ))
                |> List.map (\(tn, mdef) -> (DefinitionPropagator.TypeDeclaration tn, mdef))
                |> ListDict.from_list

        finalize_res : AnalysisRes (List ( DefinitionPropagator.DeclarationName, DefinitionPropagator.Definition ) -> Result DefinitionPropagator.Error DefinitionPropagator.Definition)
        finalize_res =
            good_fields |> Result.map (\ts -> \fs -> finalize ts fs)

        remove_reference: TypeName -> TypeName
        remove_reference tn = 
            case tn of 
                ReferenceType refto -> refto
                _ -> tn
        weak_needs =
            good_fields
                |> Result.map
                    (\fs ->
                        all_types fs
                            |> List.filter is_type_weak_need
                            |> List.map remove_reference
                            |> List.map DefinitionPropagator.TypeDeclaration
                            |> ListSet.from_list
                    )
    in
    good_fields
        |> Result.map types_needed
        |> Result.map3 (\wns fin needs -> DefinitionPropagator.Unfinished (Node name s.loc) needs wns fin) weak_needs finalize_res


ensure_good_struct_field : AST.UnqualifiedTypeWithName -> AnalysisRes (SimpleNamed Language.TypeName)
ensure_good_struct_field field =
    let
        name_res =
            case field.name.thing of
                SingleIdentifier s ->
                    Ok s

                _ ->
                    Err (StructFieldNameTooComplicated field.name.loc)

        typename_res =
            analyze_typename field.typename
    in
    ar_map2 (\name tname -> SimpleNamed name tname) name_res typename_res
