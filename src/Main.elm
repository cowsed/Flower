module Main exposing (..)

import Analysis.Analyzer as Analyzer
import Analysis.Explanations
import Browser
import Browser.Events
import CodeEditor
import Compiler exposing (CompilerError(..), compile, explain_error)
import Element exposing (Element, alignBottom, alignRight, el, fill)
import Element.Background as Background
import Element.Border
import Element.Font as Font
import Html exposing (..)
import Html.Attributes exposing (style)
import Pallete
import Parser.AST as AST
import Parser.ParserExplanations
import Task
import Time
import Ui exposing (code_rep)
import Element exposing (scrollbarY)



{-
   todo:
   - for loops
   - concept checking for types `T: UnsignedIneger`
   - array indexing
   - type thing Type1 or Type2 or Type3
-}


initial_input : String
initial_input =
    """module main

// importing the standard library
import "std"


type Positive[N] = N | n >= 0

struct a{
    val: u8
}

enum Result[E, T]{
    Err(E, T)
    Res(T)
}

fn sqrt(v: bool ) -> f64{
    return v/2
}



















fn main() -> u8{
    a: u8 = 1
    b: u8 = 2
    var res: u8 = add(a, b)
    std.println("{a} + {b} = {res}")
}
"""


htmlify_output : Result CompilerError ( AST.Program, Analyzer.GoodProgram ) -> Html.Html msg
htmlify_output res =
    Html.div []
        [ case res of
            Err _ ->
                Html.div [] []

            Ok prog ->
                Html.div [ style "padding-left" "20px" ] [ Analysis.Explanations.explain_program (Tuple.second prog), Parser.ParserExplanations.explain_program (Tuple.first prog) ]
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
            Element.el
                [ Element.width fill
                , Element.height fill
                , Element.paddingEach {top = 0, bottom = 0, left = 0, right = 4}
                , Element.Border.color Pallete.fg_c
                , Element.Border.solid
                , Element.Border.width 2
                ]
            <|
                CodeEditor.code_editor mod.editor_state (\s -> EditorAction s)

        -- Element.html (Ui.code_editor mod.source_code (\s -> Compile s))
        right_pane =
            case mod.output of
                Err e ->
                    el [ Element.width fill, Element.height fill ] <| Element.html (explain_error e)

                Ok prog ->
                    code_rep (Tuple.first prog)
    in
    Element.column
        [ Element.width fill
        , Element.height fill
        , scrollbarY
        ]
        [ title_bar
        , Element.row
            [ Element.width fill
            , Element.height Element.fill
            , scrollbarY
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
            Element.row [ Element.height (Element.fill), Element.width fill ] [ make_output mod ]
                |> Element.layout
                    [ Background.color Pallete.bg_c
                    , Font.color Pallete.fg_c
                    , Element.clip
                    , Element.height (Element.fill)
                    , Element.width Element.fill

                    -- , Element.explain Debug.todo
                    ]


type Msg
    = WindowSizeChanged (Int, Int)
    | Recompile
    | EditorAction CodeEditor.EditorState
    | GotTimeToStart Time.Posix -- for timing
    | GotTimeEnd Time.Posix


init : a -> ( Maybe Model, Cmd Msg )
init _ =
    ( Nothing, Task.perform GotTimeToStart Time.now )


update : Msg -> Maybe Model -> ( Maybe Model, Cmd Msg )
update msg mmod =
    case mmod of
        Nothing ->
            ( Just
                { editor_state = CodeEditor.EditorState initial_input 0
                , last_run_start = Time.millisToPosix 0
                , last_run_end = Time.millisToPosix 0
                , output = compile initial_input
                , window_size = (100, 100)
                }
            , Task.perform GotTimeToStart Time.now
            )

        Just mod ->
            case msg of
                WindowSizeChanged s -> (Just mod, Cmd.none)
                EditorAction es -> 
                    ( Just { mod | editor_state = es }, Task.perform GotTimeToStart Time.now )

                Recompile ->
                    ( Just mod, Task.perform GotTimeToStart Time.now )

                GotTimeToStart t ->
                    ( Just { mod | last_run_start = t, output = compile mod.editor_state.text }, Task.perform GotTimeEnd Time.now )

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
    { editor_state : CodeEditor.EditorState
    , last_run_start : Time.Posix
    , last_run_end : Time.Posix
    , output : Result Compiler.CompilerError ( AST.Program, Analyzer.GoodProgram )
    , window_size : (Int, Int)
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
-- subscriptions _ =
--   Browser.Events.onResize (\w h -> WindowSizeChanged <| Debug.log "Changed" (w, h))