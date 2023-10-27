module Analysis.Analyzer exposing (..)

import Analysis.BuiltinScopes as BuiltinScopes
import Analysis.Scope as Scope
import Analysis.Util exposing (..)
import Keyboard.Key exposing (Key(..))
import Language.Language as Language exposing (FunctionHeader, Identifier(..), IntegerSize(..), QualifiedTypeName, TypeDefinition(..), TypeName(..), TypeOfCustomType, ValueNameAndType)
import Parser.AST as AST
import Parser.ParserCommon exposing (Error(..))
import String exposing (join)
import Util


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
    = Assignment ValueNameAndType TypedExpression
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
            make_outer_scope ast

        definitions =
            Ok []

        module_name =
            Result.fromMaybe NoModuleName ast.module_name
    in
    Result.map3 (GoodProgram ast) module_name outer_scopes definitions


ar_map2 : (a -> b -> value) -> AnalysisRes a -> AnalysisRes b -> AnalysisRes value
ar_map2 join a b =
    case a of
        Err eA ->
            case b of
                Err eB ->
                    Err (add_error eA eB)

                Ok _ ->
                    Err eA

        Ok valA ->
            case b of
                Err eB ->
                    Err eB

                Ok valB ->
                    join valA valB |> Ok


ar_mapN : (a -> a -> a) -> a -> List (AnalysisRes a) -> AnalysisRes a
ar_mapN join_value value1 ls =
    let
        join =
            res_join_2 join_value
    in
    List.foldl join (Ok value1) ls


make_outer_scope : AST.Program -> Result AnalysisError Scope.FullScope
make_outer_scope prog =
    let
        builtin_scope : AnalysisRes Scope.FullScope
        builtin_scope =
            Ok { values = [], types = [], generic_types = [] }

        import_scope : AnalysisRes Scope.FullScope
        import_scope =
            analyze_imports prog.imports

        module_declarations : AnalysisRes ()
        module_declarations =
            find_this_module_declarations prog.global_typedefs

        pre_fn_scopes =
            ar_mapN Scope.merge_two_scopes
                Scope.empty_scope
                [ builtin_scope
                , import_scope
                -- , module_declarations
                ]

        full_scopes =
            Ok Scope.empty_scope

        -- pre_fn_scopes
        --     |> Result.andThen (build_this_module_value_declarations prog.global_functions)
        --     |> Result.map (\vals -> Scope.FullScope vals [])
    in
    collapse_scope_results [ full_scopes, pre_fn_scopes ]


find_this_module_declarations: List AST.TypeDefinitionType -> AnalysisRes ()
find_this_module_declarations ast_defs = Ok ()

analyze_imports : List AST.ImportAndLocation -> AnalysisRes Scope.FullScope
analyze_imports imps =
    imps
        |> List.map
            (\s ->
                BuiltinScopes.import_scope s.thing |> Result.fromMaybe (UnknownImport s)
            )
        |> collapse_scope_results


collapse_scope_results : List (AnalysisRes Scope.FullScope) -> AnalysisRes Scope.FullScope
collapse_scope_results scopes =
    ar_mapN Scope.merge_two_scopes Scope.empty_scope scopes
