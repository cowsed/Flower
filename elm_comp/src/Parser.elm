module Parser exposing (..)

import Html exposing (text)
import Html.Attributes exposing (style)
import Language exposing (ASTExpression(..), ASTFunctionDefinition, ASTFunctionHeader, ASTStatement(..), KeywordType(..), Name(..), TypeWithName, stringify_name)
import Lexer exposing (Token, TokenType(..), syntaxify_token)
import Pallete
import Util


parse : List Lexer.Token -> Result Error Program
parse toks =
    let
        base_program : Program
        base_program =
            { module_name = Nothing, imports = [], global_functions = [], needs_more = Nothing }
    in
    rec_parse toks base_program (ParseFn parse_find_module_kw)


type Error
    = NoModuleNameGiven
    | NonStringImport Util.SourceView
    | Unimplemented Program String
    | NeededMoreTokens String
    | UnknownOuterLevelObject Util.SourceView
    | ExpectedNameAfterFn Util.SourceView
    | ExpectedOpenParenAfterFn String Util.SourceView
    | ExpectedToken String Util.SourceView
    | ExpectedTypeName Util.SourceView
    | ExpectedEndOfArgListOrComma Util.SourceView
    | FailedTypeParse TypeParseError
    | FailedNamedTypeParse NamedTypeParseError
    | KeywordNotAllowedHere Util.SourceView
    | FailedExprParse ExprParseError
    | ExpectedFunctionBody Util.SourceView TokenType
    | RequireInitilizationWithValue Util.SourceView


type alias Program =
    { module_name : Maybe String
    , imports : List String
    , global_functions : List ASTFunctionDefinition
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


type TypeParseError
    = Idk Util.SourceView


parse_expected_token : String -> TokenType -> ParseFn -> ParseStep -> ParseRes
parse_expected_token reason expected after ps =
    if ps.tok.typ == expected then
        Next ps.prog after

    else
        Error (ExpectedToken reason ps.tok.loc)


parse_type : (Result TypeParseError Name -> ParseRes) -> ParseStep -> ParseRes
parse_type todo ps =
    case ps.tok.typ of
        Symbol s ->
            todo (Ok (Language.BaseName s))

        _ ->
            Error (ExpectedTypeName ps.tok.loc)


type NamedTypeParseError
    = NameError Util.SourceView String
    | TypeError TypeParseError



-- parse the following `name: Type`


parse_named_type_type : String -> (Result NamedTypeParseError TypeWithName -> ParseRes) -> ParseStep -> ParseRes
parse_named_type_type valname todo ps =
    case ps.tok.typ of
        Symbol typename ->
            todo (Ok (TypeWithName (BaseName valname) (BaseName typename)))

        _ ->
            Error (Unimplemented ps.prog "When parsing name: Type if Type is not a symbol")


parse_named_type_name : (Result NamedTypeParseError TypeWithName -> ParseRes) -> ParseStep -> ParseRes
parse_named_type_name todo ps =
    let
        after_colon valname =
            ParseFn (parse_named_type_type valname todo)
    in
    case ps.tok.typ of
        Symbol valname ->
            Next ps.prog (ParseFn (parse_expected_token "Expected `:` to split betweem value name and type" Lexer.TypeSpecifier (after_colon valname)))

        _ ->
            Error (ExpectedToken "expected a symbol name like `a` or `name` for something like `a: Type`" ps.tok.loc)


parse_until : TokenType -> ParseFn -> ParseStep -> ParseRes
parse_until typ after ps =
    if typ == ps.tok.typ then
        Next ps.prog after

    else
        Next ps.prog (ParseFn (parse_until typ after))


parse_outer : ParseStep -> ParseRes
parse_outer ps =
    case ps.tok.typ of
        Keyword kwt ->
            case kwt of
                Language.FnKeyword ->
                    Next ps.prog (ParseFn parse_global_fn)

                _ ->
                    Error (Unimplemented ps.prog "Parsing outer non fn keywords")

        NewlineToken ->
            Next ps.prog (ParseFn parse_outer)

        CommentToken _ ->
            Next ps.prog (ParseFn parse_outer)

        _ ->
            Error (Unimplemented ps.prog "Parsing outer non function things")


type ExprParseError
    = IdkExpr Util.SourceView String


parse_expr : (Result ExprParseError ASTExpression -> ParseRes) -> ParseStep -> ParseRes
parse_expr todo ps =
    case ps.tok.typ of
        Symbol s ->
            Ok (NameLookup (BaseName s)) |> todo

        _ ->
            IdkExpr ps.tok.loc "I don't know how to parse non name lookup expr" |> Err |> todo


parse_global_fn_return_statement : ASTFunctionDefinition -> ParseStep -> ParseRes
parse_global_fn_return_statement fdef ps =
    let
        what_to_do_with_expr : Result ExprParseError ASTExpression -> ParseRes
        what_to_do_with_expr res =
            case res of
                Err e ->
                    Error (FailedExprParse e)

                Ok expr ->
                    parse_global_fn_statements { fdef | statements = List.append fdef.statements [ ReturnStatement expr ] }
                        |> ParseFn
                        |> parse_expected_token "Expected newline after end of this return expression" NewlineToken
                        |> ParseFn
                        |> Next ps.prog
    in
    apply_again (ParseFn (parse_expr what_to_do_with_expr)) ps


parse_global_fn_initilization : ASTFunctionDefinition -> TypeWithName -> ParseStep -> ParseRes
parse_global_fn_initilization fdef nt ps =
    let
        todo_with_expr : Result ExprParseError ASTExpression -> ParseRes
        todo_with_expr res =
            case res of
                Err e ->
                    Error (FailedExprParse e)

                Ok expr ->
                    Next ps.prog (ParseFn (parse_global_fn_statements { fdef | statements = List.append fdef.statements [ Initilization nt expr ] }))
    in
    case ps.tok.typ of
        AssignmentToken ->
            Next ps.prog (ParseFn (parse_expr todo_with_expr))

        NewlineToken ->
            Error (RequireInitilizationWithValue ps.tok.loc)

        _ ->
            Error (Unimplemented ps.prog "what happens if no = after var a: Type = ")


parse_global_fn_statements : ASTFunctionDefinition -> ParseStep -> ParseRes
parse_global_fn_statements fdef ps =
    let
        todo_if_var : Result NamedTypeParseError TypeWithName -> ParseRes
        todo_if_var res =
            case res of
                Ok nt ->
                    Next ps.prog (ParseFn (parse_global_fn_initilization fdef nt))

                Err e ->
                    Error (FailedNamedTypeParse e)
    in
    case ps.tok.typ of
        Keyword kwt ->
            case kwt of
                ReturnKeyword ->
                    Next ps.prog (ParseFn (parse_global_fn_return_statement fdef))

                VarKeyword ->
                    Next ps.prog (ParseFn (parse_named_type_name todo_if_var))

                _ ->
                    Error (KeywordNotAllowedHere ps.tok.loc)

        CommentToken c ->
            Next ps.prog (ParseFn (parse_global_fn_statements { fdef | statements = List.append fdef.statements [ CommentStatement c ] }))

        CloseCurly ->
            let
                old_prog =
                    ps.prog

                prog =
                    { old_prog | global_functions = List.append old_prog.global_functions [ fdef ] }
            in
            Next prog (ParseFn parse_outer)

        NewlineToken ->
            parse_global_fn_statements fdef |> ParseFn |> Next ps.prog

        _ ->
            Error (Unimplemented ps.prog ("parsing global function statements like this one:\n" ++ Util.show_source_view ps.tok.loc))


parse_global_function_body : String -> ASTFunctionHeader -> ParseStep -> ParseRes
parse_global_function_body fname header ps =
    let
        fdef =
            ASTFunctionDefinition fname header []

        prog =
            ps.prog
    in
    case ps.tok.typ of
        CloseCurly ->
            Next { prog | global_functions = List.append prog.global_functions [ fdef ] } (ParseFn parse_outer)

        _ ->
            Next prog (ParseFn (parse_global_fn_statements fdef))


parse_global_fn_return : String -> ASTFunctionHeader -> ParseStep -> ParseRes
parse_global_fn_return fname header_so_far ps =
    let
        what_to_do_with_ret_type : Result TypeParseError Name -> ParseRes
        what_to_do_with_ret_type typ_res =
            case typ_res of
                Err e ->
                    Error (FailedTypeParse e)

                Ok typ ->
                    Next ps.prog (ParseFn (parse_global_function_body fname { header_so_far | return_type = Just typ }))
    in
    case ps.tok.typ of
        ReturnSpecifier ->
            Next ps.prog (ParseFn (parse_type what_to_do_with_ret_type))

        OpenCurly ->
            Next ps.prog (ParseFn (parse_global_function_body fname header_so_far))

        _ ->
            Error (ExpectedFunctionBody ps.tok.loc ps.tok.typ)


parse_global_fn_arg_list_comma_or_close : List TypeWithName -> String -> ParseStep -> ParseRes
parse_global_fn_arg_list_comma_or_close args fname ps =
    case ps.tok.typ of
        CommaToken ->
            Next ps.prog (ParseFn (parse_global_fn_arg_list_or_close args fname))

        CloseParen ->
            Next ps.prog (ParseFn (parse_global_fn_return fname { args = args, return_type = Nothing }))

        _ ->
            Error (ExpectedEndOfArgListOrComma ps.tok.loc)


parse_global_fn_arg_list_or_close : List TypeWithName -> String -> ParseStep -> ParseRes
parse_global_fn_arg_list_or_close args_sofar fname ps =
    let
        after_typedarg_occurs : Result NamedTypeParseError TypeWithName -> ParseRes
        after_typedarg_occurs res =
            case res of
                Err e ->
                    Error (FailedNamedTypeParse e)

                Ok nt ->
                    Next ps.prog (ParseFn (parse_global_fn_arg_list_comma_or_close (List.append args_sofar [ nt ]) fname))
    in
    case ps.tok.typ of
        Symbol _ ->
            apply_again (ParseFn (parse_named_type_name after_typedarg_occurs)) ps

        CloseParen ->
            Next ps.prog (ParseFn (parse_global_function_body fname { args = args_sofar, return_type = Nothing }))

        _ ->
            Error (Unimplemented ps.prog ("Failing to close func param list: name = " ++ fname))


parse_global_fn_named_open_paren : String -> ParseStep -> ParseRes
parse_global_fn_named_open_paren fname ps =
    case ps.tok.typ of
        OpenParen ->
            Next ps.prog (ParseFn (parse_global_fn_arg_list_or_close [] fname))

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
                    Error (UnknownOuterLevelObject ps.tok.loc)

        CommentToken _ ->
            Next ps.prog (ParseFn parse_find_imports)

        NewlineToken ->
            Next ps.prog (ParseFn parse_find_imports)

        _ ->
            Error (UnknownOuterLevelObject ps.tok.loc)


parse_find_module_name : ParseStep -> ParseRes
parse_find_module_name ps =
    let
        prog =
            ps.prog
    in
    case ps.tok.typ of
        Symbol s ->
            Next { prog | module_name = Just s, needs_more = Nothing } (ParseFn parse_find_imports)

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


apply_again : ParseFn -> ParseStep -> ParseRes
apply_again fn ps =
    extract_fn fn ps


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

        UnknownOuterLevelObject loc ->
            "The only things allowed at this point are `import`, a variable or a function definition\n" ++ Util.show_source_view loc

        ExpectedNameAfterFn loc ->
            "Expected a name after the fn keyword to name a function. Something like `fn name()` \n" ++ Util.show_source_view loc

        ExpectedOpenParenAfterFn s loc ->
            "Expected a close paren after the fn name `fn " ++ s ++ "()` \n" ++ Util.show_source_view loc

        ExpectedToken explanation loc ->
            explanation ++ "\n" ++ Util.show_source_view loc

        ExpectedTypeName loc ->
            "Expected a type name here.\nDid you maybe use a keyword like `return`, `fn`, `var`? You can't do that\n" ++ Util.show_source_view loc

        ExpectedEndOfArgListOrComma loc ->
            "Expected a comma to continue arg list or a close paren to end it\n++Util.show_source_view loc" ++ Util.show_source_view loc

        FailedTypeParse tpe ->
            case tpe of
                Idk loc ->
                    "Failed to parse type\n" ++ Util.show_source_view loc

        FailedNamedTypeParse tpe ->
            case tpe of
                TypeError tp ->
                    stringify_error (FailedTypeParse tp)

                NameError loc ne ->
                    "Failed to parse name of name: Type. " ++ ne ++ "\n" ++ Util.show_source_view loc

        KeywordNotAllowedHere loc ->
            "This Keyword is not allowed here\n" ++ Util.show_source_view loc

        FailedExprParse er ->
            case er of
                IdkExpr loc s ->
                    "Failed to parse expr: " ++ s ++ "\n" ++ Util.show_source_view loc

        ExpectedFunctionBody loc got ->
            "Expected a `{` to start the function body but got `" ++ syntaxify_token got ++ "`\n" ++ Util.show_source_view loc

        RequireInitilizationWithValue loc ->
            "When you are initilizaing something `var a: Type = xyz you need that = xyz or else that thing is unitialized\n" ++ Util.show_source_view loc


explain_error : Error -> Html.Html msg
explain_error e =
    case e of
        Unimplemented p reason ->
            Html.div [ Html.Attributes.style "color" Pallete.red ]
                [ Html.h2 [] [ Html.text "!!!Unimplemented!!!" ]
                , Html.pre [] [ Html.text (reason ++ "\n") ]
                , Html.text "Program so far"
                , explain_program p
                ]

        _ ->
            Html.div []
                [ Html.h3 [] [ Html.text "Parser Error" ]
                , Html.pre [ Html.Attributes.style "color" Pallete.red ] [ Html.text (stringify_error e) ]
                ]


syntax_highlight_type : Name -> Html.Html msg
syntax_highlight_type name =
    Html.span [ style "color" Pallete.blue ]
        [ text (Language.stringify_name name)
        ]


htmlify_namedarg : TypeWithName -> List (Html.Html msg)
htmlify_namedarg na =
    [ symbol_highlight (Language.stringify_name na.name)
    , text ": "
    , Html.span [] [ syntax_highlight_type na.typename ]
    ]


syntaxify_fheader : ASTFunctionHeader -> Html.Html msg
syntaxify_fheader header =
    let
        pretty_arg_lst : List (Html.Html msg)
        pretty_arg_lst =
            List.concat (List.intersperse [ text ", " ] (List.map htmlify_namedarg header.args))

        lis =
            List.concat [ [ text "(" ], pretty_arg_lst, [ text ")" ] ]

        ret : Html.Html msg
        ret =
            Html.span []
                (case header.return_type of
                    Just typ ->
                        [ Html.span [] [ text " 🡒 ", Html.span [] [ syntax_highlight_type typ ] ], text " " ]

                    Nothing ->
                        [ text " " ]
                )
    in
    Html.span [] (List.append lis [ ret ])


explain_expression : ASTExpression -> Html.Html msg
explain_expression expr =
    case expr of
        NameLookup n ->
            text ("Name look up: " ++ stringify_name n)

        FunctionCallExpr _ ->
            Debug.todo "branch 'FunctionCallExpr _' not implemented"

        LiteralExpr _ _ ->
            Debug.todo "branch 'LiteralExpr _ _' not implemented"


explain_statement : ASTStatement -> Html.Html msg
explain_statement s =
    case s of
        ReturnStatement expr ->
            Html.span [] [ text "return: ", explain_expression expr ]

        CommentStatement src ->
            Html.span [] [ text "// ", text src ]

        Initilization name expr ->
            Html.span [] [ text ("Initialize `" ++ stringify_name name.name ++ "` of type " ++ stringify_name name.typename ++ " to "), explain_expression expr ]

        _ ->
            Debug.todo "explai other statemnts"


explain_statments : List ASTStatement -> Html.Html msg
explain_statments statements =
    Html.ul [] (List.map (\s -> explain_statement s) statements |> List.map (\s -> Html.li [] [ Html.pre [] [ s ] ]))


explain_program : Program -> Html.Html msg
explain_program prog =
    let
        imports =
            Util.collapsable (Html.text "Imports") (Html.ul [] (List.map (\s -> Html.li [] [ Html.text s ]) prog.imports))

        funcs =
            Util.collapsable (text "Global Functions")
                (Html.ul []
                    (List.map
                        (\f ->
                            Html.li []
                                [ Util.collapsable (Html.code [] [ text f.name, syntaxify_fheader f.header ]) (explain_statments f.statements)
                                ]
                        )
                        prog.global_functions
                    )
                )
    in
    Html.div []
        [ Html.h4 [] [ Html.text ("Module: " ++ Maybe.withDefault "[No name]" prog.module_name) ]
        , imports
        , funcs
        ]


extract_fn : ParseFn -> (ParseStep -> ParseRes)
extract_fn fn =
    case fn of
        ParseFn f ->
            f


keyword_highlight : String -> Html.Html msg
keyword_highlight s =
    Html.span [ style "color" Pallete.red ] [ text s ]


symbol_highlight : String -> Html.Html msg
symbol_highlight s =
    Html.span [ style "color" Pallete.orange ] [ text s ]


syntaxify_expression : ASTExpression -> Html.Html msg
syntaxify_expression expr =
    case expr of
        NameLookup n ->
            symbol_highlight (stringify_name n)

        FunctionCallExpr _ ->
            Debug.todo "branch 'FunctionCallExpr _' not implemented"

        LiteralExpr _ _ ->
            Debug.todo "branch 'LiteralExpr _ _' not implemented"


string_literal_highlight : String -> Html.Html msg
string_literal_highlight s =
    Html.span [ style "color" "DarkSlateBlue" ] [ text ("\"" ++ s ++ "\"") ]


tab : Html.Html msg
tab =
    Html.text "    "


syntaxify_statement : ASTStatement -> Html.Html msg
syntaxify_statement s =
    case s of
        ReturnStatement expr ->
            Html.span []
                [ tab
                , keyword_highlight "return "
                , syntaxify_expression expr
                , text "\n"
                ]

        Initilization name expr ->
            Html.span [] (List.concat [ [ tab, keyword_highlight "var " ], htmlify_namedarg name, [ text " = ", syntaxify_expression expr, text "\n" ] ])

        CommentStatement src ->
            Html.span [ style "color" Pallete.gray ] [ tab, text ("// " ++ src), text "\n" ]

        _ ->
            Debug.todo "syntaxify statement"


collapsing_function : ASTFunctionDefinition -> Html.Html msg
collapsing_function fdef =
    let
        header =
            [ Html.span []
                [ keyword_highlight "fn "
                , symbol_highlight fdef.name
                , syntaxify_fheader fdef.header
                ]
            ]
    in
    if List.length fdef.statements == 0 then
        Html.div [] (List.concat [ header, [ text "{}" ] ])

    else
        Html.details
            [ style "background" Pallete.bg1
            , style "width" "fit-content"
            , style "padding-left" "5px"
            , style "padding-right" "5px"
            , style "border-radius" "10px"
            , Html.Attributes.attribute "open" "true"
            ]
            (List.concat
                [ [ collapsing_function_style
                  , Html.summary
                        [ style "border" "none"
                        , style "cursor" "pointer"
                        ]
                        (List.concat [ header, [ text "{" ] ])
                  ]
                , fdef.statements
                    |> List.map syntaxify_statement
                , [ text "}" ]
                ]
            )



--         List.concat
--             [ [ text "{\n" ]
--             , fdef.statements
--                 |> List.map syntaxify_statement
--             , [ text "}"
--               , text "\n"
--               , text "\n"
--               ]
--             ]


collapsing_function_style =
    Html.node "style" [] [ text """
details[open] > summary {
    list-style: none;
}
""" ]


syntaxify_function : ASTFunctionDefinition -> List (Html.Html msg)
syntaxify_function fdef =
    [ collapsing_function fdef ]



-- List.concat
--     [ [ keyword_highlight "fn "
--       , symbol_highlight fdef.name
--       , syntaxify_fheader fdef.header
--       ]
--     , if List.length fdef.statements == 0 then
--         [ text "{}\n\n" ]
--       else
--     ]


syntaxify_program : Program -> Html.Html msg
syntaxify_program prog =
    Html.code
        [ style "overflow" "scroll"
        , style "height" "400px"
        , style "width" "400px"
        , style "padding" "4px"
        , style "background-color" Pallete.bg
        , style "border-radius" "8px"
        , style "border-style" "solid"
        , style "border-width" "2px"
        , style "border-color" "black"
        , style "float" "left"
        , style "margin-left" "10px "
        ]
        [ Html.pre []
            (List.concat
                [ [ keyword_highlight "module ", symbol_highlight (Maybe.withDefault "module_name" prog.module_name), text "\n\n" ]
                , prog.imports |> List.map (\name -> [ keyword_highlight "import ", string_literal_highlight name, text "\n" ]) |> List.concat
                , List.repeat 2 (text "\n")
                , prog.global_functions |> List.map syntaxify_function |> List.concat
                ]
            )
        ]
