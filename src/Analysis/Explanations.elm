module Analysis.Explanations exposing (..)

import Analysis.Analyzer exposing (..)
import Analysis.Scope as Scope
import Analysis.Util exposing (AnalysisError(..))
import Element
import Element.Font as Font
import Language.Language as Language exposing (..)
import Pallete
import Util


header : String -> Element.Element msg
header str =
    Element.el [ Font.size 30, Font.bold ] (Element.text str)


explain_error : AnalysisError -> Element.Element msg
explain_error ae =
    Element.el [ Font.color Pallete.red_c, Font.family [ Font.monospace ] ]
        (case ae of
            NoModuleName ->
                Element.text "I need a line at the top of the program that looks like `module main`"

            UnknownImport sl ->
                Element.text ("I don't know of an import by the name `" ++ sl.thing ++ "`. \n" ++ Util.show_source_view sl.loc)

            Unimplemented why ->
                Element.text ("Unimplemented: " ++ why)

            Multiple l ->
                l |> List.map explain_error |> Element.column []

            InvalidSyntaxInStructDefinition ->
                Element.text "Invlaid Syntax in struct definition. Only allowed things are `struct Name{}` or `struct Name[A, B, C]`\n"

            BadTypeParse loc ->
                Element.text ("Arbitrary bad type parse\n" ++ Util.show_source_view loc)

            ExpectedSymbolInGenericArg loc ->
                Element.text ("Expected a one word symbol in generic arg list. something like `T` or `Name`\n" ++ Util.show_source_view loc)

            FunctionNameArgTooComplicated loc ->
                Element.text ("Function name is too complicated. I expect something like `foo()` or `do_stuff`\n" ++ Util.show_source_view loc)

            GenericArgIdentifierTooComplicated loc ->
                Element.text ("Too complicated for generic argument\n" ++ Util.show_source_view loc)

            GenericTypeNameNotValidWithoutSquareBrackets loc ->
                Element.text ("The type of `name` is a generic type but there were wasnt a [] right here. There is no generic argument deductio yet so dont do that\n" ++ Util.show_source_view loc)

            TypeNameNotFound id loc ->
                Element.text ("Type " ++ stringify_identifier id ++ " not found\n" ++ Util.show_source_view loc)

            TypeNotInstantiable typid loc ->
                Element.text <| "This type `" ++ stringify_identifier typid ++ "` is not instantiable (its not generic)\n" ++ Util.show_source_view loc

            CantInstantiateGenericWithTheseArgs reason loc ->
                Element.text <| "Cant instantiate this generic type with these type arguments:" ++ stringify_reason_for_unsustantiable reason ++ "\n" ++ Util.show_source_view loc
        )


stringify_reason_for_unsustantiable : ReasonForUninstantiable -> String
stringify_reason_for_unsustantiable reason =
    case reason of
        WrongNumber ->
            "Wrong number of arguments"


explain_program : GoodProgram -> Element.Element msg
explain_program gp =
    Element.column [ Font.size 15 ]
        [ Element.el [] (Element.text ("module: " ++ gp.module_name))
        , header "Values"
        , header "Declarations"
        , Element.el [ Element.padding 10 ] (explain_global_scope gp.outer_scope)
        ]


explain_global_scope : Scope.OverviewScope -> Element.Element msg
explain_global_scope scope =
    Element.column []
        (scope.values |> List.map explain_name_and_type)



--,--Element.html <| Util.collapsable (Html.text "Types") (Element.layout [] <| (scope.types |> List.map explain_outer_type |> List.map (\h -> Html.li [] [ h ]) |> Html.ul []))


explain_type_type : Language.TypeType -> String
explain_type_type tt =
    case tt of
        Any s ->
            s ++ ": Any"


explain_outer_type : Language.OuterType -> Element.Element msg
explain_outer_type ot =
    case ot of
        Generic id gt args ->
            Element.row []
                [ Element.text (stringify_typeoftypedef gt)
                , Element.text (stringify_identifier id)
                , Element.text " with args "
                , Element.text (String.join ", " (args |> List.map explain_type_type))
                ]

        StructOuterType st ->
            Element.el [] <| Element.text ("struct with name " ++ stringify_identifier st)

        EnumOuterType et ->
            Element.el [] <| Element.text ("enum with name " ++ stringify_identifier et)

        AliasOuterType at _ ->
            Element.el [] <| Element.text ("alias with name " ++ stringify_identifier at)


stringify_typeoftypedef : TypeOfTypeDefinition -> String
stringify_typeoftypedef gt =
    case gt of
        Language.StructDefinitionType ->
            "struct "

        Language.EnumDefinitionType ->
            "enum "

        Language.AliasDefinitionType ->
            "alias "


explain_name_and_type : Language.ValueNameAndType -> Element.Element msg
explain_name_and_type vnt =
    Element.row [] [ Element.text (Language.stringify_identifier vnt.name), Element.text " of type ", explain_type vnt.typ ]


explain_type : Language.Type -> Element.Element msg
explain_type t =
    case t of
        IntegerType isize ->
            stringify_integer_size isize |> color_text Pallete.orange_c

        FloatingPointType fsize ->
            stringify_floating_size fsize |> color_text Pallete.orange_c

        StringType ->
            "str" |> color_text Pallete.orange_c

        BooleanType ->
            "bool" |> color_text Pallete.orange_c

        FunctionType f ->
            Element.row [] <|
                [ color_text Pallete.red_c "fn "
                , explain_fheader f
                ]

        NamedType n td ->
            Element.text <| stringify_typeoftypedef td ++ " with name " ++ stringify_identifier n

        GenericInstantiation id tot args ->
            Element.column []
                [ Element.text ("generic " ++ stringify_typeoftypedef tot ++ " instantiation of " ++ stringify_identifier id ++ " with args")
                , Element.column [] (args |> List.map explain_type)
                ]


explain_fheader : FunctionHeader -> Element.Element msg
explain_fheader fh =
    let
        ret =
            fh.rtype |> Maybe.map explain_type |> Maybe.map List.singleton |> Maybe.map (\l -> Element.text " -> " :: l) |> Maybe.withDefault []

        args =
            fh.args |> List.map explain_qualified_name_andtype
    in
    Element.row []
        [ Element.text "("
        , Element.row [] (args |> List.intersperse comma_space)
        , Element.text ")"
        , Element.row [] ret
        ]


explain_qualified_name_andtype : Language.QualifiedType -> Element.Element msg
explain_qualified_name_andtype qnt =
    Element.row [] [ color_quallifier qnt.qual, space, explain_type qnt.typ ]


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


color_quallifier : Language.Qualifier -> Element.Element msg
color_quallifier qual =
    color_text Pallete.red_c (stringify_qualifier qual)


space : Element.Element msg
space =
    Element.text " "

comma_space : Element.Element msg
comma_space =
    Element.text ", "


color_text : Element.Color -> String -> Element.Element msg
color_text col str =
    Element.el [ Font.color col ] (Element.text str)
