module Analysis.BuiltinScopes exposing (..)

import Analysis.Scope as Scope
import Language.Language as Language exposing (Identifier(..), QualifiedTypeName, Qualifier(..), ReasonForUninstantiable(..), StructDefinition, TypeDefinition(..), TypeName(..), TypeOfCustomType(..), ValueNameAndType)



-- std_pair_def: Language.TypeDefinition
-- std_pair_def = Language.GenericDefin


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
                    [ ValueNameAndType (si "A") typ
                    , ValueNameAndType (si "B") typ
                    ]
                }
                    |> StructDefinitionType
                    |> Ok


std_generic_types : Scope.GenericTypeDefs
std_generic_types =
    []


std_scope : Scope.FullScope
std_scope =
    Scope.FullScope std_types [] std_generic_types


import_scope : String -> Maybe Scope.FullScope
import_scope im =
    case im of
        "std" ->
            std_scope |> Just

        _ ->
            Nothing
