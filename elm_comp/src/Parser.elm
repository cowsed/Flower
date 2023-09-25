module Parser exposing (..)

import Html
import Html.Attributes
import Language
import Lexer exposing (Token, TokenType(..))
import Util


parse : List Lexer.Token -> Result Error Program
parse toks =
    let
        base_program =
            { module_name = Nothing, imports = [], needs_more = Nothing }
    in
    rec_parse toks base_program (ParseFn parse_find_module_kw)


type Error
    = NoModuleNameGiven
    | NonStringImport Util.SourceView
    | Unimplemented Program String
    | NeededMoreTokens String
    | OnlyImportAllowed Util.SourceView
    | ExpectedNameAfterFn Util.SourceView
    | ExpectedOpenParenAfterFn String Util.SourceView
    | ExpectedToken String Util.SourceView
    | ExpectedTypeName Util.SourceView
    | ExpectedEndOfArgListOrComma Util.SourceView
    | FailedTypeParse TypeParseError


type alias Program =
    { module_name : Maybe String
    , imports : List String
    , needs_more : Maybe String
    }


type ParseFn
    = ParseFn (ParseStep -> ParseRes)


type alias ParseStep =
    { tok : Token
    , prog : Program
    }


type ParseRes
    = Error Error
    | Next Program ParseFn


extract_fn : ParseFn -> (ParseStep -> ParseRes)
extract_fn fn =
    case fn of
        ParseFn f ->
            f


type alias NamedArg =
    { name : String, typename : TypeName }


stringify_named_arg : NamedArg -> String
stringify_named_arg na =
    na.name
        ++ " : "
        ++ (case na.typename of
                BasicTypename s ->
                    s
           )


type TypeName
    = BasicTypename String


type TypeParseError
    = Idk Util.SourceView


parse_expected_token : String -> TokenType -> ParseFn -> ParseStep -> ParseRes
parse_expected_token reason expected after ps =
    if ps.tok.typ == expected then
        Next ps.prog after
    else
        Error (ExpectedToken reason ps.tok.loc)


parse_type : (Result TypeParseError TypeName -> ParseRes) -> ParseStep -> ParseRes
parse_type todo ps =
    case ps.tok.typ of
        Symbol s ->
            todo (Ok (BasicTypename s))

        _ ->
            Error (ExpectedTypeName ps.tok.loc)


parse_global_fn_arg_list_comma_or_close : List NamedArg -> String -> ParseStep -> ParseRes
parse_global_fn_arg_list_comma_or_close args fname ps =
    case ps.tok.typ of
        CommaToken ->
            Next ps.prog (ParseFn (parse_global_fn_arg_list_name args fname))

        CloseParen ->
            Error (Unimplemented ps.prog ("Parsing after function arg list (" ++ (List.map stringify_named_arg args |> String.join ", ") ++ ")"))

        _ ->
            Error (ExpectedEndOfArgListOrComma ps.tok.loc)


parse_global_fn_arg_list_type_spec : String -> List NamedArg -> String -> ParseStep -> ParseRes
parse_global_fn_arg_list_type_spec argname args fname ps =
    let
        type_user : Result TypeParseError TypeName -> ParseRes
        type_user res_typ =
            case res_typ of
                Err e ->
                    Error (FailedTypeParse e)

                Ok typ ->
                    let
                        named_typ =
                            { name = argname, typename = typ }

                        new_args =
                            List.append args [ named_typ ]
                    in
                    Next ps.prog (ParseFn (parse_global_fn_arg_list_comma_or_close new_args fname))
    in
    case ps.tok.typ of
        TypeSpecifier ->
            Next ps.prog (ParseFn (parse_type type_user))

        _ ->
            Error (ExpectedToken "Expected the type specifier `:` here to distinguish name and type" ps.tok.loc)


parse_global_fn_arg_list_name : List NamedArg -> String -> ParseStep -> ParseRes
parse_global_fn_arg_list_name args_sofar fname ps =
    case ps.tok.typ of
        Symbol argname ->
            Next ps.prog (ParseFn (parse_global_fn_arg_list_type_spec argname args_sofar fname))

        _ ->
            Error (Unimplemented ps.prog ("function arg list parseing: name = " ++ fname))


parse_global_fn_named_open_paren : String -> ParseStep -> ParseRes
parse_global_fn_named_open_paren fname ps =
    case ps.tok.typ of
        OpenParen ->
            Next ps.prog (ParseFn (parse_global_fn_arg_list_name [] fname))

        _ ->
            Error (ExpectedOpenParenAfterFn fname ps.tok.loc)


parse_global_fn : ParseStep -> ParseRes
parse_global_fn ps =
    case ps.tok.typ of
        Symbol s ->
            Next ps.prog (ParseFn (parse_global_fn_named_open_paren s))

        _ ->
            Error (ExpectedNameAfterFn ps.tok.loc)


parse_get_import_name : ParseStep -> ParseRes
parse_get_import_name ps =
    let
        prog =
            ps.prog
    in
    case ps.tok.typ of
        Literal Language.StringLiteral s ->
            Next { prog | imports = List.append prog.imports [ s ] } (ParseFn parse_find_imports)

        _ ->
            Error (NonStringImport ps.tok.loc)


parse_find_imports : ParseStep -> ParseRes
parse_find_imports ps =
    case ps.tok.typ of
        Keyword kt ->
            case kt of
                Language.ImportKeyword ->
                    Next ps.prog (ParseFn parse_get_import_name)

                Language.FnKeyword ->
                    Next ps.prog (ParseFn parse_global_fn)

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


stringify_error : Error -> String
stringify_error e =
    case e of
        NoModuleNameGiven ->
            "No Module Name Given"

        NonStringImport location ->
            "I expected a string literal as an import but got this nonsense instead\n" ++ Util.show_source_view location

        Unimplemented _ reason ->
            "Unimplemented: " ++ reason

        NeededMoreTokens why ->
            "Couldnt end because I needed more token: " ++ why

        OnlyImportAllowed loc ->
            "Keywords other than import are not allowed at this point\n" ++ Util.show_source_view loc

        ExpectedNameAfterFn loc ->
            "Expected a name after the fn keyword to name a function. Something like `fn name()` \n" ++ Util.show_source_view loc

        ExpectedOpenParenAfterFn s loc ->
            "Expected a close paren after the fn name `fn " ++ s ++ "()` \n" ++ Util.show_source_view loc

        ExpectedToken explanation loc ->
            explanation++"\n" ++ Util.show_source_view loc

        ExpectedTypeName loc ->
            "Expected a type name here\n" ++ Util.show_source_view loc

        ExpectedEndOfArgListOrComma loc ->
            "Expected a comma to continue arg list or a close paren to end it\n++Util.show_source_view loc" ++ Util.show_source_view loc

        FailedTypeParse tpe ->
            case tpe of
                Idk loc ->
                    "Failed to parse type\n" ++ Util.show_source_view loc


explain_error : Error -> Html.Html msg
explain_error e =
    case e of
        Unimplemented p reason ->
            Html.div [ Html.Attributes.style "color" "red" ]
                [ Html.h2 [] [ Html.text "!!!Unimplemented!!!" ]
                , Html.p [] [ Html.text (reason ++ "\n") ]
                , Html.text "Program so far"
                , explain_program p
                ]

        _ ->
            Html.div []
                [ Html.h3 [] [ Html.text "Parser Error" ]
                , Html.pre [ Html.Attributes.style "color" "red" ] [ Html.text (stringify_error e) ]
                ]


explain_program : Program -> Html.Html msg
explain_program prog =
    Html.div []
        [ Html.h1 [] [ Html.text "Program:" ]
        , Html.h3 [] [ Html.text ("Module: " ++ Maybe.withDefault "[No name]" prog.module_name) ]
        , Html.h4 [] [ Html.text "Imports:" ]
        , Html.ul [] (List.map (\s -> Html.li [] [ Html.text s ]) prog.imports)
        ]
