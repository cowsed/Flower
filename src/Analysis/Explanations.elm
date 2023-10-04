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

            UnknownImport sl ->
                Html.text ("I don't know of an import by the name `" ++ sl.thing ++ "`. \n" ++ Util.show_source_view sl.loc)

            Unimplemented why ->
                Html.text ("Unimplemented: " ++ why)

            Multiple l ->
                l |> List.map explain_error |> Html.div []

            InvalidSyntaxInStructDefinition ->
                Html.text "Invlaid Syntax in struct definition. Only allowed things are `struct Name{}` or `struct Name[A, B, C]`\n"

            BadTypeParse loc ->
                Html.text ("Arbitrary bad type parse\n" ++ Util.show_source_view loc)

            ExpectedSymbolInGenericArg loc ->
                Html.text ("Expected a one word symbol in generic arg list. something like `T` or `Name`\n" ++ Util.show_source_view loc)

            FunctionNameArgTooComplicated loc ->
                Html.text ("Function name is too complicated. I expect something like `foo()` or `do_stuff`\n" ++ Util.show_source_view loc)

            GenericArgIdentifierTooComplicated loc ->
                Html.text ("Too complicated for generic argument\n" ++ Util.show_source_view loc)

            GenericTypeNameNotValidWithoutSquareBrackets loc ->
                Html.text ("The type of `name` is a generic type but there were wasnt a [] right here. There is no generic argument deductio yet so dont do that\n" ++ Util.show_source_view loc)

            TypeNameNotFound id loc ->
                Html.text ("Type " ++ (stringify_identifier id) ++ " not found\n" ++ Util.show_source_view loc)
        ]


explain_program : GoodProgram -> Html.Html msg
explain_program gp =
    Html.div [ style "font-size" "15px" ]
        [ Html.h3 [] [ Html.text ("module: " ++ gp.module_name) ]
        , Util.collapsable (Html.text "Outer Scope") (explain_global_scope gp.outer_scope)
        ]


explain_global_scope : Scope.OverviewScope -> Html.Html msg
explain_global_scope scope =
    Html.div []
        [ Util.collapsable (Html.text "Values") (scope.values |> List.map explain_name_and_type |> List.map (\h -> Html.li [] [ h ]) |> Html.ul [])
        , Util.collapsable (Html.text "Types") (scope.types |> List.map explain_outer_type |> List.map (\h -> Html.li [] [ h ]) |> Html.ul [])
        ]


explain_outer_type : Language.OuterType -> Html.Html msg
explain_outer_type ot =
    case ot of
        Generic id gt args ->
            Html.span []
                [ Html.text (stringify_typeoftypedef gt)
                , Html.text (stringify_identifier id)
                , Html.text " with args "
                , Html.span [] [ Html.text (String.join ", " args) ]
                ]

        StructOuterType st ->
            Html.span [] [ Html.text ("struct with name " ++ stringify_identifier st) ]

        EnumOuterType et ->
            Html.span [] [ Html.text ("enum with name " ++ stringify_identifier et) ]

        AliasOuterType at _ ->
            Html.span [] [ Html.text ("alias with name " ++ stringify_identifier at) ]


stringify_typeoftypedef : TypeOfTypeDefinition -> String
stringify_typeoftypedef gt =
    case gt of
        Language.StructDefinitionType ->
            "generic struct "

        Language.EnumDefinitionType ->
            "generic enum "

        Language.AliasDefinitionType ->
            "generic alias "


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

        NamedType n td ->
            Html.span [] [ Html.text <| stringify_typeoftypedef td, Html.text <| " with name " ++ stringify_identifier n ]

        GenericInstantiation id args ->
            Html.span []
                [ Html.text ("generic instantiation of " ++ stringify_identifier id ++ "with args")
                , Html.ul []
                    (args
                        |> List.map explain_type
                        |> List.map (\e -> Html.li [] [ e ])
                    )
                ]


explain_fheader : FunctionHeader -> Html.Html msg
explain_fheader fh =
    let
        ret =
            fh.rtype |> Maybe.map explain_type |> Maybe.map List.singleton |> Maybe.map (\l -> Html.text "" :: l) |> Maybe.withDefault []

        args =
            fh.args |> List.map explain_qualified_name_andtype
    in
    Html.span []
        [ Html.text "("
        , Html.span [] (List.append args ret)
        , Html.text ")"
        ]


explain_qualified_name_andtype : Language.QualifiedType -> Html.Html msg
explain_qualified_name_andtype qnt =
    Html.span [] [ Html.text <| stringify_qualifier qnt.qual, explain_type qnt.typ ]


stringify_qualifier : Qualifier -> String
stringify_qualifier qual =
    case qual of
        Constant ->
            "const"

        Variable ->
            "var"


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
