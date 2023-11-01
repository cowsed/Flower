module Analysis.Util exposing (..)

import Language.Language exposing (..)
import Parser.AST as AST
import Util
import Analysis.DefinitionPropagator exposing (DefinitionPropagator)
import Analysis.DefinitionPropagator as DefinitionPropagator
import Language.Syntax as Syntax

type alias AnalysisRes a =
    Result AnalysisError a


type AnalysisError
    = UnknownImport AST.ImportNode
    | NoModuleName
    | InvalidSyntaxInStructDefinition
    | StructFieldNameTooComplicated Syntax.SourceView
    | ExpectedSymbolInGenericArg Syntax.SourceView
    | GenericArgIdentifierTooComplicated Syntax.SourceView
    | FunctionNameArgTooComplicated Syntax.SourceView
    | TypeNameTooComplicated Syntax.SourceView
    | BadTypeParse Syntax.SourceView
    | TypeNameNotFound Identifier Syntax.SourceView
    | TypeNotInstantiable Identifier Syntax.SourceView
    | CantInstantiateGenericWithTheseArgs ReasonForUninstantiable Syntax.SourceView
    | GenericTypeNameNotValidWithoutSquareBrackets Syntax.SourceView
    | Unimplemented String
    | NoSuchTypeFound Syntax.SourceView
    | NoSuchGenericTypeFound Syntax.SourceView
    | DefPropErr DefinitionPropagator.Error
    | Multiple (List AnalysisError)


res_join_2 : (a -> b -> c) -> AnalysisRes a -> AnalysisRes b -> AnalysisRes c
res_join_2 joiner res1 res2 =
    case res1 of
        Err e1 ->
            case res2 of
                Err e2 ->
                    add_error e1 e2 |> Err

                Ok _ ->
                    Err e1

        Ok s1 ->
            case res2 of
                Err e2 ->
                    Err e2

                Ok s2 ->
                    joiner s1 s2 |> Ok


res_join_n : AnalysisRes (List a) -> AnalysisRes a -> AnalysisRes (List a)
res_join_n resl res2 =
    case resl of
        Err e1 ->
            case res2 of
                Err e2 ->
                    add_error e1 e2 |> Err

                Ok _ ->
                    Err e1

        Ok s1 ->
            case res2 of
                Err e2 ->
                    Err e2

                Ok s2 ->
                    List.append s1 [ s2 ] |> Ok


add_error : AnalysisError -> AnalysisError -> AnalysisError
add_error e1 e2 =
    Multiple (List.append (flatten e1) (flatten e2))


flatten : AnalysisError -> List AnalysisError
flatten ae =
    case ae of
        Multiple l ->
            l

        _ ->
            [ ae ]

