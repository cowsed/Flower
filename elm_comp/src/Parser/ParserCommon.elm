module Parser.ParserCommon exposing (..)

import Language
import Parser.AST as AST exposing (Expression(..), ExpressionAndLocation, FullName(..), FullNameAndLocation, Statement(..), UnqualifiedTypeWithName)
import Parser.Lexer as Lexer exposing (Token, TokenType(..))
import Util exposing (escape_result)


type ParseFn
    = ParseFn (ParseStep -> ParseRes)


type alias ParseStep =
    { tok : Token
    , prog : AST.Program
    }


type ParseRes
    = Error Error
    | Next AST.Program ParseFn
    | NextNoChange ParseFn


next_pfn : (ParseStep -> ParseRes) -> ParseRes
next_pfn f =
    f |> ParseFn |> NextNoChange


type Error
    = NoModuleNameGiven
    | NonStringImport Util.SourceView
    | Unimplemented AST.Program String
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
    | UnknownTokenInEnumBody Util.SourceView
    | ExpectedCloseParenInEnumField Util.SourceView
    | ExpectedEqualInTypeDeclaration Util.SourceView


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


type alias ExprParseTodo =
    Result ExprParseError ExpressionAndLocation -> ParseRes


type alias FullNameParseTodo =
    Result Error FullNameAndLocation -> ParseRes


type alias NamedTypeParseTodo =
    Result NamedTypeParseError UnqualifiedTypeWithName -> ParseRes


type alias StatementParseTodo =
    Result StatementParseError AST.Statement -> ParseRes


type alias StatementBlockParseTodo =
    Result StatementParseError (List Statement) -> ParseRes


type alias FuncCallExprTodo =
    Result FuncCallParseError AST.FunctionCallAndLocation -> ParseRes


reapply_token_or_fail : ParseRes -> ParseStep -> ParseRes
reapply_token_or_fail res ps =
    case res of
        NextNoChange fn ->
            extract_fn fn ps

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


parse_fullname_with_gen_args_comma_or_end : FullNameParseTodo -> FullNameAndLocation -> ParseStep -> ParseRes
parse_fullname_with_gen_args_comma_or_end todo name_and_args ps =
    let
        todo_with_type : FullNameParseTodo
        todo_with_type res =
            case res of
                Err e ->
                    Error e

                Ok t ->
                    parse_fullname_with_gen_args_comma_or_end todo (AST.append_fullname_args name_and_args t) |> ParseFn |> Next ps.prog
    in
    case ps.tok.typ of
        CommaToken ->
            parse_fullname todo_with_type |> ParseFn |> Next ps.prog

        CloseSquare ->
            Ok name_and_args |> todo

        _ ->
            todo <| Err (UnexpectedTokenInGenArgList ps.tok.loc)


parse_fullname_with_ga_start_or_end : FullNameParseTodo -> FullNameAndLocation -> ParseStep -> ParseRes
parse_fullname_with_ga_start_or_end todo name_and_args ps =
    let
        todo_with_type : FullNameParseTodo
        todo_with_type res =
            case res of
                Err e ->
                    Error e

                Ok t ->
                    parse_fullname_with_gen_args_comma_or_end todo (AST.append_fullname_args name_and_args t) |> ParseFn |> Next ps.prog
    in
    case ps.tok.typ of
        CloseSquare ->
            todo (Ok name_and_args)

        _ ->
            parse_fullname todo_with_type ps


parse_fullname_gen_args_continue : FullNameParseTodo -> Language.Identifier -> Util.SourceView -> ParseStep -> ParseRes
parse_fullname_gen_args_continue todo name loc ps =
    case ps.tok.typ of
        Symbol s ->
            parse_fullname_gen_args_dot_or_end todo ps.tok.loc (AST.append_identifier name s) |> ParseFn |> Next ps.prog

        CommaToken ->
            todo (Ok (NameWithoutArgs name |> AST.with_location (Util.merge_sv loc ps.tok.loc)))

        _ ->
            Err (FailedNamedTypeParse (NameError ps.tok.loc "Expected a symbol like 'a' or 'std' here")) |> todo


parse_fullname_gen_args_dot_or_end : FullNameParseTodo -> Util.SourceView -> Language.Identifier -> ParseStep -> ParseRes
parse_fullname_gen_args_dot_or_end todo name_loc name_so_far ps =
    case ps.tok.typ of
        DotToken ->
            parse_fullname_gen_args_continue todo name_so_far name_loc |> ParseFn |> Next ps.prog

        OpenSquare ->
            parse_fullname_with_ga_start_or_end todo (NameWithArgs { base = name_so_far, args = [] } |> AST.with_location name_loc) |> ParseFn |> Next ps.prog

        _ ->
            reapply_token_or_fail (todo (Ok (NameWithoutArgs name_so_far |> AST.with_location name_loc))) ps


parse_fullname : FullNameParseTodo -> ParseStep -> ParseRes
parse_fullname todo ps =
    let
        todo_if_ref : FullNameParseTodo
        todo_if_ref res =
            res
                |> Result.mapError (\e -> Error e)
                |> Result.andThen (\fn -> todo (ReferenceToFullName fn |> AST.with_location (Util.merge_sv ps.tok.loc fn.loc) |> Ok) |> Ok)
                |> escape_result
    in
    case ps.tok.typ of
        Symbol s ->
            parse_fullname_gen_args_dot_or_end todo ps.tok.loc (Language.SingleIdentifier s) |> ParseFn |> Next ps.prog

        ReferenceToken ->
            parse_fullname todo_if_ref |> ParseFn |> Next ps.prog

        Lexer.Literal l s ->
            AST.Literal l s |> AST.with_location ps.tok.loc |> Ok |> todo

        _ ->
            Err (FailedNamedTypeParse (NameError ps.tok.loc "AAAExpected a symbol like 'a' or 'std' here")) |> todo
