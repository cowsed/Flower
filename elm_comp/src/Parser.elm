module Parser exposing (..)

import ExpressionParser exposing (..)
import Html exposing (text)
import Html.Attributes exposing (style)
import Language exposing (..)
import Lexer exposing (Token, TokenType(..), syntaxify_token)
import Pallete
import ParserCommon exposing (..)
import Util


parse : List Lexer.Token -> Result Error ParserCommon.Program
parse toks =
    let
        base_program : ParserCommon.Program
        base_program =
            { module_name = Nothing
            , imports = []
            , global_functions = []
            , needs_more = Just "Need at least a `module name` line"
            , src_tokens = toks
            }
    in
    parse_find_module_kw |> ParseFn |> rec_parse toks base_program


parse_type : (Result TypeParseError UnqualifiedTypeName -> ParseRes) -> ParseStep -> ParseRes
parse_type todo ps =
    case ps.tok.typ of
        Symbol s ->
            todo (Ok (Basic (Language.BaseName s)))

        _ ->
            Error (ExpectedTypeName ps.tok.loc)


parse_named_type_type : String -> (Result NamedTypeParseError TypeWithName -> ParseRes) -> ParseStep -> ParseRes
parse_named_type_type valname todo ps =
    -- parse the Type of `name: Type`
    case ps.tok.typ of
        Symbol typename ->
            TypeWithName (BaseName valname) (Basic (BaseName typename) |> VariableTypename) |> Ok |> todo

        _ ->
            Error (Unimplemented ps.prog "When parsing name: Type if Type is not a symbol")


parse_named_type : (Result NamedTypeParseError TypeWithName -> ParseRes) -> ParseStep -> ParseRes
parse_named_type todo ps =
    -- parse things of the form `name: Type
    let
        after_colon valname =
            ParseFn (parse_named_type_type valname todo)
    in
    case ps.tok.typ of
        Symbol valname ->
            parse_expected_token "Expected `:` to split betweem value name and type" Lexer.TypeSpecifier (after_colon valname |> Next ps.prog) |> ParseFn |> Next ps.prog

        _ ->
            Error (ExpectedToken "expected a symbol name like `a` or `name` for something like `a: Type`" ps.tok.loc)


parse_until : TokenType -> ParseFn -> ParseStep -> ParseRes
parse_until typ after ps =
    if typ == ps.tok.typ then
        Next ps.prog after

    else
        Next ps.prog (ParseFn (parse_until typ after))


parse_outer : ParseStep -> ParseRes
parse_outer ps =
    case ps.tok.typ of
        Keyword kwt ->
            case kwt of
                Language.FnKeyword ->
                    Next ps.prog (ParseFn parse_global_fn)

                _ ->
                    Error (Unimplemented ps.prog "Parsing outer non fn keywords")

        NewlineToken ->
            Next ps.prog (ParseFn parse_outer)

        CommentToken _ ->
            Next ps.prog (ParseFn parse_outer)

        _ ->
            Error (Unimplemented ps.prog "Parsing outer non function things")


parse_global_fn_fn_call_args : (Result FuncCallParseError ASTFunctionCall -> ParseRes) -> ASTFunctionCall -> ASTFunctionDefinition -> ParseStep -> ParseRes
parse_global_fn_fn_call_args todo fcall fdef ps =
    let
        what_to_do_with_expr : Result ExprParseError ASTExpression -> ParseRes
        what_to_do_with_expr res =
            case res of
                Err e ->
                    Error (FailedExprParse e)

                Ok expr ->
                    ExpressionParser.parse_func_call_continue_or_end todo { fcall | args = List.append fcall.args [ expr ] }
                        |> ParseFn
                        |> Next ps.prog
    in
    case ps.tok.typ of
        CloseParen ->
            parse_global_fn_statements { fdef | statements = List.append fdef.statements [ FunctionCallStatement fcall ] } |> ParseFn |> Next ps.prog

        _ ->
            reapply_token (ParseFn (parse_expr what_to_do_with_expr)) ps


parse_global_fn_return_statement : ASTFunctionDefinition -> ParseStep -> ParseRes
parse_global_fn_return_statement fdef ps =
    let
        what_to_do_with_expr : Result ExprParseError ASTExpression -> ParseRes
        what_to_do_with_expr res =
            case res of
                Err e ->
                    Error (FailedExprParse e)

                Ok expr ->
                    parse_global_fn_statements { fdef | statements = List.append fdef.statements [ ReturnStatement expr ] }
                        |> ParseFn
                        |> Next ps.prog
                        |> parse_expected_token ("Expected newline after end of this return expression. Hint: I think im returning `" ++ stringify_expression expr ++ "`") NewlineToken
                        |> ParseFn
                        |> Next ps.prog
    in
    reapply_token (ParseFn (parse_expr what_to_do_with_expr)) ps


parse_initilization_statement : Qualifier -> ASTFunctionDefinition -> TypeWithName -> ParseStep -> ParseRes
parse_initilization_statement qual fdef nt ps =
    let
        newtype =
            { nt | typename = make_qualified_typename qual (remove_type_qualifier nt.typename) }

        todo_with_expr : Result ExprParseError ASTExpression -> ParseRes
        todo_with_expr res =
            case res of
                Err e ->
                    Error (FailedExprParse e)

                Ok expr ->
                    Next ps.prog (ParseFn (parse_global_fn_statements { fdef | statements = List.append fdef.statements [ InitilizationStatement newtype expr ] }))
    in
    case ps.tok.typ of
        AssignmentToken ->
            Next ps.prog (ParseFn (parse_expr todo_with_expr))

        NewlineToken ->
            Error (RequireInitilizationWithValue ps.tok.loc)

        _ ->
            Error (Unimplemented ps.prog "what happens if no = after var a: Type = ")


parse_global_fn_assignment : Name -> ASTFunctionDefinition -> ParseStep -> ParseRes
parse_global_fn_assignment name fdef ps =
    let
        after_expr_parse res =
            case res of
                Err e ->
                    Error (FailedExprParse e)

                Ok expr ->
                    parse_global_fn_statements { fdef | statements = List.append fdef.statements [ AssignmentStatement name expr ] } |> ParseFn |> Next ps.prog
    in
    parse_expr after_expr_parse ps


parse_global_fn_assignment_or_fn_call_qualified_name : Name -> ASTFunctionDefinition -> ParseStep -> ParseRes
parse_global_fn_assignment_or_fn_call_qualified_name name fdef ps =
    case ps.tok.typ of
        Symbol s ->
            Next ps.prog (ParseFn (parse_global_fn_assignment_or_fn_call (append_name name s) fdef))

        _ ->
            Error (ExpectedNameAfterDot ps.tok.loc)


parse_global_fn_assignment_or_fn_call : Name -> ASTFunctionDefinition -> ParseStep -> ParseRes
parse_global_fn_assignment_or_fn_call name fdef ps =
    let
        todo : FuncCallExprTodo
        todo res =
            case res of
                Err e ->
                    Error (FailedFuncCallParse e)

                Ok fcall ->
                    parse_global_fn_statements { fdef | statements = List.append fdef.statements [ FunctionCallStatement fcall ] }
                        |> ParseFn
                        |> Next ps.prog

        what_todo_with_type : Result TypeParseError UnqualifiedTypeName -> ParseRes
        what_todo_with_type res =
            case res of
                Err e ->
                    FailedTypeParse e |> Error

                Ok t ->
                    parse_initilization_statement Constant fdef (TypeWithName name (NonQualified t)) |> ParseFn |> Next ps.prog
    in
    case ps.tok.typ of
        DotToken ->
            Next ps.prog (ParseFn (parse_global_fn_assignment_or_fn_call_qualified_name name fdef))

        OpenParen ->
            parse_global_fn_fn_call_args todo (ASTFunctionCall name []) fdef
                |> ParseFn
                |> Next ps.prog

        TypeSpecifier ->
            parse_type what_todo_with_type |> ParseFn |> Next ps.prog

        AssignmentToken ->
            parse_global_fn_assignment name fdef |> ParseFn |> Next ps.prog

        _ ->
            Error (UnknownThingWhileParsingFuncCallOrAssignment ps.tok.loc)


type alias NamedTypeParseTodo =
    Result NamedTypeParseError TypeWithName -> ParseRes


parse_global_fn_statements : ASTFunctionDefinition -> ParseStep -> ParseRes
parse_global_fn_statements fdef ps =
    let
        todo_if_var : NamedTypeParseTodo
        todo_if_var res =
            case res of
                Ok nt ->
                    parse_initilization_statement Variable fdef nt |> ParseFn |> Next ps.prog

                Err e ->
                    Error (FailedNamedTypeParse e)
    in
    case ps.tok.typ of
        Keyword kwt ->
            case kwt of
                ReturnKeyword ->
                    parse_global_fn_return_statement fdef |> ParseFn |> Next ps.prog

                VarKeyword ->
                    parse_named_type todo_if_var |> ParseFn |> Next ps.prog

                _ ->
                    Error (KeywordNotAllowedHere ps.tok.loc)

        CommentToken c ->
            parse_global_fn_statements { fdef | statements = List.append fdef.statements [ CommentStatement c ] } |> ParseFn |> Next ps.prog

        Symbol s ->
            Next ps.prog (ParseFn (parse_global_fn_assignment_or_fn_call (BaseName s) fdef))

        CloseCurly ->
            let
                old_prog =
                    ps.prog

                prog =
                    { old_prog | global_functions = List.append old_prog.global_functions [ fdef ], needs_more = Nothing }
            in
            Next prog (ParseFn parse_outer)

        NewlineToken ->
            parse_global_fn_statements fdef |> ParseFn |> Next ps.prog

        _ ->
            Error (Unimplemented ps.prog ("parsing global function statements like this one:\n" ++ Util.show_source_view ps.tok.loc))


parse_global_function_body : String -> ASTFunctionHeader -> ParseStep -> ParseRes
parse_global_function_body fname header ps =
    let
        fdef =
            ASTFunctionDefinition fname header []

        prog =
            ps.prog
    in
    case ps.tok.typ of
        OpenCurly ->
            parse_global_fn_statements fdef |> ParseFn |> Next prog

        _ ->
            Error (ExpectedOpenCurlyForFunction ps.tok.loc)


type alias TypeParseTodo =
    Result TypeParseError UnqualifiedTypeName -> ParseRes


parse_global_fn_return : String -> ASTFunctionHeader -> ParseStep -> ParseRes
parse_global_fn_return fname header_so_far ps =
    let
        what_to_do_with_ret_type : TypeParseTodo
        what_to_do_with_ret_type typ_res =
            case typ_res of
                Err e ->
                    Error (FailedTypeParse e)

                Ok typ ->
                    parse_global_function_body fname { header_so_far | return_type = Just (NonQualified typ) }
                        |> ParseFn
                        |> Next ps.prog
    in
    case ps.tok.typ of
        ReturnSpecifier ->
            parse_type what_to_do_with_ret_type |> ParseFn |> Next ps.prog

        OpenCurly ->
            reapply_token (parse_global_function_body fname header_so_far |> ParseFn) ps

        _ ->
            Error (ExpectedFunctionBody ps.tok.loc ps.tok.typ)


parse_fn_def_arg_list_comma_or_close : List TypeWithName -> String -> ParseStep -> ParseRes
parse_fn_def_arg_list_comma_or_close args fname ps =
    case ps.tok.typ of
        CommaToken ->
            parse_fn_definition_arg_list_or_close args fname |> ParseFn |> Next ps.prog

        CloseParen ->
            parse_global_fn_return fname { args = args, return_type = Nothing } |> ParseFn |> Next ps.prog

        _ ->
            Error (ExpectedEndOfArgListOrComma ps.tok.loc)


type alias NameAndTypeParseTodo =
    Result NamedTypeParseError TypeWithName -> ParseRes


parse_fn_definition_arg_list_or_close : List TypeWithName -> String -> ParseStep -> ParseRes
parse_fn_definition_arg_list_or_close args_sofar fname ps =
    let
        todo : NameAndTypeParseTodo
        todo res =
            case res of
                Err e ->
                    Error (FailedNamedTypeParse e)

                Ok nt ->
                    parse_fn_def_arg_list_comma_or_close (List.append args_sofar [ nt ]) fname |> ParseFn |> Next ps.prog
    in
    case ps.tok.typ of
        Symbol _ ->
            reapply_token (parse_named_type todo |> ParseFn) ps

        CloseParen ->
            parse_global_fn_return fname { args = args_sofar, return_type = Nothing } |> ParseFn |> Next ps.prog

        _ ->
            Error (Unimplemented ps.prog ("Failing to close func param list: name = " ++ fname))


parse_fn_definition_open_paren : String -> ParseStep -> ParseRes
parse_fn_definition_open_paren fname ps =
    case ps.tok.typ of
        OpenParen ->
            parse_fn_definition_arg_list_or_close [] fname |> ParseFn |> Next ps.prog

        _ ->
            Error (ExpectedOpenParenAfterFn fname ps.tok.loc)


parse_global_fn : ParseStep -> ParseRes
parse_global_fn ps =
    let
        prog =
            ps.prog
    in
    case ps.tok.typ of
        Symbol fname ->
            parse_fn_definition_open_paren fname |> ParseFn |> Next { prog | needs_more = Just ("I was in the middle of parsing the function `" ++ fname ++ "` definition when the file ended. Did you forget a closing bracket?") }

        _ ->
            Error (ExpectedNameAfterFn ps.tok.loc)


parse_get_import_name : ParseStep -> ParseRes
parse_get_import_name ps =
    let
        prog =
            ps.prog
    in
    case ps.tok.typ of
        Literal Language.StringLiteral s ->
            Next { prog | imports = List.append prog.imports [ s ] } (ParseFn parse_find_imports)

        _ ->
            Error (NonStringImport ps.tok.loc)


parse_find_imports : ParseStep -> ParseRes
parse_find_imports ps =
    case ps.tok.typ of
        Keyword kt ->
            case kt of
                Language.ImportKeyword ->
                    Next ps.prog (ParseFn parse_get_import_name)

                Language.FnKeyword ->
                    Next ps.prog (ParseFn parse_global_fn)

                _ ->
                    Error (UnknownOuterLevelObject ps.tok.loc)

        CommentToken _ ->
            Next ps.prog (ParseFn parse_find_imports)

        NewlineToken ->
            Next ps.prog (ParseFn parse_find_imports)

        _ ->
            Error (UnknownOuterLevelObject ps.tok.loc)


parse_find_module_name : ParseStep -> ParseRes
parse_find_module_name ps =
    let
        prog =
            ps.prog
    in
    case ps.tok.typ of
        Symbol s ->
            Next { prog | module_name = Just s, needs_more = Nothing } (ParseFn parse_find_imports)

        _ ->
            Error NoModuleNameGiven


parse_find_module_kw : ParseStep -> ParseRes
parse_find_module_kw ps =
    let
        prog =
            ps.prog
    in
    case ps.tok.typ of
        Keyword kw ->
            if kw == Language.ModuleKeyword then
                Next { prog | needs_more = Just "needs module name" } (ParseFn parse_find_module_name)

            else
                Error NoModuleNameGiven

        _ ->
            Next ps.prog (ParseFn parse_find_module_kw)


rec_parse : List Token -> ParserCommon.Program -> ParseFn -> Result Error ParserCommon.Program
rec_parse toks prog_sofar fn =
    let
        head =
            List.head toks

        res tok =
            extract_fn fn { tok = tok, prog = prog_sofar }
    in
    case head of
        Just tok ->
            case res tok of
                Error e ->
                    Err e

                Next prog_now next_fn ->
                    rec_parse (Util.always_tail toks) prog_now next_fn

        Nothing ->
            case prog_sofar.needs_more of
                Nothing ->
                    Ok prog_sofar

                Just reason ->
                    Err (NeededMoreTokens reason)


stringify_error : Error -> String
stringify_error e =
    case e of
        NoModuleNameGiven ->
            "No Module Name Given. The First non comment line in a program must be `module module_name`"

        NonStringImport location ->
            "I expected a string literal as an import but got this nonsense instead\n" ++ Util.show_source_view location

        Unimplemented _ reason ->
            "Unimplemented: " ++ reason

        NeededMoreTokens why ->
            "Couldnt end because I needed more tokens: " ++ why

        UnknownOuterLevelObject loc ->
            "The only things allowed at this point are `import`, a variable or a function definition\n" ++ Util.show_source_view loc

        ExpectedNameAfterFn loc ->
            "Expected a name after the fn keyword to name a function. Something like `fn name()` \n" ++ Util.show_source_view loc

        ExpectedOpenParenAfterFn s loc ->
            "Expected a close paren after the fn name `fn " ++ s ++ "()` \n" ++ Util.show_source_view loc

        ExpectedToken explanation loc ->
            explanation ++ "\n" ++ Util.show_source_view loc

        ExpectedTypeName loc ->
            "Expected a type name here.\nDid you maybe use a keyword like `return`, `fn`, `var`? You can't do that\n" ++ Util.show_source_view loc

        ExpectedEndOfArgListOrComma loc ->
            "Expected a comma to continue arg list or a close paren to end it\n++Util.show_source_view loc" ++ Util.show_source_view loc

        FailedTypeParse tpe ->
            case tpe of
                Idk loc ->
                    "Failed to parse type\n" ++ Util.show_source_view loc

        FailedNamedTypeParse tpe ->
            case tpe of
                TypeError tp ->
                    stringify_error (FailedTypeParse tp)

                NameError loc ne ->
                    "Failed to parse name of name: Type. " ++ ne ++ "\n" ++ Util.show_source_view loc

        KeywordNotAllowedHere loc ->
            "This Keyword is not allowed here\n" ++ Util.show_source_view loc

        FailedExprParse er ->
            case er of
                IdkExpr loc s ->
                    "Failed to parse expr: " ++ s ++ "\n" ++ Util.show_source_view loc

                ParenWhereIDidntWantIt loc ->
                    "I was expecting an expression but I found this parenthesis instead\n" ++ Util.show_source_view loc

        ExpectedFunctionBody loc got ->
            "Expected a `{` to start the function body but got `" ++ syntaxify_token got ++ "`\n" ++ Util.show_source_view loc

        RequireInitilizationWithValue loc ->
            "When you are initilizaing something `var a: Type = xyz you need that = xyz or else that thing is unitialized\n" ++ Util.show_source_view loc

        UnknownThingWhileParsingFuncCallOrAssignment loc ->
            "I was parsing the statements of a function (specifically an assignment or function call) and found something random\n" ++ Util.show_source_view loc

        FailedFuncCallParse er ->
            case er of
                IdkFuncCall loc s ->
                    "Failed to parse a function call: " ++ s ++ "\n" ++ Util.show_source_view loc

                ExpectedAnotherArgument loc ->
                    "I expected another argument after this comma\n" ++ Util.show_source_view loc

        ExpectedOpenCurlyForFunction loc ->
            "I expected an opening curly to start a function body\n" ++ Util.show_source_view loc

        ExpectedNameAfterDot loc ->
            "I expected another name after this dot. ie `a.b.c` but got " ++ Util.show_source_view_not_line loc ++ "\n" ++ Util.show_source_view loc


explain_error : Error -> Html.Html msg
explain_error e =
    case e of
        Unimplemented p reason ->
            Html.div [ Html.Attributes.style "color" Pallete.red ]
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


syntax_highlight_type : TypeName -> Html.Html msg
syntax_highlight_type name =
    Html.span [ style "color" Pallete.blue ]
        [ text (Language.stringify_type_name name)
        ]


htmlify_namedarg : TypeWithName -> List (Html.Html msg)
htmlify_namedarg na =
    [ symbol_highlight (Language.stringify_name na.name)
    , text ": "
    , Html.span [] [ syntax_highlight_type na.typename ]
    ]


syntaxify_fheader : ASTFunctionHeader -> Html.Html msg
syntaxify_fheader header =
    let
        pretty_arg_lst : List (Html.Html msg)
        pretty_arg_lst =
            List.concat (List.intersperse [ text ", " ] (List.map htmlify_namedarg header.args))

        lis =
            List.concat [ [ text "(" ], pretty_arg_lst, [ text ")" ] ]

        ret : Html.Html msg
        ret =
            Html.span []
                (case header.return_type of
                    Just typ ->
                        [ Html.span [] [ text " 🡒 ", Html.span [] [ syntax_highlight_type typ ] ], text " " ]

                    Nothing ->
                        [ text " " ]
                )
    in
    Html.span [] (List.append lis [ ret ])


explain_expression : ASTExpression -> Html.Html msg
explain_expression expr =
    case expr of
        NameLookup n ->
            text ("Name look up: " ++ stringify_name n)

        FunctionCallExpr fcall ->
            Html.span []
                [ text "Calling function: "
                , text (stringify_name fcall.fname)
                , text " with args "
                , Html.ul [] (fcall.args |> List.map (\a -> Html.li [] [ explain_expression a ]))
                ]

        LiteralExpr lt s ->
            case lt of
                StringLiteral ->
                    Html.span [] [ text ("String Literal: " ++ s) ]

                BooleanLiteral ->
                    Html.span [] [ text ("Boolean Literal: " ++ s) ]

                NumberLiteral ->
                    Html.span [] [ text ("Number Literal: " ++ s) ]

        Parenthesized e ->
            Html.span [] [ text "(", explain_expression e, text ")" ]

        InfixExpr lhs rhs op ->
            Html.span [] [ text ("Infix op: " ++ stringify_infix_op op), Html.ul [] [ Html.li [] [ explain_expression lhs ], Html.li [] [ explain_expression rhs ] ] ]


explain_statement : ASTStatement -> Html.Html msg
explain_statement s =
    case s of
        ReturnStatement expr ->
            Html.span [] [ text "return: ", explain_expression expr ]

        CommentStatement src ->
            Html.span [] [ text "// ", text src ]

        InitilizationStatement name expr ->
            Html.span [] [ text ("Initialize `" ++ stringify_name name.name ++ "` of type " ++ stringify_type_name name.typename ++ " to "), explain_expression expr ]

        AssignmentStatement name expr ->
            Html.span [] [ text ("assigning " ++ stringify_name name ++ " with "), explain_expression expr ]

        FunctionCallStatement fcal ->
            Html.span []
                [ text ("call the function " ++ stringify_name fcal.fname ++ " with args:")
                , Html.ul []
                    (fcal.args
                        |> List.map (\n -> Html.li [] [ explain_expression n ])
                    )
                ]

        _ ->
            Debug.todo "explai other statemnts"


explain_statments : List ASTStatement -> Html.Html msg
explain_statments statements =
    Html.ul [] (List.map (\s -> explain_statement s) statements |> List.map (\s -> Html.li [] [ Html.pre [] [ s ] ]))


explain_program : ParserCommon.Program -> Html.Html msg
explain_program prog =
    let
        imports =
            Util.collapsable (Html.text "Imports") (Html.ul [] (List.map (\s -> Html.li [] [ Html.text s ]) prog.imports))

        funcs =
            Util.collapsable (text "Global Functions")
                (Html.ul []
                    (List.map
                        (\f ->
                            Html.li []
                                [ Util.collapsable (Html.code [] [ text f.name, syntaxify_fheader f.header ]) (explain_statments f.statements)
                                ]
                        )
                        prog.global_functions
                    )
                )
    in
    Html.div []
        [ Html.h4 [] [ Html.text ("Module: " ++ Maybe.withDefault "[No name]" prog.module_name) ]
        , imports
        , funcs
        ]


keyword_highlight : String -> Html.Html msg
keyword_highlight s =
    Html.span [ style "color" Pallete.red ] [ text s ]


symbol_highlight : String -> Html.Html msg
symbol_highlight s =
    Html.span [ style "color" Pallete.orange ] [ text s ]


syntaxify_expression : ASTExpression -> Html.Html msg
syntaxify_expression expr =
    case expr of
        NameLookup n ->
            symbol_highlight (stringify_name n)

        FunctionCallExpr fcall ->
            Html.span []
                [ symbol_highlight (stringify_name fcall.fname)
                , text "("
                , Html.span [] (fcall.args |> List.map (\arg -> syntaxify_expression arg) |> List.intersperse (text ", "))
                , text ")"
                ]

        Parenthesized e ->
            Html.span [] [ text "(", syntaxify_expression e, text ")" ]

        LiteralExpr lt s ->
            case lt of
                StringLiteral ->
                    Html.span [] [ string_literal_highlight s ]

                NumberLiteral ->
                    Html.span [] [ number_literal_highlight s ]

                BooleanLiteral ->
                    Html.span [] [ number_literal_highlight s ]

        InfixExpr lhs rhs op ->
            Html.span [] [ syntaxify_expression lhs, text (stringify_infix_op op), syntaxify_expression rhs ]


string_literal_highlight : String -> Html.Html msg
string_literal_highlight s =
    Html.span [ style "color" "DarkSlateBlue" ] [ text ("\"" ++ s ++ "\"") ]


number_literal_highlight : String -> Html.Html msg
number_literal_highlight s =
    Html.span [ style "color" Pallete.aqua ] [ text s ]


tab : Html.Html msg
tab =
    Html.text "    "


syntaxify_statement : ASTStatement -> Html.Html msg
syntaxify_statement s =
    case s of
        ReturnStatement expr ->
            Html.span []
                [ tab
                , keyword_highlight "return "
                , syntaxify_expression expr
                , text "\n"
                ]

        InitilizationStatement taname expr ->
            let
                qual =
                    case taname.typename of
                        VariableTypename _ ->
                            "var "

                        ConstantTypename _ ->
                            ""

                        NonQualified _ ->
                            ""
            in
            Html.span [] (List.concat [ [ tab, keyword_highlight qual ], htmlify_namedarg taname, [ text " = ", syntaxify_expression expr, text "\n" ] ])

        CommentStatement src ->
            Html.span [ style "color" Pallete.gray ] [ tab, text ("// " ++ src), text "\n" ]

        AssignmentStatement name expr ->
            Html.span [] [ tab, symbol_highlight (stringify_name name), text " = ", syntaxify_expression expr, text "\n" ]

        FunctionCallStatement fcal ->
            Html.span []
                [ tab
                , symbol_highlight (stringify_name fcal.fname)
                , text "("
                , Html.span [] (fcal.args |> List.map (\e -> syntaxify_expression e) |> List.intersperse (Html.span [] [ text ", " ]))
                , text ")"
                , text "\n"
                ]

        _ ->
            Debug.todo "syntaxify statement"


collapsing_function : ASTFunctionDefinition -> Html.Html msg
collapsing_function fdef =
    let
        header =
            [ Html.span []
                [ keyword_highlight "fn "
                , symbol_highlight fdef.name
                , syntaxify_fheader fdef.header
                ]
            ]
    in
    if List.length fdef.statements == 0 then
        Html.div [] (List.concat [ header, [ text "{}" ] ])

    else
        Html.details
            [ style "background" Pallete.bg1
            , style "width" "fit-content"
            , style "padding-left" "5px"
            , style "padding-right" "5px"
            , style "border-radius" "10px"
            , Html.Attributes.attribute "open" "true"
            ]
            (List.concat
                [ [ collapsing_function_style
                  , Html.summary
                        [ style "border" "none"
                        , style "cursor" "pointer"
                        ]
                        (List.concat [ header, [ text "{" ] ])
                  ]
                , fdef.statements
                    |> List.map syntaxify_statement
                , [ text "}" ]
                ]
            )


collapsing_function_style : Html.Html msg
collapsing_function_style =
    Html.node "style" [] [ text """
details[open] > summary {
    list-style: none;
}
""" ]


syntaxify_function : ASTFunctionDefinition -> List (Html.Html msg)
syntaxify_function fdef =
    [ collapsing_function fdef ]


syntaxify_program : ParserCommon.Program -> Html.Html msg
syntaxify_program prog =
    Html.code
        [ style "font-size" "15px"
        , style "overflow" "auto"
        , style "height" "100%"
        , style "padding" "4px"
        , style "background-color" Pallete.bg
        , style "border-radius" "8px"
        , style "border-style" "solid"
        , style "border-width" "2px"
        , style "border-color" "black"
        , style "float" "left"
        , style "margin-left" "10px "
        ]
        [ Html.pre []
            (List.concat
                [ [ keyword_highlight "module ", symbol_highlight (Maybe.withDefault "module_name" prog.module_name), text "\n\n" ]
                , prog.imports |> List.map (\name -> [ keyword_highlight "import ", string_literal_highlight name, text "\n" ]) |> List.concat
                , List.repeat 2 (text "\n")
                , prog.global_functions |> List.map syntaxify_function |> List.concat
                ]
            )
        ]
