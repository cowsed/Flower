module Lexer exposing (..)

import Html exposing (pre, text)
import Html.Attributes exposing (style)
import Language exposing (KeywordType(..), LiteralType)
import Util


type Token
    = Keyword KeywordType
    | Symbol String
    | Literal LiteralType String
    | NewlineToken
    | TypeSpecifier -- :
    | CommaToken -- ,
    | DotToken -- .
    | ReturnSpecifier -- ->
    | PlusToken
    | MinusToken
    | MultiplyToken
    | DivideToken
    | OpenCurly
    | CloseCurly
    | OpenParen
    | CloseParen


type LexRes
    = Tokens (List Token) LexFn
    | Error LexError


type LexError
    = UnknownCharacter Util.SourceView Char


explain_lex_error : LexError -> Html.Html msg
explain_lex_error e =
    case e of
        UnknownCharacter sv c ->
            pre [ style "color" "red" ] [ text ((Util.addchar "Unknown character: " c)++"\n"++ Util.show_source_view sv)]


type LexFn
    = LexFn (LexStepInfo -> LexRes)


type alias LexStepInfo =
    { input_view : Int -> Int -> Util.SourceView
    , pos : Int
    , char : Char
    }


call_lexfn : LexFn -> LexStepInfo -> LexRes
call_lexfn lf lsi =
    case lf of
        LexFn f ->
            f lsi


rec_lex : LexFn -> (Int -> Int -> Util.SourceView) -> Int -> List Char -> Result LexError (List Token)
rec_lex lf iv pos cs =
    case List.head cs of
        Just c ->
            let
                lsi =
                    { input_view = iv
                    , pos = pos
                    , char = c
                    }

                res =
                    call_lexfn lf lsi

                tail =
                    List.drop 1 cs

                next lfn =
                    rec_lex lfn iv (pos + 1) tail
            in
            case res of
                Tokens toks next_lf ->
                    case next next_lf of
                        Ok toks2 ->
                            Ok (List.append toks toks2)

                        Err e ->
                            Err e

                Error e ->
                    Err e

        Nothing ->
            Ok []


lex : String -> Result LexError (List Token)
lex str =
    let
        input_view =
            Util.SourceView str
    in
    String.toList str |> rec_lex begin_lex input_view 0



-- often you have to peek ahead at a character to know if your token is done
-- once you do that you have to handle that character cuz returning will just skip it
-- use this to apply it again


apply_again : List Token -> LexFn -> LexStepInfo -> LexRes
apply_again my_toks next_lf lsi =
    let
        next_res =
            case next_lf of
                LexFn f ->
                    f lsi
    in
    case next_res of
        Tokens toks lf ->
            Tokens (List.append my_toks toks) lf

        Error _ ->
            Debug.todo "branch 'Error _' not implemented"


lex_integer : String -> LexStepInfo -> LexRes
lex_integer sofar lsi=
    if Char.isDigit lsi.char then
        Tokens [] (LexFn (lex_integer (Util.addchar sofar lsi.char)))

    else
        -- YesToken (Literal NumberLiteral sofar) begin_lex
        apply_again [ Literal Language.NumberLiteral sofar ] begin_lex lsi


lex_symbol : String -> LexStepInfo -> LexRes
lex_symbol sofar lsi =
    if Char.isAlphaNum lsi.char then
        Tokens [] (LexFn (lex_symbol (Util.addchar sofar lsi.char)))

    else
        apply_again [ symbol_or_keyword sofar ] begin_lex lsi



-- from no information


begin_lex : LexFn
begin_lex =
    LexFn lex_unknown


lex_minus_or_return : LexStepInfo -> LexRes
lex_minus_or_return lsi =
    if lsi.char == '>' then
        Tokens [ ReturnSpecifier ] begin_lex

    else
        apply_again [ MinusToken ] begin_lex lsi


lex_string_literal : String -> LexStepInfo -> LexRes
lex_string_literal sofar lsi =
    if lsi.char == '"' then
        Tokens [ Literal Language.StringLiteral sofar ] begin_lex

    else
        Tokens [] (LexFn (lex_string_literal (Util.addchar sofar lsi.char)))


lex_unknown : LexStepInfo -> LexRes
lex_unknown lsi =
    let
        c =
            lsi.char
    in
    if c == ' ' then
        Tokens [] begin_lex

    else if c == '\n' then
        Tokens [ NewlineToken ] begin_lex

    else if Char.isAlpha c then
        Tokens [] (LexFn (lex_symbol (String.fromChar c)))

    else if Char.isDigit c then
        Tokens [] (LexFn (lex_integer (String.fromChar c)))

    else if c == '"' then
        Tokens [] (LexFn (lex_string_literal ""))

    else if c == '{' then
        Tokens [ OpenCurly ] begin_lex

    else if c == '}' then
        Tokens [ CloseCurly ] begin_lex

    else if c == '(' then
        Tokens [ OpenParen ] begin_lex

    else if c == ')' then
        Tokens [ CloseParen ] begin_lex

    else if c == ':' then
        Tokens [ TypeSpecifier ] begin_lex

    else if c == ',' then
        Tokens [ CommaToken ] begin_lex

    else if c == '+' then
        Tokens [ PlusToken ] begin_lex

    else if c == '-' then
        Tokens [] (LexFn lex_minus_or_return)

    else if c == '*' then
        Tokens [ MultiplyToken ] begin_lex

    else if c == '/' then
        Tokens [ DivideToken ] begin_lex

    else
        Error (UnknownCharacter (lsi.input_view lsi.pos (lsi.pos + 1)) c)


symbol_or_keyword : String -> Token
symbol_or_keyword s =
    case is_keyword s of
        Just kwt ->
            Keyword kwt

        Nothing ->
            Symbol s


is_keyword : String -> Maybe KeywordType
is_keyword s =
    if s == "fn" then
        Just FnKeyword

    else if s == "return" then
        Just ReturnKeyword

    else if s == "module" then
        Just ModuleKeyword

    else if s == "import" then
        Just ImportKeyword

    else
        Nothing


kwt_to_string : KeywordType -> String
kwt_to_string kwt =
    case kwt of
        FnKeyword ->
            "fn"

        ReturnKeyword ->
            "return"

        ModuleKeyword ->
            "module"

        ImportKeyword ->
            "import"


syntaxify_token : Token -> String
syntaxify_token tok =
    case tok of
        Keyword kt ->
            kwt_to_string kt ++ " "

        Symbol str ->
            str

        OpenCurly ->
            "{"

        CloseCurly ->
            "}"

        OpenParen ->
            "("

        CloseParen ->
            ")"

        Literal lt str ->
            Util.syntaxify_literal lt str

        TypeSpecifier ->
            ": "

        CommaToken ->
            ", "

        DotToken ->
            "."

        ReturnSpecifier ->
            " -> "

        PlusToken ->
            " + "

        MinusToken ->
            " - "

        MultiplyToken ->
            " * "

        DivideToken ->
            " / "

        NewlineToken ->
            "\n"


token_to_str : Token -> String
token_to_str tok =
    case tok of
        Keyword kt ->
            "kw"
                ++ kwt_to_string kt

        Symbol str ->
            "[`" ++ str ++ "`]"

        OpenCurly ->
            "OpenCurly"

        CloseCurly ->
            "CloseCurly"

        OpenParen ->
            "OpenParen"

        CloseParen ->
            "CloseParen"

        Literal lt str ->
            "[Literal: "
                ++ str
                ++ (case lt of
                        Language.StringLiteral ->
                            "_str"

                        Language.BooleanLiteral ->
                            "_bool"

                        Language.NumberLiteral ->
                            "_int"
                   )
                ++ "]"

        TypeSpecifier ->
            ":"

        CommaToken ->
            ","

        DotToken ->
            "."

        ReturnSpecifier ->
            "->"

        PlusToken ->
            "+"

        MinusToken ->
            "-"

        MultiplyToken ->
            "*"

        DivideToken ->
            "/"

        NewlineToken ->
            "[\\n]"
