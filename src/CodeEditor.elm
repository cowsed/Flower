module CodeEditor exposing (..)

import Element exposing (Color, px)
import Element.Background as Background
import Element.Font as Font
import Html.Events
import List.Extra
import Pallete
import Time exposing (Month(..))
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


intersperse_normals : Range -> List ColoredRange -> List ColoredRange
intersperse_normals r s =
    if List.length s == 0 then
        [ ColoredRange r Pallete.fg_c ]

    else if List.length s == 1 then
        List.head s
            |> Maybe.map
                (\c1 ->
                    [ ColoredRange (Range r.low c1.range.low) Pallete.fg_c
                    , c1
                    , ColoredRange (Range c1.range.high r.high) Pallete.fg_c
                    ]
                )
            |> Maybe.withDefault []
            |> List.filter (\cr -> non_empty_range cr.range)

    else
        case List.head s of
            Just first ->
                zip s (Util.always_tail s)
                    -- between all specified colored sections
                    |> List.map (\( r1, r2 ) -> [ r1, ColoredRange (Range r1.range.high r2.range.low) Pallete.fg_c ])
                    -- 0 to first colored section
                    |> (::) [ ColoredRange (Range r.low first.range.low) Pallete.fg_c ]
                    |> flatten_2d
                    -- rest of line
                    |> (\l -> List.append l (List.Extra.last s |> Maybe.map List.singleton |> Maybe.withDefault [] ))
                    |> (\l ->
                            List.append l
                                (List.Extra.last s
                                    |> Maybe.map (\cr -> [ ColoredRange (Range cr.range.high r.high) Pallete.fg_c ])
                                    |> Maybe.withDefault []
                                )
                       )
                    -- last colored section to end
                    |> List.filter (\cr -> non_empty_range cr.range)

            Nothing ->
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
                            [ Font.color cr.color ]
                            (Element.text (slice_of_str source cr.range))
                    )
    in
    if line_range.high > line_range.low then
        Element.row
            [ Element.width Element.fill
            , Element.spacing 0
            , Element.padding 0
            ]
            spans
        -- [ Element.text <| slice_of_str source line_range ]

    else
        Element.el [ Element.width Element.fill, Element.height (px style.line_height) ] Element.none


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


code_editor : List ColoredRange -> EditorState -> (EditorState -> msg) -> Element.Element msg
code_editor colored_ranges state onchange =
    let

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
