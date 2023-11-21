module Ui exposing (..)

import Element
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input
import Html.Attributes
import Pallete
import Time exposing (..)


type alias MenuConfig msg =
    List (MenuItem msg)


type MenuItem msg
    = Menu String (MenuConfig msg)
    | Button String (Maybe msg)
    | SomeThing (Element.Element msg)
    | Spacer


draw_menu_item_menu : Int -> String -> MenuConfig msg -> Element.Element msg
draw_menu_item_menu level name mi =
    let
        is_top_level =
            level == 0

        direction =
            if is_top_level then
                Element.below

            else
                Element.onRight

        suffix =
            if not is_top_level then
                " ▶"

            else
                ""

        title_without_submenu =
            Element.row
                [ Element.width Element.fill
                ]
                [ Element.text name, Element.el [ Element.alignRight ] (Element.text suffix) ]

        menu =
            Element.column
                [ Background.color Pallete.bg1_c
                , Element.spacingXY 0 2
                , Element.paddingEach { left = 3, right = 0, top = 2, bottom = 2 }
                , Element.width Element.shrink
                , Border.color Pallete.fg_c
                , Border.width 1
                ]
                (List.map (draw_menu_item (level + 1)) mi)

        title_and_submenu : Element.Element msg
        title_and_submenu =
            Element.el
                [ Element.transparent True
                , Element.mouseOver [ Element.transparent False ]
                , direction menu
                , Background.color Pallete.bg_c
                , Element.width Element.fill
                ]
                title_without_submenu

        attrs =
            [ Element.inFront title_and_submenu ]
                |> (\l ->
                        if is_top_level then
                            l

                        else
                            List.append l [ Element.width Element.fill ]
                   )
    in
    Element.el attrs title_without_submenu


draw_menu_item : Int -> MenuItem msg -> Element.Element msg
draw_menu_item level it =
    case it of
        Menu s mc ->
            draw_menu_item_menu level s mc

        Button s onpress ->
            Element.Input.button
                [ Element.width Element.fill
                , Element.mouseOver
                    [ Background.color Pallete.bg_c
                    ]
                ]
                { onPress = onpress, label = Element.text s }

        SomeThing thing ->
            thing

        Spacer ->
            Element.el
                [ Element.width Element.fill
                , Border.widthEach { left = 0, right = 0, top = 0, bottom = 1 }
                , Border.color Pallete.fg_c
                ]
                Element.none
                |> Element.el
                    [ Element.width Element.fill
                    , Element.paddingEach { left = 2, right = 2, top = 2, bottom = 6 }
                    ]


draw_main_menu : MenuConfig msg -> Element.Element msg
draw_main_menu mc =
    Element.row
        [ Font.size 18
        , Element.width Element.fill
        , Element.paddingEach { top = 2, bottom = 1, left = 0, right = 0 }
        , Background.color Pallete.bg1_c
        , Element.spacing 5
        ]
        (mc |> List.map (draw_menu_item 0))


default_link : { url : String, label : Element.Element msg } -> Element.Element msg
default_link conf =
    Element.newTabLink
        [ Border.widthEach { top = 0, bottom = 1, left = 0, right = 0 }
        , Border.color (Element.rgba 0 0 0 0)
        , Element.mouseOver [ Border.color Pallete.blue_c ]
        , Font.color Pallete.blue_c
        ]
        conf


space : Element.Element msg
space =
    Element.text " "


comma_space : Element.Element msg
comma_space =
    Element.text ", "


color_text : Element.Color -> String -> Element.Element msg
color_text col str =
    Element.el [ Font.color col ] (Element.text str)


code : Element.Element msg -> Element.Element msg
code el =
    Element.el [ Border.rounded 4, Font.family [ Font.monospace ], Background.color Pallete.bg1_c ] el


code_text : String -> Element.Element msg
code_text s =
    s |> (Element.text >> code)


hoverer : Element.Element msg -> Element.Element msg -> Element.Element msg
hoverer tooltip base =
    Element.el
        [ Element.inFront
            (Element.el
                [ Element.transparent True
                , Element.mouseOver [ Element.transparent False ]
                , Element.htmlAttribute <| Html.Attributes.style "user-select" "none"
                ]
                (Element.el [ Element.above (Element.el [ Element.centerX, Element.htmlAttribute (Html.Attributes.style "pointerEvents" "none") ] tooltip) ] base)
            )
        ]
        base


tooltip_styling : Element.Element msg -> Element.Element msg
tooltip_styling el =
    el |> Element.el [ Background.color Pallete.bg1_c, Border.color Pallete.fg_c, Element.padding 10, Border.width 2, Border.rounded 2, Border.shadow { offset = ( 1, 1 ), size = 1.0, blur = 1.0, color = Pallete.fg_c } ]


stringify_time : Time.Zone -> Time.Posix -> String
stringify_time zone p =
    stringify_month (Time.toMonth zone p)
        ++ " "
        ++ (Time.toDay zone p |> String.fromInt)
        ++ ", "
        ++ (Time.toYear zone p |> String.fromInt)
        ++ " "
        ++ (Time.toHour zone p |> String.fromInt)
        ++ ":"
        ++ (Time.toMinute zone p |> String.fromInt)
        ++ " "
        ++ (Time.toSecond zone p |> String.fromInt)
        ++ ":"
        ++ (Time.toMillis zone p |> String.fromInt)


stringify_month : Time.Month -> String
stringify_month mon =
    case mon of
        Time.Jan ->
            "Jan"

        Time.Feb ->
            "Feb"

        Time.Mar ->
            "Mar"

        Time.Apr ->
            "Apr"

        Time.May ->
            "May"

        Time.Jun ->
            "Jun"

        Time.Jul ->
            "Jul"

        Time.Aug ->
            "Aug"

        Time.Sep ->
            "Sep"

        Time.Oct ->
            "Oct"

        Time.Nov ->
            "Nov"

        Time.Dec ->
            "Dec"
