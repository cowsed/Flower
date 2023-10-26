module Util exposing (..)

import Html
import Html.Attributes
import Language.Language as Language

import Element exposing (Element)

escape_result : Result er er -> er
escape_result res =
    case res of
        Err e ->
            e

        Ok v ->
            v 


collapsable : Html.Html msg -> Html.Html msg -> Html.Html msg
collapsable title internals =
    Html.details
        [ Html.Attributes.style "margin" "10px"
        , Html.Attributes.style "border-radius" "4px"
        , Html.Attributes.style "border-style" "solid"
        , Html.Attributes.style "border-width" "1px"
        , Html.Attributes.style "padding" "5px"
        , Html.Attributes.style "width" "fit-content"
        ]
        [ Html.summary [] [ title ], internals ]




type Bullet
    = Bullet String (List Bullet)


bullet : Bullet
bullet =
    Bullet "UPSC"
        [ Bullet "Essay"
            [ Bullet "If progress is not engendered it will be" []
            , Bullet "Poverty is worst form of violence" []
            , Bullet "blockchain and corruption"
                [ Bullet "beneficiary verified public registries to" []
                , Bullet "corruption is often related to delayed or" []
                ]
            , Bullet "you can learn anything from anywhere"
                [ Bullet "history" []
                , Bullet "Israel - water scarce - learn importance" []
                ]
            ]
        ]


viewBullet : Bullet -> Element msg
viewBullet (Bullet text children) =
    Element.row [ Element.spacing 12 ]
        [ Element.el [ Element.alignTop ] (Element.text "•")
        , Element.column [ Element.spacing 6 ] (Element.text text :: List.map viewBullet children)
        ]


type alias SourceView =
    { src : String
    , start : Int
    , end : Int
    }
invalid_sourceview: SourceView
invalid_sourceview = {src = "", start = -1, end = -1}
merge_sv: SourceView -> SourceView -> SourceView
merge_sv sv1 sv2 = 
    {src = sv1.src
    , start = min sv1.start sv2.start
    , end = max sv1.end sv2.end
    }

merge_svs: SourceView -> List SourceView -> SourceView
merge_svs start list = 
    List.foldl merge_sv start list

last_el : List a -> Maybe a
last_el l =
    List.head (List.drop (List.length l - 1) l)


always_tail : List a -> List a
always_tail l =
    case List.tail l of
        Just l2 ->
            l2

        Nothing ->
            []


show_source_view_not_line: SourceView -> String
show_source_view_not_line sv =
    String.slice sv.start sv.end sv.src

show_source_view : SourceView -> String
show_source_view sv =
    let
        newlines =
            String.indices "\n" sv.src

        in_front_newlines =
            newlines |> List.filter (\ind -> ind < sv.start)

        front =
            case last_el in_front_newlines of
                Just ind ->
                    ind

                Nothing ->
                    0
        we_are_newline = case newlines |> List.filter (\ind -> ind == sv.start) |> List.length of
            0 -> False
            _ -> True


        line_pos =
            sv.start - front

        shown_len =
            sv.end - sv.start

        line_num =
            List.length in_front_newlines + 1

        newlines_after =
            newlines |> List.filter (\ind -> ind >= sv.end)

        end =
            if we_are_newline then
                sv.start

            else
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
