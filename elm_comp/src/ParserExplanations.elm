module ParserExplanations exposing (..)

import Html
import Html.Attributes exposing (style)
import Language exposing (TypeName(..), make_qualified_typewithname)
import Lexer
import Pallete
import ParserCommon
import Util
import Language exposing (stringify_name_lookup_type)



-- Syntaxifications ==========================================


syntaxify_namedarg : Language.QualifiedTypeWithName -> List (Html.Html msg)
syntaxify_namedarg na =
    [ symbol_highlight (Language.stringify_name na.name)
    , Html.text ": "
    , Html.span [] [ syntaxify_type na.typename ]
    ]


syntaxify_type : Language.TypeName -> Html.Html msg
syntaxify_type name =
    Html.span [ style "color" Pallete.blue ]
        [ Html.text (Language.stringify_type_name name)
        ]


syntaxify_unqualled_type : Language.UnqualifiedTypeName -> Html.Html msg
syntaxify_unqualled_type name =
    Html.span [ style "color" Pallete.blue ]
        [ Html.text (Language.stringify_utname name)
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


syntaxify_expression : Language.ASTExpression -> Html.Html msg
syntaxify_expression expr =
    case expr of
        Language.NameWithArgsLookup n ->
            symbol_highlight (Language.stringify_name_lookup_type n)

        Language.FunctionCallExpr fcall ->
            Html.span []
                [ symbol_highlight (Language.stringify_name fcall.fname)
                , Html.text "("
                , Html.span [] (fcall.args |> List.map (\arg -> syntaxify_expression arg) |> List.intersperse (Html.text ", "))
                , Html.text ")"
                ]

        Language.Parenthesized e ->
            Html.span [] [ Html.text "(", syntaxify_expression e, Html.text ")" ]

        Language.LiteralExpr lt s ->
            case lt of
                Language.StringLiteral ->
                    Html.span [] [ syntaxify_string_literal s ]

                Language.NumberLiteral ->
                    Html.span [] [ syntaxify_number_literal s ]

                Language.BooleanLiteral ->
                    Html.span [] [ syntaxify_number_literal s ]

        Language.InfixExpr lhs rhs op ->
            Html.span [] [ syntaxify_expression lhs, Html.text (Language.stringify_infix_op op), syntaxify_expression rhs ]


syntaxify_fheader : Language.ASTFunctionHeader -> Html.Html msg
syntaxify_fheader header =
    let
        pretty_gen_arg_list : Html.Html msg
        pretty_gen_arg_list =
            case List.length header.generic_args of
                0 ->
                    Html.span [] []

                _ ->
                    Html.span []
                        [ Html.text "["
                        , Html.span []
                            (header.generic_args
                                |> List.map (\t -> syntaxify_unqualled_type t)
                                |> List.intersperse (Html.text ", ")
                            )
                        , Html.text "]"
                        ]

        pretty_arg_lst : List (Html.Html msg)
        pretty_arg_lst =
            List.concat (List.intersperse [ Html.text ", " ] (List.map syntaxify_namedarg header.args))

        lis =
            List.concat [ [ pretty_gen_arg_list, Html.text "(" ], pretty_arg_lst, [ Html.text ")" ] ]

        ret : Html.Html msg
        ret =
            Html.span []
                (case header.return_type of
                    Just typ ->
                        [ Html.span [] [ Html.text " 🡒 ", Html.span [] [ syntaxify_type typ ] ] ]

                    Nothing ->
                        [ Html.text " " ]
                )
    in
    Html.span [] (List.append lis [ ret ])


syntaxify_statement : Int -> Language.ASTStatement -> Html.Html msg
syntaxify_statement indentation_level s =
    let
        indent =
            tabs indentation_level
    in
    case s of
        Language.ReturnStatement expr ->
            Html.span []
                [ tabs indentation_level
                , syntaxify_keyword "return "
                , syntaxify_expression expr
                , Html.text "\n"
                ]

        Language.InitilizationStatement taname expr ->
            let
                qual =
                    case taname.typename of
                        Language.VariableTypename _ ->
                            "var "

                        Language.ConstantTypename _ ->
                            ""

                        Language.NonQualified _ ->
                            ""
            in
            Html.span [] (List.concat [ [ indent, syntaxify_keyword qual ], syntaxify_namedarg taname, [ Html.text " = ", syntaxify_expression expr, Html.text "\n" ] ])

        Language.CommentStatement src ->
            Html.span [ style "color" Pallete.gray ] [ indent, Html.text ("// " ++ src), Html.text "\n" ]

        Language.AssignmentStatement name expr ->
            Html.span [] [ tab, symbol_highlight (Language.stringify_name name), Html.text " = ", syntaxify_expression expr, Html.text "\n" ]

        Language.FunctionCallStatement fcal ->
            Html.span []
                [ indent
                , symbol_highlight (Language.stringify_name fcal.fname)
                , Html.text "("
                , Html.span [] (fcal.args |> List.map (\e -> syntaxify_expression e) |> List.intersperse (Html.span [] [ Html.text ", " ]))
                , Html.text ")"
                , Html.text "\n"
                ]

        Language.IfStatement expr block ->
            collapsing_block indentation_level (Html.span [] [ syntaxify_keyword "if ", syntaxify_expression expr ]) block


syntaxify_function : Int -> Language.ASTFunctionDefinition -> List (Html.Html msg)
syntaxify_function indentation fdef =
    let
        header =
            Html.span []
                [ syntaxify_keyword "fn "
                , symbol_highlight fdef.name
                , syntaxify_fheader fdef.header
                ]
    in
    [ collapsing_block indentation header fdef.statements, Html.text "\n" ]


syntaxify_program : ParserCommon.Program -> Html.Html msg
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
                , prog.imports |> List.map (\name -> [ syntaxify_keyword "import ", syntaxify_string_literal name, Html.text "\n" ]) |> List.concat
                , List.repeat 2 (Html.text "\n")
                , prog.global_structs |> List.map (\s -> syntaxify_struct 0 s)
                , prog.global_functions |> List.map (\f -> syntaxify_function 0 f) |> List.concat
                ]
            )
        ]


syntaxify_struct : Int -> ParserCommon.ASTStructDefnition -> Html.Html msg
syntaxify_struct indent struct =
    let
        header =
            syntaxify_unqualled_type struct.name

        names =
            struct.fields
                |> List.map (\f -> make_qualified_typewithname f Language.Constant)
                |> List.map syntaxify_namedarg
                |> List.map (\f -> Html.span [] [ tabs (indent + 1), Html.span [] f, Html.text "\n" ])
                |> Html.div []
    in
    Html.div []
        [ tabs indent
        , syntaxify_keyword "struct "
        , header
        , Html.text " {\n"
        , names
        , Html.text "}\n\n"
        ]


syntaxify_block : Int -> List Language.ASTStatement -> Html.Html msg
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


collapsing_block : Int -> Html.Html msg -> List Language.ASTStatement -> Html.Html msg
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
                [ Html.h3 [] [ Html.text "Parser Error" ]
                , Html.pre [ Html.Attributes.style "color" Pallete.red ] [ Html.text (stringify_error e) ]
                ]


explain_struct : ParserCommon.ASTStructDefnition -> Html.Html msg
explain_struct str =
    Html.span []
        [ Html.text "Structure with name "
        , Html.text (Language.stringify_utname str.name)
        , Html.ul []
            (str.fields
                |> List.map
                    (\f ->
                        Html.li []
                            [ Html.text "field "
                            , Html.text (Language.stringify_name f.name)
                            , Html.text " of type "
                            , Html.text (Language.stringify_utname f.typename)
                            ]
                    )
            )
        ]


explain_program : ParserCommon.Program -> Html.Html msg
explain_program prog =
    let
        imports =
            Util.collapsable (Html.text "Imports") (Html.ul [] (List.map (\s -> Html.li [] [ Html.text s ]) prog.imports))

        funcs =
            Util.collapsable (Html.text "Global Functions")
                (Html.ul []
                    (List.map
                        (\f ->
                            Html.li []
                                [ Util.collapsable (Html.code [] [ Html.text f.name, syntaxify_fheader f.header ]) (explain_statments f.statements)
                                ]
                        )
                        prog.global_functions
                    )
                )

        structs =
            Util.collapsable (Html.text "Global structures")
                (Html.ul []
                    (List.map
                        (\f ->
                            Html.li []
                                [ Util.collapsable
                                    (Html.code []
                                        [ Html.text (Language.stringify_utname <| f.name)
                                        ]
                                    )
                                    (explain_struct f)
                                ]
                        )
                        prog.global_structs
                    )
                )
    in
    Html.div [ style "font-size" "14px" ]
        [ Html.h4 [] [ Html.text ("Module: " ++ Maybe.withDefault "[No name]" prog.module_name) ]
        , imports
        , funcs
        , structs
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


explain_expression : Language.ASTExpression -> Html.Html msg
explain_expression expr =
    case expr of

        Language.NameWithArgsLookup nwargs ->
            Html.span [] [Html.text ("name look up of `"++stringify_name_lookup_type nwargs++"`")]

        Language.FunctionCallExpr fcall ->
            Html.span []
                [ Html.text "Calling function: "
                , Html.text (Language.stringify_name fcall.fname)
                , Html.text " with args "
                , Html.ul [] (fcall.args |> List.map (\a -> Html.li [] [ explain_expression a ]))
                ]

        Language.LiteralExpr lt s ->
            case lt of
                Language.StringLiteral ->
                    Html.span [] [ Html.text ("String Literal: " ++ s) ]

                Language.BooleanLiteral ->
                    Html.span [] [ Html.text ("Boolean Literal: " ++ s) ]

                Language.NumberLiteral ->
                    Html.span [] [ Html.text ("Number Literal: " ++ s) ]

        Language.Parenthesized e ->
            Html.span [] [ Html.text "(", explain_expression e, Html.text ")" ]

        Language.InfixExpr lhs rhs op ->
            Html.span [] [ Html.text ("Infix op: " ++ Language.stringify_infix_op op), Html.ul [] [ Html.li [] [ explain_expression lhs ], Html.li [] [ explain_expression rhs ] ] ]


explain_statement : Language.ASTStatement -> Html.Html msg
explain_statement s =
    case s of
        Language.ReturnStatement expr ->
            Html.span [] [ Html.text "return: ", explain_expression expr ]

        Language.CommentStatement src ->
            Html.span [] [ Html.text "// ", Html.text src ]

        Language.InitilizationStatement name expr ->
            Html.span [] [ Html.text ("Initialize `" ++ Language.stringify_name name.name ++ "` of type " ++ Language.stringify_type_name name.typename ++ " to "), explain_expression expr ]

        Language.AssignmentStatement name expr ->
            Html.span [] [ Html.text ("assigning " ++ Language.stringify_name name ++ " with "), explain_expression expr ]

        Language.FunctionCallStatement fcal ->
            Html.span []
                [ Html.text ("call the function " ++ Language.stringify_name fcal.fname ++ " with args:")
                , Html.ul []
                    (fcal.args
                        |> List.map (\n -> Html.li [] [ explain_expression n ])
                    )
                ]

        Language.IfStatement expr block ->
            Html.span [] [ Html.text "If statement, checks (", explain_expression expr, Html.text ") then does", explain_statments block ]


explain_statments : List Language.ASTStatement -> Html.Html msg
explain_statments statements =
    Html.ul [] (List.map (\s -> explain_statement s) statements |> List.map (\s -> Html.li [] [ Html.pre [] [ s ] ]))
