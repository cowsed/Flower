module Parser.Lexer exposing (..)

import Element
import Element.Font as Font
import Language.Language as Language
import Language.Syntax as Syntax exposing (Node, node_get)
import Pallete
import Util


type alias Token =
    Node TokenType


token : Syntax.SourceView -> TokenType -> Node TokenType
token loc tt =
    Node tt loc


token_type : Token -> TokenType
token_type t =
    node_get t


type TokenType
    = Keyword Syntax.KeywordType
    | Symbol String
    | Literal Syntax.LiteralType String
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
    | AndToken -- and
    | XorToken -- xor
    | OrToken -- or
    | PlusToken -- +
    | MinusToken -- -
    | MultiplyToken -- *
    | DivideToken -- /
    | OpenCurly -- {
    | CloseCurly -- }
    | OpenParen -- (
    | CloseParen -- )
    | OpenSquare -- [
    | CloseSquare -- ]
    | WhereToken -- |
    | CommentToken String


lex : String -> Result Error (List Token)
lex str =
    let
        input_view =
            Syntax.SourceView str
    in
    String.toList str |> rec_lex begin_lex input_view 0


type LexRes
    = Tokens (List Token) LexFn
    | Error Error


type Error
    = UnknownCharacter Syntax.SourceView Char
    | UnclosedStringLiteral Syntax.SourceView
    | NotEnoughDigitsInNumberLiteral Syntax.IntegerLiteralType Syntax.SourceView
    | UnknownCharacterInIntegerLiteral Syntax.IntegerLiteralType Syntax.SourceView


infix_op_from_token : Token -> Maybe Language.InfixOpType
infix_op_from_token tok =
    case node_get tok of
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

        AndToken ->
            Just Language.And

        OrToken ->
            Just Language.Or

        XorToken ->
            Just Language.Xor

        _ ->
            Nothing


explain_error : Error -> Element.Element msg
explain_error e =
    Element.column []
        [ Element.el [ Font.color Pallete.red_c, Font.family [ Font.monospace ] ]
            (case e of
                UnknownCharacter sv c ->
                    Element.text (Util.addchar "Unknown character: " c ++ "\n" ++ Syntax.show_source_view sv)

                UnclosedStringLiteral sv ->
                    Element.text ("Unclosed String Literal here: \n" ++ Syntax.show_source_view sv)

                UnknownCharacterInIntegerLiteral ilt sv ->
                    Element.text ("Unknown character in " ++ Debug.toString ilt ++ " integer Literal\n" ++ Syntax.show_source_view sv)

                NotEnoughDigitsInNumberLiteral ilt sv ->
                    Element.text ("need at least one digit in " ++ Debug.toString ilt ++ " integer Literal\n" ++ Syntax.show_source_view sv)
            )
        ]


type LexFn
    = LexFn (LexStepInfo -> LexRes)


type alias LexStepInfo =
    { input_view : Int -> Int -> Syntax.SourceView
    , view_from_start : Int -> Syntax.SourceView
    , view_this : Syntax.SourceView
    , pos : Int
    , char : Char
    }


call_lexfn : LexFn -> LexStepInfo -> LexRes
call_lexfn lf lsi =
    case lf of
        LexFn f ->
            f lsi


rec_lex : LexFn -> (Int -> Int -> Syntax.SourceView) -> Int -> List Char -> Result Error (List Token)
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


digit_allowed : Syntax.IntegerLiteralType -> Char -> Bool
digit_allowed ilt c =
    case ilt of
        Syntax.Decimal ->
            Char.isDigit c

        Syntax.Binary ->
            c == '0' || c == '1'

        Syntax.Hex ->
            Char.isDigit c || List.member c [ 'a', 'b', 'c', 'd', 'e', 'f', 'A', 'B', 'C', 'D', 'E', 'F' ]


lex_integer : Syntax.IntegerLiteralType -> Int -> String -> LexStepInfo -> LexRes
lex_integer ilt start sofar lsi =
    if digit_allowed ilt lsi.char then
        LexFn (lex_integer ilt start (Util.addchar sofar lsi.char)) |> Tokens []

    else if lsi.char == 'x' && sofar == "0" && ilt == Syntax.Decimal then
        -- hex literal
        LexFn (lex_integer Syntax.Hex start (Util.addchar "" lsi.char)) |> Tokens []

    else if lsi.char == 'b' && sofar == "0" && ilt == Syntax.Decimal then
        -- hex literal
        LexFn (lex_integer Syntax.Binary start (Util.addchar "" lsi.char)) |> Tokens []

    else if is_integer_ender lsi.char then
        apply_again [ token (lsi.view_from_start start) (Literal (Syntax.NumberLiteral ilt) sofar) ] begin_lex lsi

    else
        Error (UnknownCharacterInIntegerLiteral ilt lsi.view_this)


lex_symbol : Int -> String -> LexStepInfo -> LexRes
lex_symbol start sofar lsi =
    if Char.isAlphaNum lsi.char then
        lex_symbol start (Util.addchar sofar lsi.char) |> LexFn |> Tokens []

    else if lsi.char == '_' then
        lex_symbol start (Util.addchar sofar lsi.char) |> LexFn |> Tokens []

    else
        apply_again [ token (lsi.view_from_start start) (is_special_or_symbol sofar) ] begin_lex lsi



-- from no information


begin_lex : LexFn
begin_lex =
    LexFn lex_unknown


lex_minus_or_return : Int -> LexStepInfo -> LexRes
lex_minus_or_return start lsi =
    if lsi.char == '>' then
        Tokens [ token (lsi.input_view start (start + 2)) ReturnSpecifier ] begin_lex

    else
        apply_again [ token (lsi.input_view start (start + 1)) MinusToken ] begin_lex lsi


lex_rest_of_comment : Int -> String -> LexStepInfo -> LexRes
lex_rest_of_comment start sofar lsi =
    if lsi.char == '\n' then
        Tokens
            [ token (lsi.input_view start (start + lsi.pos - 1)) (CommentToken sofar)
            , token (lsi.input_view lsi.pos (lsi.pos + 1)) NewlineToken
            ]
            begin_lex

    else
        lex_rest_of_comment start (Util.addchar sofar lsi.char) |> LexFn |> Tokens []


lex_divide_or_comment : LexStepInfo -> LexRes
lex_divide_or_comment lsi =
    if lsi.char == '/' then
        Tokens [] (LexFn (lex_rest_of_comment (lsi.pos - 1) ""))

    else
        apply_again [ token (lsi.input_view (lsi.pos - 1) lsi.pos) DivideToken ] begin_lex lsi


lex_string_literal : Int -> String -> LexStepInfo -> LexRes
lex_string_literal start sofar lsi =
    if lsi.char == '"' then
        Tokens [ token (lsi.input_view start (lsi.pos + 1)) (Literal Syntax.StringLiteral sofar) ] begin_lex

    else if lsi.char == '\n' then
        Error (UnclosedStringLiteral (lsi.view_from_start start))

    else
        lex_string_literal start (Util.addchar sofar lsi.char) |> LexFn |> Tokens []


lex_this_or_equal_to : TokenType -> TokenType -> Int -> LexStepInfo -> LexRes
lex_this_or_equal_to type_if_e type_if_note pos lsi =
    case lsi.char of
        '=' ->
            Tokens [ token (lsi.view_from_start pos) type_if_e ] (LexFn lex_unknown)

        _ ->
            apply_again [ token (lsi.input_view pos (pos + 1)) type_if_note ] (LexFn lex_unknown) lsi


lex_unknown : LexStepInfo -> LexRes
lex_unknown lsi =
    let
        c =
            lsi.char
    in
    if c == ' ' then
        Tokens [] begin_lex

    else if c == '\n' then
        Tokens [ token lsi.view_this NewlineToken ] begin_lex

    else if Char.isAlpha c then
        lex_symbol lsi.pos (String.fromChar c) |> LexFn |> Tokens []

    else if Char.isDigit c then
        lex_integer Syntax.Decimal lsi.pos (String.fromChar c) |> LexFn |> Tokens []

    else if c == '"' then
        Tokens [] (LexFn (lex_string_literal lsi.pos ""))

    else if c == '{' then
        Tokens [ token lsi.view_this OpenCurly ] begin_lex

    else if c == '}' then
        Tokens [ token lsi.view_this CloseCurly ] begin_lex

    else if c == '(' then
        Tokens [ token lsi.view_this OpenParen ] begin_lex

    else if c == ')' then
        Tokens [ token lsi.view_this CloseParen ] begin_lex

    else if c == '[' then
        Tokens [ token lsi.view_this OpenSquare ] begin_lex

    else if c == ']' then
        Tokens [ token lsi.view_this CloseSquare ] begin_lex

    else if c == ':' then
        Tokens [ token lsi.view_this TypeSpecifier ] begin_lex

    else if c == ',' then
        Tokens [ token lsi.view_this CommaToken ] begin_lex

    else if c == '.' then
        Tokens [ token lsi.view_this DotToken ] begin_lex

    else if c == '=' then
        lex_this_or_equal_to EqualityToken AssignmentToken lsi.pos |> LexFn |> Tokens []

    else if c == '!' then
        lex_this_or_equal_to NotEqualToken NotToken lsi.pos |> LexFn |> Tokens []

    else if c == '&' then
        Tokens [ token lsi.view_this ReferenceToken ] begin_lex

    else if c == '<' then
        lex_this_or_equal_to LessThanEqualToken LessThanToken lsi.pos |> LexFn |> Tokens []

    else if c == '>' then
        lex_this_or_equal_to GreaterThanEqualToken GreaterThanToken lsi.pos |> LexFn |> Tokens []

    else if c == '+' then
        Tokens [ token lsi.view_this PlusToken ] begin_lex

    else if c == '-' then
        Tokens [] (LexFn (lex_minus_or_return lsi.pos))

    else if c == '*' then
        Tokens [ token lsi.view_this MultiplyToken ] begin_lex

    else if c == '/' then
        Tokens [] (LexFn lex_divide_or_comment)

    else if c == '|' then
        Tokens [ token lsi.view_this WhereToken ] begin_lex

    else
        Error (UnknownCharacter (lsi.input_view lsi.pos (lsi.pos + 1)) c)


is_special_or_symbol : String -> TokenType
is_special_or_symbol s =
    if s == "xor" then
        XorToken

    else if s == "and" then
        AndToken

    else if s == "or" then
        OrToken

    else
        case is_keyword s of
            Just kwt ->
                Keyword kwt

            Nothing ->
                Symbol s


is_keyword : String -> Maybe Syntax.KeywordType
is_keyword s =
    case s of
        "fn" ->
            Just Syntax.FnKeyword

        "return" ->
            Just Syntax.ReturnKeyword

        "module" ->
            Just Syntax.ModuleKeyword

        "import" ->
            Just Syntax.ImportKeyword

        "var" ->
            Just Syntax.VarKeyword

        "struct" ->
            Just Syntax.StructKeyword

        "if" ->
            Just Syntax.IfKeyword

        "while" ->
            Just Syntax.WhileKeyword

        "enum" ->
            Just Syntax.EnumKeyword

        "type" ->
            Just Syntax.TypeKeyword

        _ ->
            Nothing


kwt_to_string : Syntax.KeywordType -> String
kwt_to_string kwt =
    case kwt of
        Syntax.FnKeyword ->
            "fn"

        Syntax.ReturnKeyword ->
            "return"

        Syntax.ModuleKeyword ->
            "module"

        Syntax.ImportKeyword ->
            "import"

        Syntax.VarKeyword ->
            "var"

        Syntax.StructKeyword ->
            "struct"

        Syntax.IfKeyword ->
            "if"

        Syntax.WhileKeyword ->
            "while"

        Syntax.EnumKeyword ->
            "enum"

        Syntax.TypeKeyword ->
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

        OrToken ->
            "or"

        AndToken ->
            "and"

        XorToken ->
            "xor"


token_to_str : Token -> String
token_to_str tok =
    case token_type tok of
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
                        Syntax.StringLiteral ->
                            "_str"

                        Syntax.NumberLiteral ilt ->
                            case ilt of
                                Syntax.Binary ->
                                    "_int_bin"

                                Syntax.Hex ->
                                    "_int_hex"

                                Syntax.Decimal ->
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

        OrToken ->
            "[ or ]"

        AndToken ->
            "[ and ]"

        XorToken ->
            "[ xor ]"
