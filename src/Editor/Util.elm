module Editor.Util exposing (..)

import Element
import Html.Attributes
import List.Extra

type alias Range =
    { low : Int, high : Int }

in_range : Range -> Int -> Bool
in_range r i =
    i >= r.low && i < r.high

flatten_2d : List (List a) -> List a
flatten_2d list =
    List.foldr (++) [] list


range_isnt_empty : Range -> Bool
range_isnt_empty r =
    if r.low == r.high then
        False

    else
        True


type alias InfoRange =
    { range : Range, color : Element.Color, on_hover : Maybe String }

insert : String -> Int -> String -> String
insert initial ind new =
    String.slice 0 ind initial ++ new ++ String.slice ind (String.length initial) initial


remove : String -> Range -> String
remove s r =
    String.slice 0 r.low s ++ String.slice r.high (String.length s) s


zip : List a -> List b -> List ( a, b )
zip =
    List.map2 Tuple.pair



tooltip : (Element.Element msg -> Element.Attribute msg) -> Element.Element Never -> Element.Attribute msg
tooltip usher tooltip_ =
    Element.inFront <|
        Element.el
            [ Element.width Element.fill
            , Element.height Element.fill
            , Element.transparent True
            , Element.mouseOver [ Element.transparent False ]
            , Element.htmlAttribute <| Html.Attributes.style "user-select" "none"
            , (usher << Element.map never) <|
                Element.el [ Element.htmlAttribute (Html.Attributes.style "pointerEvents" "none") ]
                    tooltip_
            ]
            Element.none


find_first_before: String -> Int -> String -> Maybe Int
find_first_before text ind what = 
    String.indexes what text |> List.filter (\n -> n < ind) |> List.Extra.last