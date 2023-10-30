module Analysis.Scope exposing (..)

import Language.Language as Language
import List.Extra
import Language.Language exposing (Named)
import Language.Language exposing (TypeDefinition)
import Language.Language exposing (TypeName(..))
import Language.Language exposing (Identifier)


type alias TypeDefs =
    List (Language.Named Language.TypeDefinition)


type alias GenericTypeDefs =
    List (Language.Named Language.GenericTypeDefinition)


type alias ValueDefs =
    List (Language.Named Language.Value)


type alias FullScope =
    { types : TypeDefs
    , values : ValueDefs
    , generic_types : GenericTypeDefs
    }

lookup_type_in_scope: FullScope -> Language.TypeName -> Maybe (Named TypeDefinition)
lookup_type_in_scope fs tn = 
    let
        pred: Named TypeDefinition -> Bool
        pred ntd = case tn of 
            CustomTypeName id -> ntd.name == id
            _ -> False
    in
    
    List.Extra.find pred fs.types 
lookup_type_in_decl_scope: TypeDeclarationScope -> Language.TypeName -> Bool
lookup_type_in_decl_scope fs tn = 
    let
        pred: Identifier -> Bool
        pred ntd = case tn of 
            CustomTypeName id -> ntd == id
            _ -> False
    in
    
    List.any pred fs.types 


lookup_generic_type_in_decl_scope: TypeDeclarationScope -> Language.TypeName -> Bool
lookup_generic_type_in_decl_scope fs tn = 
    let
        pred: Identifier -> Bool
        pred ntd = case Debug.log "TN" tn of 
            GenericInstantiation id args -> ntd == id && (List.length args == numargs)
            _ -> False
    in
    
    List.any pred (fs.generics |> Debug.log "Gnerices: ") 


type alias TypeDeclarationScope =
    { types : List Language.Identifier
    , generics : List Language.Identifier
    }


get_declaration_scope : FullScope -> TypeDeclarationScope
get_declaration_scope scope =
    { types = scope.types |> List.map .name
    , generics = scope.generic_types |> List.map .name
    }


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
