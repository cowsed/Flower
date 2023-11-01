module Analysis.Util exposing (..)

import Language.Language exposing (..)
import Parser.AST as AST
import Util
import Analysis.DefinitionPropagator exposing (DefinitionPropagator)
import Analysis.DefinitionPropagator as DefinitionPropagator
import Language.Syntax as Syntax exposing (Node)
import Language.Language as Language

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


analyze_typename : Node AST.FullName -> AnalysisRes Language.TypeName
analyze_typename typename =
    case typename.thing of
        AST.NameWithoutArgs id ->
            CustomTypeName id |> Ok

        AST.NameWithArgs stuff ->
            (stuff.args |> List.map analyze_typename)
                |> ar_foldN (\el l -> List.append l [ el ]) []
                |> Result.map (\args -> GenericInstantiation stuff.base args)

        _ ->
            NoSuchTypeFound typename.loc |> Err


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



ar_map2 : (a -> b -> value) -> AnalysisRes a -> AnalysisRes b -> AnalysisRes value
ar_map2 join a b =
    case a of
        Err eA ->
            case b of
                Err eB ->
                    Err (add_error eA eB)

                Ok _ ->
                    Err eA

        Ok valA ->
            case b of
                Err eB ->
                    Err eB

                Ok valB ->
                    join valA valB |> Ok


ar_foldN : (a -> b -> b) -> b -> List (AnalysisRes a) -> AnalysisRes b
ar_foldN join_value value1 ls =
    let
        join : AnalysisRes a -> AnalysisRes b -> AnalysisRes b
        join =
            res_join_2 join_value

        start : AnalysisRes b
        start =
            Ok value1
    in
    List.foldl join start ls


ar_map3 : (a -> b -> c -> d) -> AnalysisRes a -> AnalysisRes b -> AnalysisRes c -> AnalysisRes d
ar_map3 joiner a b c =
    let
        ab =
            ar_map2 joiner a b
    in
    case ab of
        Err e1 ->
            case c of
                Err e2 ->
                    add_error e1 e2 |> Err

                Ok _ ->
                    e1 |> Err

        Ok j1 ->
            case c of
                Err e2 ->
                    e2 |> Err

                Ok v2 ->
                    j1 v2 |> Ok


filterSplit : (a -> Result t1 t2) -> List a -> ( List t1, List t2 )
filterSplit filterer list =
    list
        |> List.foldl
            (\a state ->
                case filterer a of
                    Err b ->
                        { state | t1s = List.append state.t1s [ b ] }

                    Ok c ->
                        { state | t2s = List.append state.t2s [ c ] }
            )
            { t1s = [], t2s = [] }
        |> (\s -> ( s.t1s, s.t2s ))
