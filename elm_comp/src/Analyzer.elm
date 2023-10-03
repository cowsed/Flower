module Analyzer exposing (..)

import Analysis.Scope as Scope
import Html
import Html.Attributes exposing (style)
import Language exposing (Identifier(..), LiteralType(..), Type, ValueNameAndType, builtin_types)
import Pallete
import Parser.AST as AST
import Util
import Language exposing (Type(..))
import Language exposing (FloatingPointSize)
import Language exposing (IntegerSize)


type alias GoodProgram =
    { module_name : String, outer_scope : Scope.ValuelessScope }


    
analyze : AST.Program -> Result AnalysisError GoodProgram
analyze prog =
    let
        outer_scopes =
            make_outer_scope prog
        assemble_gp scope name = 
            GoodProgram name scope
    in
     Result.map2 assemble_gp outer_scopes (Result.fromMaybe (NoModuleName) prog.module_name)



-- mocked imports until weve got a package manager


std_scope : Scope.ValuelessScope
std_scope =
    Scope.ValuelessScope [] []


math_scope : Scope.ValuelessScope
math_scope =
    Scope.ValuelessScope [ ValueNameAndType (QualifiedIdentifiers [ "math", "Pi" ]) (Language.FloatingPointType Language.F64) ] []


merge_scopes : List (Result AnalysisError Scope.ValuelessScope) -> Result AnalysisError Scope.ValuelessScope
merge_scopes scopes =
    let
        merge_2 : Result AnalysisError Scope.ValuelessScope -> Result AnalysisError Scope.ValuelessScope -> Result AnalysisError Scope.ValuelessScope
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


make_outer_scope : AST.Program -> Result AnalysisError Scope.ValuelessScope
make_outer_scope prog =
    let
        init_scope : Scope.ValuelessScope
        init_scope =
            { values = [], types = builtin_types }
    in
    Ok init_scope
        |> Result.andThen
            (\s ->
                import_scopes prog.imports
                    |> Result.andThen (\s2 -> Scope.merge_2_scopes s s2 |> Ok)
            )


import_scope : AST.ImportAndLocation -> Result AnalysisError Scope.ValuelessScope
import_scope im =
    case im.thing of
        "std" ->
            std_scope |> Ok

        "math" ->
            math_scope |> Ok

        _ ->
            Err (UnknownImport im.thing im.loc)


import_scopes : List AST.ImportAndLocation -> Result AnalysisError Scope.ValuelessScope
import_scopes strs =
    strs |> List.map import_scope |> merge_scopes


type AnalysisError
    = UnknownImport String Util.SourceView
    | NoModuleName
    | Multiple (List AnalysisError)


explain_error : AnalysisError -> Html.Html msg
explain_error ae =
    Html.pre [ style "color" Pallete.red ]
        [ case ae of
            NoModuleName ->
                Html.text "I need a line at the top of the program that looks like `module main`"

            UnknownImport s loc ->
                Html.text ("I don't know of an import by the name `" ++ s ++ "`. \n" ++ Util.show_source_view loc)

            Multiple l ->
                l |> List.map explain_error |> Html.div []
        ]


explain_program : GoodProgram -> Html.Html msg
explain_program gp =
    Html.div [style "font-size" "15px"]
        [ Html.h3 [] [ Html.text ("module: " ++ gp.module_name) ]
        , Util.collapsable (Html.text "Outer Scope") (explain_global_scope gp.outer_scope)
        ]


explain_global_scope : Scope.ValuelessScope -> Html.Html msg
explain_global_scope scope =
    scope.values |> List.map explain_name_and_type |> List.map (\h -> Html.li [] [h]) |> Html.ul [] 


explain_name_and_type : Language.ValueNameAndType -> Html.Html msg
explain_name_and_type vnt =
    Html.pre [] [ Html.text (Language.stringify_identifier vnt.name), Html.text " of type ", explain_type vnt.typ ]

explain_type: Language.Type -> Html.Html msg
explain_type t = 
    case t of 
        IntegerType isize -> stringify_integer_size isize |> Html.text
        FloatingPointType fsize -> stringify_floating_size fsize |> Html.text
        StringType -> "str" |> Html.text
        BooleanType -> "bool" |> Html.text

stringify_integer_size: IntegerSize -> String
stringify_integer_size size = 
    case size of
        Language.U8 -> "u8"
        Language.U16 -> "u16"
        Language.U32 -> "u32"
        Language.U64 -> "u64"
        Language.I8 -> "i8"
        Language.I16 -> "i16"
        Language.I32 -> "i32"
        Language.I64 -> "i64"

stringify_floating_size: FloatingPointSize -> String
stringify_floating_size size = 
    case size of
        Language.F32 -> "f32"
        Language.F64 -> "f64"