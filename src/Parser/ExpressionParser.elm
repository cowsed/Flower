module Parser.ExpressionParser exposing (parse_expr, parse_function_call)

import Language.Language exposing (InfixOpType, precedence)
import Language.Syntax as Syntax exposing (Node, merge_svs, node_get, node_location)
import Parser.AST as AST exposing (Expression(..), FullName, operator_to_function, with_location)
import Parser.Lexer as Lexer exposing (TokenType(..), infix_op_from_token, token_to_str, token_type)
import Parser.ParserCommon exposing (..)
import Language.Syntax exposing (SourceView)


type ExprOrInfix
    = Expr (Node Expression)
    | InfixExpr ExprOrInfix ExprOrInfix InfixOpType


extract_expr : ExprOrInfix -> Node Expression
extract_expr eor =
    case eor of
        Expr e ->
            e

        InfixExpr lhs rhs op ->
            operator_to_function op (get_loc_of_eori eor) (extract_expr lhs) (extract_expr rhs)


get_loc_of_eori : ExprOrInfix -> Syntax.SourceView
get_loc_of_eori eor =
    case eor of
        Expr eal ->
            eal.loc

        InfixExpr lhs rhs _ ->
            Syntax.merge_sv (get_loc_of_eori lhs) (get_loc_of_eori rhs)


type alias InfixOrExprTodo =
    Result ExprParseError ExprOrInfix -> ParseRes


parse_expr_check_for_infix : Node Expression -> InfixOrExprTodo -> ParseStep -> ParseRes
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
                                        -- merge_infix lhs (operator_to_function op (Syntax.merge_sv (get_loc_of_eori next_lhs) (get_loc_of_eori next_rhs)) (extract_expr next_lhs) (extract_expr next_rhs)) op
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


parse_expr_name_lookup_or_func_call : InfixOrExprTodo -> Node FullName -> ParseStep -> ParseRes
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
    case token_type ps.tok of
        OpenParen ->
            parse_function_call fn todo_after_fcall |> ParseFn |> Next ps.prog

        _ ->
            parse_expr_check_for_infix me_as_expr expr_todo ps


parse_expr : ExprParseTodo -> ParseStep -> ParseRes
parse_expr todo ps =
    let
        escape_infixing : InfixOrExprTodo
        escape_infixing res =
            res |> Result.map extract_expr |> todo
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
    case token_type ps.tok of
        Lexer.Literal t s ->
            LiteralExpr t s |> AST.with_location ps.tok.loc |> (\expr -> parse_expr_check_for_infix expr todo) |> ParseFn |> Next ps.prog

        OpenParen ->
            parse_expr_tuple_def_start todo [] |> ParseFn |> NextNoChange

        _ ->
            reapply_token_or_fail (parse_fullname todo_after_fullname |> ParseFn |> Next ps.prog) ps


parse_expr_tuple_def_start : InfixOrExprTodo -> List (Node Expression) -> ParseStep -> ParseRes
parse_expr_tuple_def_start todo sofar ps =
    let
        finish_tuple_todo : ExprParseTodo
        finish_tuple_todo res =
            case res of
                Err e ->
                    e |> FailedExprParse |> Error

                Ok exp ->
                    parse_expr_tuple_def_continue todo (List.append sofar [ exp ]) |> ParseFn |> NextNoChange
    in
    case ps.tok |> node_get of
        CloseParen ->
            EmptyParens (ps.tok |> node_location) |> Error

        _ ->
            parse_expr finish_tuple_todo ps


parse_expr_tuple_def_continue : InfixOrExprTodo -> List (Node Expression) -> ParseStep -> ParseRes
parse_expr_tuple_def_continue todo sofar ps =
    case ps.tok |> node_get of
        CommaToken ->
            let 
                finish_tuple_todo res =
                    case res of 
                        Err e -> e |> FailedExprParse |> Error
                        Ok exp -> parse_expr_tuple_def_continue todo (List.append sofar [exp]) |> ParseFn |> NextNoChange 
            in
            parse_expr finish_tuple_todo |> ParseFn |> NextNoChange

        CloseParen ->
            let
                full_loc : SourceView
                full_loc = sofar |> List.map node_location |> merge_svs (node_location ps.tok)
            in
            
            todo (AST.Tuple sofar |> with_location full_loc |> Expr |> Ok)

        _ ->
            ExpectedEndOfTupleOrComma (ps.tok |> node_location) |> FailedExprParse |> Error


parse_function_call : Node FullName -> FuncCallExprTodo -> ParseStep -> ParseRes
parse_function_call name todo ps =
    let
        what_to_do : ExprParseTodo
        what_to_do res =
            case res of
                Err e ->
                    Error (FailedExprParse e)

                Ok expr ->
                    parse_func_call_expr_continue todo (AST.FunctionCall name [ expr ] |> AST.with_location (Syntax.merge_sv name.loc expr.loc)) |> ParseFn |> Next ps.prog
    in
    case token_type ps.tok of
        CloseParen ->
            AST.FunctionCall name [] |> AST.with_location (Syntax.merge_sv name.loc ps.tok.loc) |> Ok |> todo

        _ ->
            reapply_token (ParseFn (parse_expr what_to_do)) ps


parse_func_call_expr_continue : FuncCallExprTodo -> Node AST.FunctionCall -> ParseStep -> ParseRes
parse_func_call_expr_continue todo fcall_and_loc ps =
    let
        add_to_fcall : Node AST.FunctionCall -> Node Expression -> Node AST.FunctionCall
        add_to_fcall f_and_loc e_and_loc =
            let
                f =
                    f_and_loc.thing
            in
            { thing = { f | args = List.append f.args [ e_and_loc ] }, loc = Syntax.merge_sv f_and_loc.loc e_and_loc.loc }

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
    case token_type ps.tok of
        CommaToken ->
            parse_expr what_to_do_with_expr |> ParseFn |> Next ps.prog

        CloseParen ->
            todo (Ok fcall_and_loc)

        _ ->
            Error (Unimplemented ps.prog ("What to do if not comma or ) in arg list (in func_call_continue_or_end): " ++ token_to_str ps.tok))
