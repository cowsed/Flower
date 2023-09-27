module Ui exposing (..)
import Time exposing (..)
import Html exposing (..)
import Html.Attributes exposing (style, spellcheck)
import Html.Events exposing (onInput)

import Pallete


code_editor : String -> (String -> msg)-> Html msg
code_editor src onedit=
    Html.textarea
        [ style "font-size" "15px"
        , style "overflow" "auto"
        , style "height" "400px"
        , style "width" "400px"
        , style "padding" "10px"
        , style "background-color" Pallete.bg
        , style "border-radius" "8px"
        , style "border-style" "solid"
        , style "border-width" "2px"
        , style "border-color" "black"
        , style "float" "left"
        , spellcheck False
        , onInput onedit
        ]
        [ text src
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
