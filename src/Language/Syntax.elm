module Language.Syntax exposing (..)


type KeywordType
    = FnKeyword
    | ReturnKeyword
    | ModuleKeyword
    | ImportKeyword
    | VarKeyword
    | StructKeyword
    | IfKeyword
    | WhileKeyword
    | EnumKeyword
    | TypeKeyword


type LiteralType
    = NumberLiteral
    | StringLiteral


type alias Node a =
    { thing : a
    , loc : SourceView
    }


type alias SourceView =
    { src : String
    , start : Int
    , end : Int
    }


node_location : Node a -> SourceView
node_location n =
    n.loc


node_map: (a->b) -> Node a -> Node b
node_map f na = Node (f na.thing) na.loc

node_get : Node a -> a
node_get n =
    n.thing

show_node: Node a -> String
show_node n = show_source_view n.loc

invalid_sourceview : SourceView
invalid_sourceview =
    { src = "", start = -1, end = -1 }


merge_sv : SourceView -> SourceView -> SourceView
merge_sv sv1 sv2 =
    { src = sv1.src
    , start = min sv1.start sv2.start
    , end = max sv1.end sv2.end
    }


merge_svs : SourceView -> List SourceView -> SourceView
merge_svs start list =
    List.foldl merge_sv start list


show_source_view_not_line : SourceView -> String
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

        we_are_newline =
            case newlines |> List.filter (\ind -> ind == sv.start) |> List.length of
                0 ->
                    False

                _ ->
                    True

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


last_el : List a -> Maybe a
last_el l =
    List.head (List.drop (List.length l - 1) l)
