module Parser.Lexer exposing (..)

import Html exposing (pre, text)
import Html.Attributes exposing (style)
import Language
import Pallete
import Util


type alias Token =
    { loc : Util.SourceView
    , typ : TokenType
    }


type TokenType
    = Keyword Language.KeywordType
    | Symbol String
    | Literal Language.LiteralType String
    | NewlineToken
    | TypeSpecifier -- :
    | CommaToken -- ,
    | DotToken -- .
    | ReturnSpecifier -- ->
    | AssignmentToken
    | EqualityToken -- ==
    | NotEqualToken
    | NotToken
    | LessThanToken -- <
    | LessThanEqualToken -- <=
    | GreaterThanToken -- >
    | GreaterThanEqualToken -- >=
    | ReferenceToken --&
    | PlusToken
    | MinusToken
    | MultiplyToken
    | DivideToken
    | OpenCurly
    | CloseCurly
    | OpenParen
    | CloseParen
    | OpenSquare
    | CloseSquare
    | WhereToken -- |
    | CommentToken String


lex : String -> Result Error (List Token)
lex str =
    let
        input_view =
            Util.SourceView str
    in
    String.toList str |> rec_lex begin_lex input_view 0


type LexRes
    = Tokens (List Token) LexFn
    | Error Error


type Error
    = UnknownCharacter Util.SourceView Char
    | UnclosedStringLiteral Util.SourceView
    | UnknownCharacterInIntegerLiteral Util.SourceView


infix_op_from_token : Token -> Maybe Language.InfixOpType
infix_op_from_token tok =
    case tok.typ of
        PlusToken ->
            Just Language.Addition

        MinusToken ->
            Just Language.Subtraction

        MultiplyToken ->
            Just Language.Multiplication

        DivideToken ->
            Just Language.Division

        GreaterThanToken ->
            Just Language.GreaterThan

        GreaterThanEqualToken ->
            Just Language.GreaterThanEqualTo

        LessThanToken ->
            Just Language.LessThan

        LessThanEqualToken ->
            Just Language.LessThanEqualTo

        EqualityToken ->
            Just Language.Equality

        NotEqualToken ->
            Just Language.NotEqualTo

        _ ->
            Nothing


explain_error : Error -> Html.Html msg
explain_error e =
    Html.div []
        [ Html.h1 [] [ text "Lexer Error" ]
        , pre [ style "color" Pallete.red ]
            [ case e of
                UnknownCharacter sv c ->
                    text (Util.addchar "Unknown character: " c ++ "\n" ++ Util.show_source_view sv)

                UnclosedStringLiteral sv ->
                    text ("Unclosed String Literal here: \n" ++ Util.show_source_view sv)

                UnknownCharacterInIntegerLiteral sv ->
                    text ("Unknown character in Integer Literal\n" ++ Util.show_source_view sv)
            ]
        ]


type LexFn
    = LexFn (LexStepInfo -> LexRes)


type alias LexStepInfo =
    { input_view : Int -> Int -> Util.SourceView
    , view_from_start : Int -> Util.SourceView
    , view_this : Util.SourceView
    , pos : Int
    , char : Char
    }


call_lexfn : LexFn -> LexStepInfo -> LexRes
call_lexfn lf lsi =
    case lf of
        LexFn f ->
            f lsi


rec_lex : LexFn -> (Int -> Int -> Util.SourceView) -> Int -> List Char -> Result Error (List Token)
rec_lex lf iv pos cs =
    case List.head cs of
        Just c ->
            let
                lsi =
                    { input_view = iv
                    , view_from_start = \s -> iv s pos
                    , view_this = iv pos (pos + 1)
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

        Error e ->
            Error e


is_integer_ender : Char -> Bool
is_integer_ender c =
    case c of
        ' ' ->
            True

        '\n' ->
            True

        '\t' ->
            True

        ',' ->
            True

        '(' ->
            True

        ')' ->
            True

        '}' ->
            True

        '{' ->
            True

        ']' ->
            True

        '+' ->
            True

        '-' ->
            True

        '*' ->
            True

        '/' ->
            True

        _ ->
            False


lex_integer : Int -> String -> LexStepInfo -> LexRes
lex_integer start sofar lsi =
    if Char.isDigit lsi.char then
        LexFn (lex_integer start (Util.addchar sofar lsi.char)) |> Tokens []

    else if is_integer_ender lsi.char then
        apply_again [ Token (lsi.view_from_start start) (Literal Language.NumberLiteral sofar) ] begin_lex lsi

    else
        Error (UnknownCharacterInIntegerLiteral lsi.view_this)


lex_symbol : Int -> String -> LexStepInfo -> LexRes
lex_symbol start sofar lsi =
    if Char.isAlphaNum lsi.char then
        lex_symbol start (Util.addchar sofar lsi.char) |> LexFn |> Tokens []

    else if lsi.char == '_' then
        lex_symbol start (Util.addchar sofar lsi.char) |> LexFn |> Tokens []

    else
        apply_again [ Token (lsi.view_from_start start) (is_special_or_symbol sofar) ] begin_lex lsi



-- from no information


begin_lex : LexFn
begin_lex =
    LexFn lex_unknown


lex_minus_or_return : Int -> LexStepInfo -> LexRes
lex_minus_or_return start lsi =
    if lsi.char == '>' then
        Tokens [ Token (lsi.input_view start (start + 2)) ReturnSpecifier ] begin_lex

    else
        apply_again [ Token (lsi.input_view start (start + 1)) MinusToken ] begin_lex lsi


lex_rest_of_comment : Int -> String -> LexStepInfo -> LexRes
lex_rest_of_comment start sofar lsi =
    if lsi.char == '\n' then
        Tokens
            [ Token (lsi.input_view start (start + lsi.pos - 1)) (CommentToken sofar)
            , Token (lsi.input_view lsi.pos (lsi.pos + 1)) NewlineToken
            ]
            begin_lex

    else
        lex_rest_of_comment start (Util.addchar sofar lsi.char) |> LexFn |> Tokens []


lex_divide_or_comment : LexStepInfo -> LexRes
lex_divide_or_comment lsi =
    if lsi.char == '/' then
        Tokens [] (LexFn (lex_rest_of_comment (lsi.pos - 1) ""))

    else
        apply_again [ Token (lsi.input_view (lsi.pos - 1) lsi.pos) DivideToken ] begin_lex lsi


lex_string_literal : Int -> String -> LexStepInfo -> LexRes
lex_string_literal start sofar lsi =
    if lsi.char == '"' then
        Tokens [ Token (lsi.view_from_start start) (Literal Language.StringLiteral sofar) ] begin_lex

    else if lsi.char == '\n' then
        Error (UnclosedStringLiteral (lsi.view_from_start start))

    else
        lex_string_literal start (Util.addchar sofar lsi.char) |> LexFn |> Tokens []


lex_this_or_equal_to : TokenType -> TokenType -> Int -> LexStepInfo -> LexRes
lex_this_or_equal_to type_if_e type_if_note pos lsi =
    case lsi.char of
        '=' ->
            Tokens [ Token (lsi.view_from_start pos) type_if_e ] (LexFn lex_unknown)

        _ ->
            apply_again [ Token (lsi.input_view pos (pos + 1)) type_if_note ] (LexFn lex_unknown) lsi


lex_unknown : LexStepInfo -> LexRes
lex_unknown lsi =
    let
        c =
            lsi.char
    in
    if c == ' ' then
        Tokens [] begin_lex

    else if c == '\n' then
        Tokens [ Token lsi.view_this NewlineToken ] begin_lex

    else if Char.isAlpha c then
        lex_symbol lsi.pos (String.fromChar c) |> LexFn |> Tokens []

    else if Char.isDigit c then
        lex_integer lsi.pos (String.fromChar c) |> LexFn |> Tokens []

    else if c == '"' then
        Tokens [] (LexFn (lex_string_literal lsi.pos ""))

    else if c == '{' then
        Tokens [ Token lsi.view_this OpenCurly ] begin_lex

    else if c == '}' then
        Tokens [ Token lsi.view_this CloseCurly ] begin_lex

    else if c == '(' then
        Tokens [ Token lsi.view_this OpenParen ] begin_lex

    else if c == ')' then
        Tokens [ Token lsi.view_this CloseParen ] begin_lex

    else if c == '[' then
        Tokens [ Token lsi.view_this OpenSquare ] begin_lex

    else if c == ']' then
        Tokens [ Token lsi.view_this CloseSquare ] begin_lex

    else if c == ':' then
        Tokens [ Token lsi.view_this TypeSpecifier ] begin_lex

    else if c == ',' then
        Tokens [ Token lsi.view_this CommaToken ] begin_lex

    else if c == '.' then
        Tokens [ Token lsi.view_this DotToken ] begin_lex

    else if c == '=' then
        lex_this_or_equal_to EqualityToken AssignmentToken lsi.pos |> LexFn |> Tokens []

    else if c == '!' then
        lex_this_or_equal_to NotEqualToken NotToken lsi.pos |> LexFn |> Tokens []

    else if c == '&' then
        Tokens [ Token lsi.view_this ReferenceToken ] begin_lex

    else if c == '<' then
        lex_this_or_equal_to LessThanEqualToken LessThanToken lsi.pos |> LexFn |> Tokens []

    else if c == '>' then
        lex_this_or_equal_to GreaterThanEqualToken GreaterThanToken lsi.pos |> LexFn |> Tokens []

    else if c == '+' then
        Tokens [ Token lsi.view_this PlusToken ] begin_lex

    else if c == '-' then
        Tokens [] (LexFn (lex_minus_or_return lsi.pos))

    else if c == '*' then
        Tokens [ Token lsi.view_this MultiplyToken ] begin_lex

    else if c == '/' then
        Tokens [] (LexFn lex_divide_or_comment)
    else if c =='|' then   
        Tokens [Token lsi.view_this WhereToken] begin_lex

    else
        Error (UnknownCharacter (lsi.input_view lsi.pos (lsi.pos + 1)) c)


is_special_or_symbol : String -> TokenType
is_special_or_symbol s =
    if s == "true" then
        Literal Language.BooleanLiteral s

    else if s == "false" then
        Literal Language.BooleanLiteral s

    else
        case is_keyword s of
            Just kwt ->
                Keyword kwt

            Nothing ->
                Symbol s


is_keyword : String -> Maybe Language.KeywordType
is_keyword s =
    case s of
        "fn" ->
            Just Language.FnKeyword

        "return" ->
            Just Language.ReturnKeyword

        "module" ->
            Just Language.ModuleKeyword

        "import" ->
            Just Language.ImportKeyword

        "var" ->
            Just Language.VarKeyword

        "struct" ->
            Just Language.StructKeyword

        "if" ->
            Just Language.IfKeyword

        "while" ->
            Just Language.WhileKeyword

        "enum" ->
            Just Language.EnumKeyword
        "type" ->
            Just Language.TypeKeyword

        _ ->
            Nothing


kwt_to_string : Language.KeywordType -> String
kwt_to_string kwt =
    case kwt of
        Language.FnKeyword ->
            "fn"

        Language.ReturnKeyword ->
            "return"

        Language.ModuleKeyword ->
            "module"

        Language.ImportKeyword ->
            "import"

        Language.VarKeyword ->
            "var"

        Language.StructKeyword ->
            "struct"

        Language.IfKeyword ->
            "if"

        Language.WhileKeyword ->
            "while"

        Language.EnumKeyword ->
            "enum"
        Language.TypeKeyword ->
            "Type"


syntaxify_token : TokenType -> String
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

        AssignmentToken ->
            " = "

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

        CommentToken s ->
            "//" ++ s

        EqualityToken ->
            "=="

        LessThanToken ->
            "<"

        LessThanEqualToken ->
            ">"

        GreaterThanToken ->
            ">"

        GreaterThanEqualToken ->
            ">="

        OpenSquare ->
            "["

        CloseSquare ->
            "]"

        NotToken ->
            "!"

        NotEqualToken ->
            "!="

        ReferenceToken ->
            "&"

        WhereToken ->
            "|"


token_to_str : Token -> String
token_to_str tok =
    case tok.typ of
        Keyword kt ->
            "[Keyword:"
                ++ kwt_to_string kt
                ++ "]"

        Symbol str ->
            "[`" ++ str ++ "`]"

        OpenCurly ->
            "[OpenCurly]"

        CloseCurly ->
            "[CloseCurly]"

        OpenParen ->
            "[OpenParen]"

        CloseParen ->
            "[CloseParen]"

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
            "[:]"

        CommaToken ->
            "[,]"

        DotToken ->
            "[.]"

        ReturnSpecifier ->
            "-[>]"

        PlusToken ->
            "[+]"

        MinusToken ->
            "[-]"

        MultiplyToken ->
            "[*]"

        DivideToken ->
            "[/]"

        NewlineToken ->
            "[\\n]"

        CommentToken s ->
            "[Comment: " ++ s ++ "]"

        AssignmentToken ->
            "[Assignment =]"

        EqualityToken ->
            "[==]"

        LessThanToken ->
            "[<]"

        LessThanEqualToken ->
            "[<=]"

        GreaterThanToken ->
            "[>]"

        GreaterThanEqualToken ->
            "[>=]"

        OpenSquare ->
            "[ [ ]"

        CloseSquare ->
            "[ ] ]"

        NotEqualToken ->
            "[ != ]"

        NotToken ->
            "[ ! ]"

        ReferenceToken ->
            "[ & ] "

        WhereToken ->
            "[ | ]"
