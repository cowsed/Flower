module Parser exposing (..)

import Html
import Html.Attributes
import Language
import Lexer exposing (Token, TokenType(..))
import Util


type Error
    = NoModuleNameGiven
    | NonStringImport Util.SourceView
    | Unimplemented Program
    | NeededMoreTokens String
    | OnlyImportAllowed Util.SourceView


type alias Program =
    { module_name : Maybe String
    , imports : List String
    , needs_more : Maybe String
    }


type ParseFn
    = ParseFn (ParseStep -> ParseRes)


extract_fn : ParseFn -> (ParseStep -> ParseRes)
extract_fn fn =
    case fn of
        ParseFn f ->
            f


type alias ParseStep =
    { tok : Token
    , prog : Program
    }


type ParseRes
    = Error Error
    | Next Program ParseFn


parse_get_import_name : ParseStep -> ParseRes
parse_get_import_name ps =
    let
        prog = ps.prog
    in
    case ps.tok.typ of
        Literal Language.StringLiteral s -> Next {prog | imports = List.append prog.imports [s] } (ParseFn parse_find_imports)
        _ -> Error (NonStringImport ps.tok.loc)


parse_find_imports : ParseStep -> ParseRes
parse_find_imports ps =
    case ps.tok.typ of
        Keyword kt ->
            case kt of
                Language.ImportKeyword ->
                    Next ps.prog (ParseFn parse_get_import_name)

                _ ->
                    Error (OnlyImportAllowed ps.tok.loc)

        CommentToken _ ->
            Next ps.prog (ParseFn parse_find_imports)

        NewlineToken ->
            Next ps.prog (ParseFn parse_find_imports)

        _ ->
            Error (OnlyImportAllowed ps.tok.loc)


parse_find_module_name : ParseStep -> ParseRes
parse_find_module_name ps =
    let
        prog =
            ps.prog
    in
    case ps.tok.typ of
        Symbol s ->
            Next { prog | module_name = Just s, needs_more = Nothing } (ParseFn parse_find_imports)

        CommentToken _ ->
            Next prog (ParseFn parse_find_imports)

        _ ->
            Error NoModuleNameGiven


parse_find_module_kw : ParseStep -> ParseRes
parse_find_module_kw ps =
    let
        prog =
            ps.prog
    in
    case ps.tok.typ of
        Keyword kw ->
            if kw == Language.ModuleKeyword then
                Next { prog | needs_more = Just "needs module name" } (ParseFn parse_find_module_name)

            else
                Error NoModuleNameGiven

        _ ->
            Next ps.prog (ParseFn parse_find_module_kw)


rec_parse : List Token -> Program -> ParseFn -> Result Error Program
rec_parse toks prog_sofar fn =
    let
        head =
            List.head toks

        res tok =
            extract_fn fn { tok = tok, prog = prog_sofar }
    in
    case head of
        Just tok ->
            case res tok of
                Error e ->
                    Err e

                Next prog_now next_fn ->
                    rec_parse (Util.always_tail toks) prog_now next_fn

        Nothing ->
            case prog_sofar.needs_more of
                Nothing ->
                    Ok prog_sofar

                Just reason ->
                    Err (NeededMoreTokens reason)



-- end of tokens


parse : List Lexer.Token -> Result Error Program
parse toks =
    let
        base_program =
            { module_name = Nothing, imports = [], needs_more = Nothing }
    in
    rec_parse toks base_program (ParseFn parse_find_module_kw)


stringify_error : Error -> String
stringify_error e =
    case e of
        NoModuleNameGiven ->
            "No Module Name Given"

        NonStringImport location ->
            "I expected a string literal as an import but got this nonsense instead\n" ++ Util.show_source_view location

        Unimplemented _ ->
            "Unimplemented"

        NeededMoreTokens why ->
            "Couldnt end because I needed more token: " ++ why

        OnlyImportAllowed loc ->
            "Keywords other than import are not allowed at this point\n" ++ Util.show_source_view loc


explain_error : Error -> Html.Html msg
explain_error e =
    case e of
        Unimplemented p ->
            Html.div [ Html.Attributes.style "color" "red" ] [ Html.h2 [] [ Html.text "!!!Unimplemented!!!"], Html.text "Program so far", explain_program p ]

        _ ->
            Html.div []
                [ Html.h3 [] [ Html.text "Parser Error" ]
                , Html.pre [ Html.Attributes.style "color" "red" ] [ Html.text (stringify_error e) ]
                ]


explain_program : Program -> Html.Html msg
explain_program prog =
    Html.div []
        [ Html.h1 [] [ Html.text "Program:" ]
        , Html.h2 [] [ Html.text ("Module: " ++ Maybe.withDefault "[No name]" prog.module_name) ]
        , Html.h2 [] [ Html.text "Imports:" ]
        , Html.ul [] (List.map (\s -> Html.text s) prog.imports)
        ]
