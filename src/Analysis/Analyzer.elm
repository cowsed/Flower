module Analysis.Analyzer exposing (..)

import Analysis.BuiltinScopes as BuiltinScopes
import Analysis.Scope as Scope
import Element exposing (Length)
import Language.Language as Language exposing (FunctionHeader, Identifier(..), LiteralType(..), OuterType(..), QualifiedType, Type(..), TypeOfTypeDefinition(..), ValueNameAndType, builtin_types, type_of_non_generic_outer_type)
import Parser.AST as AST
import Parser.ParserCommon exposing (Error(..))
import Util
import Language.Language exposing (IntegerSize(..))


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
        builtin_scope : AnalysisRes Scope.OverviewScope
        builtin_scope =
            Ok { values = [], types = builtin_types }

        import_scope : AnalysisRes Scope.OverviewScope
        import_scope =
            import_scopes prog.imports

        local_module_type_scope : AnalysisRes Scope.OverviewScope
        local_module_type_scope =
            build_this_module_outer_type prog.global_typedefs

        full_scopes =
            merge_scopes
                [ builtin_scope
                , import_scope
                , local_module_type_scope
                ]
                |> Result.andThen (build_this_module_values prog.global_functions)
                |> Result.map (\vals -> Scope.OverviewScope vals [])
    in
    full_scopes


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

        gen_args : AnalysisRes (Maybe (List Type))
        gen_args =
            case fdef.name.thing of
                AST.NameWithArgs nargs ->
                    nargs.args |> List.map (type_from_fullname os) |> collapse_analysis_results (\a b -> [ a, b ]) |> Result.map (\l -> Just l)

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

        is_instantiable : OuterType -> Maybe ( Identifier, TypeOfTypeDefinition, List String )
        is_instantiable ot =
            case ot of
                Generic a b c ->
                    Just ( a, b, c )

                _ ->
                    Nothing
    in
    (case fn.thing of
        AST.NameWithoutArgs name ->
            name
                |> Scope.overview_has_outer_type os
                |> Result.fromMaybe (TypeNameNotFound name fn.loc)
                |> Result.andThen (\tn -> is_valid_named_type tn |> Result.fromMaybe (GenericTypeNameNotValidWithoutSquareBrackets fn.loc))
                |> Result.map (\ot -> NamedType name ot)

        AST.NameWithArgs name_and_args ->
            let
                validated_name =
                    name_and_args.base
                        |> Scope.overview_has_outer_type os
                        |> Result.fromMaybe (TypeNameNotFound name_and_args.base fn.loc)

                validated_args : AnalysisRes (List Type)
                validated_args =
                    name_and_args.args |> List.map (type_from_fullname os) |> collapse_analysis_results (\a b -> [ a, b ])
            in
            validated_name
                |> Result.andThen (\tn -> is_instantiable tn |> Result.fromMaybe (TypeNotInstantiable name_and_args.base fn.loc))
                |> Result.map (\t -> t)
                |> Result.andThen
                    (\( gen_id, tot, gen_args ) ->
                        validated_args
                            |> Result.andThen
                                (\val_args ->
                                    Language.generic_instantiable_with tot gen_args val_args
                                        |> (\can ->
                                                case can of
                                                    Nothing ->
                                                        Ok <| GenericInstantiation gen_id tot val_args

                                                    Just r ->
                                                        CantInstantiateGenericWithTheseArgs r fn.loc |> Err
                                           )
                                )
                    )
                |> Result.map (\t -> t)

        _ ->
            BadTypeParse fn.loc |> Err
    )
        |> Result.map extract_builtins


extract_builtins : Type -> Type
extract_builtins t =
    case Debug.log "extracting " t of
        NamedType id tot ->
            if tot == AliasDefinitionType then
                case id of
                    SingleIdentifier s ->
                        case s of
                            "bool" ->
                                BooleanType
                            "u8" ->
                                IntegerType Language.U8
                            "u16" ->
                                IntegerType Language.U16
                            "u32" ->
                                IntegerType Language.U32
                            "u64" ->
                                IntegerType Language.U64
                            "i8" ->
                                IntegerType Language.I8
                            "i16" ->
                                IntegerType Language.I16
                            "i32" ->
                                IntegerType Language.I32
                            "i64" ->
                                IntegerType Language.I64
                            "str" ->
                                BooleanType
                            _ -> t

                    _ ->
                        t

            else
                t

        _ ->
            t


ensure_valid_generic_name : AST.ThingAndLocation AST.FullName -> AnalysisRes String
ensure_valid_generic_name name_and_loc =
    case name_and_loc.thing of
        AST.NameWithoutArgs id ->
            case id of
                SingleIdentifier s ->
                    Ok s

                _ ->
                    GenericArgIdentifierTooComplicated name_and_loc.loc |> Err

        _ ->
            ExpectedSymbolInGenericArg name_and_loc.loc |> Err


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
            Unimplemented "generic enum to otype" |> Err


otype_of_aliasdef : AST.AliasDefinition -> Result AnalysisError Language.OuterType
otype_of_aliasdef adef =
    case adef.name.thing of
        AST.NameWithoutArgs id ->
            EnumOuterType id |> Ok

        AST.NameWithArgs def ->
            ensure_valid_generic_names def.args
                |> Result.map (Generic def.base AliasDefinitionType)

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


type AnalysisError
    = UnknownImport AST.ImportAndLocation
    | NoModuleName
    | InvalidSyntaxInStructDefinition
    | ExpectedSymbolInGenericArg Util.SourceView
    | GenericArgIdentifierTooComplicated Util.SourceView
    | FunctionNameArgTooComplicated Util.SourceView
    | BadTypeParse Util.SourceView
    | TypeNameNotFound Identifier Util.SourceView
    | TypeNotInstantiable Identifier Util.SourceView
    | CantInstantiateGenericWithTheseArgs Language.ReasonForUninstantiable Util.SourceView
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
