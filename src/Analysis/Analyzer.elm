module Analysis.Analyzer exposing (..)

import Analysis.BuiltinScopes as BuiltinScopes
import Analysis.DefinitionPropagator as DefinitionPropagator
import Analysis.Scope as Scope
import Analysis.Util exposing (..)
import Keyboard.Key exposing (Key(..))
import Language.Language as Language exposing (Identifier(..), IntegerSize(..), Named, SimpleNamed, TypeDefinition(..), TypeName(..), extract_builtins, named_get, named_name)
import Language.Syntax as Syntax exposing (Node, node_get, node_map)
import ListDict exposing (ListDict)
import ListSet exposing (ListSet)
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


ensure_good_generic_args : List (Node AST.FullName) -> AnalysisRes (List String)
ensure_good_generic_args ls =
    Debug.todo " ensure good generic args"


ensure_good_custom_type_name : Node AST.FullName -> AnalysisRes TypeDeclarationName
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


get_unfinished_struct_or_generic : AST.StructDefnition -> AnalysisRes DefinitionPropagator.Unfinished
get_unfinished_struct_or_generic sdt =
    let
        good_name =
            ensure_good_custom_type_name sdt.name
    in
    good_name
        |> Result.andThen
            (\n ->
                case n of
                    Plain s ->
                        get_unfinished_struct (Node s sdt.name.loc) sdt.fields

                    Generic s args ->
                        Debug.todo "Get Unfinished Generic Struct"
            )


get_unfinished_struct : Node Identifier -> List AST.UnqualifiedTypeWithName -> AnalysisRes DefinitionPropagator.Unfinished
get_unfinished_struct s fields =
    let
        name =
            node_get s |> CustomTypeName |> DefinitionPropagator.TypeDeclaration

        good_fields : AnalysisRes (List (SimpleNamed TypeName))
        good_fields =
            fields |> List.map ensure_good_struct_field |> ar_foldN (::) []

        types_needed : List (SimpleNamed TypeName) -> ListSet DefinitionPropagator.DeclarationName
        types_needed fs =
            List.foldl (\nt -> ListSet.insert (DefinitionPropagator.TypeDeclaration nt.value)) ListSet.empty fs

        add_data : AnalysisRes (( DefinitionPropagator.DeclarationName, DefinitionPropagator.Definition ) -> DefinitionPropagator.Output)
        add_data =
            Ok <|
                \( tn, def ) ->
                    Debug.log ("add data called: " ++ Debug.toString tn) <|
                        DefinitionPropagator.Complete (DefinitionPropagator.TypeDef (Language.StructDefinitionType (Language.StructDefinition [])))

        -- add_field fnn ruf =
        -- ruf |> Result.andThen (\uf -> ensure_good_struct_field fnn |> Result.map  (\nt -> nt.))
    in
    good_fields
        |> Result.map types_needed
        |> Result.map2 (\add_func needs -> DefinitionPropagator.Unfinished (Node name s.loc) needs add_func) add_data


get_unfinished : AST.TypeDefinitionType -> AnalysisRes DefinitionPropagator.Unfinished
get_unfinished tdt =
    case tdt of
        AST.StructDefType sdt ->
            get_unfinished_struct_or_generic sdt

        _ ->
            Debug.todo "get unfinished enum and alias"



-- AST.EnumDefType edt ->
-- edt.name |> ensure_good_custom_type_name |> Result.map (\a -> ( a, tdt ))
--
-- AST.AliasDefType adt ->
-- adt.name |> ensure_good_custom_type_name |> Result.map (\a -> ( a, tdt ))


type TypeDeclarationName
    = Plain Identifier
    | Generic Identifier (List String)


extract_unfinished : List AST.TypeDefinitionType -> AnalysisRes (List DefinitionPropagator.Unfinished)
extract_unfinished ls =
    let
        l : List (AnalysisRes DefinitionPropagator.Unfinished)
        l =
            ls |> List.map get_unfinished
    in
    List.foldl (\a b -> res_join_n b a) (Ok []) l


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


ensure_good_struct_field : AST.UnqualifiedTypeWithName -> AnalysisRes (SimpleNamed Language.TypeName)
ensure_good_struct_field field =
    let
        name_res =
            case field.name.thing of
                SingleIdentifier s ->
                    Ok s

                _ ->
                    Err (StructFieldNameTooComplicated field.name.loc)

        typename_res =
            analyze_typename field.typename
    in
    ar_map2 (\name tname -> SimpleNamed name tname) name_res typename_res


make_outer_type_scope : AST.Program -> AnalysisRes Scope.FullScope
make_outer_type_scope prog =
    let
        builtin_scope : AnalysisRes Scope.FullScope
        builtin_scope =
            Ok BuiltinScopes.builtin_scope

        import_scope : AnalysisRes Scope.FullScope
        import_scope =
            analyze_imports prog.imports

        completed_scopes =
            Result.map2 Scope.merge_two_scopes builtin_scope import_scope

        incompletes : AnalysisRes (List DefinitionPropagator.Unfinished)
        incompletes =
            extract_unfinished prog.global_typedefs

        --
        --
        -- module_type_definitions : Scope.TypeDeclarationScope -> List ( Identifier, AST.TypeDefinitionType ) -> AnalysisRes Scope.TypeDefs
        -- module_type_definitions dscope l =
        -- l |> List.map (extract_typedefs dscope) |> ar_foldN (\el li -> List.append li [ el ]) []
        -- module_generic_type_definitions : Scope.TypeDeclarationScope -> List ( ( Identifier, List String ), AST.TypeDefinitionType ) -> AnalysisRes Scope.GenericTypeDefs
        -- module_generic_type_definitions dscope gens =
        -- Debug.log "module generic type definitions" (Ok [])
        complete_defs : Scope.FullScope -> List ( Node DefinitionPropagator.DeclarationName, DefinitionPropagator.Definition )
        complete_defs s =
            s.types
                |> List.map
                    (\ntn ->
                        ( node_map named_name ntn
                            |> node_map CustomTypeName
                            |> node_map DefinitionPropagator.TypeDeclaration
                        , DefinitionPropagator.TypeDef (node_get ntn |> named_get)
                        )
                    )
                |> Debug.log "completed defs"
    in
    completed_scopes
        |> Result.map complete_defs
        |> Result.andThen
            (\defs ->
                incompletes
                    |> Result.andThen (\incs -> DefinitionPropagator.from_definitions_and_declarations defs incs |> Result.mapError DefPropErr)
            )
        -- |> Result.andThen (incompletes |> Result.map DefinitionPropagator.add_many_incomplete)
        |> Result.andThen (\dp -> DefinitionPropagator.to_full_scope dp |> Result.mapError DefPropErr)


analyze_imports : List AST.ImportNode -> AnalysisRes Scope.FullScope
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
