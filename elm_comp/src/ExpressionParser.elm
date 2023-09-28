module ExpressionParser exposing (..)
import ParserCommon exposing (..)
import Lexer exposing (TokenType(..))
import Language exposing (ASTFunctionCall, ASTExpression(..), Name(..))

type alias FuncCallExprTodo =
    Result FuncCallParseError ASTFunctionCall -> ParseRes


parse_expr : Maybe Name -> ExprParseWhatTodo -> ParseStep -> ParseRes
parse_expr name todo ps =
    case ps.tok.typ of
        Symbol s ->
            Next ps.prog (ParseFn (parse_expr_name_or_fcall (Language.append_maybe_name name s) todo))
        Literal lt s ->LiteralExpr lt s |> Ok |> todo 

        CloseParen -> ParenWhereIDidntWantIt ps.tok.loc |> Err |> todo
        NewlineToken -> IdkExpr ps.tok.loc "I Expected an expression but got the end of the line" |> Err |> todo
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
        DotToken -> parse_expr (Just name) todo |> ParseFn |> Next ps.prog 
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
                    Next ps.prog (ParseFn (parse_func_call_continue_or_end todo (ASTFunctionCall name [ expr ])))
    in
    case ps.tok.typ of
        CloseParen ->
            todo (Ok (ASTFunctionCall name []))

        _ ->
            reapply_token (ParseFn (parse_expr Nothing what_to_do)) ps




parse_func_call_continue_or_end : (Result FuncCallParseError ASTFunctionCall -> ParseRes) -> ASTFunctionCall -> ParseStep -> ParseRes
parse_func_call_continue_or_end todo fcall ps =
    let
        what_to_do_with_expr : Result ExprParseError ASTExpression -> ParseRes
        what_to_do_with_expr res =
            case res of
                Err e ->
                    case e of
                        ParenWhereIDidntWantIt _ -> Error (FailedFuncCallParse (ExpectedAnotherArgument ps.tok.loc)) -- use this tok.loc because were looking at a paren right here
                        _  -> Error (FailedExprParse  e)

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
            parse_expr Nothing what_to_do_with_expr |> ParseFn |> Next ps.prog

        CloseParen ->
            todo (Ok fcall)

        _ ->
            Error (Unimplemented ps.prog "What to do if not comma or ) in arg list (in func_call_continue_or_end)")






-- called after name(


