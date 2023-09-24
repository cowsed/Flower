module Util exposing (..)

import Language


type alias SourceView =
    { src : String
    , start : Int
    , end : Int
    }


last_el : List a -> Maybe a
last_el l =
    List.head (List.drop (List.length l - 1) l)


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
    in
    String.fromInt line_num ++ " | " ++ String.slice (front + 1) end sv.src


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
