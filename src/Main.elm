module Main exposing (..)

import Analysis.Analyzer as Analyzer
import Analysis.Explanations
import Browser
import Compiler exposing (CompilerError(..), compile, explain_error)
import Editor.CodeEditor as Editor
import Editor.Util
import Element exposing (Element, alignBottom, alignRight, alignTop, el, fill, scrollbarY)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Generating.Generator exposing (generate)
import Html
import Keyboard.Event
import Language.Syntax as Syntax exposing (Node, node_get, node_location)
import Pallete
import Parser.Lexer as Lexer
import Parser.ParserExplanations
import Task
import Time
import Ui
import Util exposing (escape_result)



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
import "std"

struct A{
    a: i32
}

fn main() -> i32{
    std.puts("Hello")

}
"""



{--"""module main

// importing the standard library
import "std"


fn add(a: u8, b: u8) {
    return a + b
}


fn main() -> i32{
    a: u8 = 1
    b: u8 = 2
    var res: u8 = add(a, b)
    std.println("{a} + {b} = {res}")
    return 0
}
"""
-}
{-
   type Positive[N] = N | n >= 0

   struct a{
       val: u8
   }

   enum Result[E, T]{
       Err(E)
       Res(T)
   }

   fn sqrt(v: bool ) -> f64{
       return v/2
   }

-}


header str =
    Element.el [ Font.size 25, Font.semiBold ] (Element.text str)


output_ui : Result CompilerError Analyzer.GoodProgram -> Element.Element msg
output_ui res =
    Element.el []
        (case res of
            Err e ->
                explain_error e

            Ok prog ->
                Element.column [ Element.padding 10 ]
                    [ Analysis.Explanations.explain_program prog |> Element.el [ Border.solid, Border.width 2, Border.rounded 8, Element.padding 4 ]
                    , Parser.ParserExplanations.explain_program prog.ast
                    , header "LLVM IR"
                    , generate prog |> .src |> Element.text |> Ui.code |> Element.el [ Border.solid, Border.width 2, Border.rounded 8, Element.padding 4 ]
                    ]
        )


color_tok_type : Lexer.TokenType -> Element.Color
color_tok_type tt =
    case tt of
        Lexer.Symbol _ ->
            Pallete.orange_c

        Lexer.Keyword _ ->
            Pallete.red_c

        Lexer.CommentToken _ ->
            Pallete.gray_c

        Lexer.Literal _ _ ->
            Pallete.aqua_c

        _ ->
            Pallete.fg_c


range_from_toks : List Lexer.Token -> List Editor.Util.InfoRange
range_from_toks toks =
    toks
        |> List.map
            (\t ->
                Editor.Util.InfoRange
                    (Editor.Util.Range (node_location t).start (node_location t).end)
                    (color_tok_type (node_get t))
                    (Just <| Lexer.syntaxify_token (node_get t))
            )


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
            Element.row [ Element.width fill, alignBottom, Element.padding 4, Border.widthEach { bottom = 0, left = 0, right = 0, top = 2 } ]
                [ Element.text ("Compiled in " ++ millis_elapsed mod.last_run_start mod.last_run_end ++ " ms")
                ]

        left_pane =
            Element.el
                [ Element.width fill
                , Element.height fill
                , Element.paddingEach { top = 0, bottom = 0, left = 0, right = 4 }
                , Border.color Pallete.fg_c
                , Border.solid
                , Border.width 2
                ]
            <|
                Editor.code_editor mod.editor_state (\s -> EditorAction s)

        right_pane =
            Element.column [ Element.width fill, Element.height fill, alignTop, scrollbarY ]
                [ Element.el
                    [ Element.width fill
                    , Element.height Element.fill
                    ]
                    (output_ui mod.output)
                ]
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
            ]
        , footer
        ]


view : Maybe Model -> Html.Html Msg
view mmod =
    case mmod of
        Nothing ->
            Html.text "Not Loaded Yet"

        Just mod ->
            Element.row [ Element.height Element.fill, Element.width fill ] [ make_output mod ]
                |> Element.layout
                    [ Background.color Pallete.bg_c
                    , Font.color Pallete.fg_c
                    , Element.clip
                    , Element.height Element.fill
                    , Element.width Element.fill

                    -- , Element.explain Debug.todo
                    ]


type Msg
    = WindowSizeChanged ( Int, Int )
    | Recompile
    | EditorKey Keyboard.Event.KeyboardEvent
    | EditorAction Editor.EditorState
    | CompileStartedAtTime Time.Posix -- for timing
    | CompileFinishedAtTime Time.Posix


init : a -> ( Maybe Model, Cmd Msg )
init _ =
    ( Nothing, Task.perform CompileStartedAtTime Time.now )


update : Msg -> Maybe Model -> ( Maybe Model, Cmd Msg )
update msg mmod =
    case mmod of
        Nothing ->
            ( Just
                { editor_state = Editor.EditorState initial_input 0 False [] Nothing False
                , last_run_start = Time.millisToPosix 0
                , last_run_end = Time.millisToPosix 0
                , output = compile initial_input
                , window_size = ( 100, 100 )
                , db_console = [ "Message 1" ]
                }
            , Task.perform CompileStartedAtTime Time.now
            )

        Just mod ->
            case msg of
                WindowSizeChanged s ->
                    ( Just { mod | window_size = s }, Cmd.none )

                EditorKey ke ->
                    let
                        newes =
                            if mod.editor_state.focused then
                                Editor.update_editor mod.editor_state ke |> Tuple.first

                            else
                                mod.editor_state

                        m =
                            { mod | editor_state = newes }
                    in
                    update (EditorAction newes) (Just m)

                EditorAction es ->
                    ( Just { mod | editor_state = es, db_console = List.append mod.db_console [ "editor action: selection = " ++ Debug.toString es.selection ] }, Task.perform CompileStartedAtTime Time.now )

                Recompile ->
                    ( Just mod, Task.perform CompileStartedAtTime Time.now )

                CompileStartedAtTime t ->
                    ( Just { mod | last_run_start = t, output = compile mod.editor_state.text }, Task.perform CompileFinishedAtTime Time.now )

                CompileFinishedAtTime t ->
                    let
                        es =
                            mod.editor_state

                        colored_ranges =
                            mod.output
                                |> Result.map (\gp -> range_from_toks gp.ast.src_tokens)
                                |> Result.mapError
                                    (\e ->
                                        case e of
                                            Compiler.Parse _ toks ->
                                                range_from_toks toks

                                            Compiler.Analysis _ ast ->
                                                range_from_toks ast.src_tokens

                                            _ ->
                                                []
                                    )
                                |> escape_result

                        new_es =
                            { es | info_ranges = colored_ranges }
                    in
                    ( { mod | last_run_end = t, editor_state = new_es }
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
    { editor_state : Editor.EditorState
    , last_run_start : Time.Posix
    , last_run_end : Time.Posix
    , output : Result Compiler.CompilerError Analyzer.GoodProgram
    , window_size : ( Int, Int )
    , db_console : List String
    }



-- main : Program () Model Msg


main : Program () (Maybe Model) Msg
main =
    Browser.element
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        }


subscriptions : Maybe Model -> Sub Msg
subscriptions _ =
    Sub.batch []
