module Parser.ParserExplanations exposing (..)

import Html
import Html.Attributes exposing (style)
import Pallete as Pallete
import Parser.AST as AST exposing (AliasDefinition, Expression(..), FullName,  TypeDefinitionType(..), make_qualified_typewithname, stringify_fullname)
import Language.Language as Language exposing (Identifier(..))
import Parser.Lexer as Lexer
import Parser.ParserCommon as ParserCommon
import Util



-- Syntaxifications ==========================================


syntaxify_namedarg : AST.QualifiedTypeWithName -> List (Html.Html msg)
syntaxify_namedarg na =
    [ symbol_highlight (Language.stringify_identifier na.name)
    , Html.text ": "
    , Html.span [] [ syntaxify_fullname na.typename.thing ]
    ]


syntaxify_keyword : String -> Html.Html msg
syntaxify_keyword s =
    Html.span [ style "color" Pallete.red ] [ Html.text s ]


symbol_highlight : String -> Html.Html msg
symbol_highlight s =
    Html.span [ style "color" Pallete.orange ] [ Html.text s ]


syntaxify_string_literal : String -> Html.Html msg
syntaxify_string_literal s =
    Html.span [ style "color" "DarkSlateBlue" ] [ Html.text ("\"" ++ s ++ "\"") ]


syntaxify_number_literal : String -> Html.Html msg
syntaxify_number_literal s =
    Html.span [ style "color" Pallete.aqua ] [ Html.text s ]


syntaxify_identifier : Identifier -> Html.Html msg
syntaxify_identifier id =
    case id of
        SingleIdentifier s ->
            symbol_highlight s

        QualifiedIdentifiers ls ->
            ls |> List.map symbol_highlight |> List.intersperse (Html.text ".") |> Html.span []


syntaxify_literal : Language.LiteralType -> String -> Html.Html msg
syntaxify_literal l s =
    case l of
        Language.StringLiteral ->
            syntaxify_string_literal ("\"" ++ s ++ "\"")

        Language.BooleanLiteral ->
            Html.text s

        Language.NumberLiteral ->
            syntaxify_number_literal s


syntaxify_fullname : FullName -> Html.Html msg
syntaxify_fullname fn =
    case fn of
        AST.Literal l s ->
            syntaxify_literal l s |> (\t -> Html.span [] [ t ])

        AST.NameWithoutArgs id ->
            syntaxify_identifier id

        AST.NameWithArgs nl ->
            Html.span []
                [ syntaxify_identifier nl.base
                , Html.text "["
                , Html.span [] (nl.args |> List.map (\f -> syntaxify_fullname f.thing) |> List.intersperse (Html.text ", "))
                , Html.text "]"
                ]

        AST.ReferenceToFullName fn2 ->
            Html.span [] [ Html.text "&", syntaxify_fullname fn2.thing ]

        AST.Constrained name constraint ->
            Html.span [] [ syntaxify_fullname name.thing, Html.text " | ", syntaxify_expression constraint.thing ]


syntaxify_expression : AST.Expression -> Html.Html msg
syntaxify_expression expr =
    case expr of
        AST.NameLookup n ->
            syntaxify_fullname n.thing

        AST.FunctionCallExpr fcall ->
            Html.span []
                [ syntaxify_fullname fcall.thing.fname.thing
                , Html.text "("
                , Html.span [] (fcall.thing.args |> List.map (\arg -> syntaxify_expression arg.thing) |> List.intersperse (Html.text ", "))
                , Html.text ")"
                ]

        AST.Parenthesized e ->
            Html.span [] [ Html.text "(", syntaxify_expression e.thing, Html.text ")" ]

        AST.LiteralExpr lt s ->
            case lt of
                Language.StringLiteral ->
                    Html.span [] [ syntaxify_string_literal s ]

                Language.NumberLiteral ->
                    Html.span [] [ syntaxify_number_literal s ]

                Language.BooleanLiteral ->
                    Html.span [] [ syntaxify_number_literal s ]

        AST.InfixExpr lhs rhs op ->
            Html.span [] [ syntaxify_expression lhs.thing, Html.text (" " ++ Language.stringify_infix_op op ++ " "), syntaxify_expression rhs.thing ]


syntaxify_fheader : AST.FunctionHeader -> Html.Html msg
syntaxify_fheader header =
    let
        pretty_arg_lst : List (Html.Html msg)
        pretty_arg_lst =
            List.concat (List.intersperse [ Html.text ", " ] (List.map syntaxify_namedarg header.args))

        lis =
            List.concat [ [ Html.text "(" ], pretty_arg_lst, [ Html.text ")" ] ]

        ret : Html.Html msg
        ret =
            Html.span []
                (case header.return_type of
                    Just typ ->
                        [ Html.span [] [ Html.text " 🡒 ", Html.span [] [ syntaxify_fullname typ.thing ] ] ]

                    Nothing ->
                        [ Html.text " " ]
                )
    in
    Html.span [] (List.append lis [ ret ])


syntaxify_statement : Int -> AST.Statement -> Html.Html msg
syntaxify_statement indentation_level s =
    let
        indent =
            tabs indentation_level
    in
    case s of
        AST.ReturnStatement expr ->
            Html.span []
                [ tabs indentation_level
                , syntaxify_keyword "return "
                , case expr of
                    Just e ->
                        syntaxify_expression e.thing

                    Nothing ->
                        Html.text ""
                , Html.text "\n"
                ]

        AST.InitilizationStatement taname expr ->
            let
                qual =
                    case taname.qualifiedness of
                        Language.Constant ->
                            ""

                        Language.Variable ->
                            "var "
            in
            Html.span [] (List.concat [ [ indent, syntaxify_keyword qual ], syntaxify_namedarg taname, [ Html.text " = ", syntaxify_expression expr.thing, Html.text "\n" ] ])

        AST.CommentStatement src ->
            Html.span [ style "color" Pallete.gray ] [ indent, Html.text ("// " ++ src), Html.text "\n" ]

        AST.AssignmentStatement name expr ->
            Html.span [] [ tab, symbol_highlight (Language.stringify_identifier name), Html.text " = ", syntaxify_expression expr.thing, Html.text "\n" ]

        AST.FunctionCallStatement fcal ->
            Html.span []
                [ indent
                , symbol_highlight (AST.stringify_fullname fcal.thing.fname.thing)
                , Html.text "("
                , Html.span [] (fcal.thing.args |> List.map (\e -> syntaxify_expression e.thing) |> List.intersperse (Html.span [] [ Html.text ", " ]))
                , Html.text ")"
                , Html.text "\n"
                ]

        AST.IfStatement expr block ->
            collapsing_block indentation_level (Html.span [] [ syntaxify_keyword "if ", syntaxify_expression expr.thing ]) block

        AST.WhileStatement expr block ->
            collapsing_block indentation_level (Html.span [] [ syntaxify_keyword "while ", syntaxify_expression expr.thing ]) block


syntaxify_function : Int -> AST.FunctionDefinition -> List (Html.Html msg)
syntaxify_function indentation fdef =
    let
        header =
            Html.span []
                [ syntaxify_keyword "fn "
                , syntaxify_fullname fdef.name.thing
                , syntaxify_fheader fdef.header
                ]
    in
    [ collapsing_block indentation header fdef.statements, Html.text "\n" ]


syntaxify_program : AST.Program -> Html.Html msg
syntaxify_program prog =
    Html.code
        [ style "font-size" "15px"
        , style "background-color" Pallete.bg
        , style "overflow" "none"
        , style "border-color" Pallete.fg
        , style "width" "100%"
        , style "height" "100%"
        , style "border-style" "solid solid solid none"
        , style "border-width" "2px"
        , style "padding" "5px"
        ]
        [ Html.pre []
            (List.concat
                [ [ syntaxify_keyword "module ", symbol_highlight (Maybe.withDefault "module_name" prog.module_name), Html.text "\n\n" ]
                , prog.imports |> List.map (\name -> [ syntaxify_keyword "import ", syntaxify_string_literal name.thing, Html.text "\n" ]) |> List.concat
                , List.repeat 2 (Html.text "\n")
                , prog.global_typedefs |> List.map (syntaxify_typedef 0)
                , prog.global_functions |> List.map (\f -> syntaxify_function 0 f) |> List.concat
                ]
            )
        ]


syntaxify_typedef : Int -> AST.TypeDefinitionType -> Html.Html msg
syntaxify_typedef indent typ =
    case typ of
        StructDefType s ->
            syntaxify_struct indent s

        EnumDefType s ->
            syntaxify_enum indent s

        AliasDefType s ->
            syntaxify_alias_type indent s


syntaxify_alias_type : Int -> AliasDefinition -> Html.Html msg
syntaxify_alias_type indent ad =
    Html.div []
        [ Html.span []
            [ tabs indent
            , syntaxify_keyword "type "
            , syntaxify_fullname ad.name.thing
            , Html.text " = "
            , syntaxify_fullname ad.alias_to.thing
            , Html.text "\n"
            ]
        , Html.text "\n"
        ]


syntaxify_enum_field : Int -> AST.EnumField -> Html.Html msg
syntaxify_enum_field indents ef =
    let
        my_tabs =
            tabs indents
    in
    if List.length ef.args == 0 then
        Html.div [] [ my_tabs, symbol_highlight ef.name ]

    else
        Html.div []
            [ my_tabs
            , symbol_highlight ef.name
            , Html.text "("
            , Html.span [] (ef.args |> List.map (\f -> syntaxify_fullname f.thing) |> List.intersperse (Html.text ", "))
            , Html.text ")"
            ]


syntaxify_enum : Int -> AST.EnumDefinition -> Html.Html msg
syntaxify_enum indent enum =
    let
        indents =
            tabs indent

        fields =
            enum.fields |> List.map (syntaxify_enum_field (indent + 1)) |> Html.div []
    in
    Html.div []
        [ Html.details
            [ style "background" Pallete.bg1
            , style "width" "fit-content"
            , style "padding-left" "0px"
            , style "padding-right" "5px"
            , style "border-radius" "10px"
            , Html.Attributes.attribute "open" "true"
            ]
            [ collapsing_block_style
            , Html.summary
                [ style "border" "none"
                , style "cursor" "pointer"
                ]
                [ indents
                , syntaxify_keyword "enum "
                , syntaxify_fullname enum.name.thing
                , Html.text " {\n"
                ]
            , fields

            -- , indents
            , Html.text "}\n"
            ]
        , Html.text "\n"
        ]


syntaxify_struct : Int -> AST.StructDefnition -> Html.Html msg
syntaxify_struct indent struct =
    let
        header =
            syntaxify_fullname struct.name.thing

        names =
            struct.fields
                |> List.map (\f -> make_qualified_typewithname f Language.Constant)
                |> List.map syntaxify_namedarg
                |> List.map (\f -> Html.span [] [ tabs (indent + 1), Html.span [] f, Html.text "\n" ])
                |> Html.div []

        indents =
            tabs indent
    in
    Html.div []
        [ Html.details
            [ style "background" Pallete.bg1
            , style "width" "fit-content"
            , style "padding-left" "0px"
            , style "padding-right" "5px"
            , style "border-radius" "10px"
            , Html.Attributes.attribute "open" "true"
            ]
            [ collapsing_block_style
            , Html.summary
                [ style "border" "none"
                , style "cursor" "pointer"
                ]
                [ indents
                , syntaxify_keyword "struct "
                , header
                , Html.text " {\n"
                ]
            , names
            , indents
            , Html.text "}\n"
            ]
        , Html.text "\n"
        ]


syntaxify_block : Int -> List AST.Statement -> Html.Html msg
syntaxify_block indentation_level states =
    let
        outer_indent =
            tabs indentation_level
    in
    Html.div []
        (List.concat
            [ [ Html.text " {\n" ]
            , states |> List.map (syntaxify_statement (indentation_level + 1))
            , [ outer_indent, Html.text "}\n" ]
            ]
        )


collapsing_block : Int -> Html.Html msg -> List AST.Statement -> Html.Html msg
collapsing_block indentation header block =
    let
        indent =
            if indentation == 0 then
                Html.span [] []

            else
                Html.span [ style "padding-left" ".25em" ]
                    [ Html.text (String.repeat (indentation - 1) "    " ++ "  ")
                    ]
    in
    if List.length block == 0 then
        Html.div [] [ tabs indentation, header, Html.text "{}\n" ]

    else
        Html.details
            [ style "background" Pallete.bg1
            , style "width" "fit-content"
            , style "padding-left" "0px"
            , style "padding-right" "5px"
            , style "border-radius" "10px"
            , Html.Attributes.attribute "open" "true"
            ]
            (List.concat
                [ [ collapsing_block_style
                  , Html.summary
                        [ style "border" "none"
                        , style "cursor" "pointer"
                        ]
                        [ indent
                        , header
                        , Html.text " {\n"
                        ]
                  ]
                , block
                    |> List.map (\s -> syntaxify_statement (indentation + 1) s)
                , [ tabs indentation, Html.text "}\n" ]
                ]
            )


collapsing_block_style : Html.Html msg
collapsing_block_style =
    Html.node "style" [] [ Html.text """
details[open] > summary {
}
""" ]



-- Explanations ==============================================


explain_error : ParserCommon.Error -> Html.Html msg
explain_error e =
    case e of
        ParserCommon.Unimplemented p reason ->
            Html.div [ style "color" Pallete.red ]
                [ Html.h2 [] [ Html.text "!!!Unimplemented!!!" ]
                , Html.pre [] [ Html.text (reason ++ "\n") ]
                , Html.text "Program so far"
                , explain_program p
                ]

        _ ->
            Html.div []
                [ Html.pre [ Html.Attributes.style "color" Pallete.red ] [ Html.text (stringify_error e) ]
                ]


explain_struct : AST.StructDefnition -> Html.Html msg
explain_struct str =
    Html.span []
        [ Html.text "Structure with name "
        , Html.text (AST.stringify_fullname str.name.thing)
        , Html.ul []
            (str.fields
                |> List.map
                    (\f ->
                        Html.li []
                            [ Html.text "field "
                            , Html.text (Language.stringify_identifier f.name)
                            , Html.text " of type "
                            , Html.text (AST.stringify_fullname f.typename.thing)
                            ]
                    )
            )
        ]


explain_enum_field : AST.EnumField -> Html.Html msg
explain_enum_field field =
    if List.length field.args > 0 then
        Html.span []
            [ Html.text field.name
            , Html.text " with args "
            , Html.ul []
                (field.args |> List.map (\f -> stringify_fullname f.thing)|> List.map Html.text |> List.map (\s -> Html.li [] [ s ]))
            ]

    else
        Html.text field.name


explain_enum : AST.EnumDefinition -> Html.Html msg
explain_enum enum =
    Html.span []
        [ Html.text ("Enum with name " ++ stringify_fullname enum.name.thing ++ " and fields")
        , Html.ul
            []
            (enum.fields |> List.map explain_enum_field |> List.map (\el -> Html.li [] [ el ]))
        ]


explain_program : AST.Program -> Html.Html msg
explain_program prog =
    let
        imports =
            Util.collapsable (Html.text "Imports") (Html.ul [] (List.map (\s -> Html.li [] [ Html.text s.thing ]) prog.imports))

        funcs =
            Util.collapsable (Html.text "Global Functions")
                (Html.ul []
                    (List.map
                        (\f ->
                            Html.li []
                                [ Util.collapsable (Html.code [] [ Html.text (stringify_fullname f.name.thing), syntaxify_fheader f.header ]) (explain_statments f.statements)
                                ]
                        )
                        prog.global_functions
                    )
                )

        typedefs =
            Util.collapsable (Html.text "Global typedefs")
                (Html.ul []
                    (List.map
                        (\f ->
                            Html.li []
                                [ explain_typedef f ]
                        )
                        prog.global_typedefs
                    )
                )
    in
    Html.div [ style "font-size" "14px" ]
        [ Html.h4 [] [ Html.text ("Module: " ++ Maybe.withDefault "[No name]" prog.module_name) ]
        , imports
        , funcs
        , typedefs
        ]


explain_typedef : TypeDefinitionType -> Html.Html msg
explain_typedef tt =
    case tt of
        StructDefType s ->
            Util.collapsable
                (Html.code []
                    [ Html.text (AST.stringify_fullname s.name.thing)
                    ]
                )
                (explain_struct s)

        EnumDefType s ->
            Util.collapsable
                (Html.code []
                    [ Html.text (AST.stringify_fullname s.name.thing)
                    ]
                )
                (explain_enum s)

        AliasDefType s ->
            explain_alias s


explain_alias : AliasDefinition -> Html.Html msg
explain_alias ad =
    Html.pre []
        [ Html.text "Type alias of "
        , Html.text (AST.stringify_fullname ad.name.thing)
        , Html.text " to "
        , Html.text (AST.stringify_fullname ad.alias_to.thing)
        ]


tab : Html.Html msg
tab =
    Html.text "    "


tabs : Int -> Html.Html msg
tabs number =
    Html.text (String.repeat number "    ")


stringify_error : ParserCommon.Error -> String
stringify_error e =
    case e of
        ParserCommon.NoModuleNameGiven ->
            "No Module Name Given. The First non comment line in a program must be `module module_name`"

        ParserCommon.NonStringImport location ->
            "I expected a string literal as an import but got this nonsense instead\n" ++ Util.show_source_view location

        ParserCommon.Unimplemented _ reason ->
            "Unimplemented: " ++ reason

        ParserCommon.NeededMoreTokens why ->
            "Couldnt end because I needed more tokens: " ++ why

        ParserCommon.UnknownOuterLevelObject loc ->
            "The only things allowed at this point are `import`, a variable or a function definition, or a type definition (struct, alias, enum)\n" ++ Util.show_source_view loc

        ParserCommon.ExpectedNameAfterFn loc ->
            "Expected a name after the fn keyword to name a function. Something like `fn name()` \n" ++ Util.show_source_view loc

        ParserCommon.ExpectedOpenParenAfterFn s loc ->
            "Expected a close paren after the fn name `fn " ++ s ++ "()` \n" ++ Util.show_source_view loc

        ParserCommon.ExpectedToken explanation loc ->
            explanation ++ "\n" ++ Util.show_source_view loc

        ParserCommon.ExpectedTypeName loc ->
            "Expected a type name here.\nDid you maybe use a keyword like `return`, `fn`, `var`? You can't do that\n" ++ Util.show_source_view loc

        ParserCommon.ExpectedEndOfArgListOrComma loc ->
            "Expected a comma to continue arg list or a close paren to end it\n" ++ Util.show_source_view loc

        ParserCommon.FailedTypeParse tpe ->
            case tpe of
                ParserCommon.Idk loc ->
                    "Failed to parse type\n" ++ Util.show_source_view loc

                ParserCommon.UnexpectedTokenInTypesGenArgList loc ->
                    "Unexpexted otken in types generic arg list \n" ++ Util.show_source_view loc

        ParserCommon.FailedNamedTypeParse tpe ->
            case tpe of
                ParserCommon.TypeError tp ->
                    stringify_error (ParserCommon.FailedTypeParse tp)

                ParserCommon.NameError loc ne ->
                    "Failed to parse name of name: Type. " ++ ne ++ "\n" ++ Util.show_source_view loc

        ParserCommon.KeywordNotAllowedHere loc ->
            "This Keyword is not allowed here\n" ++ Util.show_source_view loc

        ParserCommon.FailedExprParse er ->
            case er of
                ParserCommon.IdkExpr loc s ->
                    "Failed to parse expr: " ++ s ++ "\n" ++ Util.show_source_view loc

                ParserCommon.ParenWhereIDidntWantIt loc ->
                    "I was expecting an expression but I found this parenthesis instead\n" ++ Util.show_source_view loc

        ParserCommon.ExpectedFunctionBody loc got ->
            "Expected a `{` to start the function body but got `" ++ Lexer.syntaxify_token got ++ "`\n" ++ Util.show_source_view loc

        ParserCommon.RequireInitilizationWithValue loc ->
            "When you are initilizaing something `var a: Type = xyz you need that = xyz or else that thing is unitialized\n" ++ Util.show_source_view loc

        ParserCommon.UnknownThingWhileParsingFuncCallOrAssignment loc ->
            "I was parsing the statements of a function (specifically an assignment or function call) and found something random\n" ++ Util.show_source_view loc

        ParserCommon.FailedFuncCallParse er ->
            case er of
                ParserCommon.IdkFuncCall loc s ->
                    "Failed to parse a function call: " ++ s ++ "\n" ++ Util.show_source_view loc

                ParserCommon.ExpectedAnotherArgument loc ->
                    "I expected another argument after this comma\n" ++ Util.show_source_view loc

        ParserCommon.ExpectedOpenCurlyForFunction loc ->
            "I expected an opening curly to start a function body\n" ++ Util.show_source_view loc

        ParserCommon.ExpectedNameAfterDot loc ->
            "I expected another name after this dot. ie `a.b.c` but got " ++ Util.show_source_view_not_line loc ++ "\n" ++ Util.show_source_view loc

        ParserCommon.FailedBlockParse er ->
            case er of
                ParserCommon.None ->
                    "Statement Parse Error"

        ParserCommon.UnexpectedTokenInGenArgList loc ->
            "Unexpected Token in generic arg list\n" ++ Util.show_source_view loc

        ParserCommon.ExpectedNameForStruct loc ->
            "I expected a name for a structure here but all i got was\n" ++ Util.show_source_view loc

        ParserCommon.UnknownTokenInEnumBody loc ->
            "Unexpected token in enum body\n" ++ Util.show_source_view loc

        ParserCommon.ExpectedCloseParenInEnumField loc ->
            "I got to the end of the line without a ). Enum fields should look like `Field(Type1, Type2)`\n" ++ Util.show_source_view loc

        ParserCommon.ExpectedEqualInTypeDeclaration loc ->
            "I expected an = like `type Name =` \n" ++ Util.show_source_view loc


explain_expression : AST.Expression -> Html.Html msg
explain_expression expr =
    case expr of
        AST.NameLookup nwargs ->
            Html.span [] [ Html.text ("name look up of `" ++ stringify_fullname nwargs.thing ++ "`") ]

        AST.FunctionCallExpr fcall ->
            Html.span []
                [ Html.text "Calling function: "
                , Html.text (AST.stringify_fullname fcall.thing.fname.thing)
                , Html.text " with args "
                , Html.ul [] (fcall.thing.args |> List.map (\a -> Html.li [] [ explain_expression a.thing ]))
                ]

        AST.LiteralExpr lt s ->
            case lt of
                Language.StringLiteral ->
                    Html.span [] [ Html.text ("String Literal: " ++ s) ]

                Language.BooleanLiteral ->
                    Html.span [] [ Html.text ("Boolean Literal: " ++ s) ]

                Language.NumberLiteral ->
                    Html.span [] [ Html.text ("Number Literal: " ++ s) ]

        AST.Parenthesized e ->
            Html.span [] [ Html.text "(", explain_expression e.thing, Html.text ")" ]

        AST.InfixExpr lhs rhs op ->
            Html.span [] [ Html.text ("Infix op: " ++ Language.stringify_infix_op op), Html.ul [] [ Html.li [] [ explain_expression lhs.thing ], Html.li [] [ explain_expression rhs.thing ] ] ]


explain_statement : AST.Statement -> Html.Html msg
explain_statement s =
    case s of
        AST.ReturnStatement expr ->
            Html.span []
                [ Html.text "return: "
                , case expr of
                    Just e ->
                        explain_expression e.thing

                    Nothing ->
                        Html.text "Nothing"
                ]

        AST.CommentStatement src ->
            Html.span [] [ Html.text "// ", Html.text src ]

        AST.InitilizationStatement name expr ->
            Html.span [] [ Html.text ("Initialize `" ++ Language.stringify_identifier name.name ++ "` of type " ++ AST.stringify_fullname name.typename.thing ++ " to "), explain_expression expr.thing ]

        AST.AssignmentStatement name expr ->
            Html.span [] [ Html.text ("assigning " ++ Language.stringify_identifier name ++ " with "), explain_expression expr.thing ]

        AST.FunctionCallStatement fcal ->
            Html.span []
                [ Html.text ("call the function " ++ AST.stringify_fullname fcal.thing.fname.thing ++ " with args:")
                , Html.ul []
                    (fcal.thing.args
                        |> List.map (\n -> Html.li [] [ explain_expression n.thing ])
                    )
                ]

        AST.IfStatement expr block ->
            Html.span [] [ Html.text "If statement, checks (", explain_expression expr.thing, Html.text ") then does", explain_statments block ]

        AST.WhileStatement expr block ->
            Html.span [] [ Html.text "While statement, checks (", explain_expression expr.thing, Html.text ") then does", explain_statments block ]


explain_statments : List AST.Statement -> Html.Html msg
explain_statments statements =
    Html.ul [] (List.map (\s -> explain_statement s) statements |> List.map (\s -> Html.li [] [ Html.pre [] [ s ] ]))
