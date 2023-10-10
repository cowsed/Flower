module Editor.CodeEditor exposing (..)

import Editor.Util exposing (..)
import Element exposing (alignRight, px)
import Element.Background as Background
import Element.Border as Border
import Element.Events
import Element.Font as Font
import Html
import Html.Attributes
import Html.Events
import Json.Decode as Decode
import Keyboard.Event
import Keyboard.Key
import List.Extra
import Pallete
import Time exposing (Month(..))
import Util


type alias EditorState =
    { text : String
    , cursor_pos : Int
    , focused : Bool
    , info_ranges : List InfoRange
    , selection: Maybe Range 
    }


type alias EditorStyle =
    { line_height : Int
    }


range_of_str : String -> Range -> String
range_of_str s r =
    s |> String.dropLeft r.low |> String.dropRight (String.length s - r.high)


intersperse_normal_text : Range -> List InfoRange -> List InfoRange
intersperse_normal_text r s =
    if List.length s == 0 then
        [ InfoRange r Pallete.fg_c Nothing ]

    else if List.length s == 1 then
        List.head s
            |> Maybe.map
                (\c1 ->
                    [ InfoRange (Range r.low c1.range.low) Pallete.fg_c Nothing
                    , c1
                    , InfoRange (Range c1.range.high r.high) Pallete.fg_c Nothing
                    ]
                )
            |> Maybe.withDefault []
            |> List.filter (\cr -> range_isnt_empty cr.range)

    else
        case List.head s of
            Just first ->
                zip s (Util.always_tail s)
                    -- between all specified colored sections
                    |> List.map (\( r1, r2 ) -> [ r1, InfoRange (Range r1.range.high r2.range.low) Pallete.fg_c Nothing ])
                    -- 0 to first colored section
                    |> (::) [ InfoRange (Range r.low first.range.low) Pallete.fg_c Nothing ]
                    |> flatten_2d
                    -- rest of line
                    |> (\l -> List.append l (List.Extra.last s |> Maybe.map List.singleton |> Maybe.withDefault []))
                    |> (\l ->
                            List.append l
                                (List.Extra.last s
                                    |> Maybe.map (\cr -> [ InfoRange (Range cr.range.high r.high) Pallete.fg_c Nothing ])
                                    |> Maybe.withDefault []
                                )
                       )
                    -- last colored section to end
                    |> List.filter (\cr -> range_isnt_empty cr.range)

            Nothing ->
                [ InfoRange r Pallete.fg_c Nothing ]


build_colored_range : (EditorState -> msg) -> EditorState -> InfoRange -> Element.Element msg
build_colored_range onchange state ir =
    let
        am_selected: Int -> Bool
        am_selected i = 
            state.selection |> Maybe.map (\r -> if r.high /= 99999999999 then  in_range r i else False) |> Maybe.withDefault False
        onclick index =
            Element.Events.onClick (onchange { state | cursor_pos = index, focused = True, selection = Nothing })
        onmousedown index = Element.Events.onMouseDown (onchange {state | selection = Just (Range index 99999999999)})
        onmouseup index = Element.Events.onMouseUp (onchange {state | cursor_pos = index, selection = state.selection |> Maybe.map (\r -> Range r.low index)})
    in
    Element.row
        [ Font.color ir.color
        ]
        (range_of_str state.text ir.range
            |> String.toList
            |> List.map String.fromChar
            |> List.indexedMap Tuple.pair
            |> List.map
                (\( i, s ) ->
                    [ Element.el
                        [-- onclick (ir.range.low + i)
                        onmousedown (ir.range.low + i)
                        , onmouseup (ir.range.low + i)
                        , Border.widthEach { left = 1, right = 0, top = 0, bottom = 0 }
                        , if ir.range.low + i == state.cursor_pos then
                            Border.color Pallete.fg_c

                          else
                            Border.color Pallete.bg_c
                        , if am_selected (ir.range.low + i) then
                            Background.color Pallete.bg1_c
                        else 
                            Background.color Pallete.bg_c
                        ]
                        (Element.text s)
                    ]
                )
            |> flatten_2d
        )


make_splits : List Int -> List Range
make_splits l =
    case List.head l of
        Just _ ->
            zip l (Util.always_tail l) |> List.map (\( lo, hi ) -> Range (lo + 1) hi)

        Nothing ->
            []


split_colors_per_row : List Range -> List InfoRange -> List (List InfoRange)
split_colors_per_row rs crs =
    let
        range_in_range : Range -> InfoRange -> Bool
        range_in_range r cr =
            if r.low <= cr.range.low && r.high >= cr.range.high then
                True

            else
                False
    in
    rs |> List.map (\r -> List.filter (range_in_range r) crs)


code_line : (EditorState -> msg) -> EditorStyle -> EditorState -> ( Range, List InfoRange ) -> Element.Element msg
code_line onchange style state ( line_range, colors ) =
    let
        ranges =
            colors
                |> intersperse_normal_text line_range

        restofline =
            Element.el
                [ Element.width Element.fill
                , Element.height (px style.line_height)
                , Element.Events.onClick (onchange { state | cursor_pos = line_range.high })
                , alignRight
                , Border.widthEach { left = 1, right = 0, top = 0, bottom = 0 }
                , Border.color
                    (if line_range.high == state.cursor_pos then
                        if state.focused then
                            Pallete.fg_c

                        else
                            Pallete.red_c

                     else
                        Pallete.bg_c
                    )
                ]
                Element.none

        spans : List (Element.Element msg)
        spans =
            ranges
                |> List.map (build_colored_range onchange state)
                |> (\l -> List.append l [ restofline ])
    in
    Element.row
        [ Element.width Element.fill
        ]
        [ Element.row
            [ Element.width Element.fill
            , Element.spacing 0
            , Element.padding 0
            ]
            spans
        ]


code_editor : EditorState -> (EditorState -> msg) -> Element.Element msg
code_editor state onchange =
    let
        style =
            { line_height = 20 }

        newlines =
            String.indexes "\n" state.text

        splits =
            newlines |> List.append [ -1 ] |> make_splits

        color_splits : List (List InfoRange)
        color_splits =
            split_colors_per_row splits state.info_ranges

        code_lines =
            zip splits color_splits |> List.map (code_line onchange style state)

        line_nums =
            make_line_nums style (List.length code_lines)

        code_line_col =
            Element.column
                [ Element.width Element.fill
                ]
                code_lines

        decoder : Decode.Decoder ( msg, Bool )
        decoder =
            Decode.map (\ke -> ( update_editor state ke |> Tuple.mapFirst onchange)) Keyboard.Event.decodeKeyboardEvent

        key_override : Html.Attribute msg
        key_override =
            Html.Events.preventDefaultOn
                "keydown"
                decoder
    in
    Element.el
        [ Element.scrollbarY
        , Element.width Element.fill
        , Element.Events.onLoseFocus (onchange { state | focused = False })
        , Element.Events.onFocus (onchange { state | focused = True })
        , Html.Attributes.tabindex 0 |> Element.htmlAttribute
        , key_override |> Element.htmlAttribute
        , Html.Attributes.style "user-select" "none" |> Element.htmlAttribute
        ]
        (Element.row
            [ Element.spacingXY 0 2
            , Font.size style.line_height
            , Font.family [ Font.monospace ]
            , Element.width Element.fill
            ]
            [ line_nums
            , code_line_col
            ]
        )


update_editor : EditorState -> Keyboard.Event.KeyboardEvent -> (EditorState, Bool)
update_editor state ke =
    let
        action =
            action_from_key ke
    in
    action
        |> Maybe.map
            (\act ->
                case act of
                    Backspace ->
                        { state | text = remove state.text (Range (state.cursor_pos - 1) state.cursor_pos), cursor_pos = state.cursor_pos - 1 }

                    InsertAtCursor s ->
                        { state | text = insert (state.text) state.cursor_pos s, cursor_pos = state.cursor_pos + String.length s }

                    MoveCursorLeft ->
                        { state | cursor_pos = max 0 (state.cursor_pos - 1) } |> clear_selection

                    MoveCursorRight ->
                        { state | cursor_pos = min (String.length state.text - 1) (state.cursor_pos + 1) } |> clear_selection

                    MoveCursorUp ->
                        { state | cursor_pos = calc_cursor_move_up state.text state.cursor_pos } |> clear_selection

                    MoveCursorDown ->
                        { state | cursor_pos = calc_cursor_move_down state.text state.cursor_pos } |> clear_selection
            )
        |> Maybe.map used_keypress
        |> Maybe.withDefault (state, False)
clear_selection: EditorState -> EditorState
clear_selection es = {es | selection = Nothing}

used_keypress: EditorState -> (EditorState, Bool)
used_keypress es = (es, True)

calc_cursor_move_up : String -> Int -> Int
calc_cursor_move_up src i =
    let
        newlines =
            List.append [ 0 ] (String.indexes "\n" src)

        before =
            List.filter (\n -> n <= i) newlines |> Debug.log "newline split"

        prevl =
            List.Extra.getAt (List.length before - 2) before

        thisl =
            List.Extra.getAt (List.length before - 1) before

        calc_prev prevline thisline =
            let
                ll =
                    thisline - prevline |> Debug.log "prev line length"

                pos_on_line =
                    i - thisline |> Debug.log "pos on line"
            in
            min ll pos_on_line + prevline

        pos =
            Maybe.map2 calc_prev prevl thisl |> Maybe.withDefault (prevl |> Maybe.withDefault 0)
    in
    pos


calc_cursor_move_down : String -> Int -> Int
calc_cursor_move_down src i =
    let
        newlines =
            List.append [ 0 ] (String.indexes "\n" src)

        after =
            List.Extra.find (\n -> n > i) newlines

        after2 =
            after |> Maybe.andThen (\v -> List.Extra.find (\n -> n > v) newlines)

        before =
            newlines |> List.filter (\n -> n <= i) |> List.Extra.last

        calc_prev thislinestart thislineend nextlineend =
            let
                ll =
                    nextlineend - thislineend |> Debug.log "next line length"

                pos_on_line =
                    i - thislinestart |> Debug.log "pos on line"
            in
            min ll pos_on_line + thislineend

        pos =
            Maybe.map3 calc_prev before after after2 |> Maybe.withDefault (String.length src - 1)
    in
    pos


type KeyAction
    = Backspace
    | InsertAtCursor String
    | MoveCursorLeft
    | MoveCursorRight
    | MoveCursorUp
    | MoveCursorDown


action_from_key : Keyboard.Event.KeyboardEvent -> Maybe KeyAction
action_from_key ke =
    case is_text_keye (Debug.log "Key: " ke) of
        Just s ->
            InsertAtCursor s |> Just

        Nothing ->
            case ke.keyCode of
                Keyboard.Key.Backspace ->
                    Just Backspace

                Keyboard.Key.Enter ->
                    Just (InsertAtCursor "\n")

                Keyboard.Key.Tab ->
                    Just (InsertAtCursor "    ")

                Keyboard.Key.Left ->
                    MoveCursorLeft |> Just

                Keyboard.Key.Right ->
                    MoveCursorRight |> Just

                Keyboard.Key.Up ->
                    MoveCursorUp |> Just

                Keyboard.Key.Down ->
                    MoveCursorDown |> Just

                _ ->
                    Nothing


is_text_keye : Keyboard.Event.KeyboardEvent -> Maybe String
is_text_keye ke =
    if ke.ctrlKey || ke.altKey || ke.metaKey then
        Nothing

    else
        ke.key
            |> Maybe.andThen
                (\s ->
                    if String.length s == 1 then
                        Just s

                    else
                        Nothing
                )


make_line_nums : EditorStyle -> Int -> Element.Element msg
make_line_nums style len =
    Element.column
        [ Background.color Pallete.bg1_c
        , Element.paddingEach { left = 4, right = 4, top = 0, bottom = 0 }
        , Font.size style.line_height
        , Element.alignTop
        , Element.htmlAttribute <| Html.Attributes.style "user-select" "none"
        ]
        (List.range 1 len |> List.map (\i -> Element.text (String.fromInt i)))
