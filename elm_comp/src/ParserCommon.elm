module ParserCommon exposing (..)

import Language exposing (ASTExpression(..), ASTFunctionDefinition, ASTStatement(..), UnqualifiedTypeWithName)
import Lexer exposing (Token, TokenType(..))
import Util
import Language exposing (UnqualifiedTypeName)


type alias Program =
    { module_name : Maybe String
    , imports : List String
    , global_functions : List ASTFunctionDefinition
    , needs_more : Maybe String
    , src_tokens : List Token
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

type alias NameWithGenArgsTodo = Result Error (Language.Name, List Language.UnqualifiedTypeName) -> ParseRes 
    

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
        Next prog fn -> extract_fn fn {ps | prog = prog}

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
