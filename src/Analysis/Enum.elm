module Analysis.Enum exposing (get_unfinished)

import Analysis.DefinitionPropagator as DefinitionPropagator exposing (DeclarationName(..), Definition(..), Error(..))
import Analysis.Util exposing (AnalysisRes, analyze_typename, ar_foldN)
import Language.Language as Language exposing (EnumTagDefinition(..), Identifier, SimpleNamed, TypeDefinition(..), TypeName(..), snamed_get, snamed_name)
import Language.Syntax exposing (Node, node_map)
import ListDict exposing (ListDict)
import ListSet exposing (ListSet)
import Parser.AST as AST


finalize : List Language.EnumTagDefinition -> List ( DefinitionPropagator.DeclarationName, DefinitionPropagator.Definition ) -> Result DefinitionPropagator.Error DefinitionPropagator.Definition
finalize tags defs =
    let
        defs_dict : ListDict DeclarationName Definition
        defs_dict =
            ListDict.from_list defs

        has_all_of_tags_types : EnumTagDefinition -> Result DefinitionPropagator.Error EnumTagDefinition
        has_all_of_tags_types tag =
            case tag of
                JustTag _ ->
                    Ok tag

                TagAndTypes tagname tys ->
                    List.foldl
                        (\typ rtyps ->
                            case ListDict.get (DefinitionPropagator.TypeDeclaration typ) defs_dict of
                                Just _ ->
                                    rtyps |> Result.map (\types -> List.append types [ typ ])

                                Nothing ->
                                    Err (DefinitionPromisedButNotFound (TypeDeclaration typ))
                        )
                        (Ok [])
                        tys
                        |> Result.map (TagAndTypes tagname)
    in
    tags
        |> List.map has_all_of_tags_types
        |> (\t -> t)
        |> List.foldl
            (\res list ->
                case res of
                    Ok thing ->
                        list |> Result.map (\l -> List.append l [ thing ])

                    Err e ->
                        list |> Result.mapError (\ers -> MultipleErrs [ ers, e ])
            )
            (Ok [])
        |> Result.map
            (\goodtags ->
                EnumDefinitionType goodtags
                    |> DefinitionPropagator.TypeDef
            )


is_type_weak_need : TypeName -> Bool
is_type_weak_need tn =
    case tn of
        ReferenceType _ ->
            True

        _ ->
            False


get_unfinished : Node Identifier -> List AST.EnumField -> AnalysisRes DefinitionPropagator.Unfinished
get_unfinished nid fields =
    let
        -- needed_types : ListSet DefinitionPropagator.DeclarationName
        tags : AnalysisRes (List (SimpleNamed (List TypeName)))
        tags =
            fields
                |> List.map ensure_good_enum_field
                |> (\t -> t)
                |> ar_foldN (::) []

        real_tags : AnalysisRes (List EnumTagDefinition)
        real_tags =
            tags
                |> Result.map
                    (\l ->
                        l
                            |> List.map
                                (\sn ->
                                    if List.length (snamed_get sn) == 0 then
                                        JustTag (snamed_name sn)

                                    else
                                        TagAndTypes (snamed_name sn) (snamed_get sn)
                                )
                    )

        all_types : AnalysisRes (List TypeName)
        all_types =
            tags
                |> Result.map
                    (\l ->
                        l
                            |> List.map snamed_get
                            |> List.concat
                    )

        needed_types : AnalysisRes (ListSet DeclarationName)
        needed_types =
            all_types
                |> Result.map
                    (\l ->
                        l
                            |> (\t -> t)
                            |> List.filter (not << is_type_weak_need)
                            |> List.map DefinitionPropagator.TypeDeclaration
                            |> ListSet.from_list
                    )

        remove_reference : TypeName -> TypeName
        remove_reference tn =
            case tn of
                ReferenceType refto ->
                    refto

                _ ->
                    tn

        weak_needs : AnalysisRes (ListSet DeclarationName)
        weak_needs =
            all_types
                |> Result.map
                    (\l ->
                        l
                            |> List.filter is_type_weak_need
                            |> List.map remove_reference
                            |> List.map TypeDeclaration
                            |> ListSet.from_list
                    )

        finalize_res : AnalysisRes (List ( DefinitionPropagator.DeclarationName, DefinitionPropagator.Definition ) -> Result DefinitionPropagator.Error DefinitionPropagator.Definition)
        finalize_res =
            real_tags |> Result.map finalize

        decl_name : Node DefinitionPropagator.DeclarationName
        decl_name =
            nid
                |> node_map (\id -> CustomTypeName id |> DefinitionPropagator.TypeDeclaration)
    in
    Result.map3
        (DefinitionPropagator.Unfinished decl_name)
        (needed_types |> Result.map ListSet.to_list |> Result.map (List.map (\n -> ( n, Nothing ))) |> Result.map ListDict.from_list)
        weak_needs
        finalize_res


ensure_good_enum_field : AST.EnumField -> AnalysisRes (SimpleNamed (List Language.TypeName))
ensure_good_enum_field field =
    let
        typename_reses : List (AnalysisRes Language.TypeName)
        typename_reses =
            field.args |> List.map analyze_typename

        folder : Language.TypeName -> List Language.TypeName -> List Language.TypeName
        folder mtn ml =
            List.append ml [ mtn ]
    in
    typename_reses
        |> ar_foldN folder []
        |> (\t -> t)
        |> Result.map (SimpleNamed field.name)
