module Compiler exposing (..)

import Html
import Html.Attributes exposing (style)
import Lexer exposing (Token)
import Parser 
import ParserCommon
import Lexer exposing (token_to_str)
import Element exposing (Attribute)


type CompilerError
    = Lex Lexer.Error
    | Parse ParserCommon.Error (List Token)


explain_toks: List Token -> Html.Html msg
explain_toks toks =
    toks |> List.map token_to_str |> String.join "\n" |> (\s -> Html.textarea [] [Html.text s])
explain_error : CompilerError -> Html.Html msg
explain_error e =
    case e of
        Lex le ->
            Lexer.explain_error le

        Parse pe toks->
            Html.div []  [Parser.explain_error pe, explain_toks toks]


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
