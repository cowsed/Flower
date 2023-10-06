module CodeEditor exposing (..)

import Element exposing (Color, px)
import Element.Background as Background
import Element.Border
import Element.Events
import Element.Font as Font
import Html.Attributes
import Html.Events
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
            , (usher << Element.map never) <|
                Element.el [ Element.htmlAttribute (Html.Attributes.style "pointerEvents" "none") ]
                    tooltip_
            ]
            Element.none


element_info : String -> InfoRange -> Element.Element msg
element_info source ir =
    let
        s =
            ir.on_hover

        tool =
            s
                |> Maybe.map
                    (\t ->
                        tooltip Element.above
                            (Element.el
                                [ Background.color Pallete.bg1_c
                                , Element.padding 6
                                , Element.Border.rounded 6
                                ]
                                (Element.text t)
                            )
                    )
    in
    Element.el
        [ Font.color ir.color
        , tool |> Maybe.withDefault (Font.color ir.color)
        ]
        (Element.text (slice_of_str source ir.range))


code_line : EditorStyle -> String -> Int -> ( Range, List InfoRange ) -> Element.Element msg
code_line style source cursor ( line_range, colors ) =
    let
        ranges =
            colors
                |> intersperse_normal_text line_range

        spans : List (Element.Element msg)
        spans =
            ranges
                |> List.map (element_info source)
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


split_colors : List Range -> List InfoRange -> List (List InfoRange)
split_colors rs crs =
    let
        in_range : Range -> InfoRange -> Bool
        in_range r cr =
            if r.low <= cr.range.low && r.high >= cr.range.high then
                True

            else
                False
    in
    rs |> List.map (\r -> List.filter (in_range r) crs)


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
            zip splits color_splits |> List.map (code_line style state.text state.cursor_pos)

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
