module Analysis.Analyzer exposing (..)

import Analysis.BuiltinScopes as BuiltinScopes
import Analysis.Scope as Scope
import Analysis.Util exposing (..)
import Json.Decode exposing (bool)
import Keyboard.Key exposing (Key(..))
import Language.Language as Language exposing (FunctionHeader, Identifier(..), IntegerSize(..), Named, QualifiedTypeName, TypeDefinition(..), TypeName(..), TypeOfCustomType, ValueNameAndType)
import Parser.AST as AST
import Parser.ParserCommon exposing (Error(..))
import String exposing (join)


type alias GoodProgram =
    { ast : AST.Program
    , module_name : String
    , global_scope : Scope.FullScope
    , definitions : List FunctionDefinition
    }


type TypedExpression
    = FunctionCall Identifier FunctionDefinition (List TypedExpression) (Maybe TypeName)
    | ScopeLookup Identifier TypeName
    | Instantiation



-- | StructConstruction


type Statement
    = Assignment ValueNameAndType TypedExpression
    | BareExpression TypedExpression


type alias FunctionDefinition =
    { typ : Language.FunctionHeader
    , statements : List Statement
    }


analyze : AST.Program -> Result AnalysisError GoodProgram
analyze ast =
    let
        outer_scopes : Result AnalysisError Scope.FullScope
        outer_scopes =
            make_outer_type_scope ast

        definitions =
            Ok []

        module_name =
            Result.fromMaybe NoModuleName ast.module_name
    in
    Result.map3 (GoodProgram ast) module_name outer_scopes definitions


ensure_good_generic_args : List AST.FullNameAndLocation -> AnalysisRes (List String)
ensure_good_generic_args ls =
    Debug.todo " A"


ensure_good_custom_type_name : AST.FullNameAndLocation -> AnalysisRes TypeDeclarationName
ensure_good_custom_type_name fn =
    case fn.thing of
        AST.NameWithoutArgs id ->
            case id of
                SingleIdentifier _ ->
                    Ok (Plain id)

                QualifiedIdentifiers _ ->
                    Err (TypeNameTooComplicated fn.loc)

        AST.NameWithArgs id ->
            case id.base of
                SingleIdentifier _ ->
                    ensure_good_generic_args id.args |> Result.map (\l -> Generic id.base l)

                QualifiedIdentifiers _ ->
                    Err (TypeNameTooComplicated fn.loc)

        _ ->
            Err (TypeNameTooComplicated fn.loc)


get_typename : AST.TypeDefinitionType -> AnalysisRes ( TypeDeclarationName, AST.TypeDefinitionType )
get_typename tdt =
    case tdt of
        AST.StructDefType sdt ->
            sdt.name |> ensure_good_custom_type_name |> Result.map (\a -> ( a, tdt ))

        AST.EnumDefType edt ->
            edt.name |> ensure_good_custom_type_name |> Result.map (\a -> ( a, tdt ))

        AST.AliasDefType adt ->
            adt.name |> ensure_good_custom_type_name |> Result.map (\a -> ( a, tdt ))


type TypeDeclarationName
    = Plain Identifier
    | Generic Identifier (List String)


extract_typenames : List AST.TypeDefinitionType -> AnalysisRes (List ( TypeDeclarationName, AST.TypeDefinitionType ))
extract_typenames ls =
    let
        l : List (AnalysisRes ( TypeDeclarationName, AST.TypeDefinitionType ))
        l =
            ls |> List.map get_typename
    in
    List.foldl (\a b -> res_join_n b a) (Ok []) l


analyze_struct_def : AST.StructDefnition -> AnalysisRes Language.StructDefinition
analyze_struct_def tdt =
    Debug.todo "Analyze Struct"


extract_typedefs : ( Identifier, AST.TypeDefinitionType ) -> AnalysisRes (Named TypeDefinition)
extract_typedefs ( name, def ) =
    (case def of
        AST.StructDefType sd ->
            analyze_struct_def sd |> Result.map Language.StructDefinitionType

        AST.EnumDefType _ ->
            Debug.todo "enum analyzing"

        AST.AliasDefType _ ->
            Debug.todo "alias analyzing"
    )
        |> Result.map (\d -> Named name d)


make_outer_type_scope : AST.Program -> AnalysisRes Scope.FullScope
make_outer_type_scope prog =
    let
        builtin_scope : AnalysisRes Scope.FullScope
        builtin_scope =
            Ok { values = [], types = [], generic_types = [] }

        import_scope : AnalysisRes Scope.FullScope
        import_scope =
            analyze_imports prog.imports

        module_type_names : AnalysisRes (List ( TypeDeclarationName, AST.TypeDefinitionType ))
        module_type_names =
            extract_typenames prog.global_typedefs |> Debug.log "Extracted names"

        module_type_definitions : List ( Identifier, AST.TypeDefinitionType ) -> AnalysisRes Scope.TypeDefs
        module_type_definitions l =
            l |> List.map extract_typedefs |> ar_foldN (\el li -> List.append li [ el ]) []

        module_generic_type_definitions : List ( ( Identifier, List String ), AST.TypeDefinitionType ) -> AnalysisRes Scope.GenericTypeDefs
        module_generic_type_definitions gens =
            Debug.todo "generics"

        types_and_generics =
            module_type_names
                |> Result.map
                    (filterSplit
                        (\( tdn, tdt ) ->
                            case tdn of
                                Plain id ->
                                    Err ( id, tdt )

                                Generic id args ->
                                    Ok ( ( id, args ), tdt )
                        )
                    )
                |> Result.map (\( ts, gens ) -> { types = ts, generics = gens })

        type_scope =
            types_and_generics
                |> Result.andThen
                    (\lis ->
                        Result.map2
                            (\a b -> Scope.FullScope a [] b)
                            (module_type_definitions lis.types)
                            (module_generic_type_definitions lis.generics)
                    )

        pre_fn_scopes =
            ar_foldN Scope.merge_two_scopes
                Scope.empty_scope
                [ builtin_scope
                , import_scope  
                , type_scope

                ]
    in
    pre_fn_scopes


find_this_module_declarations : List AST.TypeDefinitionType -> AnalysisRes Scope.ValueDefs
find_this_module_declarations ast_defs =
    Ok []


analyze_imports : List AST.ImportAndLocation -> AnalysisRes Scope.FullScope
analyze_imports imps =
    imps
        |> List.map
            (\s ->
                BuiltinScopes.import_scope s.thing |> Result.fromMaybe (UnknownImport s)
            )
        |> collapse_scope_results


collapse_scope_results : List (AnalysisRes Scope.FullScope) -> AnalysisRes Scope.FullScope
collapse_scope_results scopes =
    ar_foldN Scope.merge_two_scopes Scope.empty_scope scopes


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
