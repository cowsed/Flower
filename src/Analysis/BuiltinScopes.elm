module Analysis.BuiltinScopes exposing (..)

import Analysis.Scope as Scope
import Language.Language as Language exposing (Identifier(..), Named, Qualifier(..), ReasonForUninstantiable(..), SimpleNamed, TypeDefinition(..), TypeName(..), TypeOfCustomType(..), integers)



-- std_pair_def: Language.TypeDefinition
-- std_pair_def = Language.GenericDefin


builtin_string : Named TypeDefinition
builtin_string =
    Named (si "string") (StructDefinitionType { fields = [ SimpleNamed "len" integers.i64, SimpleNamed "cap" integers.i64 ] })


builtin_maybe : Named Language.TypeDefinition
builtin_maybe =
    Named (si "Maybe")
        (EnumDefinitionType [ Language.JustTag "Nothing", Language.TagAndTypes "Some" [ CustomTypeName (si "T") ] ])


std_types : Scope.TypeDefs
std_types =
    []


si : String -> Identifier
si s =
    SingleIdentifier s


std_pair_generic : Language.GenericTypeDefinition
std_pair_generic types =
    if List.length types /= 1 then
        Err WrongNumber

    else
        case List.head types of
            Nothing ->
                Err WrongNumber

            Just typ ->
                { fields =
                    [ SimpleNamed "A" typ
                    , SimpleNamed "B" typ
                    ]
                }
                    |> StructDefinitionType
                    |> Ok


std_generic_types : Scope.GenericTypeDefs
std_generic_types =
    [ Named (si "pair") std_pair_generic ]


std_scope : Scope.FullScope
std_scope =
    Scope.FullScope std_types [] std_generic_types


builtin_scope : Scope.FullScope
builtin_scope =
    { types = [ builtin_string, builtin_maybe ]
    , generic_types = []
    , values = []
    }


import_scope : String -> Maybe Scope.FullScope
import_scope im =
    case im of
        "std" ->
            std_scope |> Just

        _ ->
            Nothing
