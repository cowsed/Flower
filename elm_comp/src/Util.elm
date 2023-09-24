module Util exposing (..)

import Html
import Html.Attributes
import Language


collapsable : String -> Html.Html msg -> Html.Html msg
collapsable title internals =
    Html.details [Html.Attributes.style "background-color" "gray" ] [ Html.summary [] [ Html.text title ] , internals]


type alias SourceView =
    { src : String
    , start : Int
    , end : Int
    }


last_el : List a -> Maybe a
last_el l =
    List.head (List.drop (List.length l - 1) l)

always_tail: List a -> List a
always_tail l = 
    case List.tail l of
        Just l2 -> l2
        Nothing -> []

show_source_view : SourceView -> String
show_source_view sv =
    let
        newlines =
            String.indices "\n" sv.src

        in_front_newlines =
            newlines |> List.filter (\ind -> ind <= sv.start)

        front =
            case last_el in_front_newlines of
                Just ind ->
                    ind

                Nothing ->
                    0

        line_pos =
            sv.start - front

        shown_len =
            sv.end - sv.start

        line_num =
            List.length in_front_newlines + 1

        newlines_after =
            newlines |> List.filter (\ind -> ind >= sv.end)

        end =
            case List.head newlines_after of
                Just ind ->
                    ind

                Nothing ->
                    String.length sv.src

        prefix =
            String.fromInt line_num ++ " | "

        marker_line =
            "\n" ++ String.repeat (line_pos + String.length prefix - 1) " " ++ String.repeat shown_len "^"
    in
    prefix ++ String.slice (front + 1) end sv.src ++ marker_line


addchar : String -> Char -> String
addchar s c =
    s ++ String.fromChar c


syntaxify_literal : Language.LiteralType -> String -> String
syntaxify_literal lt str =
    case lt of
        Language.StringLiteral ->
            "\"" ++ str ++ "\""

        Language.BooleanLiteral ->
            str

        Language.NumberLiteral ->
            str
