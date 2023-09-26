module ParserCommon exposing (..)

import Language exposing (ASTExpression(..), ASTFunctionDefinition)
import Lexer exposing (Token, TokenType(..))
import Util


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
    | ExpectedOpenCurlyForFunction Util.SourceView


type TypeParseError
    = Idk Util.SourceView


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

apply_again : ParseFn -> ParseStep -> ParseRes
apply_again fn ps =
    extract_fn fn ps

extract_fn : ParseFn -> (ParseStep -> ParseRes)
extract_fn fn =
    case fn of
        ParseFn f ->
            f
