module Analysis.Scope exposing (..)

import Language.Language as Language


type alias TypeDefs =
    List (Language.Named Language.TypeDefinition)


type alias GenericTypeDefs =
    List Language.GenericTypeDefinition


type alias ValueDefs =
    List (Language.Named Language.Value)


type alias FullScope =
    { types : TypeDefs
    , values : ValueDefs
    , generic_types : GenericTypeDefs
    }

-- type alias DeclarationScope = {
--     values
-- }

merge_two_scopes : FullScope -> FullScope -> FullScope
merge_two_scopes a b =
    { types = List.append a.types b.types
    , values = List.append a.values b.values
    , generic_types = List.append a.generic_types b.generic_types
    }


merge_scopes : List FullScope -> FullScope
merge_scopes ls =
    List.foldl merge_two_scopes empty_scope ls


empty_scope : FullScope
empty_scope =
    { types = [], values = [], generic_types = [] }
