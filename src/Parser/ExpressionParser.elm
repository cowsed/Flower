module Parser.ExpressionParser exposing (parse_expr, parse_function_call)

import Language.Language exposing (InfixOpType, precedence)
import Parser.AST as AST exposing (Expression(..), ExpressionAndLocation, FullNameAndLocation, FunctionCallAndLocation, operator_to_function, with_location)
import Parser.Lexer as Lexer exposing (TokenType(..), infix_op_from_token, token_to_str)
import Parser.ParserCommon exposing (..)
import Util


type ExprOrInfix
    = Expr ExpressionAndLocation
    | InfixExpr ExprOrInfix ExprOrInfix InfixOpType


extract_expr : ExprOrInfix -> ExpressionAndLocation
extract_expr eor =
    case eor of
        Expr e ->
            e

        InfixExpr lhs rhs op ->
            operator_to_function op (get_loc_of_eori eor) (extract_expr lhs) (extract_expr rhs)


get_loc_of_eori : ExprOrInfix -> Util.SourceView
get_loc_of_eori eor =
    case eor of
        Expr eal ->
            eal.loc

        InfixExpr lhs rhs _ ->
            Util.merge_sv (get_loc_of_eori lhs) (get_loc_of_eori rhs)



type alias InfixOrExprTodo = Result ExprParseError ExprOrInfix -> ParseRes

parse_expr_check_for_infix : ExpressionAndLocation -> InfixOrExprTodo -> ParseStep -> ParseRes
parse_expr_check_for_infix lhs outer_todo ps =
    case infix_op_from_token ps.tok of
        Nothing ->
            reapply_token_or_fail (outer_todo (Ok (Expr lhs))) ps

        Just op ->
            let
                expr_after_todo : Result ExprParseError ExprOrInfix -> ParseRes
                expr_after_todo res =
                    case res of
                        Err e ->
                            outer_todo (Err e)

                        Ok expr_or_infix ->
                            case expr_or_infix of
                                InfixExpr next_lhs next_rhs next_op ->
                                    if precedence next_op >= precedence op then
                                        -- merge_infix lhs (operator_to_function op (Util.merge_sv (get_loc_of_eori next_lhs) (get_loc_of_eori next_rhs)) (extract_expr next_lhs) (extract_expr next_rhs)) op
                                        InfixExpr (Expr lhs) (InfixExpr next_lhs next_rhs next_op) op
                                            |> Ok
                                            |> outer_todo

                                    else
                                        InfixExpr
                                            (InfixExpr (Expr lhs) next_lhs op)
                                            next_rhs
                                            next_op
                                            |> Ok
                                            |> outer_todo

                                Expr e ->
                                    outer_todo (Ok (InfixExpr (Expr lhs) (Expr e) op))
            in
            parse_expr_infix expr_after_todo |> ParseFn |> Next ps.prog


parse_expr_name_lookup_or_func_call : InfixOrExprTodo -> FullNameAndLocation -> ParseStep -> ParseRes
parse_expr_name_lookup_or_func_call expr_todo fn ps =
    let
        me_as_expr =
            NameLookup fn |> AST.with_location fn.loc

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


parse_expr: ExprParseTodo -> ParseStep -> ParseRes
parse_expr todo ps = 
    let
        escape_infixing: InfixOrExprTodo
        escape_infixing res =
            res |> Result.map (extract_expr) |> todo 

    in
    reapply_token_or_fail (escape_infixing |> parse_expr_infix |> ParseFn |> Next ps.prog) ps

parse_expr_infix : InfixOrExprTodo -> ParseStep -> ParseRes
parse_expr_infix todo ps =
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
            LiteralExpr t s |> AST.with_location ps.tok.loc |> (\expr -> parse_expr_check_for_infix expr todo) |> ParseFn |> Next ps.prog

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
            AST.FunctionCall name [] |> AST.with_location (Util.merge_sv name.loc ps.tok.loc) |> Ok |> todo

        _ ->
            reapply_token (ParseFn (parse_expr what_to_do)) ps


parse_func_call_expr_continue : FuncCallExprTodo -> FunctionCallAndLocation -> ParseStep -> ParseRes
parse_func_call_expr_continue todo fcall_and_loc ps =
    let
        add_to_fcall : FunctionCallAndLocation -> ExpressionAndLocation -> FunctionCallAndLocation
        add_to_fcall f_and_loc e_and_loc =
            let
                f =
                    f_and_loc.thing

            in
            { thing = { f | args = List.append f.args [ e_and_loc ] }, loc = Util.merge_sv f_and_loc.loc e_and_loc.loc }

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
            Error (Unimplemented ps.prog ("What to do if not comma or ) in arg list (in func_call_continue_or_end): " ++ token_to_str ps.tok))
