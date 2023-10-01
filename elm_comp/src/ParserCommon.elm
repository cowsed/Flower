module ParserCommon exposing (..)

import Language exposing (ASTExpression(..), ASTFunctionDefinition, ASTStatement(..), UnqualifiedTypeName, UnqualifiedTypeWithName)
import Lexer exposing (Token, TokenType(..))
import Util
import Language exposing (FullName(..))


type alias Program =
    { module_name : Maybe String
    , imports : List String
    , global_structs : List ASTStructDefnition
    , global_functions : List ASTFunctionDefinition
    , needs_more : Maybe String
    , src_tokens : List Token
    }


type alias ASTStructDefnition =
    { name : FullName
    , fields : List UnqualifiedTypeWithName
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
    | UnknownThingWhileParsingFuncCallOrAssignment Util.SourceView
    | FailedFuncCallParse FuncCallParseError
    | FailedBlockParse StatementParseError
    | ExpectedOpenCurlyForFunction Util.SourceView
    | ExpectedNameAfterDot Util.SourceView
    | UnexpectedTokenInGenArgList Util.SourceView
    | ExpectedNameForStruct Util.SourceView


type StatementParseError
    = None


type TypeParseError
    = Idk Util.SourceView
    | UnexpectedTokenInTypesGenArgList Util.SourceView


type NamedTypeParseError
    = NameError Util.SourceView String
    | TypeError TypeParseError


type FuncCallParseError
    = IdkFuncCall Util.SourceView String
    | ExpectedAnotherArgument Util.SourceView


type ExprParseError
    = IdkExpr Util.SourceView String
    | ParenWhereIDidntWantIt Util.SourceView


type alias ExprParseWhatTodo =
    Result ExprParseError ASTExpression -> ParseRes


type alias TypenameParseTodo =
    Result TypeParseError UnqualifiedTypeName -> ParseRes


type alias NameWithSquareArgsTodo =
    Result Error FullName -> ParseRes


type alias NamedTypeParseTodo =
    Result NamedTypeParseError UnqualifiedTypeWithName -> ParseRes


type alias StatementParseTodo =
    Result StatementParseError Language.ASTStatement -> ParseRes


type alias StatementBlockParseTodo =
    Result StatementParseError (List ASTStatement) -> ParseRes


type alias FuncCallExprTodo =
    Result FuncCallParseError Language.ASTFunctionCall -> ParseRes


reapply_token_or_fail : ParseRes -> ParseStep -> ParseRes
reapply_token_or_fail res ps =
    case res of
        Next prog fn ->
            extract_fn fn { ps | prog = prog }

        Error e ->
            Error e


reapply_token : ParseFn -> ParseStep -> ParseRes
reapply_token fn ps =
    extract_fn fn ps


extract_fn : ParseFn -> (ParseStep -> ParseRes)
extract_fn fn =
    case fn of
        ParseFn f ->
            f


parse_expected_token : String -> TokenType -> ParseRes -> ParseStep -> ParseRes
parse_expected_token reason expected after ps =
    if ps.tok.typ == expected then
        after

    else
        Error (ExpectedToken reason ps.tok.loc)



parse_name_with_gen_args_comma_or_end : NameWithSquareArgsTodo -> FullName -> ParseStep -> ParseRes
parse_name_with_gen_args_comma_or_end todo name_and_args ps =
    let
        todo_with_type : NameWithSquareArgsTodo
        todo_with_type res =
            case res of
                Err e ->
                    Error e

                Ok t ->
                    parse_name_with_gen_args_comma_or_end todo (Language.append_generic_name name_and_args t) |> ParseFn |> Next ps.prog
    in
    case ps.tok.typ of
        CommaToken ->
            parse_name_with_square_args todo_with_type |> ParseFn |> Next ps.prog

        CloseSquare ->
            Ok name_and_args |> todo

        _ ->
            todo <| Err (UnexpectedTokenInGenArgList ps.tok.loc)


parse_name_with_gen_args_ga_start_or_end : NameWithSquareArgsTodo -> UnqualifiedTypeName -> ParseStep -> ParseRes
parse_name_with_gen_args_ga_start_or_end todo name_and_args ps =
    let
        todo_with_type : Result TypeParseError FullName -> ParseRes
        todo_with_type res =
            case res of
                Err e ->
                    Error (FailedTypeParse e)

                Ok t ->
                    parse_name_with_gen_args_comma_or_end todo (Language.append_generic_name name_and_args t) |> ParseFn |> Next ps.prog
    in
    case ps.tok.typ of
        CloseSquare ->
            todo (Ok name_and_args)

        _ ->
            parse_name_with_square_args todo_with_type ps


parse_name_with_gen_args_continue_name : NameWithSquareArgsTodo -> Language.Identifier -> ParseStep -> ParseRes
parse_name_with_gen_args_continue_name todo name ps =
    case ps.tok.typ of
        Symbol s ->
            parse_name_with_gen_args_dot_or_end todo (Language.append_identifier name s) |> ParseFn |> Next ps.prog

        CommaToken ->
            todo (Ok (Language.Basic name))

        _ ->
            Err (FailedNamedTypeParse (NameError ps.tok.loc "Expected a symbol like 'a' or 'std' here")) |> todo


parse_name_with_gen_args_dot_or_end : NameWithSquareArgsTodo -> Language.Identifier -> ParseStep -> ParseRes
parse_name_with_gen_args_dot_or_end todo name_so_far ps =
    case ps.tok.typ of
        DotToken ->
            parse_name_with_gen_args_continue_name todo name_so_far |> ParseFn |> Next ps.prog

        OpenSquare ->
            parse_name_with_gen_args_ga_start_or_end todo (Language.Basic name_so_far) |> ParseFn |> Next ps.prog

        _ ->
            reapply_token_or_fail (todo (Ok (Language.Basic name_so_far))) ps


parse_name_with_square_args : NameWithSquareArgsTodo -> ParseStep -> ParseRes
parse_name_with_square_args todo ps =
    case ps.tok.typ of
        Symbol s ->
            parse_name_with_gen_args_dot_or_end todo (Language.SingleIdentifier s) |> ParseFn |> Next ps.prog

        _ ->
            Err (FailedNamedTypeParse (NameError ps.tok.loc "AAAExpected a symbol like 'a' or 'std' here")) |> todo
