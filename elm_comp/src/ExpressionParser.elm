module ExpressionParser exposing (..)

import Language exposing (ASTExpression(..), ASTFunctionCall, Name(..), precedence, stringify_name, stringify_infix_op)
import Lexer exposing (TokenType(..), infix_op_from_token)
import ParserCommon exposing (..)
import Util


type alias FuncCallExprTodo =
    Result FuncCallParseError ASTFunctionCall -> ParseRes

stringify_expression : ASTExpression -> String
stringify_expression expr =
    case expr of
        NameLookup n ->
            stringify_name n

        FunctionCallExpr fc ->
            stringify_name fc.fname ++ "(" ++ (fc.args |> List.map stringify_expression |> String.join ", ") ++ ")"

        LiteralExpr _ s ->
            s

        Parenthesized e ->
            stringify_expression e
        InfixExpr lhs rhs op ->
            stringify_expression lhs ++ stringify_infix_op op ++ stringify_expression rhs


parse_expr_check_for_infix : ASTExpression -> ExprParseWhatTodo -> ParseStep -> ParseRes
parse_expr_check_for_infix lhs outer_todo ps =
    case infix_op_from_token ps.tok of
        Nothing ->
            reapply_token_or_fail (outer_todo (Ok lhs)) ps

        Just op ->
            let
                expr_after_todo : ExprParseWhatTodo
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



parse_expr : ExprParseWhatTodo -> ParseStep -> ParseRes
parse_expr todo ps =
    parse_expr_continued_name Nothing todo ps


parse_expr_continued_name : Maybe Name -> ExprParseWhatTodo -> ParseStep -> ParseRes
parse_expr_continued_name qualled_name_so_far outer_todo ps =
    let
        todo : ExprParseWhatTodo
        todo res =
            case res of
                Err e ->
                    Error (FailedExprParse e)

                Ok e ->
                    parse_expr_check_for_infix e outer_todo |> ParseFn |> Next ps.prog
    in
    case ps.tok.typ of
        Symbol s ->
            Next ps.prog (ParseFn (parse_expr_name_or_fcall (Language.append_maybe_name qualled_name_so_far s) todo))

        Literal lt s ->
            LiteralExpr lt s |> Ok |> todo

        OpenParen ->
            let
                after : ExprParseWhatTodo
                after res =
                    res |> Result.andThen (\e -> Ok (Parenthesized e)) |> todo |> parse_expected_token ("Expected a closing ) to match this\n" ++ Util.show_source_view ps.tok.loc) CloseParen |> ParseFn |> Next ps.prog
            in
            parse_expr_continued_name qualled_name_so_far after |> ParseFn |> Next ps.prog

        NewlineToken ->
            IdkExpr ps.tok.loc "I Expected an expression but got the end of the line" |> Err |> todo

        CloseParen ->
            ParenWhereIDidntWantIt ps.tok.loc |> Err |> todo

        _ ->
            IdkExpr ps.tok.loc "I don't know how to parse non name lookup expr" |> Err |> todo


parse_expr_name_or_fcall : Name -> ExprParseWhatTodo -> ParseStep -> ParseRes
parse_expr_name_or_fcall name todo ps =
    let
        func_todo : FuncCallExprTodo
        func_todo res =
            case res of
                Ok fcall ->
                    FunctionCallExpr fcall |> Ok |> todo

                Err e ->
                    Error (FailedFuncCallParse e)
    in
    case ps.tok.typ of
        -- start func
        OpenParen ->
            parse_function_call name func_todo |> ParseFn |> Next ps.prog

        --continue building name
        DotToken ->
            parse_expr_continued_name (Just name) todo |> ParseFn |> Next ps.prog

        -- was just a name
        _ ->
            case NameLookup name |> Ok |> todo of
                Error e ->
                    Error e

                Next prog fn ->
                    reapply_token fn { ps | prog = prog }


parse_function_call : Name -> FuncCallExprTodo -> ParseStep -> ParseRes
parse_function_call name todo ps =
    let
        what_to_do : ExprParseWhatTodo
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



-- called after name(
