module Ui exposing (..)

import Element
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Html.Attributes
import Pallete
import Time exposing (..)


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


hoverer : Element.Element msg -> Element.Element msg -> Element.Element msg
hoverer tooltip base =
    Element.el
        [ Element.inFront
            (Element.el
                [ Element.transparent True
                , Element.mouseOver [ Element.transparent False ]
                , Element.htmlAttribute <| Html.Attributes.style "user-select" "none"
                ]
                (Element.el [ Element.above (Element.el [Element.centerX, Element.htmlAttribute (Html.Attributes.style "pointerEvents" "none") ] tooltip) ] base)
            )
        ]
        base

tooltip_styling: Element.Element msg -> Element.Element msg
tooltip_styling el = el |> Element.el [Background.color Pallete.bg1_c, Border.color Pallete.fg_c, Element.padding 10, Border.width 2, Border.rounded 2, Border.shadow {offset = (1,1), size = 1.0, blur = 1.0, color = Pallete.fg_c}]


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
