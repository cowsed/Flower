module Analysis.Analyzer exposing (..)

import Analysis.BuiltinScopes as BuiltinScopes
import Analysis.Scope as Scope
import Language exposing (Identifier(..), LiteralType(..), Type(..), builtin_types)
import Parser.AST as AST
import Parser.ParserCommon exposing (Error(..))
import Util


type alias GoodProgram =
    { module_name : String, outer_scope : Scope.OverviewScope }


analyze : AST.Program -> Result AnalysisError GoodProgram
analyze prog =
    let
        outer_scopes =
            make_outer_scope prog

        assemble_gp scope name =
            GoodProgram name scope
    in
    Result.map2 assemble_gp outer_scopes (Result.fromMaybe NoModuleName prog.module_name)



-- mocked imports until weve got a package manager


merge_scopes : List (Result AnalysisError Scope.OverviewScope) -> Result AnalysisError Scope.OverviewScope
merge_scopes scopes =
    let
        merge_2 : Result AnalysisError Scope.OverviewScope -> Result AnalysisError Scope.OverviewScope -> Result AnalysisError Scope.OverviewScope
        merge_2 res1 res2 =
            case res1 of
                Err e1 ->
                    case res2 of
                        Err e2 ->
                            Multiple [ e1, e2 ] |> Err

                        Ok _ ->
                            Err e1

                Ok s1 ->
                    case res2 of
                        Err e2 ->
                            Err e2

                        Ok s2 ->
                            Scope.merge_2_scopes s1 s2 |> Ok
    in
    List.foldl merge_2 (Ok Scope.empty_scope) scopes


make_outer_scope : AST.Program -> Result AnalysisError Scope.OverviewScope
make_outer_scope prog =
    let
        builtin_scope : Scope.OverviewScope
        builtin_scope =
            { values = [], types = builtin_types }

        imported_scopes =
            import_scopes prog.imports

        global_scope =
            scope_from_typedefs prog.global_typedefs
    in
    merge_scopes [ Ok builtin_scope, imported_scopes, global_scope ]


scope_from_typedef : AST.TypeDefinitionType -> Result AnalysisError Scope.OverviewScope
scope_from_typedef t =
    case t of
        AST.StructDefType s ->
            Unimplemented "scope from struct def" |> Err

        AST.EnumDefType edef ->
            Unimplemented "scope from enum def" |> Err

        AST.AliasDefType adef ->
            Unimplemented "scope from alias def" |> Err


scope_from_typedefs : List AST.TypeDefinitionType -> Result AnalysisError Scope.OverviewScope
scope_from_typedefs l =
    l |> List.map scope_from_typedef |> merge_scopes


import_scope : AST.ImportAndLocation -> Result AnalysisError Scope.OverviewScope
import_scope im =
    case im.thing of
        "std" ->
            BuiltinScopes.std_scope |> Ok

        "math" ->
            BuiltinScopes.math_scope |> Ok

        _ ->
            Err (UnknownImport im.thing im.loc)


import_scopes : List AST.ImportAndLocation -> Result AnalysisError Scope.OverviewScope
import_scopes strs =
    strs |> List.map import_scope |> merge_scopes


type AnalysisError
    = UnknownImport String Util.SourceView
    | NoModuleName
    | Unimplemented String
    | Multiple (List AnalysisError)
