module CodeEditor exposing (..)

import Element exposing (Color, Element, px, width)
import Element.Background as Background
import Element.Font as Font
import Html exposing (output)
import Html.Events
import Pallete
import Util


type alias Range =
    { low : Int, high : Int }


type alias ColoredRange =
    { range : Range, color : Color }


type alias EditorState =
    { text : String
    , cursor_pos : Int
    }


type alias EditorStyle =
    { line_height : Int
    }


slice_of_str : String -> Range -> String
slice_of_str s r =
    s |> String.dropLeft (r.low) |> String.dropRight (String.length s - r.high)


intersperse_normals : Range -> List ColoredRange -> List ColoredRange
intersperse_normals r s =
    if List.length s > 0 then
        zip s (Util.always_tail s) |> List.map (\( r1, r2 ) -> ColoredRange (Range r1.range.high r2.range.low) Pallete.fg_c)

    else
        [ ColoredRange r Pallete.fg_c ]


code_line : EditorStyle -> String -> ( Range, List ColoredRange ) -> Element.Element msg
code_line style source ( line_range, colors ) =
    let
        spans : List (Element.Element msg)
        spans =
            colors
                |> intersperse_normals line_range
                |> List.map
                    (\cr ->
                        Element.el
                            [ Font.color cr.color]
                            (Element.text (slice_of_str source cr.range))
                    )
    in
    if line_range.high > line_range.low + 1 then
        Element.row
            [ Element.width Element.fill
            , Element.spacing 0
            , Element.padding 0
            -- , Element.height (px style.line_height)
            ]
            spans
        -- [ Element.text <| slice_of_str source line_range ]

    else
        Element.el [ Element.width Element.fill, Element.height (px style.line_height) ] Element.none


zip =
    List.map2 Tuple.pair


make_splits : List Int -> List Range
make_splits l =
    case List.head l of
        Just _ ->
            zip l (Util.always_tail l) |> List.map (\( lo, hi ) -> Range (lo+1) hi)

        Nothing ->
            []


split_colors : List Range -> List ColoredRange -> List (List ColoredRange)
split_colors rs crs =
    let
        in_range : Range -> ColoredRange -> Bool
        in_range r cr =
            if r.low <= cr.range.low && r.high >= cr.range.high then
                True

            else
                False
    in
    rs |> List.map (\r -> List.filter (in_range r) crs)


code_editor : EditorState -> (EditorState -> msg) -> Element.Element msg
code_editor state onchange =
    let
        colored_ranges =[]
            -- [ ColoredRange (Range 0 10) Pallete.red_c, ColoredRange (Range 10 20) Pallete.green_c ]

        style =
            { line_height = 20 }

        newlines =
            String.indexes "\n" state.text

        splits =
            newlines |> List.append [ -1 ] |> make_splits

        color_splits : List (List ColoredRange)
        color_splits =
            split_colors splits colored_ranges

        output_lines =
            zip splits color_splits |> List.map (code_line style state.text)

        num_lines =
            List.length output_lines

        line_nums =
            Element.column
                [ Background.color Pallete.bg1_c
                , Element.paddingEach { left = 4, right = 4, top = 0, bottom = 0 }
                , Font.size style.line_height
                , Element.alignTop
                ]
                (List.range 1 num_lines |> List.map (\i -> Element.text (String.fromInt i)))
    in
    Element.el
        [ Element.scrollbarY
        , Element.width Element.fill
        ]
        (Element.row
            [ Element.spacingXY 0 2
            , Element.htmlAttribute (Html.Events.onClick (Debug.log "AHASDASD" (onchange state)))
            , Font.size style.line_height
            , Font.family [ Font.monospace ]
            , Element.width Element.fill

            -- , Element.alignTop
            -- , Element.height Element.fill
            ]
            [ line_nums
            , Element.column []
                output_lines
            ]
        )
