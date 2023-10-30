module Analysis.Analyzer exposing (..)

import Analysis.BuiltinScopes as BuiltinScopes
import Analysis.Scope as Scope
import Analysis.Util exposing (..)
import Keyboard.Key exposing (Key(..))
import Language.Language as Language exposing (FunctionHeader, Identifier(..), IntegerSize(..), Named, QualifiedTypeName, SimpleNamed, TypeDefinition(..), TypeName(..), TypeOfCustomType, extract_builtins)
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
    = Assignment (Named TypeName) TypedExpression
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
    Debug.todo " ensure good generic args"


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


extract_type_declarations : List AST.TypeDefinitionType -> AnalysisRes (List ( TypeDeclarationName, AST.TypeDefinitionType ))
extract_type_declarations ls =
    let
        l : List (AnalysisRes ( TypeDeclarationName, AST.TypeDefinitionType ))
        l =
            ls |> List.map get_typename
    in
    List.foldl (\a b -> res_join_n b a) (Ok []) l


analyze_typename : Scope.TypeDeclarationScope -> AST.FullNameAndLocation -> AnalysisRes Language.TypeName
analyze_typename scope typename =
    let
        -- todo give error saying that type exists it just needs generic arguments
        try_find_generic_type : Language.TypeName -> AnalysisRes Language.TypeName
        try_find_generic_type tn =
            if Scope.lookup_generic_type_in_decl_scope scope tn then
                Ok tn

            else
                Err (NoSuchGenericTypeFound typename.loc)

        try_find_type : Language.TypeName -> AnalysisRes Language.TypeName
        try_find_type tn =
            let
                from_builtin =
                    extract_builtins tn

                from_scope =
                    if Scope.lookup_type_in_decl_scope scope tn then
                        Just tn

                    else
                        Nothing

                res =
                    case from_builtin of
                        Just t ->
                            Ok t

                        Nothing ->
                            case from_scope of
                                Just t ->
                                    Ok t

                                Nothing ->
                                    NoSuchTypeFound typename.loc |> Err
            in
            res
    in
    case typename.thing of
        AST.NameWithoutArgs id ->
            CustomTypeName id |> try_find_type

        AST.NameWithArgs stuff ->
            (stuff.args |> List.map (analyze_typename scope)) |> ar_foldN (\el l -> List.append l [el]) []
                |> Result.map (\args -> GenericInstantiation stuff.base args)
                |> Result.andThen try_find_generic_type

        _ ->
            NoSuchTypeFound typename.loc |> Err


ensure_good_struct_field : Scope.TypeDeclarationScope -> AST.UnqualifiedTypeWithName -> AnalysisRes (SimpleNamed Language.TypeName)
ensure_good_struct_field scope field =
    let
        name_res =
            case field.name.thing of
                SingleIdentifier s ->
                    Ok s

                _ ->
                    Err (StructFieldNameTooComplicated field.name.loc)

        typename_res =
            analyze_typename scope field.typename
    in
    ar_map2 (\name tname -> SimpleNamed name tname) name_res typename_res


analyze_struct_def : Scope.TypeDeclarationScope -> AST.StructDefnition -> AnalysisRes Language.StructDefinition
analyze_struct_def declscope tdt =
    tdt.fields
        |> List.map (ensure_good_struct_field declscope)
        |> ar_foldN (\el l -> List.append l [ el ]) []
        |> Result.map Language.StructDefinition


extract_typedefs : Scope.TypeDeclarationScope -> ( Identifier, AST.TypeDefinitionType ) -> AnalysisRes (Named TypeDefinition)
extract_typedefs declscope ( name, def ) =
    (case def of
        AST.StructDefType sd ->
            analyze_struct_def declscope sd |> Result.map Language.StructDefinitionType

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
            Ok BuiltinScopes.builtin_scope

        import_scope : AnalysisRes Scope.FullScope
        import_scope =
            analyze_imports prog.imports

        declscope =
            ar_foldN Scope.merge_two_scopes
                Scope.empty_scope
                [ builtin_scope
                , import_scope
                ]
                |> Result.map Scope.get_declaration_scope

        module_type_names : AnalysisRes (List ( TypeDeclarationName, AST.TypeDefinitionType ))
        module_type_names =
            extract_type_declarations prog.global_typedefs |> Debug.log "Extracted names"

        module_type_definitions : Scope.TypeDeclarationScope -> List ( Identifier, AST.TypeDefinitionType ) -> AnalysisRes Scope.TypeDefs
        module_type_definitions dscope l =
            l |> List.map (extract_typedefs dscope) |> ar_foldN (\el li -> List.append li [ el ]) []

        module_generic_type_definitions : Scope.TypeDeclarationScope -> List ( ( Identifier, List String ), AST.TypeDefinitionType ) -> AnalysisRes Scope.GenericTypeDefs
        module_generic_type_definitions dscope gens =
            Debug.log "module generic type definitions" (Ok [])

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

        type_scope dscope =
            types_and_generics
                |> Result.andThen
                    (\lis ->
                        Result.map2
                            (\a b -> Scope.FullScope a [] b)
                            (module_type_definitions dscope lis.types)
                            (module_generic_type_definitions dscope lis.generics)
                    )

        pre_fn_scopes =
            ar_foldN Scope.merge_two_scopes
                Scope.empty_scope
                [ builtin_scope
                , import_scope
                , declscope |> Result.andThen type_scope
                ]
                |> Debug.log "pre_fn scopes"
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
