module Main exposing (..)

import Browser
import Compiler exposing (CompilerError(..), compile)
import Html exposing (..)
import Html.Attributes exposing (style)
import Lexer
import Parser
import ParserCommon
import Task
import Time
import Ui exposing (code_editor)
import Util



{-
   todo:
   - keyword not allowed error gets emitted from parseName with note about which words are reserved
   - infix operator expressions
   - ~~fullnames std.print(std.time)~~
   - ~~a: Type = 123123213123 is a const thing~~
   - qualified name for types everywhere not just expressons
-}


initial_input : String
initial_input =
    """module main

// importing the standard library
import "std"


// adding 2 numbers
fn add(a: u8, b: u8) -> u8{
    var c: u8 = a
    if a {
        return a
    }
    return c
}

fn main() -> u8{
    a: u8 = 1
    b: u8 = 2
    var res: u8 = add(a, b)
    std.println("{a} + {b} = {res}")
}
"""


htmlify_output : Result CompilerError ParserCommon.Program -> Html.Html msg
htmlify_output res =
    case res of
        Err _ ->
            Html.div [] []

        Ok prog ->
            Parser.explain_program prog


make_output : Model -> Html.Html Msg
make_output mod =
    let
        result : Result CompilerError ParserCommon.Program
        result =
            compile mod.source_code

        pretty_toks =
            case result of
                Ok prog ->
                    Html.pre [] (prog.src_tokens |> List.map Lexer.token_to_str |> List.map (\x -> x ++ "\n") |> List.map text)

                Err e ->
                    case e of
                        Parse _ toks ->
                            Html.pre [] (toks |> List.map Lexer.token_to_str |> List.map (\x -> x ++ "\n") |> List.map text)

                        Lex _ ->
                            Html.pre [] [ text "Lex error" ]
    in
    Html.div []
        [ Html.node "style" [] [ text global_css ]
        , Html.div
            [  style "overflow" "auto"
            ]
            [ code_editor mod.source_code (\s -> DoUpdate s)
            , case result of
                Err e ->
                    Html.span []
                        [ Compiler.explain_error e
                        ]

                Ok prog ->
                    Html.div [ style "float" "left" ]
                        [ Parser.syntaxify_program prog
                        ]
            ]
        , htmlify_output result
        , Html.hr [] []
        , Util.collapsable (text "Tokens") pretty_toks
        ]


view : Maybe Model -> Html.Html Msg
view mmod =
    case mmod of
        Nothing ->
            text "Not Loaded Yet"

        Just mod ->
            mod.output


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
      -- | Recompile String
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

                GotTimeToStart s t ->
                    ( Just { mod | source_code = s, last_run_start = t, output = make_output { mod | source_code = s, last_run_start = t } }, Task.perform GotTimeEnd Time.now )

                GotTimeEnd t ->
                    ( { mod
                        | last_run_end = t
                        , output =
                            Html.div []
                                [ text ("CompileAndBuildTime: " ++ millis_elapsed mod.last_run_start t ++ " ms")
                                , mod.output
                                ]
                      }
                        |> Just
                    , Cmd.none
                    )


millis_elapsed : Time.Posix -> Time.Posix -> String
millis_elapsed start end =
    let
        differenceMillis =
            Time.posixToMillis end - Time.posixToMillis start
    in
    differenceMillis |> String.fromInt


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
