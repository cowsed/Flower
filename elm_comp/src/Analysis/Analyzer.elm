module Analysis.Analyzer exposing (..)

import Analysis.BuiltinScopes as BuiltinScopes
import Analysis.Scope as Scope
import Language exposing (Identifier(..), LiteralType(..), OuterType(..), GenericType(..), Type(..), builtin_types)
import Parser.ParserCommon exposing (Error(..))
import Util
import Parser.AST as AST

type alias GoodProgram =
    { module_name : String, outer_scope : Scope.OverviewScope }

 
analyze : AST.Program -> Result AnalysisError GoodProgram
analyze prog =
    let
        outer_scopes =
            make_outer_scope prog

        assemble_gp scope name =
            GoodProgram name scope

        module_name =
            Result.fromMaybe NoModuleName prog.module_name
    in
    Result.map2 assemble_gp outer_scopes module_name


merge_scopes : List (Result AnalysisError Scope.OverviewScope) -> Result AnalysisError Scope.OverviewScope
merge_scopes scopes =
    let
        merge_2 : AnalysisRes Scope.OverviewScope -> AnalysisRes Scope.OverviewScope -> AnalysisRes Scope.OverviewScope
        merge_2 res1 res2 =
            res_join_2 Scope.merge_2_scopes res1 res2
    in
    List.foldl merge_2 (Ok Scope.empty_scope) scopes


make_outer_scope : AST.Program -> Result AnalysisError Scope.OverviewScope
make_outer_scope prog =
    let
        builtin_scope : Scope.OverviewScope
        builtin_scope =
            { values = [], types = builtin_types }

        imported_scopes =
            import_scopes prog.imports

        global_scope =
            build_global_scope prog.global_typedefs
    in
    merge_scopes [ Ok builtin_scope, imported_scopes, global_scope ]


ensure_valid_generic_name : AST.ThingAndLocation AST.FullName -> AnalysisRes String
ensure_valid_generic_name name_and_loc =
    case name_and_loc.thing of 
        AST.NameWithoutArgs id -> case id of 
            SingleIdentifier s -> Ok s
            _ -> GenericArgIdentifierTooComplicated name_and_loc.loc |> Err
        _ -> ExpectedSymbolInGenericArg name_and_loc.loc |> Err


ensure_valid_generic_names : List (AST.ThingAndLocation AST.FullName) -> Result AnalysisError (List String)
ensure_valid_generic_names l =
    l
        |> List.map ensure_valid_generic_name
        |> collapse_analysis_results (\a b -> [ a, b ])


collapse_analysis_results : (a -> a -> List a) -> List (Result AnalysisError a) -> Result AnalysisError (List a)
collapse_analysis_results joiner l =
    case List.head l of
        Just el ->
            res_join_n (collapse_analysis_results joiner (Util.always_tail l)) el

        Nothing ->
            Ok []


otype_of_structdef : AST.StructDefnition -> Result AnalysisError Language.OuterType
otype_of_structdef sdef =
    case sdef.name.thing of
        AST.NameWithoutArgs id ->
            StructOuterType id |> Ok

        AST.NameWithArgs def ->
            ensure_valid_generic_names def.args
                |> Result.map (Generic def.base GenericStruct)

        _ ->
            InvalidSyntaxInStructDefinition |> Err


otype_of_enumdef : AST.EnumDefinition -> Result AnalysisError Language.OuterType
otype_of_enumdef edef =
    case edef.name.thing of
        AST.NameWithoutArgs id ->
            EnumOuterType id |> Ok

        AST.NameWithArgs def ->
            ensure_valid_generic_names def.args
                |> Result.map (Generic def.base GenericEnum)


        _ ->
            Unimplemented "generic enum to otype" |> Err


otype_of_aliasdef : AST.AliasDefinition -> Result AnalysisError Language.OuterType
otype_of_aliasdef adef =
    case adef.name.thing of
        AST.NameWithoutArgs id ->
            EnumOuterType id |> Ok


        AST.NameWithArgs def ->
            ensure_valid_generic_names def.args
                |> Result.map (Generic def.base GenericAlias)


        _ ->
            Unimplemented "generic alias to otype" |> Err


otype_of_typedef : AST.TypeDefinitionType -> Result AnalysisError Language.OuterType
otype_of_typedef t =
    case t of
        AST.StructDefType sdef ->
            otype_of_structdef sdef

        AST.EnumDefType edef ->
            otype_of_enumdef edef

        AST.AliasDefType adef ->
            otype_of_aliasdef adef


build_global_scope : List AST.TypeDefinitionType -> Result AnalysisError Scope.OverviewScope
build_global_scope l =
    let
        types : Result AnalysisError Scope.OverviewScope
        types =
            l |> List.map otype_of_typedef |> List.map (\ot -> scope_from_type (Debug.log "Outer Type:" ot)) |> merge_scopes
    in
    types


scope_from_type : Result AnalysisError OuterType -> Result AnalysisError Scope.OverviewScope
scope_from_type res =
    case res of
        Err e ->
            Err e

        Ok t ->
            Scope.OverviewScope [] [ t ] |> Ok


import_scopes : List AST.ImportAndLocation -> Result AnalysisError Scope.OverviewScope
import_scopes strs =
    strs
        |> List.map
            (\sl ->
                BuiltinScopes.import_scope sl |> Result.fromMaybe (UnknownImport sl)
            )
        |> merge_scopes


type AnalysisError
    = UnknownImport AST.ImportAndLocation
    | NoModuleName
    | InvalidSyntaxInStructDefinition
    | ExpectedSymbolInGenericArg Util.SourceView
    | GenericArgIdentifierTooComplicated Util.SourceView
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


type alias AnalysisRes a =
    Result AnalysisError a


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
