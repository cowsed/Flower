module Analysis.Analyzer exposing (..)

import Analysis.Scope as Scope
import Language exposing (Identifier(..), LiteralType(..), Type(..), ValueNameAndType, builtin_types)
import Parser.AST as AST
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


std_puts_v : ValueNameAndType
std_puts_v =
    ValueNameAndType (Language.SingleIdentifier "puts") (Language.FunctionType { args = [ Language.StringType ], rtype = Nothing })


std_scope : Scope.OverviewScope
std_scope =
    Scope.OverviewScope [ std_puts_v ] [] |> Scope.qualify_all "std"


math_scope : Scope.OverviewScope
math_scope =
    Scope.OverviewScope [ ValueNameAndType (SingleIdentifier "Pi") (Language.FloatingPointType Language.F64) ] []  |> Scope.qualify_all "math"


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
        init_scope : Scope.OverviewScope
        init_scope =
            { values = [], types = builtin_types }
    in
    Ok init_scope
        |> Result.andThen
            (\s ->
                import_scopes prog.imports
                    |> Result.andThen (\s2 -> Scope.merge_2_scopes s s2 |> Ok)
            )


import_scope : AST.ImportAndLocation -> Result AnalysisError Scope.OverviewScope
import_scope im =
    case im.thing of
        "std" ->
            std_scope |> Ok

        "math" ->
            math_scope |> Ok

        _ ->
            Err (UnknownImport im.thing im.loc)


import_scopes : List AST.ImportAndLocation -> Result AnalysisError Scope.OverviewScope
import_scopes strs =
    strs |> List.map import_scope |> merge_scopes


type AnalysisError
    = UnknownImport String Util.SourceView
    | NoModuleName
    | Multiple (List AnalysisError)
