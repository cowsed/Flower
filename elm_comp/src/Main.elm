module Main exposing (..)

import Browser
import Html exposing (..)
import Html.Attributes exposing (spellcheck, style)
import Html.Events exposing (onInput)
import Lexer
import Pallete
import Parser
import ParserCommon
import Task
import Time
import Util



{-
   todo:
   - keyword not allowed error gets emitted from parseName with note about which words are reserved
   -
-}


initial_input : String
initial_input =
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


make_output : Model -> Html.Html Msg
make_output mod =
    let
        lex_result =
            Lexer.lex mod.source_code |> wrap_lexer_output

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
        , Html.div
            [ style "font-size" "15px"
            , style "overflow" "auto"
            ]
            [ Html.textarea
                [ style "font-size" "15px"
                , style "overflow" "scroll"
                , style "height" "400px"
                , style "width" "400px"
                , style "padding" "10px"
                , style "background-color" Pallete.bg
                , style "border-radius" "8px"
                , style "border-style" "solid"
                , style "border-width" "2px"
                , style "border-color" "black"
                , style "float" "left"
                , spellcheck False
                , onInput (\s -> DoUpdate s)
                ]
                [ text mod.source_code
                ]
            , case result of
                Err _ ->
                    Html.span [] []

                Ok prog ->
                    Html.div [ style "float" "left" ]
                        [ Parser.syntaxify_program prog
                        ]
            ]
        , text ("Last Run Started: " ++ stringify_time Time.utc mod.last_run_start)
        , Html.br [] []
        , text ("Last Run Ended: " ++ stringify_time Time.utc mod.last_run_end)
        , htmlify_output result
        , Html.hr [] []
        , Util.collapsable (text "Tokens") pretty_toks
        ]


view : Maybe Model -> Html.Html Msg
view mmod =
    case mmod of
        Nothing ->
            text "NotLoadedYet"

        Just mod ->
            mod.output


stringify_time : Time.Zone -> Time.Posix -> String
stringify_time zone p =
    stringify_month (Time.toMonth zone p)
        ++ " "
        ++ (Time.toDay zone p |> String.fromInt)
        ++ ", "
        ++ (Time.toYear zone p |> String.fromInt)
        ++ " "
        ++ (Time.toHour zone p |> String.fromInt)
        ++ ":"
        ++ (Time.toMinute zone p |> String.fromInt)
        ++ " "
        ++ (Time.toSecond zone p |> String.fromInt)
        ++ ":"
        ++ (Time.toMillis zone p |> String.fromInt)


stringify_month : Time.Month -> String
stringify_month mon =
    case mon of
        Time.Jan ->
            "Jan"

        Time.Feb ->
            "Feb"

        Time.Mar ->
            "Mar"

        Time.Apr ->
            "Apr"

        Time.May ->
            "May"

        Time.Jun ->
            "Jun"

        Time.Jul ->
            "Jul"

        Time.Aug ->
            "Aug"

        Time.Sep ->
            "Sep"

        Time.Oct ->
            "Oct"

        Time.Nov ->
            "Nov"

        Time.Dec ->
            "Dec"


global_css : String
global_css =
    """
    body { 
        background: #fbf1c7;
        color : #fc3836";
    } 
    """


type Msg
    = DoUpdate String
    | Recompile String
    | GotTimeToStart String Time.Posix
    | GotTimeEnd Time.Posix


init : a -> ( Maybe Model, Cmd Msg )
init _ =
    ( Nothing, Task.perform (GotTimeToStart initial_input) Time.now )


update : Msg -> Maybe Model -> ( Maybe Model, Cmd Msg )
update msg mmod =
    case mmod of
        Nothing ->
            ( Just
                { source_code = initial_input
                , last_run_start = Time.millisToPosix 0
                , last_run_end = Time.millisToPosix 0
                , output = text "Compiling..."
                }
            , Task.perform (GotTimeToStart initial_input) Time.now
            )

        Just mod ->
            case msg of
                DoUpdate s ->
                    ( Just mod, Task.perform (GotTimeToStart s) Time.now )

                Recompile s ->
                    ( Just { mod | source_code = s }, Cmd.none )

                GotTimeToStart s t ->
                    ( { mod
                        | last_run_start = t
                        , output =
                            case update (Recompile s) mmod |> Tuple.first of
                                Nothing ->
                                    text "terrible error this shouldnt happen"

                                Just mod_after ->
                                    make_output mod_after
                      }
                        |> Just
                    , Task.perform GotTimeEnd Time.now
                    )

                GotTimeEnd t ->
                    ( { mod | last_run_end = t } |> Just, Cmd.none )


type alias Model =
    { source_code : String
    , last_run_start : Time.Posix
    , last_run_end : Time.Posix
    , output : Html.Html Msg
    }



-- main : Program () Model Msg


main : Program () (Maybe Model) Msg
main =
    Browser.element
        { init = init
        , view = view
        , update = update
        , subscriptions = \_ -> Sub.none
        }
