module Analysis.Analyzer exposing (..)

import Analysis.BuiltinScopes as BuiltinScopes
import Analysis.Scope as Scope
import Element exposing (Length)
import Language.Language as Language exposing (FunctionHeader, Identifier(..), IntegerSize(..), LiteralType(..), OuterType(..), QualifiedType, Type(..), TypeOfTypeDefinition(..), ValueNameAndType, builtin_types, type_of_non_generic_outer_type)
import Parser.AST as AST
import Parser.ParserCommon exposing (Error(..))
import Util
import Analysis.Util exposing (..)


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


make_outer_scope : AST.Program -> Result AnalysisError Scope.OverviewScope
make_outer_scope prog =
    let
        builtin_scope : AnalysisRes Scope.OverviewScope
        builtin_scope =
            Ok { values = [], types = builtin_types }

        import_scope : AnalysisRes Scope.OverviewScope
        import_scope =
            import_scopes prog.imports

        local_module_type_scope : AnalysisRes Scope.OverviewScope
        local_module_type_scope =
            build_this_module_outer_type prog.global_typedefs

        pre_fn_scopes = merge_scopes
                [ builtin_scope
                , import_scope
                , local_module_type_scope
                ]
        full_scopes =
            pre_fn_scopes
                |> Result.andThen (build_this_module_values prog.global_functions)
                |> Result.map (\vals -> Scope.OverviewScope vals [])
    in
    merge_scopes [full_scopes, pre_fn_scopes]


build_this_module_values : List AST.FunctionDefinition -> Scope.OverviewScope -> AnalysisRes (List ValueNameAndType)
build_this_module_values l os =
    l
        |> List.map (otype_of_fndef os)
        |> collapse_analysis_results (\a b -> [ a, b ])


otype_of_fndef : Scope.OverviewScope -> AST.FunctionDefinition -> AnalysisRes Language.ValueNameAndType
otype_of_fndef os fdef =
    let
        name : AnalysisRes String
        name =
            case fdef.name.thing of
                AST.NameWithoutArgs nm ->
                    case nm of
                        SingleIdentifier s ->
                            s |> Ok

                        _ ->
                            FunctionNameArgTooComplicated fdef.name.loc |> Err

                AST.NameWithArgs nm ->
                    case nm.base of
                        SingleIdentifier s ->
                            s |> Ok

                        _ ->
                            FunctionNameArgTooComplicated fdef.name.loc |> Err

                _ ->
                    FunctionNameArgTooComplicated fdef.name.loc |> Err

        gen_args : AnalysisRes (Maybe (List Language.TypeType))
        gen_args =
            case fdef.name.thing of
                AST.NameWithArgs nargs ->
                    nargs.args |> ensure_valid_generic_names |> Result.map (\l -> Just l)

                _ ->
                    Nothing |> Ok

        header =
            fheader_from_ast os fdef.header
    in
    Result.map2 (\n h -> ValueNameAndType (SingleIdentifier n) (Language.FunctionType h)) name header


fheader_from_ast : Scope.OverviewScope -> AST.FunctionHeader -> AnalysisRes Language.FunctionHeader
fheader_from_ast os fh =
    let
        args : AnalysisRes (List Language.QualifiedType)
        args =
            fh.args
                |> List.map (qualed_type_and_name_from_ast os)
                |> collapse_analysis_results (\qt1 qt2 -> [ qt1, qt2 ])

        ret : AnalysisRes (Maybe Language.Type)
        ret =
            case fh.return_type of
                Nothing ->
                    Nothing |> Ok

                Just t ->
                    t |> (\fn -> type_from_fullname os fn |> Result.map Just)
    in
    Result.map2 (\a -> FunctionHeader a) args (Debug.log "ret type of fheader" ret)


qualed_type_and_name_from_ast : Scope.OverviewScope -> AST.QualifiedTypeWithName -> AnalysisRes Language.QualifiedType
qualed_type_and_name_from_ast os qtwn =
    type_from_fullname os qtwn.typename |> Result.map (QualifiedType qtwn.qualifiedness)


type_from_fullname : Scope.OverviewScope -> AST.FullNameAndLocation -> AnalysisRes Language.Type
type_from_fullname os fn =
    let
        is_valid_named_type : OuterType -> Maybe TypeOfTypeDefinition
        is_valid_named_type ot =
            case ot of
                _ ->
                    type_of_non_generic_outer_type ot

    in
    (case fn.thing of
        AST.NameWithoutArgs name ->
            name
                |> Scope.overview_has_outer_type os
                |> Result.fromMaybe (TypeNameNotFound name fn.loc)
                |> Result.andThen (\tn -> is_valid_named_type tn |> Result.fromMaybe (GenericTypeNameNotValidWithoutSquareBrackets fn.loc))
                |> Result.map (\ot -> NamedType name ot)

        AST.NameWithArgs name_and_args ->
            generic_instantiation_type_from_fullname os fn name_and_args

        _ ->
            BadTypeParse fn.loc |> Err
    )
        |> Result.map Language.extract_builtins


generic_instantiation_type_from_fullname : Scope.OverviewScope -> AST.FullNameAndLocation -> { a | base : Identifier, args : List AST.FullNameAndLocation } -> Result AnalysisError Type
generic_instantiation_type_from_fullname os fn name_and_args =
    let
        is_instantiable : OuterType -> Maybe ( Identifier, TypeOfTypeDefinition, List Language.TypeType )
        is_instantiable ot =
            case ot of
                Generic a b c ->
                    Just ( a, b, c )

                _ ->
                    Nothing
        validated_name =
            name_and_args.base
                |> Scope.overview_has_outer_type os
                |> Result.fromMaybe (TypeNameNotFound name_and_args.base fn.loc)

        validated_args : AnalysisRes (List Type)
        validated_args =
            name_and_args.args |> List.map (type_from_fullname os) |> collapse_analysis_results (\a b -> [ a, b ])

        wrap_can_instantiate_err gen_id tot val_args can =
            case can of
                Nothing ->
                    Ok <| GenericInstantiation gen_id tot val_args

                Just r ->
                    CantInstantiateGenericWithTheseArgs r fn.loc |> Err
    in
    validated_name
        |> Result.andThen (\tn -> is_instantiable tn |> Result.fromMaybe (TypeNotInstantiable name_and_args.base fn.loc))
        |> Result.andThen
            (\( gen_id, tot, gen_args ) ->
                validated_args
                    |> Result.andThen
                        (\val_args ->
                            Language.is_generic_instantiable_with tot gen_args val_args |> wrap_can_instantiate_err gen_id tot val_args
                        )
            )




ensure_valid_generic_name : AST.ThingAndLocation AST.FullName -> AnalysisRes Language.TypeType
ensure_valid_generic_name name_and_loc =
    case name_and_loc.thing of
        AST.NameWithoutArgs id ->
            case id of
                SingleIdentifier s ->
                    Language.Any s |> Ok

                _ ->
                    GenericArgIdentifierTooComplicated name_and_loc.loc |> Err

        _ ->
            ExpectedSymbolInGenericArg name_and_loc.loc |> Err


ensure_valid_generic_names : List AST.FullNameAndLocation -> Result AnalysisError (List Language.TypeType)
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
                |> Result.map (Generic def.base StructDefinitionType)

        _ ->
            InvalidSyntaxInStructDefinition |> Err


otype_of_enumdef : AST.EnumDefinition -> Result AnalysisError Language.OuterType
otype_of_enumdef edef =
    case edef.name.thing of
        AST.NameWithoutArgs id ->
            EnumOuterType id |> Ok

        AST.NameWithArgs def ->
            ensure_valid_generic_names def.args
                |> Result.map (Generic def.base EnumDefinitionType)

        _ ->
            Analysis.Util.Unimplemented "generic enum to otype" |> Err


otype_of_aliasdef : AST.AliasDefinition -> Result AnalysisError Language.OuterType
otype_of_aliasdef adef =
    case adef.name.thing of
        AST.NameWithoutArgs id ->
            EnumOuterType id |> Ok

        AST.NameWithArgs def ->
            ensure_valid_generic_names def.args
                |> Result.map (Generic def.base AliasDefinitionType)

        _ ->
            Analysis.Util.Unimplemented "generic alias to otype" |> Err


otype_of_typedef : AST.TypeDefinitionType -> Result AnalysisError Language.OuterType
otype_of_typedef t =
    case t of
        AST.StructDefType sdef ->
            otype_of_structdef sdef

        AST.EnumDefType edef ->
            otype_of_enumdef edef

        AST.AliasDefType adef ->
            otype_of_aliasdef adef


build_this_module_outer_type : List AST.TypeDefinitionType -> Result AnalysisError Scope.OverviewScope
build_this_module_outer_type l =
    let
        types : Result AnalysisError (List OuterType)
        types =
            l |> List.map otype_of_typedef |> collapse_analysis_results (\a b -> [ a, b ])

        scope =
            types |> Result.andThen (\ts -> Scope.OverviewScope [] ts |> Ok)
    in
    scope


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

