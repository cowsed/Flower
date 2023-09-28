module Compiler exposing (..)

import Html
import Lexer exposing (Token)
import Parser exposing (parse)
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
        lex_result =
            Lexer.lex src |> wrap_lexer_output

        parse toks =
            Parser.parse toks |> wrap_parser_output toks
    in
    lex_result |> Result.andThen parse
