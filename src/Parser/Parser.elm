module Parser.Parser exposing (..)

import Language.Language as Language exposing (Identifier(..))
import Language.Syntax exposing (KeywordType(..))
import Parser.AST as AST exposing (..)
import Parser.ExpressionParser as ExpressionParser exposing (..)
import Parser.Lexer as Lexer exposing (Token, TokenType(..))
import Parser.ParserCommon exposing (..)
import Result
import Util exposing (escape_result)


parse : List Lexer.Token -> Result Error AST.Program
parse toks =
    let
        base_program : AST.Program
        base_program =
            { module_name = Nothing
            , imports = []
            , global_typedefs = []
            , global_functions = []
            , needs_more = Just "Need at least a `module name` line"
            , src_tokens = toks
            }
    in
    parse_find_module_kw |> ParseFn |> rec_parse toks base_program


parse_possibly_constrained_fullname_after_type : FullNameParseTodo -> FullNameAndLocation -> ParseStep -> ParseRes
parse_possibly_constrained_fullname_after_type todo fn ps =
    let
        todo_with_constraint : ExprParseTodo
        todo_with_constraint res =
            res
                |> Result.mapError (\e -> FailedExprParse e |> Error)
                |> Result.andThen (\expr -> todo (Constrained fn expr |> AST.with_location (Util.merge_sv fn.loc expr.loc) |> Ok) |> Ok)
                |> escape_result
    in
    case ps.tok.typ of
        WhereToken ->
            parse_expr todo_with_constraint |> next_pfn

        _ ->
            reapply_token_or_fail (todo (Ok fn)) ps


parse_possibly_constrained_fullname : FullNameParseTodo -> ParseStep -> ParseRes
parse_possibly_constrained_fullname todo_after ps =
    let
        todo : FullNameParseTodo
        todo res =
            res
                |> Result.mapError (\e -> Error e)
                |> Result.andThen (\fname -> parse_possibly_constrained_fullname_after_type todo_after fname |> next_pfn |> Ok)
                |> escape_result
    in
    parse_fullname todo ps


parse_struct_fields : AST.FullNameAndLocation -> List AST.UnqualifiedTypeWithName -> ParseStep -> ParseRes
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
                    parse_struct_fields name (List.append list [ nt ]) |> next_pfn
    in
    case ps.tok.typ of
        CloseCurly ->
            parse_outer_scope |> ParseFn |> Next { prog | global_typedefs = List.append prog.global_typedefs [ StructDefType me_as_struct ] }

        NewlineToken ->
            parse_struct_fields name list |> next_pfn

        _ ->
            parse_named_type todo ps


parse_struct : ParseStep -> ParseRes
parse_struct ps =
    let
        todo : FullNameParseTodo
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
            parse_fullname todo ps

        _ ->
            Error (ExpectedNameForStruct ps.tok.loc)


parse_enum_field_arg_list_close_or_continue : EnumField -> EnumDefinition -> ParseStep -> ParseRes
parse_enum_field_arg_list_close_or_continue ef edef ps =
    case ps.tok.typ of
        CommaToken ->
            parse_enum_field_arg_list ef edef |> next_pfn

        CloseParen ->
            parse_enum_body { edef | fields = List.append edef.fields [ ef ] } |> next_pfn

        NewlineToken ->
            ExpectedCloseParenInEnumField ps.tok.loc |> Error

        _ ->
            UnknownTokenInEnumBody ps.tok.loc |> Error


parse_enum_field_arg_list : EnumField -> EnumDefinition -> ParseStep -> ParseRes
parse_enum_field_arg_list ef edef ps =
    let
        todo : FullNameParseTodo
        todo res =
            res
                |> Result.mapError (\e -> Error e)
                |> Result.andThen (\fn -> parse_enum_field_arg_list_close_or_continue (add_arg_to_enum_field ef fn) edef |> next_pfn |> Ok)
                |> escape_result
    in
    parse_fullname todo ps


parse_enum_plain_symbol_or_more : String -> EnumDefinition -> ParseStep -> ParseRes
parse_enum_plain_symbol_or_more s edef ps =
    case ps.tok.typ of
        NewlineToken ->
            parse_enum_body { edef | fields = List.append edef.fields [ EnumField s [] ] } |> next_pfn

        OpenParen ->
            parse_enum_field_arg_list (EnumField s []) edef |> next_pfn

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
            parse_enum_plain_symbol_or_more s edef |> next_pfn

        CloseCurly ->
            parse_outer_scope |> ParseFn |> Next { prog | global_typedefs = List.append prog.global_typedefs [ EnumDefType edef ] }

        NewlineToken ->
            parse_enum_body edef |> next_pfn

        _ ->
            UnknownTokenInEnumBody ps.tok.loc |> Error


parse_enum : ParseStep -> ParseRes
parse_enum ps =
    let
        todo_with_full_name : FullNameParseTodo
        todo_with_full_name res =
            case res of
                Err e ->
                    Error e

                Ok fn ->
                    parse_enum_body (AST.EnumDefinition fn [])
                        |> ParseFn
                        |> Next ps.prog
                        |> parse_expected_token "Expected `{` to start an enum body" OpenCurly
                        |> ParseFn
                        |> Next ps.prog
    in
    parse_fullname todo_with_full_name ps


parse_type_declaration_after_first_name : FullNameAndLocation -> FullNameAndLocation -> ParseStep -> ParseRes
parse_type_declaration_after_first_name typname n ps =
    let
        prog =
            ps.prog

        prog_after =
            { prog | global_typedefs = List.append prog.global_typedefs [ AliasDefType (AliasDefinition typname n) ] }
    in
    parse_outer_scope |> ParseFn |> Next prog_after


parse_type_declaration_body : FullNameAndLocation -> ParseStep -> ParseRes
parse_type_declaration_body fname ps =
    let
        after_fn2 : FullNameParseTodo
        after_fn2 res =
            res
                |> Result.mapError (\e -> Error e)
                |> Result.andThen (\fn -> parse_type_declaration_after_first_name fname fn |> next_pfn |> Ok)
                |> escape_result
    in
    parse_possibly_constrained_fullname after_fn2 ps


parse_type_declaration : ParseStep -> ParseRes
parse_type_declaration ps =
    let
        parse_equal : FullNameAndLocation -> ParseStep -> ParseRes
        parse_equal fname pes =
            case pes.tok.typ of
                AssignmentToken ->
                    parse_type_declaration_body fname |> next_pfn

                _ ->
                    ExpectedEqualInTypeDeclaration pes.tok.loc |> Error

        todo_with_full_name : FullNameParseTodo
        todo_with_full_name res =
            res
                |> Result.mapError (\e -> Error e)
                |> Result.andThen (\fn -> parse_equal fn |> next_pfn |> Ok)
                |> escape_result
    in
    parse_fullname todo_with_full_name ps


parse_outer_scope : ParseStep -> ParseRes
parse_outer_scope ps =
    case ps.tok.typ of
        Keyword kwt ->
            case kwt of
                Language.Syntax.FnKeyword ->
                    Next ps.prog (ParseFn parse_global_fn)

                Language.Syntax.StructKeyword ->
                    parse_struct |> next_pfn

                Language.Syntax.EnumKeyword ->
                    parse_enum |> next_pfn

                Language.Syntax.TypeKeyword ->
                    parse_type_declaration |> next_pfn

                _ ->
                    Error (Unimplemented ps.prog "Parsing other outer keywords")

        NewlineToken ->
            Next ps.prog (ParseFn parse_outer_scope)

        CommentToken _ ->
            Next ps.prog (ParseFn parse_outer_scope)

        _ ->
            Error (Unimplemented ps.prog "Parsing outer non function things")




parse_typename : FullNameParseTodo -> ParseStep -> ParseRes
parse_typename outer_todo ps =
    let
        todo_with_type_and_args : FullNameParseTodo
        todo_with_type_and_args res =
            case res of
                Err e ->
                    Error e

                Ok nt ->
                    outer_todo <| Ok nt

        todo_with_type_and_args_ref : FullNameParseTodo
        todo_with_type_and_args_ref res =
            case res of
                Err e ->
                    Error e

                Ok nt ->
                    outer_todo <| Ok (ReferenceToFullName nt |> AST.with_location (Util.merge_sv ps.tok.loc nt.loc))
    in
    case ps.tok.typ of
        ReferenceToken ->
            parse_typename todo_with_type_and_args_ref |> next_pfn

        _ ->
            parse_fullname todo_with_type_and_args ps


parse_named_type_type : String -> NamedTypeParseTodo -> ParseStep -> ParseRes
parse_named_type_type valname todo ps =
    let
        todo_with_type : FullNameParseTodo
        todo_with_type res =
            case res of
                Err e ->
                    Error e

                Ok t ->
                    UnqualifiedTypeWithName (Language.SingleIdentifier valname) t |> Ok |> todo
    in
    parse_possibly_constrained_fullname todo_with_type ps




parse_consume_next : TokenType -> ParseFn -> ParseStep -> ParseRes
parse_consume_next what todo ps =
    if ps.tok.typ == what then
        parse_consume_next what todo |> next_pfn

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
            parse_expected_token "Expected `:` to split betweem value name and type" Lexer.TypeSpecifier (after_colon valname |> Next ps.prog) |> next_pfn

        _ ->
            Error (ExpectedToken "expected a symbol name like `a` or `name` for something like `a: Type`" ps.tok.loc)


parse_until : TokenType -> ParseFn -> ParseStep -> ParseRes
parse_until typ after ps =
    if typ == ps.tok.typ then
        Next ps.prog after

    else
        Next ps.prog (ParseFn (parse_until typ after))




parse_global_fn_return_statement : StatementParseTodo -> ParseStep -> ParseRes
parse_global_fn_return_statement todo ps =
    let
        what_to_do_with_expr : ExprParseTodo
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
        NewlineToken ->
            todo (ReturnStatement Nothing |> Ok)

        CommentToken _ ->
            todo (ReturnStatement Nothing |> Ok)

        _ ->
            reapply_token (ParseFn (parse_expr what_to_do_with_expr)) ps


parse_initilization_statement : StatementParseTodo -> Language.Qualifier -> UnqualifiedTypeWithName -> ParseStep -> ParseRes
parse_initilization_statement todo qual nt ps =
    let
        newtype =
            make_qualified_typewithname nt qual

        todo_with_expr : ExprParseTodo
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


parse_global_fn_assignment_or_fn_call_qualified_name : Util.SourceView  -> Identifier -> StatementParseTodo -> ParseStep -> ParseRes
parse_global_fn_assignment_or_fn_call_qualified_name loc name fdef ps =
    case ps.tok.typ of
        Symbol s ->
            Next ps.prog (ParseFn (parse_statement_assignment_or_fn_call loc (append_identifier name s) fdef))

        _ ->
            Error (ExpectedNameAfterDot ps.tok.loc)


parse_statement_assignment_or_fn_call : Util.SourceView -> Identifier -> StatementParseTodo -> ParseStep -> ParseRes
parse_statement_assignment_or_fn_call id_loc name statement_todo ps =
    let
        todo_with_funccall : FuncCallExprTodo
        todo_with_funccall res =
            case res of
                Err e ->
                    Error (FailedFuncCallParse e)

                Ok fcall ->
                    statement_todo (Ok (FunctionCallStatement fcall))

        what_todo_with_type : FullNameParseTodo
        what_todo_with_type res =
            case res of
                Err e ->
                    Error e

                Ok t ->
                    parse_initilization_statement statement_todo Language.Constant (UnqualifiedTypeWithName name t) |> next_pfn
    in
    case ps.tok.typ of
        DotToken ->
            parse_global_fn_assignment_or_fn_call_qualified_name (Util.merge_sv id_loc ps.tok.loc) name statement_todo |> next_pfn

        OpenParen ->
            ExpressionParser.parse_function_call (NameWithoutArgs name |> AST.with_location ps.tok.loc) todo_with_funccall  
                |> ParseFn
                |> Next ps.prog

        TypeSpecifier ->
            parse_typename what_todo_with_type |> next_pfn

        AssignmentToken ->
            parse_global_fn_assignment name statement_todo |> next_pfn

        _ ->
            Error (UnknownThingWhileParsingFuncCallOrAssignment ps.tok.loc)


parse_while_statement : StatementParseTodo -> ParseStep -> ParseRes
parse_while_statement what_todo_with_statement ps =
    let
        what_todo_after_block : ExpressionAndLocation -> Result StatementParseError (List Statement) -> ParseRes
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
                            ((parse_statements [] (what_todo_after_block expr) |> next_pfn)
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
        what_todo_after_block : ExpressionAndLocation -> Result StatementParseError (List Statement) -> ParseRes
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
                            ((parse_statements [] (what_todo_after_block expr) |> next_pfn)
                                |> parse_expected_token "Expected a `{` to start the body of an if statement." OpenCurly
                                |> ParseFn
                                |> Next ps.prog
                            )
                    )
                --
                |> escape_result
    in
    parse_expr what_todo_with_expr ps


parse_statements : List Statement -> StatementBlockParseTodo -> ParseStep -> ParseRes
parse_statements statements todo_with_block ps =
    let
        what_todo_with_statement : Result StatementParseError Statement -> ParseRes
        what_todo_with_statement res =
            case res of
                Err e ->
                    Error (FailedBlockParse e)

                Ok s ->
                    parse_statements (List.append statements [ s ]) todo_with_block |> next_pfn

        todo_if_var : NamedTypeParseTodo
        todo_if_var res =
            case res of
                Ok nt ->
                    parse_initilization_statement what_todo_with_statement Language.Variable nt |> next_pfn

                Err e ->
                    Error (FailedNamedTypeParse e)
    in
    case ps.tok.typ of
        Keyword kwt ->
            case kwt of
                Language.Syntax.ReturnKeyword ->
                    parse_global_fn_return_statement what_todo_with_statement |> next_pfn

                Language.Syntax.VarKeyword ->
                    parse_named_type todo_if_var |> next_pfn

                Language.Syntax.IfKeyword ->
                    parse_if_statement what_todo_with_statement |> next_pfn

                Language.Syntax.WhileKeyword ->
                    parse_while_statement what_todo_with_statement |> next_pfn

                _ ->
                    Error (KeywordNotAllowedHere ps.tok.loc)

        CommentToken c ->
            parse_statements (List.append statements [ CommentStatement c ]) todo_with_block |> next_pfn

        Symbol s ->
            parse_statement_assignment_or_fn_call ps.tok.loc (SingleIdentifier s) what_todo_with_statement |> next_pfn

        CloseCurly ->
            todo_with_block (Ok statements)

        NewlineToken ->
            parse_statements statements todo_with_block |> next_pfn

        _ ->
            Error (Unimplemented ps.prog ("parsing global function statements like this one:\n" ++ Util.show_source_view ps.tok.loc))


parse_global_function_body : FullNameAndLocation -> FunctionHeader -> ParseStep -> ParseRes
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
            parse_statements [] what_todo_with_block |> next_pfn

        _ ->
            Error (ExpectedOpenCurlyForFunction ps.tok.loc)


parse_global_fn_return_specifier : FullNameAndLocation -> FunctionHeader -> ParseStep -> ParseRes
parse_global_fn_return_specifier fname header_so_far ps =
    let
        what_to_do_with_ret_type : FullNameParseTodo
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
            parse_possibly_constrained_fullname what_to_do_with_ret_type |> next_pfn

        OpenCurly ->
            reapply_token (parse_global_function_body fname header_so_far |> ParseFn) ps

        _ ->
            Error (ExpectedFunctionBody ps.tok.loc ps.tok.typ)


parse_fn_def_arg_list_comma_or_close : List QualifiedTypeWithName -> FullNameAndLocation -> ParseStep -> ParseRes
parse_fn_def_arg_list_comma_or_close args fname ps =
    case ps.tok.typ of
        CommaToken ->
            parse_fn_definition_arg_list_or_close args fname |> next_pfn

        CloseParen ->
            parse_global_fn_return_specifier fname { args = args, return_type = Nothing } |> next_pfn

        _ ->
            Error (ExpectedEndOfArgListOrComma ps.tok.loc)


parse_fn_definition_arg_list_or_close : List QualifiedTypeWithName -> FullNameAndLocation -> ParseStep -> ParseRes
parse_fn_definition_arg_list_or_close args_sofar fname ps =
    let
        todo : NamedTypeParseTodo
        todo res =
            case res of
                Err e ->
                    Error (FailedNamedTypeParse e)

                Ok nt ->
                    parse_fn_def_arg_list_comma_or_close (List.append args_sofar [ make_qualified_typewithname nt Language.Constant ]) fname |> next_pfn
    in
    case ps.tok.typ of
        Symbol _ ->
            reapply_token (parse_named_type todo |> ParseFn) ps

        CloseParen ->
            parse_global_fn_return_specifier fname { args = args_sofar, return_type = Nothing } |> next_pfn

        _ ->
            Error (Unimplemented ps.prog ("Failing to close func param list: name = " ++ stringify_fullname fname.thing))


parse_fn_definition_open_paren : FullNameAndLocation -> ParseStep -> ParseRes
parse_fn_definition_open_paren fname ps =
    case ps.tok.typ of
        OpenParen ->
            parse_fn_definition_arg_list_or_close [] fname |> next_pfn

        _ ->
            Error (ExpectedOpenParenAfterFn (stringify_fullname fname.thing) ps.tok.loc)


parse_global_fn : ParseStep -> ParseRes
parse_global_fn ps =
    let
        todo_with_name : FullNameParseTodo
        todo_with_name res =
            case res of
                Err e ->
                    Error e

                Ok n ->
                    parse_fn_definition_open_paren n |> next_pfn
    in
    case ps.tok.typ of
        Symbol _ ->
            parse_fullname todo_with_name ps

        _ ->
            Error (ExpectedNameAfterFn ps.tok.loc)




parse_find_imports : ParseStep -> ParseRes
parse_find_imports ps =
    let
        parse_get_import_name : ParseStep -> ParseRes
        parse_get_import_name pss =
            let
                prog =
                    pss.prog
            in
            case pss.tok.typ of
                Lexer.Literal Language.StringLiteral s ->
                    Next { prog | imports = List.append prog.imports [ AST.ThingAndLocation s pss.tok.loc ] } (ParseFn parse_find_imports)

                _ ->
                    Error (NonStringImport pss.tok.loc)

    in
    
    case ps.tok.typ of
        Keyword kt ->
            case kt of
                Language.Syntax.ImportKeyword ->
                    Next ps.prog (ParseFn parse_get_import_name)

                Language.Syntax.FnKeyword ->
                    Next ps.prog (ParseFn parse_global_fn)

                Language.Syntax.StructKeyword ->
                    parse_struct |> next_pfn

                Language.Syntax.TypeKeyword ->
                    parse_type_declaration |> next_pfn

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
            if kw == Language.Syntax.ModuleKeyword then
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

                NextNoChange next_fn ->
                    rec_parse (Util.always_tail toks) prog_sofar next_fn

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
