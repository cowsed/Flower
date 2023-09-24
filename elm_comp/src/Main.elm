module Main exposing (..)

-- import Browser.Navigation exposing (Key)
import Html exposing (pre, text)
import Language exposing (Expression, KeywordType(..), LiteralType, Type)

import Util

import Lexer
import Parser





input : String
input =
    """//example dude
module main
// importing the standard library
import "std"
import "math"
import "std"
fn add(a: u8, b: u8) -> u8{
    return a + b
}
fn double(a: u8) -> u8{
    return a * "2"
}
fn main(){

}
"""


type CompilerError
    = Lex Lexer.Error
    | Parse Parser.Error


htmlify_output : Result CompilerError Parser.Program -> Html.Html msg
htmlify_output res =
    case res of
        Err ce ->
            case ce of
                Lex le ->
                    Lexer.explain_error le

                Parse pe ->
                    Parser.explain_error pe

        Ok prog ->
            Parser.explain_program prog


wrap_lexer_output : Result Lexer.Error (List Lexer.Token) -> Result CompilerError (List Lexer.Token)
wrap_lexer_output res =
    case res of
        Err e ->
            Err (Lex e)

        Ok toks ->
            Ok toks


wrap_parser_output : Result Parser.Error Parser.Program -> Result CompilerError Parser.Program
wrap_parser_output res =
    case res of
        Err e ->
            Err (Parse e)

        Ok prog ->
            Ok prog


main : Html.Html msg
main =
    let
        lex_result =
            Lexer.lex input |> wrap_lexer_output

        pretty_toks =
            case lex_result of
                Ok toks ->
                    Html.pre [  ] (toks |>List.map Lexer.token_to_str |> List.map (\x -> (x++"\n")) |>List.map text )

                Err _ ->
                    Html.pre [] [ text "Lexing error" ]

        -- parse_result : Result CompilerError Parser.Program
        -- parse_result =
        --     case lex_result of
        --         Err e ->
        --             Err (Lex e)
        --         Ok toks ->
        --             case Parser.parse toks of
        --                 Err e ->
        --                     Err (Parse e)
        --                 Ok prog -> Ok prog
        parse: List Lexer.Token -> Result CompilerError Parser.Program
        parse toks =
            Parser.parse toks |> wrap_parser_output

        result : Result CompilerError Parser.Program
        result =
            lex_result |> Result.andThen parse
    in
    Html.div []
        [ Util.collapsable "Tokens" (pretty_toks)
        , htmlify_output result
        , Html.hr [] []
        , Html.code [] [pre [] [text input]]
        ]
