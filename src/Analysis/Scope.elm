module Analysis.Scope exposing (..)

import Language.Language as Language

-- Scope that only has 
--   names and types of values
--   Type definitions
-- Does not have the actual definitions of the values
type alias OverviewScope =
    { values : List Language.ValueNameAndType
    , types : List Language.OuterType
    }
 
overview_has_outer_type: OverviewScope -> Language.Identifier -> Maybe Language.OuterType
overview_has_outer_type os id = 
    let
        matches = List.filter (\ot -> (Language.get_id ot) == id) os.types
    in
    
    if (matches |> List.length) > 0 then
        List.head matches
    else 
    Nothing

qualify_all_names : String -> OverviewScope -> OverviewScope
qualify_all_names q s =
    { s | values = s.values |> List.map (Language.qualify_vnt_name q), types = s.types |> List.map (Language.qualify_type_name q) }


empty_scope : OverviewScope
empty_scope =
    OverviewScope [] []


add_val_to_scope : OverviewScope -> Language.ValueNameAndType -> OverviewScope
add_val_to_scope scope val =
    { scope | values = List.append scope.values [ val ] }


add_type_to_scope : OverviewScope -> Language.OuterType -> OverviewScope
add_type_to_scope scope val =
    { scope | types = List.append scope.types [ val ] }


merge_2_scopes : OverviewScope -> OverviewScope -> OverviewScope
merge_2_scopes s1 s2 =
    { values = List.append s1.values s2.values
    , types = List.append s1.types s2.types
    }
