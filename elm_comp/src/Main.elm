module Main exposing (..)

import Browser.Navigation exposing (Key)
import Html exposing (pre, text)
import Html.Attributes exposing (style)
import Language exposing (Expression, KeywordType(..), LiteralType, Type)
import Lexer
import Util










input_view : Int -> Int -> Util.SourceView
input_view =
    Util.SourceView input

















input : String
input =
    """module main
import "std"
@property(addable)
fn add(a: u8, b: u8) -> u8{
    return a + b
}
fn double(a: u8) -> u8{
    return a * "2"
}
fn main(){

}
"""


main : Html.Html msg
main =
    let
        -- tokstr =
        -- lex input |> List.map token_to_str |> String.join " "
        syn_html =
            case Lexer.lex input of
                Ok toks ->
                    pre [] [ text (List.map Lexer.syntaxify_token toks |> String.join "") ]

                Err e ->
                    Lexer.explain_lex_error e
    in
    syn_html
