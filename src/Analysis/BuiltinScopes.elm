module Analysis.BuiltinScopes exposing (..)

import Analysis.Scope as Scope
import Language.Language as Language exposing (Identifier(..), Named, Qualifier(..), ReasonForUninstantiable(..), SimpleNamed, TypeDefinition(..), TypeName(..), TypeOfCustomType(..), si)
import Language.Syntax as Syntax
import Language.Language exposing (integers_types)



-- std_pair_def: Language.TypeDefinition
-- std_pair_def = Language.GenericDefin


builtin_string : Named TypeDefinition
builtin_string =
    Named (si "string") (StructDefinitionType { fields = [ SimpleNamed "len" integers_types.i64, SimpleNamed "cap" integers_types.i64 ] })


builtin_maybe : Named Language.GenericTypeDefinition
builtin_maybe =
    let
        body garg =
            EnumDefinitionType [ Language.JustTag "Nothing", Language.TagAndTypes "Some" [ garg ] ]

        builder args =
            one_arg_only args |> Result.map body
    in
    Named (si "Maybe") builder


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


std_types : Scope.TypeDefs
std_types =
    []



-- std_pair_generic : Named Language.GenericTypeDefinition
-- std_pair_generic =
--     (\types ->
--         one_arg_only types
--             |> Result.map
--                 (\typ ->
--                     StructDefinitionType
--                         { fields =
--                             [ SimpleNamed "A" typ
--                             , SimpleNamed "B" typ
--                             ]
--                         }
--                 )
--     )
--         |> Named (si "pair")


std_generic_types : Scope.GenericTypeDefs
std_generic_types =
    []


std_scope : Scope.FullScope
std_scope =
    Scope.FullScope std_types [] std_generic_types


builtin_scope : Scope.FullScope
builtin_scope =
    { types = [ Syntax.Node builtin_string Syntax.invalid_sourceview ]
    , generic_types = [ Syntax.Node builtin_maybe Syntax.invalid_sourceview ]
    , values = []
    }


import_scope : String -> Maybe Scope.FullScope
import_scope im =
    case im of
        "std" ->
            std_scope |> Just

        _ ->
            Nothing
