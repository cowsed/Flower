module Parser.ParserCommon exposing (..)

import Language.Language as Language
import Parser.AST as AST exposing (Expression(..), FullName(..), Statement(..), UnqualifiedTypeWithName)
import Parser.Lexer as Lexer exposing (Token, TokenType(..), token_type)
import Util exposing (escape_result)
import Language.Syntax as Syntax exposing (Node, node_get, node_location)


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
    | NonStringImport Syntax.SourceView
    | Unimplemented AST.Program String
    | NeededMoreTokens String
    | UnknownOuterLevelObject Syntax.SourceView
    | ExpectedNameAfterFn Syntax.SourceView
    | ExpectedOpenParenAfterFn String Syntax.SourceView
    | ExpectedToken String Syntax.SourceView
    | ExpectedTypeName Syntax.SourceView
    | ExpectedEndOfArgListOrComma Syntax.SourceView
    | FailedTypeParse TypeParseError
    | FailedNamedTypeParse NamedTypeParseError
    | KeywordNotAllowedHere Syntax.SourceView
    | FailedExprParse ExprParseError
    | ExpectedFunctionBody Syntax.SourceView TokenType
    | RequireInitilizationWithValue Syntax.SourceView
    | UnknownThingWhileParsingFuncCallOrAssignment Syntax.SourceView
    | FailedFuncCallParse FuncCallParseError
    | FailedBlockParse StatementParseError
    | ExpectedOpenCurlyForFunction Syntax.SourceView
    | ExpectedNameAfterDot Syntax.SourceView
    | UnexpectedTokenInGenArgList Syntax.SourceView
    | ExpectedNameForStruct Syntax.SourceView
    | UnknownTokenInEnumBody Syntax.SourceView
    | ExpectedCloseParenInEnumField Syntax.SourceView
    | ExpectedEqualInTypeDeclaration Syntax.SourceView


type StatementParseError
    = None


type TypeParseError
    = Idk Syntax.SourceView
    | UnexpectedTokenInTypesGenArgList Syntax.SourceView


type NamedTypeParseError
    = NameError Syntax.SourceView String
    | TypeError TypeParseError


type FuncCallParseError
    = IdkFuncCall Syntax.SourceView String
    | ExpectedAnotherArgument Syntax.SourceView


type ExprParseError
    = IdkExpr Syntax.SourceView String
    | ParenWhereIDidntWantIt Syntax.SourceView


type alias ExprParseTodo =
    Result ExprParseError (Node Expression) -> ParseRes


type alias FullNameParseTodo =
    Result Error (Node FullName) -> ParseRes


type alias NamedTypeParseTodo =
    Result NamedTypeParseError UnqualifiedTypeWithName -> ParseRes


type alias StatementParseTodo =
    Result StatementParseError AST.Statement -> ParseRes


type alias StatementBlockParseTodo =
    Result StatementParseError (List Statement) -> ParseRes


type alias FuncCallExprTodo =
    Result FuncCallParseError (Node AST.FunctionCall) -> ParseRes


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
    if token_type ps.tok == expected then
        after

    else
        Error (ExpectedToken reason ps.tok.loc)


parse_fullname_with_gen_args_comma_or_end : FullNameParseTodo -> (Node FullName) -> ParseStep -> ParseRes
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
    case token_type ps.tok of
        CommaToken ->
            parse_fullname todo_with_type |> ParseFn |> Next ps.prog

        CloseSquare ->
            Ok name_and_args |> todo

        _ ->
            todo <| Err (UnexpectedTokenInGenArgList ps.tok.loc)


parse_fullname_with_ga_start_or_end : FullNameParseTodo -> (Node FullName) -> ParseStep -> ParseRes
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
    case token_type ps.tok of
        CloseSquare ->
            todo (Ok name_and_args)

        _ ->
            parse_fullname todo_with_type ps


parse_fullname_gen_args_continue : FullNameParseTodo -> Language.Identifier -> Syntax.SourceView -> ParseStep -> ParseRes
parse_fullname_gen_args_continue todo name idloc ps =
    case token_type ps.tok of
        Symbol s ->
            parse_fullname_gen_args_dot_or_end todo (Syntax.merge_sv idloc ps.tok.loc) (AST.append_identifier name s) |> ParseFn |> Next ps.prog

        CommaToken ->
            todo (Ok (NameWithoutArgs name |> AST.with_location (Syntax.merge_sv idloc ps.tok.loc)))

        _ ->
            Err (FailedNamedTypeParse (NameError ps.tok.loc "Expected a symbol like 'a' or 'std' here")) |> todo


parse_fullname_gen_args_dot_or_end : FullNameParseTodo -> Syntax.SourceView -> Language.Identifier -> ParseStep -> ParseRes
parse_fullname_gen_args_dot_or_end todo name_loc name_so_far ps =

    
    case token_type ps.tok of
        DotToken ->
            parse_fullname_gen_args_continue todo name_so_far name_loc |> ParseFn |> Next ps.prog

        OpenSquare ->
            parse_fullname_with_ga_start_or_end todo (NameWithArgs { base = name_so_far, args = [] } |> AST.with_location name_loc) |> ParseFn |> Next ps.prog


        _ ->
            reapply_token_or_fail (todo (Ok (NameWithoutArgs name_so_far |> AST.with_location name_loc))) ps


parse_fullname : FullNameParseTodo -> ParseStep -> ParseRes
parse_fullname todo ps =
    let
        inner_todo = todo
        todo_if_ref : FullNameParseTodo
        todo_if_ref res =
            res
                |> Result.mapError (\e -> Error e)
                |> Result.andThen (\fn -> inner_todo (ReferenceToFullName fn |> AST.with_location (Syntax.merge_sv ps.tok.loc fn.loc) |> Ok) |> Ok)
                |> escape_result
    in
    case token_type ps.tok of
        Symbol s ->
            parse_fullname_gen_args_dot_or_end inner_todo ps.tok.loc (Language.SingleIdentifier s) |> ParseFn |> Next ps.prog

        ReferenceToken ->
            parse_fullname todo_if_ref |> ParseFn |> Next ps.prog


        Lexer.Literal l s ->
            AST.Literal l s |> AST.with_location ps.tok.loc |> Ok |> todo

        _ ->
            Err (FailedNamedTypeParse (NameError ps.tok.loc "AAAExpected a symbol like 'a' or 'std' here")) |> todo
