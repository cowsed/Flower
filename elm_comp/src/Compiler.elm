module Compiler exposing (..)

import Lexer 
import ParserCommon
import Parser exposing (parse)
import Lexer exposing (Token)


type CompilerError
    = Lex Lexer.Error
    | Parse ParserCommon.Error (List Token)


wrap_lexer_output : Result Lexer.Error (List Lexer.Token) -> Result CompilerError (List Lexer.Token)
wrap_lexer_output res =
    case res of
        Err e ->
            Err (Lex e)

        Ok toks ->
            Ok toks

wrap_parser_output : (List Token) ->Result ParserCommon.Error ParserCommon.Program -> Result CompilerError ParserCommon.Program
wrap_parser_output toks res =
    case res of
        Err e ->
            Err (Parse e toks)

        Ok prog ->
            Ok prog



compile: String -> Result CompilerError ParserCommon.Program
compile src = 
    let
        lex_result =
            Lexer.lex src |> wrap_lexer_output

        parse toks =
            Parser.parse toks |> wrap_parser_output toks

    in 
        lex_result |> Result.andThen parse