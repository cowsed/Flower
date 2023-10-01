module ExpressionParser exposing (..)

import Language exposing (ASTExpression(..), ASTFunctionCall, FullName, Identifier(..), precedence, stringify_fullname, stringify_infix_op)
import Lexer exposing (TokenType(..), infix_op_from_token)
import ParserCommon exposing (..)


stringify_expression : ASTExpression -> String
stringify_expression expr =
    case expr of
        NameLookup n ->
            stringify_fullname n

        FunctionCallExpr fc ->
            stringify_fullname fc.fname ++ "(" ++ (fc.args |> List.map stringify_expression |> String.join ", ") ++ ")"

        LiteralExpr _ s ->
            s

        Parenthesized e ->
            stringify_expression e

        InfixExpr lhs rhs op ->
            stringify_expression lhs ++ stringify_infix_op op ++ stringify_expression rhs


parse_expr_check_for_infix : ASTExpression -> ExprParseTodo -> ParseStep -> ParseRes
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
                            case this_rhs of
                                InfixExpr next_lhs next_rhs next_op ->
                                    if precedence next_op >= precedence op then
                                        Ok (InfixExpr lhs this_rhs op) |> outer_todo

                                    else
                                        Ok (InfixExpr (InfixExpr lhs next_lhs op) next_rhs next_op) |> outer_todo

                                _ ->
                                    outer_todo (Ok (InfixExpr lhs this_rhs op))
            in
            parse_expr expr_after_todo |> ParseFn |> Next ps.prog


parse_expr_name_lookup_or_func_call : ExprParseTodo -> FullName -> ParseStep -> ParseRes
parse_expr_name_lookup_or_func_call expr_todo fn ps =
    let
        me_as_expr =
            NameLookup fn

        todo_after_fcall : FuncCallExprTodo
        todo_after_fcall res =
            case res of
                Err e ->
                    Error (FailedFuncCallParse e)

                Ok fcall ->
                    parse_expr_check_for_infix (FunctionCallExpr fcall) expr_todo |> ParseFn |> Next ps.prog
    in
    case ps.tok.typ of
        OpenParen ->
            parse_function_call fn todo_after_fcall |> ParseFn |> Next ps.prog

        _ ->
            parse_expr_check_for_infix me_as_expr expr_todo ps


parse_expr : ExprParseTodo -> ParseStep -> ParseRes
parse_expr todo ps =
    let
        todo_after_fullname : NameWithSquareArgsTodo
        todo_after_fullname res =
            case res of
                Err e ->
                    Error e

                Ok fn ->
                    parse_expr_name_lookup_or_func_call todo fn |> ParseFn |> Next ps.prog
    in
    case ps.tok.typ of
        Lexer.Literal t s ->
            (LiteralExpr t s) |> Ok |> todo

        _ ->
            reapply_token_or_fail (parse_full_name todo_after_fullname |> ParseFn |> Next ps.prog) ps




parse_function_call : FullName -> FuncCallExprTodo -> ParseStep -> ParseRes
parse_function_call name todo ps =
    let
        what_to_do : ExprParseTodo
        what_to_do res =
            case res of
                Err e ->
                    Error (FailedExprParse e)

                Ok expr ->
                    parse_func_call_continue_or_end todo (ASTFunctionCall name [ expr ]) |> ParseFn |> Next ps.prog
    in
    case ps.tok.typ of
        CloseParen ->
            todo (Ok (ASTFunctionCall name []))

        _ ->
            reapply_token (ParseFn (parse_expr what_to_do)) ps


parse_func_call_continue_or_end : (Result FuncCallParseError ASTFunctionCall -> ParseRes) -> ASTFunctionCall -> ParseStep -> ParseRes
parse_func_call_continue_or_end todo fcall ps =
    let
        what_to_do_with_expr : Result ExprParseError ASTExpression -> ParseRes
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
                        (parse_func_call_continue_or_end
                            todo
                            { fcall | args = List.append fcall.args [ expr ] }
                        )
                        |> Next ps.prog
    in
    case ps.tok.typ of
        CommaToken ->
            parse_expr what_to_do_with_expr |> ParseFn |> Next ps.prog

        CloseParen ->
            todo (Ok fcall)

        _ ->
            Error (Unimplemented ps.prog "What to do if not comma or ) in arg list (in func_call_continue_or_end)")


