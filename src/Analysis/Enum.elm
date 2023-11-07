module Analysis.Enum exposing (get_unfinished)

import Analysis.DefinitionPropagator as DefinitionPropagator
import Analysis.Util exposing (AnalysisRes, analyze_typename, ar_foldN)
import Language.Language as Language exposing (Identifier, SimpleNamed, TypeName(..))
import Language.Syntax exposing (Node, node_map)
import ListDict exposing (ListDict)
import ListSet exposing (ListSet)
import Parser.AST as AST


finalize : List Language.EnumTagDefinition -> List ( DefinitionPropagator.DeclarationName, DefinitionPropagator.Definition ) -> Result DefinitionPropagator.Error DefinitionPropagator.Definition
finalize =
    \l1 l2 -> Debug.todo "im"


get_unfinished : Node Identifier -> List AST.EnumField -> AnalysisRes DefinitionPropagator.Unfinished
get_unfinished nid ed =
    let
        -- needed_types : ListSet DefinitionPropagator.DeclarationName
        needed_types : AnalysisRes (ListSet a)
        needed_types =
            Ok ListSet.empty

        finalize_res =
            Ok (finalize [])

        decl_name : Node DefinitionPropagator.DeclarationName
        decl_name =
            nid
                |> node_map (\id -> CustomTypeName id |> DefinitionPropagator.TypeDeclaration)


    in
    Result.map2
        (DefinitionPropagator.Unfinished decl_name)
        (needed_types |> Result.map ListSet.to_list |> Result.map (List.map (\n -> ( n, Nothing ))) |> Result.map ListDict.from_list)
        finalize_res


ensure_good_enum_field : AST.EnumField -> AnalysisRes (SimpleNamed (List Language.TypeName))
ensure_good_enum_field field =
    let
        typename_reses : List (AnalysisRes Language.TypeName)
        typename_reses =
            field.args |> List.map analyze_typename

        folder : Language.TypeName -> List Language.TypeName -> List Language.TypeName
        folder mtn ml =
            List.append ml [ mtn ]
    in
    typename_reses
        |> ar_foldN folder []
        |> (\t -> t)
        |> Result.map (SimpleNamed field.name)
