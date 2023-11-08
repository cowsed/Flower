module ListSet exposing (..)


type alias ListSet a =
    { elems : List a
    }


filter : (a -> Bool) -> ListSet a -> ListSet a
filter pred s =
    ListSet (List.filter pred s.elems)


from_list : List a -> ListSet a
from_list l =
    { elems = l }


remove : a -> ListSet a -> ListSet a
remove target ls =
    ls.elems |> List.filter (\el -> el /= target) |> ListSet


insert : a -> ListSet a -> ListSet a
insert el ls =
    if member el ls then
        ls
        -- here already

    else
        -- not here, addon
        { ls | elems = List.append ls.elems [ el ] }


insert_all : List a -> ListSet a -> ListSet a
insert_all l ls =
    List.foldl insert ls l


merge : ListSet a -> ListSet a -> ListSet a
merge a b =
    insert_all a.elems b


member : a -> ListSet a -> Bool
member el ls =
    List.any (\e -> e == el) ls.elems


empty : ListSet a
empty =
    ListSet []


to_list : ListSet a -> List a
to_list ls =
    ls.elems


size : ListSet a -> Int
size ls =
    List.length ls.elems
