module Analysis.Util exposing (..)

import Language.Language exposing (..)
import Parser.AST as AST
import Util


type alias AnalysisRes a =
    Result AnalysisError a


type AnalysisError
    = UnknownImport AST.ImportAndLocation
    | NoModuleName
    | InvalidSyntaxInStructDefinition
    | ExpectedSymbolInGenericArg Util.SourceView
    | GenericArgIdentifierTooComplicated Util.SourceView
    | FunctionNameArgTooComplicated Util.SourceView
    | TypeNameTooComplicated Util.SourceView
    | BadTypeParse Util.SourceView
    | TypeNameNotFound Identifier Util.SourceView
    | TypeNotInstantiable Identifier Util.SourceView
    | CantInstantiateGenericWithTheseArgs ReasonForUninstantiable Util.SourceView
    | GenericTypeNameNotValidWithoutSquareBrackets Util.SourceView
    | Unimplemented String
    | Multiple (List AnalysisError)


res_join_2 : (a -> a -> b) -> AnalysisRes a -> AnalysisRes a -> AnalysisRes b
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

