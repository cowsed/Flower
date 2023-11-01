module ListSet exposing (..)


type alias ListSet a =
    { elems : List a
    }


insert : a -> ListSet a -> ListSet a
insert el ls =
    if member el ls then
        ls
        -- here already

    else
        -- not here, addon
        { ls | elems = List.append ls.elems [ el ] }


member : a -> ListSet a -> Bool
member el ls =
    List.any (\e -> e == el) ls.elems

empty : ListSet a
empty = ListSet []

to_list: ListSet a -> List a
to_list ls = ls.elems