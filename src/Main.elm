module Main exposing (..)

import Analysis.Analyzer as Analyzer
import Analysis.Explanations
import Browser
import Compiler exposing (CompilerError(..), compile, explain_error)
import Editor.CodeEditor as Editor
import Editor.Util
import Element exposing (Element, alignBottom, alignTop, el, fill, scrollbarY)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input
import File
import File.Download
import File.Select
import Generating.Generator exposing (generate)
import Html
import Keyboard.Event
import Language.Syntax exposing (node_get, node_location)
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
import "std/console"


fn main() -> i32{
    console.print("Hello")
    console.print_err("To stderr")
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


header : String -> Element msg
header str =
    Element.el [ Font.size 25, Font.semiBold ] (Element.text str)


output_ui : Bool -> (Bool -> msg) -> Result CompilerError Analyzer.GoodProgram -> Element.Element msg
output_ui filter_builtins onchange res =
    Element.el []
        (case res of
            Err e ->
                explain_error e

            Ok prog ->
                Element.column [ Element.padding 10 ]
                    [ Element.Input.checkbox []
                        { onChange = onchange
                        , checked = filter_builtins
                        , icon = Element.Input.defaultCheckbox
                        , label = Element.Input.labelRight [] (Element.text "Hide Builtins")
                        }
                    , Analysis.Explanations.explain_program filter_builtins prog |> Element.el [ Border.solid, Border.width 2, Border.rounded 8, Element.padding 4 ]
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


main_menu : { items : List (Ui.MenuItem Msg) }
main_menu =
    { items =
        [ Ui.Menu "File"
            { items =
                [ Ui.Button "Save" (Just (SaveFileAs { name = "editor.flower", mimetype = "text/plain" }))
                , Ui.Button "Open" (Just (FileRequested [ "text" ] FileSelected))
                , Ui.Menu "More" { items = [ Ui.Button "thing1" Nothing, Ui.Button "thing2" Nothing ] }
                ]
            }
        , Ui.Menu "Help"
            { items =
                [ Ui.SomeThing
                    (Ui.default_link { url = "https://github.com/cowsed/Flower", label = Element.text "Documentation" })
                , Ui.SomeThing
                    (Ui.default_link { url = "https://github.com/cowsed/Flower", label = Element.text "About" })
                ]
            }
        ]
    }


make_output : Model -> Element Msg
make_output mod =
    let
        footer =
            Element.row [ Element.width fill, alignBottom, Element.padding 4, Border.widthEach { bottom = 0, left = 0, right = 0, top = 2 } ]
                [ Element.text ("Compiled in " ++ millis_elapsed mod.last_run_start mod.last_run_end ++ " ms")
                , el [ Element.centerX ] (Element.text ("Flower" ++ " v0.0.2"))
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
                    (output_ui mod.filter_builtins ToggleFilterBuiltins mod.output)
                ]
    in
    Element.column
        [ Element.width fill
        , Element.height fill
        , scrollbarY
        ]
        [ Ui.draw_main_menu main_menu
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
                    ]


type Msg
    = WindowSizeChanged ( Int, Int )
    | Recompile
    | ToggleFilterBuiltins Bool
    | EditorKey Keyboard.Event.KeyboardEvent
    | EditorAction Editor.EditorState
    | CompileStartedAtTime Time.Posix -- for timing
    | CompileFinishedAtTime Time.Posix
    | FileRequested (List String) (File.File -> Msg)
    | FileSelected File.File
    | FileLoaded String
    | SaveFileAs { name : String, mimetype : String }


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
                , filter_builtins = False
                , output = compile initial_input
                , window_size = ( 100, 100 )
                , db_console = [ "Message 1" ]
                }
            , Task.perform CompileStartedAtTime Time.now
            )

        Just mod ->
            case msg of
                FileRequested types onload ->
                    ( Just mod, File.Select.file types onload )

                FileSelected file ->
                    ( Just mod, Task.perform FileLoaded (File.toString file) )

                FileLoaded filecontents ->
                    let
                        es =
                            mod.editor_state

                        newes =
                            { es | text = filecontents }
                    in
                    update (EditorAction newes) (Just mod)

                SaveFileAs { name, mimetype } ->
                    ( Just mod
                    , File.Download.string name mimetype mod.editor_state.text
                    )

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

                ToggleFilterBuiltins b ->
                    ( Just { mod | filter_builtins = b }, Cmd.none )


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
    , filter_builtins : Bool
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
