module Analysis.Struct exposing (..)

import Analysis.DefinitionPropagator as DefinitionPropagator
import Analysis.Util exposing (AnalysisError(..), AnalysisRes, analyze_typename, ar_foldN, ar_map2)
import Json.Decode exposing (field)
import Language.Language as Language exposing (Identifier(..), SimpleNamed, StructDefinition, TypeDefinition(..), TypeName(..))
import Language.Syntax as Syntax exposing (Node, node_get, node_location)
import ListDict exposing (ListDict)
import ListSet exposing (..)
import Parser.AST as AST


get_unfinished_struct : Node Identifier -> List AST.UnqualifiedTypeWithName -> AnalysisRes DefinitionPropagator.Unfinished
get_unfinished_struct s ast_fields =
    let
        name =
            node_get s |> CustomTypeName |> DefinitionPropagator.TypeDeclaration

        good_fields : AnalysisRes (List (SimpleNamed TypeName))
        good_fields =
            ast_fields |> List.map ensure_good_struct_field |> ar_foldN (::) []

        types_needed : List (SimpleNamed TypeName) -> ListDict DefinitionPropagator.DeclarationName (Maybe DefinitionPropagator.Definition)
        types_needed fs =
            List.foldl (\nt -> ListSet.insert (DefinitionPropagator.TypeDeclaration nt.value)) ListSet.empty fs
                |> ListSet.to_list
                |> List.map (\n -> ( n, Nothing ))
                |> ListDict.from_list

        finalize : List (SimpleNamed TypeName) -> List ( DefinitionPropagator.DeclarationName, DefinitionPropagator.Definition ) -> Result DefinitionPropagator.Error DefinitionPropagator.Definition
        finalize field_decls ts =
            let
                get_add : SimpleNamed TypeName -> List (SimpleNamed Language.TypeDefinition) -> List (SimpleNamed Language.TypeDefinition)
                get_add f l =
                    l
            in
            List.foldl (Result.map << get_add) (Ok []) field_decls
                |> Result.map (DefinitionPropagator.TypeDef << Language.StructDefinitionType << Language.StructDefinition)
        finalize_res = good_fields |> Result.map finalize

        -- add_field fnn ruf =
        -- ruf |> Result.andThen (\uf -> ensure_good_struct_field fnn |> Result.map  (\nt -> nt.))
    in
    good_fields
        |> Result.map types_needed
        |> Result.map2 (\fin needs -> DefinitionPropagator.Unfinished (Node name s.loc) needs fin) finalize_res


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
