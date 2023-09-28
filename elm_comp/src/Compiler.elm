module Compiler exposing (..)

import Html
import Lexer exposing (Token)
import Parser 
import ParserCommon


type CompilerError
    = Lex Lexer.Error
    | Parse ParserCommon.Error (List Token)


explain_error : CompilerError -> Html.Html msg
explain_error e =
    case e of
        Lex le ->
            Lexer.explain_error le

        Parse pe _ ->
            Parser.explain_error pe


wrap_lexer_output : Result Lexer.Error (List Lexer.Token) -> Result CompilerError (List Lexer.Token)
wrap_lexer_output res =
    case res of
        Err e ->
            Lex e |> Err

        Ok toks ->
            Ok toks


wrap_parser_output : List Token -> Result ParserCommon.Error ParserCommon.Program -> Result CompilerError ParserCommon.Program
wrap_parser_output toks res =
    case res of
        Err e ->
            Parse e toks |> Err

        Ok prog ->
            Ok prog


compile : String -> Result CompilerError ParserCommon.Program
compile src =
    let
        lex_result : Result CompilerError (List Token)
        lex_result =
            Lexer.lex src |> Result.mapError (\e -> Lex e)
    in
    lex_result
        |> Result.andThen (\toks -> Parser.parse toks |> Result.mapError (\e -> Parse e toks))
