module Main exposing (..)

import Browser.Navigation exposing (Key)
import Html exposing (pre, text)
import Html.Attributes exposing (start)


type alias SourceView =
    { str : String
    , start : Int
    , end : Int
    }


type LiteralType
    = BooleanLiteral
    | NumberLiteral
    | StringLiteral


type Expression
    = Expression
    | LiteralExpression
    | NameLookupExpression
    | FunctionCallExoression


type Type
    = BooleanType
    | IntegerType
    | StringType
    | ConstrainedType Type Expression



-- sumtype, product type, list


type KeywordType
    = FnKeyword
    | ReturnKeyword


is_keyword : String -> Maybe KeywordType
is_keyword s =
    if s == "fn" then
        Just FnKeyword

    else if s == "return" then
        Just ReturnKeyword

    else
        Nothing


kwt_to_string : KeywordType -> String
kwt_to_string kwt =
    case kwt of
        FnKeyword ->
            "fn"

        ReturnKeyword ->
            "return"


type Token
    = Keyword KeywordType
    | Symbol String
    | Literal LiteralType String
    | TypeSpecifier
    | CommaToken
    | DotToken
    | ReturnSpecifier
    | PlusToken
    | MinusToken
    | MultiplyToken
    | DivideToken
    | OpenCurly
    | CloseCurly
    | OpenParen
    | CloseParen


syntaxify_token : Token -> String
syntaxify_token tok =
    case tok of
        Keyword kt ->
            kwt_to_string kt ++ " "

        Symbol str ->
            str

        OpenCurly ->
            "{\n"

        CloseCurly ->
            "\n}\n"

        OpenParen ->
            "("

        CloseParen ->
            ")"

        Literal lt str ->
            str

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
                        StringLiteral ->
                            "_str"

                        BooleanLiteral ->
                            "_bool"

                        NumberLiteral ->
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


input : String
input =
    """
fn add(a: u8, b: u8) -> u8{
    return a + b
}
fn double(a: u8) -> u8{
    return a * "2"
}
fn main(){

}
"""


input_view : Int -> Int -> SourceView
input_view =
    SourceView input


type LexRes
    = NoToken LexFn
    | YesToken Token LexFn
    | YesTokens (List Token) LexFn


type LexFn
    = LexFn (Char -> LexRes)


addchar : String -> Char -> String
addchar s c =
    s ++ String.fromChar c


symbol_or_keyword : String -> Token
symbol_or_keyword s =
    case is_keyword s of
        Just kwt ->
            Keyword kwt

        Nothing ->
            Symbol s



-- often you have to peek ahead at a character to know if your token is done
-- once you do that you have to handle that character cuz returning will just skip it
-- use this to apply it again


apply_again : List Token -> LexFn -> Char -> LexRes
apply_again my_toks next_lf the_c =
    let
        next_res =
            case next_lf of
                LexFn f ->
                    f the_c
    in
    case next_res of
        NoToken lf ->
            YesTokens my_toks lf

        YesToken tok lf ->
            YesTokens (List.append my_toks [ tok ]) lf

        YesTokens toks lf ->
            YesTokens (List.append my_toks toks) lf


lex_number : String -> Char -> LexRes
lex_number sofar c =
    if Char.isDigit c then
        NoToken (LexFn (lex_number (addchar sofar c)))

    else
        -- YesToken (Literal NumberLiteral sofar) begin_lex
        apply_again [ Literal NumberLiteral sofar ] begin_lex c


lex_symbol : String -> Char -> LexRes
lex_symbol sofar c =
    if Char.isAlphaNum c then
        NoToken (LexFn (lex_symbol (addchar sofar c)))

    else
        apply_again [ symbol_or_keyword sofar ] begin_lex c



-- from no information


begin_lex : LexFn
begin_lex =
    LexFn start_lex


minus_or_return_lex : Char -> LexRes
minus_or_return_lex c =
    if c == '>' then
        YesToken ReturnSpecifier begin_lex

    else
        apply_again [ MinusToken ] begin_lex c


lex_string : String -> Char -> LexRes
lex_string sofar c =
    if c == '"' then
        YesToken (Literal StringLiteral sofar) begin_lex

    else
        NoToken (LexFn (lex_string (addchar sofar c)))


start_lex : Char -> LexRes
start_lex c =
    if c == ' ' || c == '\n' then
        NoToken begin_lex

    else if Char.isAlpha c then
        NoToken (LexFn (lex_symbol (String.fromChar c)))

    else if Char.isDigit c then
        NoToken (LexFn (lex_number (String.fromChar c)))

    else if c == '"' then
        NoToken (LexFn (lex_string ""))

    else if c == '{' then
        YesToken OpenCurly begin_lex

    else if c == '}' then
        YesToken CloseCurly begin_lex

    else if c == '(' then
        YesToken OpenParen begin_lex

    else if c == ')' then
        YesToken CloseParen begin_lex

    else if c == ':' then
        YesToken TypeSpecifier begin_lex

    else if c == ',' then
        YesToken CommaToken begin_lex

    else if c == '+' then
        YesToken PlusToken begin_lex

    else if c == '-' then
        NoToken (LexFn minus_or_return_lex)

    else if c == '*' then
        YesToken MultiplyToken begin_lex

    else if c == '/' then
        YesToken DivideToken begin_lex

    else
        YesToken (Symbol (String.fromChar c)) (LexFn start_lex)


call_lexfn : LexFn -> Char -> LexRes
call_lexfn lf c =
    case lf of
        LexFn f ->
            f c


rec_lex : LexFn -> List Char -> List Token
rec_lex lf cs =
    case List.head cs of
        Just c ->
            let
                res =
                    call_lexfn lf c
            in
            case res of
                NoToken lfn ->
                    rec_lex lfn (List.drop 1 cs)

                YesToken tok lfy ->
                    tok :: rec_lex lfy (List.drop 1 cs)

                YesTokens toks lfs ->
                    List.append toks (rec_lex lfs (List.drop 1 cs))

        Nothing ->
            []



-- consume char, call func1, return func2, consume char, call func2


lex : String -> List Token
lex str =
    let
        chars =
            String.toList str

        -- chars_with_idx =
        -- zip (List.range 0 (List.length chars)) chars
    in
    rec_lex (LexFn start_lex) chars


main : Html.Html msg
main =
    let
        tokstr =
            lex input |> List.map token_to_str |> String.join " "

        syn =
            lex input |> List.map syntaxify_token |> String.join ""
    in
    pre [] [ text tokstr ]
