module CodeEditor exposing (..)

import Browser.Events as Events
import Element exposing (Color, alignRight, px)
import Element.Background as Background
import Element.Border as Border
import Element.Events
import Element.Font as Font
import Html.Attributes
import Html.Events
import Json.Decode as Decode
import Keyboard.Event
import Keyboard.Key
import List.Extra
import Pallete
import Time exposing (Month(..))
import Util


type alias Range =
    { low : Int, high : Int }


type alias InfoRange =
    { range : Range, color : Color, on_hover : Maybe String }


type alias EditorState =
    { text : String
    , cursor_pos : Int
    , focused : Bool
    }


type alias EditorStyle =
    { line_height : Int
    }


in_range : Range -> Int -> Bool
in_range r i =
    i >= r.low && i < r.high


range_of_str : String -> Range -> String
range_of_str s r =
    s |> String.dropLeft r.low |> String.dropRight (String.length s - r.high)


flatten_2d : List (List a) -> List a
flatten_2d list =
    List.foldr (++) [] list


non_empty_range : Range -> Bool
non_empty_range r =
    if r.low == r.high then
        False

    else
        True


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
            |> List.filter (\cr -> non_empty_range cr.range)

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
                    |> List.filter (\cr -> non_empty_range cr.range)

            Nothing ->
                [ InfoRange r Pallete.fg_c Nothing ]


tooltip : (Element.Element msg -> Element.Attribute msg) -> Element.Element Never -> Element.Attribute msg
tooltip usher tooltip_ =
    Element.inFront <|
        Element.el
            [ Element.width Element.fill
            , Element.height Element.fill
            , Element.transparent True
            , Element.mouseOver [ Element.transparent False ]
            , Element.htmlAttribute <| Html.Attributes.style "user-select" "none"
            , (usher << Element.map never) <|
                Element.el [ Element.htmlAttribute (Html.Attributes.style "pointerEvents" "none") ]
                    tooltip_
            ]
            Element.none


element_info : (EditorState -> msg) -> EditorState -> InfoRange -> Element.Element msg
element_info onchange state ir =
    let
        focus_handler =
            Element.Events.onClick (onchange { state | focused = True })

        tool =
            ir.on_hover
                |> Maybe.map
                    (\t ->
                        tooltip Element.above
                            (Element.el
                                [ Background.color Pallete.bg1_c
                                , Element.padding 6
                                , Border.rounded 6
                                ]
                                (Element.text t)
                            )
                    )
    in
    Element.row
        [ Font.color ir.color

        -- , Element.Events.onDoubleClick (onchange state)
        -- , tool |> Maybe.withDefault (Font.color ir.color)
        ]
        (range_of_str state.text ir.range
            |> String.toList
            |> List.map String.fromChar
            |> List.indexedMap Tuple.pair
            |> List.map
                (\( i, s ) ->
                    [ Element.el
                        ([ Element.Events.onMouseDown (onchange { state | cursor_pos = ir.range.low + i, focused = True })
                         , Border.widthEach { left = 1, right = 0, top = 0, bottom = 0 }

                         -- , Element.Events.onMouseDown (onchange {state | text = insert state.text state.cursor_pos "A"})
                         ]
                            |> List.append
                                (if ir.range.low + i == state.cursor_pos then
                                    [ Border.color Pallete.fg_c
                                    ]

                                 else
                                    [ Border.color Pallete.bg_c ]
                                )
                        )
                        (Element.text s)
                    ]
                )
            |> flatten_2d
        )


insert : String -> Int -> String -> String
insert initial ind new =
    String.slice 0 ind initial ++ new ++ String.slice ind (String.length initial) initial


remove : String -> Range -> String
remove s r =
    String.slice 0 r.low s ++ String.slice r.high (String.length s) s


zip : List a -> List b -> List ( a, b )
zip =
    List.map2 Tuple.pair


make_splits : List Int -> List Range
make_splits l =
    case List.head l of
        Just _ ->
            zip l (Util.always_tail l) |> List.map (\( lo, hi ) -> Range (lo + 1) hi)

        Nothing ->
            []


split_colors : List Range -> List InfoRange -> List (List InfoRange)
split_colors rs crs =
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
        focus_handler =
            Element.Events.onClick (onchange { state | focused = True })

        ranges =
            colors
                |> intersperse_normal_text line_range

        restofline =
            Element.el
                [ focus_handler
                , Element.width Element.fill
                , Element.height (px style.line_height)
                , Element.Events.onClick (onchange { state | cursor_pos = line_range.high })
                , alignRight
                , Border.widthEach { left = 1, right = 0, top = 0, bottom = 0 }
                , Border.color
                    (if line_range.high == state.cursor_pos then
                        Pallete.fg_c

                     else
                        Pallete.bg_c
                    )
                ]
                Element.none

        spans : List (Element.Element msg)
        spans =
            ranges
                |> List.map (element_info onchange state)
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


code_editor : List InfoRange -> EditorState -> (EditorState -> msg) -> Element.Element msg
code_editor colored_ranges state onchange =
    let
        style =
            { line_height = 20 }

        newlines =
            String.indexes "\n" state.text

        splits =
            newlines |> List.append [ -1 ] |> make_splits

        color_splits : List (List InfoRange)
        color_splits =
            split_colors splits colored_ranges

        output_lines =
            zip splits color_splits |> List.map (code_line onchange style state)

        num_lines =
            List.length output_lines

        line_nums =
            Element.column
                [ Background.color Pallete.bg1_c
                , Element.paddingEach { left = 4, right = 4, top = 0, bottom = 0 }
                , Font.size style.line_height
                , Element.alignTop
                , Element.htmlAttribute <| Html.Attributes.style "user-select" "none"
                ]
                (List.range 1 num_lines |> List.map (\i -> Element.text (String.fromInt i)))
    in
    Element.el
        [ Element.scrollbarY
        , Element.width Element.fill
        , Element.Events.onLoseFocus (onchange { state | focused = False })
        , Element.Events.onFocus (onchange { state | focused = True })
        , Html.Attributes.tabindex 0 |> Element.htmlAttribute
        , Html.Events.preventDefaultOn "keydown" (Decode.succeed (onchange (update_editor state ), True)) |> Element.htmlAttribute
        ]
        (Element.row
            [ Element.spacingXY 0 2
            , Font.size style.line_height
            , Font.family [ Font.monospace ]
            , Element.width Element.fill
            ]
            [ line_nums
            , Element.column
                [ Element.width Element.fill
                ]
                output_lines
            ]
        )


update_editor : EditorState -> Keyboard.Event.KeyboardEvent -> EditorState
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
                        { state | text = insert state.text state.cursor_pos s, cursor_pos = state.cursor_pos + String.length s }

                    MoveCursorLeft ->
                        { state | cursor_pos = max 0 (state.cursor_pos - 1) }

                    MoveCursorRight ->
                        { state | cursor_pos = min (String.length state.text - 1) (state.cursor_pos + 1) }
            )
        |> Maybe.withDefault state


type KeyAction
    = Backspace
    | InsertAtCursor String
    | MoveCursorLeft
    | MoveCursorRight


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
                        Debug.log s Nothing
                )
