module Language.Requirement exposing (..)
import Language.Language as Language
import Util


type alias Requirements = List Requirement

type Requirement
    = NeedsType {whattype: Language.TypeName, why: Reason}


type Reason 
    = TypeUsedHere Util.SourceView
