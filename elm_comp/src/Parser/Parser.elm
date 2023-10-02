module Parser.Parser exposing (..)

import Language
import Parser.AST as AST exposing (..)
import Parser.ExpressionParser as ExpressionParser exposing (..)
import Parser.Lexer as Lexer exposing (Token, TokenType(..))
import Parser.ParserCommon as ParserCommon exposing (..)
import Result
import Util exposing (escape_result)


parse : List Lexer.Token -> Result Error AST.Program
parse toks =
    let
        base_program : AST.Program
        base_program =
            { module_name = Nothing
            , imports = []
            , global_functions = []
            , global_structs = []
            , global_enums = []
            , needs_more = Just "Need at least a `module name` line"
            , src_tokens = toks
            }
    in
    parse_find_module_kw |> ParseFn |> rec_parse toks base_program


parse_possibly_constrained_fullname_after_type : NameWithSquareArgsTodo -> FullName -> ParseStep -> ParseRes
parse_possibly_constrained_fullname_after_type todo fn ps =
    let
        todo_with_constraint : ExprParseTodo
        todo_with_constraint res =
            res
                |> Result.mapError (\e -> FailedExprParse e |> Error)
                |> Result.andThen (\expr -> todo (Constrained fn expr |> Ok) |> Ok)
                |> escape_result
    in
    case Debug.log "possibly" ps.tok.typ of
        WhereToken ->
            parse_expr todo_with_constraint |> ParseFn |> Next ps.prog

        _ ->
            reapply_token_or_fail (todo (Ok fn)) ps


parse_possibly_constrained_fullname : NameWithSquareArgsTodo -> ParseStep -> ParseRes
parse_possibly_constrained_fullname todo_after ps =
    let
        todo : NameWithSquareArgsTodo
        todo res =
            res
                |> Result.mapError (\e -> Error e)
                |> Result.andThen (\fname -> parse_possibly_constrained_fullname_after_type todo_after fname |> ParseFn |> Next ps.prog |> Ok)
                |> escape_result
    in
    parse_full_name todo ps


parse_struct_fields : AST.FullName -> List AST.UnqualifiedTypeWithName -> ParseStep -> ParseRes
parse_struct_fields name list ps =
    let
        prog =
            ps.prog

        me_as_struct =
            AST.StructDefnition name list

        todo : NamedTypeParseTodo
        todo res =
            case res of
                Err e ->
                    FailedNamedTypeParse e |> Error

                Ok nt ->
                    parse_struct_fields name (List.append list [ nt ]) |> ParseFn |> Next ps.prog
    in
    case ps.tok.typ of
        CloseCurly ->
            parse_outer_scope |> ParseFn |> Next { prog | global_structs = List.append prog.global_structs [ me_as_struct ] }

        NewlineToken ->
            parse_struct_fields name list |> ParseFn |> Next ps.prog

        _ ->
            parse_named_type todo ps


parse_struct : ParseStep -> ParseRes
parse_struct ps =
    let
        todo : NameWithSquareArgsTodo
        todo res =
            case res of
                Err e ->
                    Error e

                Ok name ->
                    parse_struct_fields name []
                        |> ParseFn
                        |> Next ps.prog
                        |> parse_expected_token "{ to start a structure defintion" OpenCurly
                        |> ParseFn
                        |> Next ps.prog
    in
    case ps.tok.typ of
        Symbol _ ->
            parse_full_name todo ps

        _ ->
            Error (ExpectedNameForStruct ps.tok.loc)


parse_enum_field_arg_list_close_or_continue : EnumField -> EnumDefinition -> ParseStep -> ParseRes
parse_enum_field_arg_list_close_or_continue ef edef ps =
    case ps.tok.typ of
        CommaToken ->
            parse_enum_field_arg_list ef edef |> ParseFn |> Next ps.prog

        CloseParen ->
            parse_enum_body { edef | fields = List.append edef.fields [ ef ] } |> ParseFn |> Next ps.prog

        NewlineToken ->
            ExpectedCloseParenInEnumField ps.tok.loc |> Error

        _ ->
            UnknownTokenInEnumBody ps.tok.loc |> Error


parse_enum_field_arg_list : EnumField -> EnumDefinition -> ParseStep -> ParseRes
parse_enum_field_arg_list ef edef ps =
    let
        todo : NameWithSquareArgsTodo
        todo res =
            res
                |> Result.mapError (\e -> Error e)
                |> Result.andThen (\fn -> parse_enum_field_arg_list_close_or_continue (add_arg_to_enum_field ef fn) edef |> ParseFn |> Next ps.prog |> Ok)
                |> escape_result
    in
    parse_full_name todo ps


parse_enum_plain_symbol_or_more : String -> EnumDefinition -> ParseStep -> ParseRes
parse_enum_plain_symbol_or_more s edef ps =
    case ps.tok.typ of
        NewlineToken ->
            parse_enum_body { edef | fields = List.append edef.fields [ EnumField s [] ] } |> ParseFn |> Next ps.prog

        OpenParen ->
            parse_enum_field_arg_list (EnumField s []) edef |> ParseFn |> Next ps.prog

        _ ->
            UnknownTokenInEnumBody ps.tok.loc |> Error


parse_enum_body : EnumDefinition -> ParseStep -> ParseRes
parse_enum_body edef ps =
    let
        prog =
            ps.prog
    in
    case ps.tok.typ of
        Symbol s ->
            parse_enum_plain_symbol_or_more s edef |> ParseFn |> Next ps.prog

        CloseCurly ->
            parse_outer_scope |> ParseFn |> Next { prog | global_enums = List.append prog.global_enums [ edef ] }

        NewlineToken ->
            parse_enum_body edef |> ParseFn |> Next ps.prog

        _ ->
            UnknownTokenInEnumBody ps.tok.loc |> Error


parse_enum : ParseStep -> ParseRes
parse_enum ps =
    let
        todo_with_full_name : NameWithSquareArgsTodo
        todo_with_full_name res =
            case res of
                Err e ->
                    Error e

                Ok fn ->
                    parse_enum_body (EnumDefinition fn [])
                        |> ParseFn
                        |> Next ps.prog
                        |> parse_expected_token "Expected `{` to start an enum body" OpenCurly
                        |> ParseFn
                        |> Next ps.prog
    in
    parse_full_name todo_with_full_name ps


parse_outer_scope : ParseStep -> ParseRes
parse_outer_scope ps =
    case ps.tok.typ of
        Keyword kwt ->
            case kwt of
                Language.FnKeyword ->
                    Next ps.prog (ParseFn parse_global_fn)

                Language.StructKeyword ->
                    parse_struct |> ParseFn |> Next ps.prog

                Language.EnumKeyword ->
                    parse_enum |> ParseFn |> Next ps.prog

                _ ->
                    Error (Unimplemented ps.prog "Parsing other outer keywords")

        NewlineToken ->
            Next ps.prog (ParseFn parse_outer_scope)

        CommentToken _ ->
            Next ps.prog (ParseFn parse_outer_scope)

        _ ->
            Error (Unimplemented ps.prog "Parsing outer non function things")



-- no gen arg list


parse_typename : NameWithSquareArgsTodo -> ParseStep -> ParseRes
parse_typename todo ps =
    let
        todo_with_type_and_args : NameWithSquareArgsTodo
        todo_with_type_and_args res =
            case res of
                Err e ->
                    Error e

                Ok nt ->
                    todo <| Ok nt

        todo_with_type_and_args_ref : NameWithSquareArgsTodo
        todo_with_type_and_args_ref res =
            case res of
                Err e ->
                    Error e

                Ok nt ->
                    todo <| Ok (ReferenceToFullName nt)
    in
    case ps.tok.typ of
        ReferenceToken ->
            parse_typename todo_with_type_and_args_ref |> ParseFn |> Next ps.prog

        _ ->
            parse_full_name todo_with_type_and_args ps


parse_named_type_type : String -> NamedTypeParseTodo -> ParseStep -> ParseRes
parse_named_type_type valname todo ps =
    let
        todo_with_type : NameWithSquareArgsTodo
        todo_with_type res =
            case res of
                Err e ->
                    Error e

                Ok t ->
                    UnqualifiedTypeWithName (AST.SingleIdentifier valname) t |> Ok |> todo
    in
    parse_possibly_constrained_fullname todo_with_type ps



-- case ps.tok.typ of
--     Symbol typename ->
--         TypeWithName (BaseName valname) (Basic (BaseName typename) |> VariableTypename) |> Ok |> todo
--     _ ->
--         Error (Unimplemented ps.prog "When parsing name: Type if Type is not a symbol")


parse_consume_this : TokenType -> ParseFn -> ParseStep -> ParseRes
parse_consume_this what todo ps =
    if ps.tok.typ == what then
        parse_consume_this what todo |> ParseFn |> Next ps.prog

    else
        extract_fn todo ps


parse_named_type : NamedTypeParseTodo -> ParseStep -> ParseRes
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


parse_global_fn_fn_call_args : (Result FuncCallParseError FunctionCall -> ParseRes) -> FunctionCall -> StatementParseTodo -> ParseStep -> ParseRes
parse_global_fn_fn_call_args todo fcall statement_todo ps =
    let
        what_to_do_with_expr : Result ExprParseError Expression -> ParseRes
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
        what_to_do_with_expr : Result ExprParseError Expression -> ParseRes
        what_to_do_with_expr res =
            case res of
                Err e ->
                    Error (FailedExprParse e)

                Ok expr ->
                    todo (Ok (ReturnStatement (Just expr)))
                        |> parse_expected_token ("Expected newline after end of this return expression. Hint: I think im returning `" ++ stringify_expression expr ++ "`") NewlineToken
                        |> ParseFn
                        |> Next ps.prog
    in
    case ps.tok.typ of
        NewlineToken -> todo (ReturnStatement Nothing |> Ok)
        CommentToken _ -> todo (ReturnStatement Nothing |> Ok)
        _ ->
            reapply_token (ParseFn (parse_expr what_to_do_with_expr)) ps


parse_initilization_statement : StatementParseTodo -> Qualifier -> UnqualifiedTypeWithName -> ParseStep -> ParseRes
parse_initilization_statement todo qual nt ps =
    let
        newtype =
            make_qualified_typewithname nt qual

        todo_with_expr : Result ExprParseError Expression -> ParseRes
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


parse_global_fn_assignment : Identifier -> StatementParseTodo -> ParseStep -> ParseRes
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


parse_global_fn_assignment_or_fn_call_qualified_name : Identifier -> StatementParseTodo -> ParseStep -> ParseRes
parse_global_fn_assignment_or_fn_call_qualified_name name fdef ps =
    case ps.tok.typ of
        Symbol s ->
            Next ps.prog (ParseFn (parse_statement_assignment_or_fn_call (append_identifier name s) fdef))

        _ ->
            Error (ExpectedNameAfterDot ps.tok.loc)


parse_statement_assignment_or_fn_call : Identifier -> StatementParseTodo -> ParseStep -> ParseRes
parse_statement_assignment_or_fn_call name statement_todo ps =
    let
        todo_with_funccall : FuncCallExprTodo
        todo_with_funccall res =
            case res of
                Err e ->
                    Error (FailedFuncCallParse e)

                Ok fcall ->
                    statement_todo (Ok (FunctionCallStatement fcall))

        what_todo_with_type : NameWithSquareArgsTodo
        what_todo_with_type res =
            case res of
                Err e ->
                    Error e

                Ok t ->
                    parse_initilization_statement statement_todo Constant (UnqualifiedTypeWithName name t) |> ParseFn |> Next ps.prog
    in
    case ps.tok.typ of
        DotToken ->
            parse_global_fn_assignment_or_fn_call_qualified_name name statement_todo |> ParseFn |> Next ps.prog

        OpenParen ->
            parse_global_fn_fn_call_args todo_with_funccall (AST.FunctionCall (NameWithoutArgs name) []) statement_todo
                |> ParseFn
                |> Next ps.prog

        TypeSpecifier ->
            parse_typename what_todo_with_type |> ParseFn |> Next ps.prog

        AssignmentToken ->
            parse_global_fn_assignment name statement_todo |> ParseFn |> Next ps.prog

        _ ->
            Error (UnknownThingWhileParsingFuncCallOrAssignment ps.tok.loc)


parse_while_statement : StatementParseTodo -> ParseStep -> ParseRes
parse_while_statement what_todo_with_statement ps =
    let
        what_todo_after_block : Expression -> Result StatementParseError (List Statement) -> ParseRes
        what_todo_after_block expr res =
            case res of
                Err e ->
                    Error (FailedBlockParse e)

                Ok block ->
                    what_todo_with_statement (Ok (WhileStatement expr block))

        what_todo_with_expr : ExprParseTodo
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


parse_if_statement : StatementParseTodo -> ParseStep -> ParseRes
parse_if_statement what_todo_with_statement ps =
    let
        what_todo_after_block : Expression -> Result StatementParseError (List Statement) -> ParseRes
        what_todo_after_block expr res =
            case res of
                Err e ->
                    Error (FailedBlockParse e)

                Ok block ->
                    what_todo_with_statement (Ok (IfStatement expr block))

        what_todo_with_expr : ExprParseTodo
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


parse_block_statements : List Statement -> StatementBlockParseTodo -> ParseStep -> ParseRes
parse_block_statements statements todo_with_block ps =
    let
        what_todo_with_statement : Result StatementParseError Statement -> ParseRes
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
                Language.ReturnKeyword ->
                    parse_global_fn_return_statement what_todo_with_statement |> ParseFn |> Next ps.prog

                Language.VarKeyword ->
                    parse_named_type todo_if_var |> ParseFn |> Next ps.prog

                Language.IfKeyword ->
                    parse_if_statement what_todo_with_statement |> ParseFn |> Next ps.prog

                Language.WhileKeyword ->
                    parse_while_statement what_todo_with_statement |> ParseFn |> Next ps.prog

                _ ->
                    Error (KeywordNotAllowedHere ps.tok.loc)

        CommentToken c ->
            parse_block_statements (List.append statements [ CommentStatement c ]) todo_with_block |> ParseFn |> Next ps.prog

        Symbol s ->
            parse_statement_assignment_or_fn_call (SingleIdentifier s) what_todo_with_statement |> ParseFn |> Next ps.prog

        CloseCurly ->
            todo_with_block (Ok statements)

        NewlineToken ->
            parse_block_statements statements todo_with_block |> ParseFn |> Next ps.prog

        _ ->
            Error (Unimplemented ps.prog ("parsing global function statements like this one:\n" ++ Util.show_source_view ps.tok.loc))


parse_global_function_body : FullName -> FunctionHeader -> ParseStep -> ParseRes
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
                    Next { prog | global_functions = List.append prog.global_functions [ AST.FunctionDefinition fname header block ], needs_more = Nothing } (ParseFn parse_outer_scope)
    in
    case ps.tok.typ of
        OpenCurly ->
            parse_block_statements [] what_todo_with_block |> ParseFn |> Next ps.prog

        _ ->
            Error (ExpectedOpenCurlyForFunction ps.tok.loc)


parse_global_fn_return : FullName -> FunctionHeader -> ParseStep -> ParseRes
parse_global_fn_return fname header_so_far ps =
    let
        what_to_do_with_ret_type : NameWithSquareArgsTodo
        what_to_do_with_ret_type typ_res =
            case typ_res of
                Err e ->
                    Error e

                Ok typ ->
                    parse_global_function_body fname { header_so_far | return_type = Just typ }
                        |> ParseFn
                        |> Next ps.prog
    in
    case ps.tok.typ of
        ReturnSpecifier ->
            parse_typename what_to_do_with_ret_type |> ParseFn |> Next ps.prog

        OpenCurly ->
            reapply_token (parse_global_function_body fname header_so_far |> ParseFn) ps

        _ ->
            Error (ExpectedFunctionBody ps.tok.loc ps.tok.typ)


parse_fn_def_arg_list_comma_or_close : List QualifiedTypeWithName -> FullName -> ParseStep -> ParseRes
parse_fn_def_arg_list_comma_or_close args fname ps =
    case ps.tok.typ of
        CommaToken ->
            parse_fn_definition_arg_list_or_close args fname |> ParseFn |> Next ps.prog

        CloseParen ->
            parse_global_fn_return fname { args = args, return_type = Nothing } |> ParseFn |> Next ps.prog

        _ ->
            Error (ExpectedEndOfArgListOrComma ps.tok.loc)


parse_fn_definition_arg_list_or_close : List QualifiedTypeWithName -> FullName -> ParseStep -> ParseRes
parse_fn_definition_arg_list_or_close args_sofar fname ps =
    let
        todo : NamedTypeParseTodo
        todo res =
            case res of
                Err e ->
                    Error (FailedNamedTypeParse e)

                Ok nt ->
                    parse_fn_def_arg_list_comma_or_close (List.append args_sofar [ make_qualified_typewithname nt Constant ]) fname |> ParseFn |> Next ps.prog
    in
    case ps.tok.typ of
        Symbol _ ->
            reapply_token (parse_named_type todo |> ParseFn) ps

        CloseParen ->
            parse_global_fn_return fname { args = args_sofar, return_type = Nothing } |> ParseFn |> Next ps.prog

        _ ->
            Error (Unimplemented ps.prog ("Failing to close func param list: name = " ++ stringify_fullname fname))


parse_fn_definition_open_paren : FullName -> ParseStep -> ParseRes
parse_fn_definition_open_paren fname ps =
    case ps.tok.typ of
        OpenParen ->
            parse_fn_definition_arg_list_or_close [] fname |> ParseFn |> Next ps.prog

        _ ->
            Error (ExpectedOpenParenAfterFn (stringify_fullname fname) ps.tok.loc)


parse_global_fn : ParseStep -> ParseRes
parse_global_fn ps =
    let
        todo_with_name : NameWithSquareArgsTodo
        todo_with_name res =
            case res of
                Err e ->
                    Error e

                Ok n ->
                    parse_fn_definition_open_paren n |> ParseFn |> Next ps.prog
    in
    case ps.tok.typ of
        Symbol _ ->
            parse_full_name todo_with_name ps

        _ ->
            Error (ExpectedNameAfterFn ps.tok.loc)


parse_get_import_name : ParseStep -> ParseRes
parse_get_import_name ps =
    let
        prog =
            ps.prog
    in
    case ps.tok.typ of
        Lexer.Literal Language.StringLiteral s ->
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

                Language.StructKeyword ->
                    parse_struct |> ParseFn |> Next ps.prog

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


rec_parse : List Token -> AST.Program -> ParseFn -> Result Error AST.Program
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



-- _ ->
--     Debug.todo "syntaxify statement"
