module ListDict exposing (..)


type alias ListDict k v =
    { elems : List ( k, v )
    }


empty : ListDict k v
empty =
    ListDict []



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
            dict.elems
            |> ListDict

    else
        { dict | elems = List.append dict.elems [ ( k, v ) ] }



--Insert a key-value pair into a dictionary. Replaces value when there is a collision.

to_list: ListDict k v -> List (k,v)
to_list d = d.elems

has_key : k -> ListDict k v -> Bool
has_key k dict =
    List.any (\( key, _ ) -> key == k) dict.elems


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
        dict.elems
