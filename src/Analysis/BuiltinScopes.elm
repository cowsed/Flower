module Analysis.BuiltinScopes exposing (..)

import Analysis.Scope as Scope
import Language.Language as Language exposing (Identifier(..), OuterType, QualifiedType, Qualifier(..), ValueNameAndType)
import Parser.AST as AST
import Language.Language exposing (OuterType(..))


std_puts_v : ValueNameAndType
std_puts_v =
    ValueNameAndType (Language.SingleIdentifier "puts") (Language.FunctionType { args = [ QualifiedType Constant Language.StringType ], rtype = Nothing })


std_pair_t : OuterType
std_pair_t =
    Generic (SingleIdentifier "pair") Language.StructDefinitionType ["T"]


std_scope : Scope.OverviewScope
std_scope =
    Scope.OverviewScope [ std_puts_v ] [ std_pair_t ] |> Scope.qualify_all_names "std"


math_scope : Scope.OverviewScope
math_scope =
    Scope.OverviewScope [ ValueNameAndType (SingleIdentifier "Pi") (Language.FloatingPointType Language.F64) ] [] |> Scope.qualify_all_names "math"


import_scope : AST.ImportAndLocation -> Maybe Scope.OverviewScope
import_scope im =
    case im.thing of
        "std" ->
            std_scope |> Just

        "math" ->
            math_scope |> Just

        _ ->
            Nothing
