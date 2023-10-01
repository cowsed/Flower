module Ui exposing (..)

import Element exposing (Element)
import Element.Font as Font
import Html
import Html.Attributes exposing (spellcheck, style)
import Html.Events exposing (onInput)
import Pallete
import ParserCommon
import Time exposing (..)
import ParserExplanations


code_rep : ParserCommon.Program -> Element msg
code_rep prog =
    Element.column
        [ Element.width Element.fill
        , Element.height Element.fill
        , Font.family [ Font.monospace ]
        ]
        [ Element.html (ParserExplanations.syntaxify_program prog)
        ]


code_editor : String -> (String -> msg) -> Html.Html msg
code_editor src onedit =
    Html.textarea
        [ style "font-size" "15px"
        , style "background-color" Pallete.bg
        , style "overflow" "none"
        , style "border-color" Pallete.fg
        , style "width" "50%"
        , style "height" "99%"
                -- , style "padding" "5px"
        , style "resize" "none"
        , spellcheck False
        , onInput onedit
        ]
        [ Html.text src
        ]


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
