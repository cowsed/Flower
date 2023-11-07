module ListDict exposing (..)


type ListDict k v
    = ListDict
        { elems : List ( k, v )
        }


empty : ListDict k v
empty =
    ListDict { elems = [] }


get_elems : ListDict k v -> List ( k, v )
get_elems d =
    case d of
        ListDict ld ->
            ld.elems


insert : k -> v -> ListDict k v -> ListDict k v
insert k v dict =
    if has_key k dict then
        -- update
        List.foldl
            (\( elk, elv ) els ->
                (if elk == k then
                    [ ( k, v ) ]

                 else
                    [ ( elk, elv ) ]
                )
                    |> List.append els
            )
            []
            (dict |> get_elems)
            |> (\els -> { elems = els })
            |> ListDict

    else
        ListDict { elems = List.append (get_elems dict) [ ( k, v ) ] }



--Insert a key-value pair into a dictionary. Replaces value when there is a collision.


to_list : ListDict k v -> List ( k, v )
to_list d =
    d |> get_elems


from_list : List ( k, v ) -> ListDict k v
from_list l =
    List.foldl
        (\( k, v ) ld -> insert k v ld)
        empty
        l


values : ListDict k v -> List v
values d =
    d |> get_elems |> List.map Tuple.second


keys : ListDict k v -> List k
keys d =
    d |> get_elems |> List.map Tuple.first


drop : k -> ListDict k v -> ListDict k v
drop todrop ld =
    ld|> get_elems
        |> List.filter (\( k, _ ) -> k /= todrop)
        |> from_list


has_key : k -> ListDict k v -> Bool
has_key k dict =
    List.any (\( key, _ ) -> key == k) (dict |> get_elems)


get : k -> ListDict k v -> Maybe v
get k dict =
    List.foldl
        (\( el_k, el_v ) state ->
            case state of
                Just val ->
                    Just val

                Nothing ->
                    if el_k == k then
                        Just el_v

                    else
                        Nothing
        )
        Nothing
        (dict |> get_elems)
