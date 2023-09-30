module Parser exposing (..)

import ExpressionParser exposing (..)
import Html exposing (text)
import Html.Attributes exposing (style)
import Language exposing (..)
import Lexer exposing (Token, TokenType(..), syntaxify_token)
import Pallete
import ParserCommon exposing (..)
import Result
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


type alias TypeParseTodo =
    Result TypeParseError UnqualifiedTypeName -> ParseRes


parse_outer_scope : ParseStep -> ParseRes
parse_outer_scope ps =
    case ps.tok.typ of
        Keyword kwt ->
            case kwt of
                Language.FnKeyword ->
                    Next ps.prog (ParseFn parse_global_fn)

                _ ->
                    Error (Unimplemented ps.prog "Parsing outer non fn keywords")

        NewlineToken ->
            Next ps.prog (ParseFn parse_outer_scope)

        CommentToken _ ->
            Next ps.prog (ParseFn parse_outer_scope)

        _ ->
            Error (Unimplemented ps.prog "Parsing outer non function things")


parse_type_name_gen_arg_list_comma_or_end : TypeParseTodo -> String -> List UnqualifiedTypeName -> ParseStep -> ParseRes
parse_type_name_gen_arg_list_comma_or_end todo base_name gen_list ps =
    let
        todo_with_type : TypeParseTodo
        todo_with_type res =
            case res of
                Err e ->
                    todo (Err e)

                Ok t ->
                    parse_type_name_gen_arg_list_comma_or_end todo base_name (List.append gen_list [ t ]) |> ParseFn |> Next ps.prog

        this_type =
            Generic (BaseName base_name) gen_list
    in
    case ps.tok.typ of
        CommaToken ->
            parse_type_name todo_with_type |> ParseFn |> Next ps.prog

        CloseSquare ->
            todo (Ok this_type)

        _ ->
            Error (Unimplemented ps.prog ("Make an error for unhandled token when parsing generic arg list on a typename\n"++Util.show_source_view ps.tok.loc))


parse_type_name_gen_arg_list_continue_or_end : TypeParseTodo -> String -> List UnqualifiedTypeName -> ParseStep -> ParseRes
parse_type_name_gen_arg_list_continue_or_end todo base_name gen_list ps =
    let
        todo_with_type : TypeParseTodo
        todo_with_type res =
            case res of
                Err e ->
                    todo (Err e)

                Ok t ->
                    parse_type_name_gen_arg_list_comma_or_end todo base_name (List.append gen_list [ t ]) |> ParseFn |> Next ps.prog
    in
    parse_type_name todo_with_type ps


parse_type_name_gen_arg_list_start : TypeParseTodo -> String -> ParseStep -> ParseRes
parse_type_name_gen_arg_list_start todo base_name ps =
    case ps.tok.typ of
        OpenSquare ->
            parse_type_name_gen_arg_list_continue_or_end todo base_name [] |> ParseFn |> Next ps.prog

        _ ->
            reapply_token_or_fail (todo (Ok (Basic (Language.BaseName base_name)))) ps



-- no gen arg list


parse_type_name : TypenameParseTodo -> ParseStep -> ParseRes
parse_type_name todo ps =
    case Debug.log "parsing type " ps.tok.typ of
        Symbol s ->
            parse_type_name_gen_arg_list_start todo s |> ParseFn |> Next ps.prog

        _ ->
            Error (ExpectedTypeName ps.tok.loc)


parse_named_type_type : String -> (Result NamedTypeParseError UnqualifiedTypeWithName -> ParseRes) -> ParseStep -> ParseRes
parse_named_type_type valname todo ps =
    let
        todo_with_type : TypeParseTodo
        todo_with_type res =
            case res of
                Err e ->
                    FailedNamedTypeParse (TypeError e) |> Error

                Ok t ->
                    todo (Ok (UnqualifiedTypeWithName (BaseName valname) t))
    in
    -- parse the Type of `name: Type`
    parse_type_name todo_with_type ps



-- case ps.tok.typ of
--     Symbol typename ->
--         TypeWithName (BaseName valname) (Basic (BaseName typename) |> VariableTypename) |> Ok |> todo
--     _ ->
--         Error (Unimplemented ps.prog "When parsing name: Type if Type is not a symbol")


parse_named_type : (Result NamedTypeParseError UnqualifiedTypeWithName -> ParseRes) -> ParseStep -> ParseRes
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


parse_global_fn_fn_call_args : (Result FuncCallParseError ASTFunctionCall -> ParseRes) -> ASTFunctionCall -> StatementParseTodo -> ParseStep -> ParseRes
parse_global_fn_fn_call_args todo fcall statement_todo ps =
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
            statement_todo (Ok (FunctionCallStatement fcall))

        _ ->
            reapply_token (ParseFn (parse_expr what_to_do_with_expr)) ps


parse_global_fn_return_statement : StatementParseTodo -> ParseStep -> ParseRes
parse_global_fn_return_statement todo ps =
    let
        what_to_do_with_expr : Result ExprParseError ASTExpression -> ParseRes
        what_to_do_with_expr res =
            case res of
                Err e ->
                    Error (FailedExprParse e)

                Ok expr ->
                    todo (Ok (ReturnStatement expr))
                        |> parse_expected_token ("Expected newline after end of this return expression. Hint: I think im returning `" ++ stringify_expression expr ++ "`") NewlineToken
                        |> ParseFn
                        |> Next ps.prog
    in
    reapply_token (ParseFn (parse_expr what_to_do_with_expr)) ps


parse_initilization_statement : StatementParseTodo -> Qualifier -> UnqualifiedTypeWithName -> ParseStep -> ParseRes
parse_initilization_statement todo qual nt ps =
    let
        newtype =
            make_qualified_typewithname nt qual

        todo_with_expr : Result ExprParseError ASTExpression -> ParseRes
        todo_with_expr res =
            case res of
                Err e ->
                    Error (FailedExprParse e)

                Ok expr ->
                    -- Next ps.prog (ParseFn (parse_block_statements { fdef | statements = List.append fdef.statements [ InitilizationStatement newtype expr ] }))
                    todo (Ok (InitilizationStatement newtype expr))
    in
    case ps.tok.typ of
        AssignmentToken ->
            Next ps.prog (ParseFn (parse_expr todo_with_expr))

        NewlineToken ->
            Error (RequireInitilizationWithValue ps.tok.loc)

        _ ->
            Error (Unimplemented ps.prog "what happens if no = after var a: Type = ")


parse_global_fn_assignment : Name -> StatementParseTodo -> ParseStep -> ParseRes
parse_global_fn_assignment name todo ps =
    let
        after_expr_parse res =
            case res of
                Err e ->
                    Error (FailedExprParse e)

                Ok expr ->
                    todo (Ok (AssignmentStatement name expr))
    in
    parse_expr after_expr_parse ps


parse_global_fn_assignment_or_fn_call_qualified_name : Name -> StatementParseTodo -> ParseStep -> ParseRes
parse_global_fn_assignment_or_fn_call_qualified_name name fdef ps =
    case ps.tok.typ of
        Symbol s ->
            Next ps.prog (ParseFn (parse_global_fn_assignment_or_fn_call (append_name name s) fdef))

        _ ->
            Error (ExpectedNameAfterDot ps.tok.loc)


parse_global_fn_assignment_or_fn_call : Name -> StatementParseTodo -> ParseStep -> ParseRes
parse_global_fn_assignment_or_fn_call name statement_todo ps =
    let
        todo_with_funccall : FuncCallExprTodo
        todo_with_funccall res =
            case res of
                Err e ->
                    Error (FailedFuncCallParse e)

                Ok fcall ->
                    statement_todo (Ok (FunctionCallStatement fcall))

        what_todo_with_type : Result TypeParseError UnqualifiedTypeName -> ParseRes
        what_todo_with_type res =
            case res of
                Err e ->
                    FailedTypeParse e |> Error

                Ok t ->
                    parse_initilization_statement statement_todo Constant (UnqualifiedTypeWithName name t) |> ParseFn |> Next ps.prog
    in
    case ps.tok.typ of
        DotToken ->
            parse_global_fn_assignment_or_fn_call_qualified_name name statement_todo |> ParseFn |> Next ps.prog

        OpenParen ->
            parse_global_fn_fn_call_args todo_with_funccall (ASTFunctionCall name []) statement_todo
                |> ParseFn
                |> Next ps.prog

        TypeSpecifier ->
            parse_type_name what_todo_with_type |> ParseFn |> Next ps.prog

        AssignmentToken ->
            parse_global_fn_assignment name statement_todo |> ParseFn |> Next ps.prog

        _ ->
            Error (UnknownThingWhileParsingFuncCallOrAssignment ps.tok.loc)


escape_result : Result er er -> er
escape_result res =
    case res of
        Err e ->
            e

        Ok v ->
            v


parse_if_statement : StatementParseTodo -> ParseStep -> ParseRes
parse_if_statement what_todo_with_statement ps =
    let
        what_todo_after_block : ASTExpression -> Result StatementParseError (List ASTStatement) -> ParseRes
        what_todo_after_block expr res =
            case res of
                Err e ->
                    Error (FailedBlockParse e)

                Ok block ->
                    what_todo_with_statement (Ok (IfStatement expr block))

        what_todo_with_expr : ExprParseWhatTodo
        what_todo_with_expr res =
            res
                |> Result.mapError (\e -> Error (FailedExprParse e))
                -- change err to ParseRes
                |> Result.andThen
                    (\expr ->
                        Ok
                            ((parse_block_statements [] (what_todo_after_block expr) |> ParseFn |> Next ps.prog)
                                |> parse_expected_token "Expected a `{` to start the body of an if statement." OpenCurly
                                |> ParseFn
                                |> Next ps.prog
                            )
                    )
                --
                |> escape_result
    in
    parse_expr what_todo_with_expr ps


parse_block_statements : List ASTStatement -> StatementBlockParseTodo -> ParseStep -> ParseRes
parse_block_statements statements todo_with_block ps =
    let
        what_todo_with_statement : Result StatementParseError ASTStatement -> ParseRes
        what_todo_with_statement res =
            case res of
                Err e ->
                    Error (FailedBlockParse e)

                Ok s ->
                    parse_block_statements (List.append statements [ s ]) todo_with_block |> ParseFn |> Next ps.prog

        todo_if_var : NamedTypeParseTodo
        todo_if_var res =
            case res of
                Ok nt ->
                    parse_initilization_statement what_todo_with_statement Variable nt |> ParseFn |> Next ps.prog

                Err e ->
                    Error (FailedNamedTypeParse e)
    in
    case ps.tok.typ of
        Keyword kwt ->
            case kwt of
                ReturnKeyword ->
                    parse_global_fn_return_statement what_todo_with_statement |> ParseFn |> Next ps.prog

                VarKeyword ->
                    parse_named_type todo_if_var |> ParseFn |> Next ps.prog

                IfKeyword ->
                    parse_if_statement what_todo_with_statement |> ParseFn |> Next ps.prog

                _ ->
                    Error (KeywordNotAllowedHere ps.tok.loc)

        CommentToken c ->
            parse_block_statements (List.append statements [ CommentStatement c ]) todo_with_block |> ParseFn |> Next ps.prog

        Symbol s ->
            parse_global_fn_assignment_or_fn_call (BaseName s) what_todo_with_statement |> ParseFn |> Next ps.prog

        CloseCurly ->
            todo_with_block (Ok statements)

        NewlineToken ->
            parse_block_statements statements todo_with_block |> ParseFn |> Next ps.prog

        _ ->
            Error (Unimplemented ps.prog ("parsing global function statements like this one:\n" ++ Util.show_source_view ps.tok.loc))


parse_global_function_body : String -> ASTFunctionHeader -> ParseStep -> ParseRes
parse_global_function_body fname header ps =
    let
        prog =
            ps.prog

        what_todo_with_block : StatementBlockParseTodo
        what_todo_with_block res =
            case res of
                Err e ->
                    Error (FailedBlockParse e)

                Ok block ->
                    Next { prog | global_functions = List.append prog.global_functions [ ASTFunctionDefinition fname header block ], needs_more = Nothing } (ParseFn parse_outer_scope)
    in
    case ps.tok.typ of
        OpenCurly ->
            parse_block_statements [] what_todo_with_block |> ParseFn |> Next ps.prog

        _ ->
            Error (ExpectedOpenCurlyForFunction ps.tok.loc)


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
            parse_type_name what_to_do_with_ret_type |> ParseFn |> Next ps.prog

        OpenCurly ->
            reapply_token (parse_global_function_body fname header_so_far |> ParseFn) ps

        _ ->
            Error (ExpectedFunctionBody ps.tok.loc ps.tok.typ)


parse_fn_def_arg_list_comma_or_close : List QualifiedTypeWithName -> List UnqualifiedTypeName -> String -> ParseStep -> ParseRes
parse_fn_def_arg_list_comma_or_close args gen_list fname ps =
    case ps.tok.typ of
        CommaToken ->
            parse_fn_definition_arg_list_or_close args gen_list fname |> ParseFn |> Next ps.prog

        CloseParen ->
            parse_global_fn_return fname { generic_args = gen_list, args = args, return_type = Nothing } |> ParseFn |> Next ps.prog

        _ ->
            Error (ExpectedEndOfArgListOrComma ps.tok.loc)


parse_fn_definition_arg_list_or_close : List QualifiedTypeWithName -> List UnqualifiedTypeName -> String -> ParseStep -> ParseRes
parse_fn_definition_arg_list_or_close args_sofar gen_list fname ps =
    let
        todo : NamedTypeParseTodo
        todo res =
            case res of
                Err e ->
                    Error (FailedNamedTypeParse e)

                Ok nt ->
                    parse_fn_def_arg_list_comma_or_close (List.append args_sofar [ make_qualified_typewithname nt Constant ]) gen_list fname |> ParseFn |> Next ps.prog
    in
    case ps.tok.typ of
        Symbol _ ->
            reapply_token (parse_named_type todo |> ParseFn) ps

        CloseParen ->
            parse_global_fn_return fname { generic_args = gen_list, args = args_sofar, return_type = Nothing } |> ParseFn |> Next ps.prog

        _ ->
            Error (Unimplemented ps.prog ("Failing to close func param list: name = " ++ fname))


parse_fn_definition_open_paren : String -> List UnqualifiedTypeName -> ParseStep -> ParseRes
parse_fn_definition_open_paren fname gen_list ps =
    case ps.tok.typ of
        OpenParen ->
            parse_fn_definition_arg_list_or_close [] gen_list fname |> ParseFn |> Next ps.prog

        _ ->
            Error (ExpectedOpenParenAfterFn fname ps.tok.loc)


parse_fn_def_generic_arg_list_comma_or_close : String -> List UnqualifiedTypeName -> ParseStep -> ParseRes
parse_fn_def_generic_arg_list_comma_or_close fname gen_list ps =
    let
        todo_with_typ : Result TypeParseError UnqualifiedTypeName -> ParseRes
        todo_with_typ res =
            case res of
                Err e ->
                    Error (FailedTypeParse e)

                Ok t ->
                    parse_fn_def_generic_arg_list_comma_or_close fname (List.append gen_list [ t ]) |> ParseFn |> Next ps.prog
    in
    case ps.tok.typ of
        CommaToken ->
            parse_type_name todo_with_typ |> ParseFn |> Next ps.prog

        CloseSquare ->
            parse_fn_definition_open_paren fname gen_list |> ParseFn |> Next ps.prog

        _ ->
            Error (UnexpectedTokenInGenArgList ps.tok.loc)


parse_fn_def_generic_arg_list_or_close : String -> List UnqualifiedTypeName -> ParseStep -> ParseRes
parse_fn_def_generic_arg_list_or_close fname gen_list ps =
    let
        todo_with_typ : Result TypeParseError UnqualifiedTypeName -> ParseRes
        todo_with_typ res =
            case res of
                Err e ->
                    Error (FailedTypeParse e)

                Ok t ->
                    parse_fn_def_generic_arg_list_comma_or_close fname (List.append gen_list [ t ]) |> ParseFn |> Next ps.prog
    in
    case ps.tok.typ of
        CloseSquare ->
            parse_fn_definition_open_paren fname gen_list |> ParseFn |> Next ps.prog

        _ ->
            parse_type_name todo_with_typ ps


parse_global_fn_args_or_generics : String -> ParseStep -> ParseRes
parse_global_fn_args_or_generics fname ps =
    let
        prog =
            ps.prog
    in
    case ps.tok.typ of
        OpenParen ->
            parse_fn_definition_arg_list_or_close [] [] fname
                |> ParseFn
                |> Next { prog | needs_more = Just ("I was in the middle of parsing the function `" ++ fname ++ "` definition when the file ended. Did you forget a closing bracket?") }

        OpenSquare ->
            parse_fn_def_generic_arg_list_or_close fname [] |> ParseFn |> Next ps.prog

        _ ->
            Error (Unimplemented ps.prog "what to do what to do ")


parse_global_fn : ParseStep -> ParseRes
parse_global_fn ps =
    case ps.tok.typ of
        Symbol fname ->
            parse_global_fn_args_or_generics fname |> ParseFn |> Next ps.prog

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
            "Expected a comma to continue arg list or a close paren to end it\n" ++ Util.show_source_view loc

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

        FailedBlockParse er ->
            case er of
                None ->
                    "Statement Parse Error"

        UnexpectedTokenInGenArgList loc ->
            "Unexpected Token in generic arg list\n" ++ Util.show_source_view loc


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


htmlify_namedarg : QualifiedTypeWithName -> List (Html.Html msg)
htmlify_namedarg na =
    [ symbol_highlight (Language.stringify_name na.name)
    , text ": "
    , Html.span [] [ syntax_highlight_type na.typename ]
    ]


syntaxify_fheader : ASTFunctionHeader -> Html.Html msg
syntaxify_fheader header =
    let
        pretty_gen_arg_list : Html.Html msg
        pretty_gen_arg_list =
            case List.length header.generic_args of
                0 ->
                    Html.span [] []

                _ ->
                    Html.span []
                        [ text "["
                        , Html.span []
                            (header.generic_args
                                |> List.map (\t -> syntax_highlight_type (NonQualified t))
                                |> List.intersperse (text ", ")
                            )
                        , text "]"
                        ]

        pretty_arg_lst : List (Html.Html msg)
        pretty_arg_lst =
            List.concat (List.intersperse [ text ", " ] (List.map htmlify_namedarg header.args))

        lis =
            List.concat [ [ pretty_gen_arg_list, text "(" ], pretty_arg_lst, [ text ")" ] ]

        ret : Html.Html msg
        ret =
            Html.span []
                (case header.return_type of
                    Just typ ->
                        [ Html.span [] [ text " 🡒 ", Html.span [] [ syntax_highlight_type typ ] ] ]

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

        IfStatement expr block ->
            Html.span [] [ text "If statement, checks", explain_expression expr, text "then does", explain_statments block ]



-- _ ->
--     Debug.todo "explai other statemnts"


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


tabs : Int -> Html.Html msg
tabs number =
    Html.text (String.repeat number "    ")


syntaxify_statement : Int -> ASTStatement -> Html.Html msg
syntaxify_statement indentation_level s =
    let
        indent =
            tabs indentation_level
    in
    case s of
        ReturnStatement expr ->
            Html.span []
                [ tabs indentation_level
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
            Html.span [] (List.concat [ [ indent, keyword_highlight qual ], htmlify_namedarg taname, [ text " = ", syntaxify_expression expr, text "\n" ] ])

        CommentStatement src ->
            Html.span [ style "color" Pallete.gray ] [ indent, text ("// " ++ src), text "\n" ]

        AssignmentStatement name expr ->
            Html.span [] [ tab, symbol_highlight (stringify_name name), text " = ", syntaxify_expression expr, text "\n" ]

        FunctionCallStatement fcal ->
            Html.span []
                [ indent
                , symbol_highlight (stringify_name fcal.fname)
                , text "("
                , Html.span [] (fcal.args |> List.map (\e -> syntaxify_expression e) |> List.intersperse (Html.span [] [ text ", " ]))
                , text ")"
                , text "\n"
                ]

        IfStatement expr block ->
            collapsing_block indentation_level (Html.span [] [ keyword_highlight "if ", syntaxify_expression expr ]) block



-- _ ->
--     Debug.todo "syntaxify statement"


syntaxify_block : Int -> List ASTStatement -> Html.Html msg
syntaxify_block indentation_level states =
    let
        outer_indent =
            tabs indentation_level
    in
    Html.span [] (List.concat [ [ text " {\n" ], states |> List.map (syntaxify_statement (indentation_level + 1)), [ outer_indent, text "}\n" ] ])


collapsing_block : Int -> Html.Html msg -> List ASTStatement -> Html.Html msg
collapsing_block indentation header block =
    let
        indent =
            if indentation == 0 then
                Html.span [] []

            else
                Html.span [ style "padding-left" ".25em" ]
                    [ text (String.repeat (indentation - 1) "    " ++ "  ")
                    ]
    in
    if List.length block == 0 then
        Html.div [] [ tabs indentation, header, text "{}" ]

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
                        , text " {"
                        ]
                  ]
                , block
                    |> List.map (\s -> syntaxify_statement (indentation + 1) s)
                , [ tabs indentation, text "}" ]
                ]
            )


collapsing_block_style : Html.Html msg
collapsing_block_style =
    Html.node "style" [] [ text """
details[open] > summary {
}
""" ]


syntaxify_function : Int -> ASTFunctionDefinition -> List (Html.Html msg)
syntaxify_function indentation fdef =
    let
        header =
            Html.span []
                [ keyword_highlight "fn "
                , symbol_highlight fdef.name
                , syntaxify_fheader fdef.header
                ]
    in
    [ collapsing_block indentation header fdef.statements ]


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
                , prog.global_functions |> List.map (\f -> syntaxify_function 0 f) |> List.concat
                ]
            )
        ]
