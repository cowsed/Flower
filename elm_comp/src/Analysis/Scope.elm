module Analysis.Scope exposing (..)

import Language

-- Scope that only has 
--   names and types of values
--   Type definitions
-- Does not have the actual definitions of the values
type alias OverviewScope =
    { values : List Language.ValueNameAndType
    , types : List Language.Type
    }


qualify_all : String -> OverviewScope -> OverviewScope
qualify_all q s =
    { s | values = s.values |> List.map (Language.qualify_vnt_name q) }


empty_scope : OverviewScope
empty_scope =
    OverviewScope [] []


add_val_to_scope : OverviewScope -> Language.ValueNameAndType -> OverviewScope
add_val_to_scope scope val =
    { scope | values = List.append scope.values [ val ] }


add_type_to_scope : OverviewScope -> Language.Type -> OverviewScope
add_type_to_scope scope val =
    { scope | types = List.append scope.types [ val ] }


merge_2_scopes : OverviewScope -> OverviewScope -> OverviewScope
merge_2_scopes s1 s2 =
    { values = List.append s1.values s2.values
    , types = List.append s1.types s2.types
    }
