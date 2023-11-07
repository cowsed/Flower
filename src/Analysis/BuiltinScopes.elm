module Analysis.BuiltinScopes exposing (..)

import Analysis.Scope as Scope
import Language.Language as Language exposing (Identifier(..), Named, Qualifier(..), ReasonForUninstantiable(..), SimpleNamed, TypeDefinition(..), TypeName(..), TypeOfCustomType(..), integer_size_name, si)
import Language.Syntax as Syntax



-- std_pair_def: Language.TypeDefinition
-- std_pair_def = Language.GenericDefin


builtin_string : Named TypeDefinition
builtin_string =
    Named (si "string")
        (StructDefinitionType
            { fields =
                [ SimpleNamed "len" (CustomTypeName (si "u64"))
                , SimpleNamed "cap" (CustomTypeName (si "u64"))
                ]
            }
        )


builtin_maybe : Named Language.GenericTypeDefinition
builtin_maybe =
    let
        body garg =
            EnumDefinitionType [ Language.JustTag "Nothing", Language.TagAndTypes "Some" [ garg ] ]

        builder args =
            one_arg_only args |> Result.map body
    in
    Named (si "Maybe") builder


builtin_bool : Named Language.TypeDefinition
builtin_bool =
    EnumDefinitionType
        [ Language.JustTag "true"
        , Language.JustTag "false"
        ]
        |> Named (si "bool")


one_arg_only : List TypeName -> Result ReasonForUninstantiable TypeName
one_arg_only args =
    case List.head args of
        Just garg ->
            if List.length args == 1 then
                garg
                    |> Ok

            else
                WrongNumber |> Err

        Nothing ->
            WrongNumber |> Err


std_console_types : Scope.TypeDefs
std_console_types =
    []


std_generic_types : Scope.GenericTypeDefs
std_generic_types =
    []


std_console_scope : Scope.FullScope
std_console_scope =
    Scope.FullScope std_console_types [] std_generic_types


builtin_ints : List (Named TypeDefinition)
builtin_ints =
    Language.integer_sizes
        |> List.map
            (\is ->
                Language.IntegerDefinitionType is
                    |> Named (si (integer_size_name is))
            )


builtin_floats : List (Named TypeDefinition)
builtin_floats =
    [ Named (si "f32") (FloatDefinitionType Language.F32)
    , Named (si "f64") (FloatDefinitionType Language.F64)
    ]


builtin_types : List (Named TypeDefinition)
builtin_types =
    List.concat [ builtin_ints, builtin_floats, [ builtin_string, builtin_bool ] ]


builtin_scope : Scope.FullScope
builtin_scope =
    { types = builtin_types |> List.map (\t -> Syntax.Node t Syntax.invalid_sourceview)
    , generic_types = [ Syntax.Node builtin_maybe Syntax.invalid_sourceview ]
    , values = []
    }


import_scope : String -> Maybe Scope.FullScope
import_scope im =
    case im of
        "std/console" ->
            std_console_scope |> Just

        _ ->
            Nothing
