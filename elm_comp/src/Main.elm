module Main exposing (..)

-- import Browser.Navigation exposing (Key)
import Html exposing (pre, text)
import Html.Attributes exposing (style)
import Language exposing (KeywordType(..))
import ParserCommon exposing (Program)

import Util
import Pallete

import Lexer
import Parser

{- 
todo:
- keyword not allowed error gets emitted from parseName with note about which words are reserved
- 
-}

input : String
input =
    """module main

// importing the standard library
import "std"
import "math" // importing another library
import "github.com/cowsed/image"


// adding 2 numbers
fn add(a: u8, b: u8) -> u8{
    var c: u8 = a
    // this is not how adding works
    c = f(a, d(a))
    return a(c, d)
}

// doubling a number
fn double(a: u8) -> u8{
    return a
}

fn add2(a: u1, b: u6) {}

fn main(){

}
"""


type CompilerError
    = Lex Lexer.Error
    | Parse ParserCommon.Error


htmlify_output : Result CompilerError ParserCommon.Program -> Html.Html msg
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


wrap_parser_output : Result ParserCommon.Error ParserCommon.Program -> Result CompilerError ParserCommon.Program
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
                    Html.pre [] (toks |> List.map Lexer.token_to_str |> List.map (\x -> x ++ "\n") |> List.map text)

                Err _ ->
                    Html.pre [] [ text "Lexing error" ]

        parse : List Lexer.Token -> Result CompilerError ParserCommon.Program
        parse toks =
            Parser.parse toks |> wrap_parser_output

        result : Result CompilerError ParserCommon.Program
        result =
            lex_result |> Result.andThen parse
    in
    Html.div []
        [ Html.node "style" [] [ text global_css ]
        , htmlify_output result
        , Html.hr [] []
        , Html.div
            [ style "font-size" "15px"
            , style "overflow" "auto"
            ]
            [ Html.div
                [ style "overflow" "scroll"
                , style "height" "400px"
                , style "width" "400px"
                , style "padding" "4px"
                , style "background-color" Pallete.bg
                , style "border-radius" "8px"
                , style "border-style" "solid"
                , style "border-width" "2px"
                , style "border-color" "black"
                , style "float" "left"
                ]
                [ Html.code [] [ pre [] [ text input ] ]
                ]
            , case result of
                Err _ ->
                    Html.span [] []

                Ok prog ->
                    Html.div [ style "float" "left" ]
                        [ Parser.syntaxify_program prog
                        ]
            ]
        , Util.collapsable (text "Tokens") pretty_toks

        ]


global_css : String
global_css =
    """
    body { 
        background: #fbf1c7;
        color : #fc3836";
    } 
    """
