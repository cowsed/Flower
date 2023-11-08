module Analysis.Analyzer exposing (..)

import Analysis.BuiltinScopes as BuiltinScopes
import Analysis.DefinitionPropagator as DefinitionPropagator
import Analysis.Scope as Scope
import Analysis.Struct as Struct
import Analysis.Util exposing (..)
import Keyboard.Key exposing (Key(..))
import Language.Language as Language exposing (Identifier(..), IntegerSize(..), Named, TypeDefinition(..), TypeName(..), named_get, named_name)
import Language.Syntax  exposing (Node, node_get, node_map)
import Parser.AST as AST
import Parser.ParserCommon exposing (Error(..))
import Analysis.Enum as Enum


type alias GoodProgram =
    { ast : AST.Program
    , module_name : String
    , global_scope : Scope.FullScope
    , definitions : List FunctionDefinition
    }


type TypedExpression
    = FunctionCall Identifier FunctionDefinition (List TypedExpression) (Maybe TypeName)
    | ScopeLookup Identifier TypeName
    | Instantiation



-- | StructConstruction


type Statement
    = Assignment (Named TypeName) TypedExpression
    | BareExpression TypedExpression


type alias FunctionDefinition =
    { typ : Language.FunctionHeader
    , statements : List Statement
    }


analyze : AST.Program -> Result AnalysisError GoodProgram
analyze ast =
    let
        outer_scopes : Result AnalysisError Scope.FullScope
        outer_scopes =
            make_outer_type_scope ast

        definitions =
            Ok []

        module_name =
            Result.fromMaybe NoModuleName ast.module_name
    in
    Result.map3 (GoodProgram ast) module_name outer_scopes definitions


ensure_good_generic_args : List (Node AST.FullName) -> AnalysisRes (List String)
ensure_good_generic_args _ =
    Debug.todo " ensure good generic args"


ensure_good_custom_type_name : Node AST.FullName -> AnalysisRes TypeDeclarationName
ensure_good_custom_type_name fn =
    case fn.thing of
        AST.NameWithoutArgs id ->
            case id of
                SingleIdentifier _ ->
                    Ok (Plain id)

                QualifiedIdentifiers _ ->
                    Err (TypeNameTooComplicated fn.loc)

        AST.NameWithArgs id ->
            case id.base of
                SingleIdentifier _ ->
                    ensure_good_generic_args id.args |> Result.map (\l -> Generic id.base l)

                QualifiedIdentifiers _ ->
                    Err (TypeNameTooComplicated fn.loc)

        _ ->
            Err (TypeNameTooComplicated fn.loc)


get_unfinished_struct_or_generic : AST.StructDefnition -> AnalysisRes DefinitionPropagator.Unfinished
get_unfinished_struct_or_generic sdt =
    let
        good_name =
            ensure_good_custom_type_name sdt.name
    in
    good_name
        |> Result.andThen
            (\n ->
                case n of
                    Plain s ->
                        Struct.get_unfinished_struct (Node s sdt.name.loc) sdt.fields

                    Generic _ _ ->
                        Debug.todo "Get Unfinished Generic Struct"
            )


get_unfinished_enum_or_generic : AST.EnumDefinition -> AnalysisRes DefinitionPropagator.Unfinished
get_unfinished_enum_or_generic edt =
    let
        good_name =
            ensure_good_custom_type_name edt.name
    in
    good_name
        |> Result.andThen
            (\n ->
                case n of
                    Plain s ->
                        Enum.get_unfinished (Node s edt.name.loc) edt.fields

                    Generic _ _ ->
                        Debug.todo "Get Unfinished Generic Enum"
            )


get_unfinished : AST.TypeDefinitionType -> AnalysisRes DefinitionPropagator.Unfinished
get_unfinished tdt =
    case tdt of
        AST.StructDefType sdt ->
            get_unfinished_struct_or_generic sdt

        AST.EnumDefType edt ->
            get_unfinished_enum_or_generic edt

        _ ->
            Debug.todo "get unfinished enum and alias"



-- AST.EnumDefType edt ->
-- edt.name |> ensure_good_custom_type_name |> Result.map (\a -> ( a, tdt ))
--
-- AST.AliasDefType adt ->
-- adt.name |> ensure_good_custom_type_name |> Result.map (\a -> ( a, tdt ))


type TypeDeclarationName
    = Plain Identifier
    | Generic Identifier (List String)


extract_unfinished : List AST.TypeDefinitionType -> AnalysisRes (List DefinitionPropagator.Unfinished)
extract_unfinished ls =
    let
        l : List (AnalysisRes DefinitionPropagator.Unfinished)
        l =
            ls |> List.map get_unfinished
    in
    List.foldl res_join_n (Ok []) l


make_outer_type_scope : AST.Program -> AnalysisRes Scope.FullScope
make_outer_type_scope prog =
    let
        builtin_scope : AnalysisRes Scope.FullScope
        builtin_scope =
            Ok BuiltinScopes.builtin_scope

        import_scope : AnalysisRes Scope.FullScope
        import_scope =
            analyze_imports prog.imports

        completed_scopes =
            Result.map2 Scope.merge_two_scopes builtin_scope import_scope

        incompletes : AnalysisRes (List DefinitionPropagator.Unfinished)
        incompletes =
            extract_unfinished prog.global_typedefs


        complete_defs : Scope.FullScope -> List ( Node DefinitionPropagator.DeclarationName, DefinitionPropagator.Definition )
        complete_defs s =
            s.types
                |> List.map
                    (\ntn ->
                        ( node_map named_name ntn
                            |> node_map CustomTypeName
                            |> node_map DefinitionPropagator.TypeDeclaration
                        , DefinitionPropagator.TypeDef (node_get ntn |> named_get)
                        )
                    )
    in
    completed_scopes
        |> Result.map complete_defs
        |> Result.andThen
            (\defs ->
                incompletes
                    |> Result.andThen (\incs -> DefinitionPropagator.from_definitions_and_declarations defs incs |> Result.mapError DefPropErr)
            )
        -- |> Result.andThen (incompletes |> Result.map DefinitionPropagator.add_many_incomplete)
        |> Result.andThen (\dp -> DefinitionPropagator.to_full_scope dp |> Result.mapError DefPropErr)


analyze_imports : List AST.ImportNode -> AnalysisRes Scope.FullScope
analyze_imports imps =
    imps
        |> List.map
            (\s ->
                BuiltinScopes.import_scope s.thing |> Result.fromMaybe (UnknownImport s)
            )
        |> collapse_scope_results


collapse_scope_results : List (AnalysisRes Scope.FullScope) -> AnalysisRes Scope.FullScope
collapse_scope_results scopes =
    ar_foldN Scope.merge_two_scopes Scope.empty_scope scopes
