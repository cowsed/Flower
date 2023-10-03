module Analysis.Explanations exposing (..)

import Analysis.Analyzer exposing (..)
import Analysis.Scope as Scope
import Html
import Html.Attributes exposing (style)
import Language exposing (..)
import Pallete
import Util


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
    Html.div [ style "font-size" "15px" ]
        [ Html.h3 [] [ Html.text ("module: " ++ gp.module_name) ]
        , Util.collapsable (Html.text "Outer Scope") (explain_global_scope gp.outer_scope)
        ]


explain_global_scope : Scope.OverviewScope -> Html.Html msg
explain_global_scope scope =
    scope.values |> List.map explain_name_and_type |> List.map (\h -> Html.li [] [ h ]) |> Html.ul []


explain_name_and_type : Language.ValueNameAndType -> Html.Html msg
explain_name_and_type vnt =
    Html.pre [] [ Html.text (Language.stringify_identifier vnt.name), Html.text " of type ", explain_type vnt.typ ]


explain_type : Language.Type -> Html.Html msg
explain_type t =
    case t of
        IntegerType isize ->
            stringify_integer_size isize |> Html.text

        FloatingPointType fsize ->
            stringify_floating_size fsize |> Html.text

        StringType ->
            "str" |> Html.text

        BooleanType ->
            "bool" |> Html.text

        FunctionType f ->
            Html.span [] [ Html.text "fn", explain_fheader f ]


explain_fheader : FunctionHeader -> Html.Html msg
explain_fheader fh =
    let
        ret =
            fh.rtype |> Maybe.map explain_type |> Maybe.map List.singleton |> Maybe.map (\l -> Html.text "" :: l) |> Maybe.withDefault []

        args =
            fh.args |> List.map explain_type
    in
    Html.span []
        [ Html.text "("
        , Html.span [] (List.append args ret)
        , Html.text ")"
        ]


stringify_integer_size : IntegerSize -> String
stringify_integer_size size =
    case size of
        Language.U8 ->
            "u8"

        Language.U16 ->
            "u16"

        Language.U32 ->
            "u32"

        Language.U64 ->
            "u64"

        Language.I8 ->
            "i8"

        Language.I16 ->
            "i16"

        Language.I32 ->
            "i32"

        Language.I64 ->
            "i64"


stringify_floating_size : FloatingPointSize -> String
stringify_floating_size size =
    case size of
        Language.F32 ->
            "f32"

        Language.F64 ->
            "f64"
