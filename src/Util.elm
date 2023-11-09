module Util exposing (..)

import Element exposing (Element)
import Html
import Html.Attributes
import Language.Syntax as Syntax


escape_result : Result er er -> er
escape_result res =
    case res of
        Err e ->
            e

        Ok v ->
            v


collapsable_el : Element.Element msg -> Element.Element msg -> Element.Element msg
collapsable_el header body =
    Element.column [] [ header, body ]


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


type Bullet msg
    = Bullet (Element.Element msg) (List (Bullet msg))


viewBullet : Bullet msg -> Element msg
viewBullet (Bullet text children) =
    Element.row [ Element.spacing 12 ]
        [ Element.el [ Element.alignTop ] (Element.text "•")
        , Element.column [ Element.spacing 6 ] (text :: List.map viewBullet children)
        ]


viewBulletList : List (Bullet msg) -> Element msg
viewBulletList bullets =
    Element.column [ Element.spacing 6 ] (List.map viewBullet bullets)


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


addchar : String -> Char -> String
addchar s c =
    s ++ String.fromChar c


syntaxify_literal : Syntax.LiteralType -> String -> String
syntaxify_literal lt str =
    case lt of
        Syntax.StringLiteral ->
            "\"" ++ str ++ "\""

        Syntax.NumberLiteral ilt ->
            str |> String.append (Debug.toString ilt)
