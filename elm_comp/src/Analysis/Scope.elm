module Analysis.Scope exposing (..)

import Language

type alias ValuelessScope =
    { values : List Language.ValueNameAndType
    , types : List Language.Type
    }

empty_scope : ValuelessScope
empty_scope =
    ValuelessScope [] []


add_val_to_scope : ValuelessScope -> Language.ValueNameAndType -> ValuelessScope
add_val_to_scope scope val =
    { scope | values = List.append scope.values [ val ] }


add_type_to_scope : ValuelessScope -> Language.Type -> ValuelessScope
add_type_to_scope scope val =
    { scope | types = List.append scope.types [ val ] }


merge_2_scopes : ValuelessScope -> ValuelessScope -> ValuelessScope
merge_2_scopes s1 s2 =
    { values = List.append s1.values s2.values
    , types = List.append s1.types s2.types
    }


