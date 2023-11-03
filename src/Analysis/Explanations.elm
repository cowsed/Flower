module Analysis.Explanations exposing (..)

import Analysis.Analyzer exposing (..)
import Analysis.DefinitionPropagator as DefinitionPropagator exposing (Error(..))
import Analysis.Scope as Scope
import Analysis.Util exposing (AnalysisError(..))
import Element
import Element.Border as Border
import Element.Font as Font
import Language.Language as Language exposing (..)
import Language.Syntax as Syntax
import Pallete
import Ui exposing (color_text, comma_space, space)
import Util exposing (escape_result, viewBullet)


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
                Element.text ("I don't know of an import by the name `" ++ sl.thing ++ "`. \n" ++ Syntax.show_source_view sl.loc)

            Unimplemented why ->
                Element.text ("Unimplemented: " ++ why)

            Multiple l ->
                l |> List.map explain_error |> Element.column []

            InvalidSyntaxInStructDefinition ->
                Element.text "Invlaid Syntax in struct definition. Only allowed things are `struct Name{}` or `struct Name[A, B, C]`\n"

            BadTypeParse loc ->
                Element.text ("Arbitrary bad type parse\n" ++ Syntax.show_source_view loc)

            ExpectedSymbolInGenericArg loc ->
                Element.text ("Expected a one word symbol in generic arg list. something like `T` or `Name`\n" ++ Syntax.show_source_view loc)

            FunctionNameArgTooComplicated loc ->
                Element.text ("Function name is too complicated. I expect something like `foo()` or `do_stuff`\n" ++ Syntax.show_source_view loc)

            GenericArgIdentifierTooComplicated loc ->
                Element.text ("Too complicated for generic argument\n" ++ Syntax.show_source_view loc)

            GenericTypeNameNotValidWithoutSquareBrackets loc ->
                Element.text ("The type of `name` is a generic type but there were wasnt a [] right here. There is no generic argument deductio yet so dont do that\n" ++ Syntax.show_source_view loc)

            TypeNameNotFound id loc ->
                Element.text ("Type " ++ stringify_identifier id ++ " not found\n" ++ Syntax.show_source_view loc)

            TypeNotInstantiable typid loc ->
                Element.text <| "This type `" ++ stringify_identifier typid ++ "` is not instantiable (its not generic)\n" ++ Syntax.show_source_view loc

            CantInstantiateGenericWithTheseArgs reason loc ->
                Element.text <| "Cant instantiate this generic type with these type arguments:" ++ stringify_reason_for_unsustantiable reason ++ "\n" ++ Syntax.show_source_view loc

            TypeNameTooComplicated loc ->
                Element.text <| "This name is too complicated for a struct. I expect something like `struct Name`" ++ "\n" ++ Syntax.show_source_view loc

            StructFieldNameTooComplicated loc ->
                Element.text <| "This name is too complicated for a struct field. I expect something like `name: Type`" ++ "\n" ++ Syntax.show_source_view loc

            NoSuchTypeFound loc ->
                Element.text <| "I couldnt find this type: TODO better" ++ "\n" ++ Syntax.show_source_view loc

            NoSuchGenericTypeFound loc ->
                Element.text <| "I couldnt find this generic type: TODO better" ++ "\n" ++ Syntax.show_source_view loc

            DefPropErr e ->
                case e of
                    DuplicateDefinition locs ->
                        Element.text <| "Duplicate Definition. First:\n" ++ Syntax.show_source_view locs.first ++ "\nSecond:\n" ++ Syntax.show_source_view locs.second

                    TypePromisedButNotFound t ->
                        Element.row [] [ Element.text "finalize was called so iexpected this type but it wasnt here", explain_typename t ]

                    StillHaveIncompletes types ->
                        types
                            |> List.map
                                (\( name, needs ) ->
                                    Element.column []
                                        [ Element.row []
                                            [ Element.text "Incomplete Type "
                                            , explain_declaration_name name
                                            , Element.text ". needs: "
                                            ]
                                        , Element.column [ Border.width 1 ] (needs |> List.map explain_declaration_name)
                                        ]
                                )
                            |> Element.column []
                    RecursiveDefinition ts -> Element.row [] (ts |> List.map explain_declaration_name |> List.intersperse (Element.text " defined in terms of \n") )
                    DefinitionPropagator.MultipleErrs ls -> Element.column [] (ls |> List.map (explain_error << DefPropErr))
        )


explain_declaration_name : DefinitionPropagator.DeclarationName -> Element.Element msg
explain_declaration_name dp =
    case dp of
        DefinitionPropagator.TypeDeclaration td ->
            explain_typename td


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
            , scope.values |> List.map Syntax.node_get |> List.map explain_value_name_and_type
            , [ header "Types" ]
            , scope.types |> List.map Syntax.node_get |> List.map (\nt -> explain_type_def nt.value)
            , [ header "Generic Types" ]
            , scope.generic_types |> List.map Syntax.node_get |> List.map explain_generic_type_def
            ]
        )


explain_generic_type_def : Named Language.GenericTypeDefinition -> Element.Element msg
explain_generic_type_def ngt =
    ngt.value [ CustomTypeName (Language.SingleIdentifier "T") ]
        |> Result.mapError (\e -> Debug.toString e |> Element.text)
        |> Result.map (\sd -> Element.row [] [ explain_type_def sd ])
        |> escape_result



--,--Element.html <| Util.collapsable (Html.text "Types") (Element.layout [] <| ( |> List.map (\h -> Html.li [] [ h ]) |> Html.ul []))


explain_type_type : Language.TypeType -> String
explain_type_type tt =
    case tt of
        Any s ->
            s ++ ": Any"


explain_type_def : Language.TypeDefinition -> Element.Element msg
explain_type_def td =
    case td of
        StructDefinitionType def ->
            Element.column []
                [ Element.row [] [ Element.text "struct with " ]
                , def.fields
                    |> List.map (\sn -> explain_type_def sn.value)
                    |> List.map (\e -> Util.Bullet e [])
                    |> Util.Bullet (Element.text "Fields")
                    |> viewBullet
                ]

        EnumDefinitionType edt ->
            Element.column []
                [ Element.row [] [ Element.text "enum with name " ]
                , Util.Bullet (Element.text "Tags") (edt |> List.map explain_enum_tag |> List.map (\e -> Util.Bullet e [])) |> viewBullet
                ]

        AliasDefinitionType _ ->
            Element.row [] [ Element.text "alias with name " ]

        IntegerDefinitionType isize ->
            explain_integer isize


explain_enum_tag : EnumTagDefinition -> Element.Element msg
explain_enum_tag etd =
    case etd of
        JustTag n ->
            Ui.code_text n

        TagAndTypes n ts ->
            Element.row [] [ Ui.code_text n, Element.text " with types ", viewBullet <| Util.Bullet Element.none (ts |> List.map explain_typename |> List.map (\e -> Util.Bullet e [])) ]


explain_value_name_and_type : Named Value -> Element.Element msg
explain_value_name_and_type vnt =
    Element.row []
        [ Element.text (Language.stringify_identifier vnt.name) |> Ui.code
        , Element.text " of type "
        , explain_typename (values_type vnt.value) |> Ui.code
        ]


explain_named_typename : SimpleNamed TypeName -> Element.Element msg
explain_named_typename vnt =
    Element.row []
        [ Element.text vnt.name |> Ui.code
        , Element.text " of type "
        , explain_typename vnt.value |> Ui.code
        ]


explain_integer : IntegerSize -> Element.Element msg
explain_integer i =
    (case i of
        U8 ->
            Element.text "8 bit (1 byte) unsigned integer"

        U16 ->
            Element.text "16 bit (2 byte) unsigned integer"

        U32 ->
            Element.text "32 bit (4 byte) unsigned integer"

        U64 ->
            Element.text "64 bit (8 byte) unsigned integer"

        I8 ->
            Element.text "8 bit (1 byte) signed integer"

        I16 ->
            Element.text "16 bit (2 byte) signed integer"

        I32 ->
            Element.text "32 bit (4 byte) signed integer"

        I64 ->
            Element.text "64 bit (8 byte) signed integer"

        Uint ->
            Element.text "system word size unsigned integer. if this over/under flows, will crash"

        Int ->
            Element.text "system word size signed integer. if this over/under flows, will crash"
    )
        |> (\l -> Element.paragraph [] [ l ])


explain_typename : Language.TypeName -> Element.Element msg
explain_typename t =
    case t of
        IntegerType isize ->
            stringify_integer_size isize |> color_text Pallete.orange_c |> Ui.hoverer (explain_integer isize |> Ui.tooltip_styling)

        FloatingPointType fsize ->
            stringify_floating_size fsize |> color_text Pallete.orange_c

        FunctionType f ->
            Element.row [] <|
                [ color_text Pallete.red_c "fn "
                , explain_fheader f
                ]

        CustomTypeName id ->
            Element.row [] [ Element.text "Custom type with name ", Element.text (stringify_identifier id) ]

        GenericInstantiation id args ->
            Element.row []
                [ Element.text "Generic Instantiation of "
                , Element.text (stringify_identifier id)
                , Element.text " with args "
                , Element.row [] (args |> List.map explain_typename)
                ]


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

        Language.Uint ->
            "uint"

        Language.Int ->
            "int"


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
