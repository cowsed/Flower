module Parser.ExpressionParser exposing (parse_expr, parse_function_call)

import Language.Language exposing (InfixOpType, precedence)
import Parser.AST as AST exposing (Expression(..), ExpressionAndLocation, FullName, FunctionCall, with_location)
import Parser.Lexer as Lexer exposing (TokenType(..), infix_op_from_token)
import Parser.ParserCommon exposing (..)
import Util
import Parser.AST exposing (FullNameAndLocation)
import Parser.AST exposing (FunctionCallAndLocation)
import Parser.Lexer exposing (token_to_str)


merge_infix : ExpressionAndLocation -> ExpressionAndLocation -> InfixOpType -> ExpressionAndLocation
merge_infix lhs rhs op =
    InfixExpr lhs rhs op |> with_location (Util.merge_sv lhs.loc rhs.loc)


parse_expr_check_for_infix : ExpressionAndLocation -> ExprParseTodo -> ParseStep -> ParseRes
parse_expr_check_for_infix lhs outer_todo ps =
    case infix_op_from_token ps.tok of
        Nothing ->
            reapply_token_or_fail (outer_todo (Ok lhs)) ps

        Just op ->
            let
                expr_after_todo : ExprParseTodo
                expr_after_todo res =
                    case res of
                        Err _ ->
                            outer_todo res

                        Ok this_rhs ->
                            case this_rhs.thing of
                                InfixExpr next_lhs next_rhs next_op ->
                                    if precedence next_op >= precedence op then
                                        merge_infix lhs this_rhs op
                                            |> Ok
                                            |> outer_todo

                                    else
                                        merge_infix
                                            (merge_infix lhs next_lhs op)
                                            next_rhs
                                            next_op
                                            |> Ok
                                            |> outer_todo

                                _ ->
                                    outer_todo (Ok (InfixExpr lhs this_rhs op |> AST.with_location (Util.merge_sv lhs.loc this_rhs.loc)))
            in
            parse_expr expr_after_todo |> ParseFn |> Next ps.prog


parse_expr_name_lookup_or_func_call : ExprParseTodo -> FullNameAndLocation -> ParseStep -> ParseRes
parse_expr_name_lookup_or_func_call expr_todo fn ps =
    let
        me_as_expr =
            NameLookup (fn) |> AST.with_location fn.loc

        todo_after_fcall : FuncCallExprTodo
        todo_after_fcall res =
            case res of
                Err e ->
                    Error (FailedFuncCallParse e)

                Ok fcall ->
                    parse_expr_check_for_infix (FunctionCallExpr fcall |> with_location fcall.loc) expr_todo |> ParseFn |> Next ps.prog
    in
    case ps.tok.typ of
        OpenParen ->
            parse_function_call fn todo_after_fcall |> ParseFn |> Next ps.prog

        _ ->
            parse_expr_check_for_infix me_as_expr expr_todo ps


parse_expr : ExprParseTodo -> ParseStep -> ParseRes
parse_expr todo ps =
    let
        todo_after_fullname : FullNameParseTodo
        todo_after_fullname res =
            case res of
                Err e ->
                    Error e

                Ok fn ->
                    parse_expr_name_lookup_or_func_call todo fn |> ParseFn |> Next ps.prog
    in
    case ps.tok.typ of
        Lexer.Literal t s ->
            LiteralExpr t s |> AST.with_location ps.tok.loc |> Ok |> todo

        _ ->
            reapply_token_or_fail (parse_fullname todo_after_fullname |> ParseFn |> Next ps.prog) ps


parse_function_call : FullNameAndLocation -> FuncCallExprTodo -> ParseStep -> ParseRes
parse_function_call name todo ps =
    let
        what_to_do : ExprParseTodo
        what_to_do res =
            case res of
                Err e ->
                    Error (FailedExprParse e)

                Ok expr ->
                    parse_func_call_expr_continue todo (AST.FunctionCall name [ expr ] |> AST.with_location (Util.merge_sv name.loc expr.loc)) |> ParseFn |> Next ps.prog
    in
    case ps.tok.typ of
        CloseParen ->
            AST.FunctionCall name [] |> AST.with_location (Util.merge_sv name.loc ps.tok.loc)|> Ok |> todo
        _ ->
            reapply_token (ParseFn (parse_expr what_to_do)) ps


parse_func_call_expr_continue : FuncCallExprTodo -> FunctionCallAndLocation -> ParseStep -> ParseRes
parse_func_call_expr_continue todo fcall_and_loc ps =
    let
        add_to_fcall: FunctionCallAndLocation -> ExpressionAndLocation -> FunctionCallAndLocation
        add_to_fcall f_and_loc e_and_loc = 
            let
                f = f_and_loc.thing
                e = e_and_loc.thing
            in
            {thing = {f | args = List.append f.args [e_and_loc]}, loc = Util.merge_sv f_and_loc.loc e_and_loc.loc}
        what_to_do_with_expr : ExprParseTodo
        what_to_do_with_expr res =
            case res of
                Err e ->
                    case e of
                        ParenWhereIDidntWantIt _ ->
                            Error (FailedFuncCallParse (ExpectedAnotherArgument ps.tok.loc))

                        -- use this tok.loc because were looking at a paren right here
                        _ ->
                            Error (FailedExprParse e)

                Ok expr ->
                    ParseFn
                        (parse_func_call_expr_continue
                            todo
                            (add_to_fcall fcall_and_loc expr)
                        )
                        |> Next ps.prog
    in
    case ps.tok.typ of
        CommaToken ->
            parse_expr what_to_do_with_expr |> ParseFn |> Next ps.prog

        CloseParen ->
            todo (Ok fcall_and_loc)

        _ ->
            Error (Unimplemented ps.prog ("What to do if not comma or ) in arg list (in func_call_continue_or_end): "++(token_to_str ps.tok)))
