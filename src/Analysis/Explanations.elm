module Analysis.Explanations exposing (..)

import Analysis.Analyzer exposing (..)
import Analysis.Scope as Scope
import Analysis.Util exposing (AnalysisError(..))
import Element
import Element.Font as Font
import Language.Language as Language exposing (..)
import Pallete
import Ui exposing (color_text, comma_space, space)
import Util


header : String -> Element.Element msg
header str =
    Element.el [ Font.size 25, Font.semiBold ] (Element.text str)


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
            TypeNameTooComplicated loc ->
                Element.text <| "This name is too complicated for a struct. I expect something like `struct Name`" ++"\n" ++ Util.show_source_view loc
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
        , Element.el [ Element.padding 10 ] (explain_global_scope gp.global_scope)
        ]


explain_global_scope : Scope.FullScope -> Element.Element msg
explain_global_scope scope =
    Element.column [ Element.spacing 6 ]
        (List.concat
            [ [ header "Values" ]
            , scope.values |> List.map explain_name_and_type
            , [ header "Types" ]
            , scope.types |> List.map explain_outer_type
            ]
        )



--,--Element.html <| Util.collapsable (Html.text "Types") (Element.layout [] <| ( |> List.map (\h -> Html.li [] [ h ]) |> Html.ul []))


explain_type_type : Language.TypeType -> String
explain_type_type tt =
    case tt of
        Any s ->
            s ++ ": Any"


explain_outer_type : Named Language.TypeDefinition -> Element.Element msg
explain_outer_type nt =
    case named_get nt of
        StructDefinitionType _ ->
            Element.el [] <| Element.text ("struct with name " ++ stringify_identifier nt.name)

        EnumDefinitionType _ ->
            Element.el [] <| Element.text ("enum with name " ++ stringify_identifier nt.name)

        AliasDefinitionType _ ->
            Element.row [] [ Element.text "alias with name ", Ui.code (Element.text <| stringify_identifier nt.name) ]


stringify_typeoftypedef : TypeDefinition -> String
stringify_typeoftypedef gt =
    case gt of
        Language.StructDefinitionType _ ->
            "struct "

        Language.EnumDefinitionType _ ->
            "enum "

        Language.AliasDefinitionType _ ->
            "alias "


explain_name_and_type : Named Value -> Element.Element msg
explain_name_and_type vnt =
    Element.row []
        [ Element.text (Language.stringify_identifier vnt.name) |> Ui.code
        , Element.text " of type "
        , explain_typename (values_type vnt.value) |> Ui.code
        ]


explain_typename : Language.TypeName -> Element.Element msg
explain_typename t =
    case t of
        IntegerType isize ->
            stringify_integer_size isize |> color_text Pallete.orange_c

        FloatingPointType fsize ->
            stringify_floating_size fsize |> color_text Pallete.orange_c

        FunctionType f ->
            Element.row [] <|
                [ color_text Pallete.red_c "fn "
                , explain_fheader f
                ]

        CustomTypeName _ ->
            Debug.todo "branch 'CustomTypeName _' not implemented"

        GenericInstantiation _ _ ->
            Debug.todo "branch 'GenericInstantiation _ _' not implemented"


explain_fheader : FunctionHeader -> Element.Element msg
explain_fheader fh =
    let
        ret =
            fh.rtype |> Maybe.map explain_typename |> Maybe.map List.singleton |> Maybe.map (\l -> Element.text " -> " :: l) |> Maybe.withDefault []

        args =
            fh.args |> List.map explain_qualified_name_andtype
    in
    Element.row []
        [ Element.text "("
        , Element.row [] (args |> List.intersperse comma_space)
        , Element.text ")"
        , Element.row [] ret
        ]


explain_qualified_name_andtype : Language.QualifiedTypeName -> Element.Element msg
explain_qualified_name_andtype qnt =
    Element.row [] [ color_quallifier qnt.qual, space, explain_typename qnt.typ ]


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
