module Main exposing (..)

-- import Element exposing (Element, el)

import Browser
import Compiler exposing (CompilerError(..), compile)
import Element exposing (Element, alignBottom, alignRight, el, fill)
import Element.Background as Background
import Element.Font as Font
import Html exposing (..)
import Html.Attributes exposing (style)
import Pallete
import Task
import Time
import Ui exposing (code_rep)
import Compiler exposing (explain_error)
import Parser.ParserExplanations
import Parser.AST as AST 



{-
   todo:
   - keyword not allowed error gets emitted from parseName with note about which words are reserved
   - infix operator expressions
   - ~~fullnames std.print(std.time)~~
   - ~~a: Type = 123123213123 is a const thing~~
   - ~~module.thing.name for types everywhere not just expressons~~
   - struct parsing
   - enum parsing
   - ~~reference type parsing~~
   - while and for loops
   - concept checking for types `T: UnsignedIneger`
   - ~~THERE IS A SYNTACTIC AMBIGUITY BETWEEN~~
    - ~~name1[name2](expr) - generic function call of name1 with generic args name2 with expr ~
    - ~~name1[name2](expr) - array of functions lookup on name1 with index variable name2 then~~ 
   - array indexing
-}


initial_input : String
initial_input =
    """module main

// importing the standard library
import "std"

struct a{
    val: u8


}

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


htmlify_output : Result CompilerError AST.Program -> Html.Html msg
htmlify_output res =
    Html.div []
        [ case res of
            Err _ ->
                Html.div [] []

            Ok prog ->
                Html.div [style "padding-left" "20px"] [Parser.ParserExplanations.explain_program prog]
        ]


make_output : Model -> Element Msg
make_output mod =
    let
        title_bar =
            Element.row
                [ Font.size 30
                , Element.width fill
                , Background.color Pallete.bg1_c
                , Element.paddingXY 10 6
                ]
                [ el [ Element.alignLeft ] (Element.text ("Flower" ++ " v0.0.2"))
                , el [ alignRight ] (Element.text "About")
                ]

        footer =
            Element.row [ Element.width fill, alignBottom, Element.padding 4 ]
                [ Element.text ("Compiled in " ++ millis_elapsed mod.last_run_start mod.last_run_end ++ " ms")
                ]

        left_pane =
            Element.html (Ui.code_editor mod.source_code (\s -> Compile s))

        right_pane =
            case mod.output of
                Err e ->
                    el [ Element.width fill, Element.height fill ] <| Element.html (explain_error e)

                Ok prog ->
                    code_rep prog
    in
    Element.column
        [ Element.width fill
        , Element.height fill
        ]
        [ title_bar
        , Element.row
            [ Element.width fill
            , Element.height Element.fill
            ]
            [ left_pane
            , right_pane
            , Element.el
                [ Element.width fill
                , Element.height Element.fill
                ]
                (Element.html (htmlify_output mod.output))
            ]
        , footer
        ]




view : Maybe Model -> Html.Html Msg
view mmod =
    case mmod of
        Nothing ->
            text "Not Loaded Yet"

        Just mod ->
            Element.row [ Element.height (Element.fill |> Element.maximum 1800), Element.width fill ] [ make_output mod ]
                |> Element.layout
                    [ Background.color Pallete.bg_c
                    , Font.color Pallete.fg_c

                    , Element.clip
                    , Element.height Element.fill
                    , Element.width Element.fill

                    -- , Element.explain Debug.todo
                    ]


type Msg
    = Compile String
    | GotTimeToStart String Time.Posix -- for timing
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
                , output = compile initial_input
                }
            , Task.perform (GotTimeToStart initial_input) Time.now
            )

        Just mod ->
            case msg of
                Compile s ->
                    ( Just mod, Task.perform (GotTimeToStart s) Time.now )

                GotTimeToStart s t ->
                    ( Just { mod | source_code = s, last_run_start = t, output = compile s }, Task.perform GotTimeEnd Time.now )

                GotTimeEnd t ->
                    ( { mod | last_run_end = t }
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
    , output : Result Compiler.CompilerError AST.Program
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
