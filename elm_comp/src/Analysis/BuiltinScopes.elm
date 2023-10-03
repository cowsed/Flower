module Analysis.BuiltinScopes exposing (..)
import Language exposing (ValueNameAndType, Identifier(..))
import Analysis.Scope as Scope
import Parser.AST as AST
std_puts_v :ValueNameAndType
std_puts_v =
    ValueNameAndType (Language.SingleIdentifier "puts") (Language.FunctionType { args = [ Language.StringType ], rtype = Nothing })


std_scope : Scope.OverviewScope
std_scope =
    Scope.OverviewScope [ std_puts_v ] [] |> Scope.qualify_all "std"

math_scope : Scope.OverviewScope
math_scope =
    Scope.OverviewScope [ ValueNameAndType (SingleIdentifier "Pi") (Language.FloatingPointType Language.F64) ] []  |> Scope.qualify_all "math"


import_scope : AST.ImportAndLocation -> Maybe Scope.OverviewScope
import_scope im =
    case im.thing of
        "std" ->
            std_scope |> Just

        "math" ->
            math_scope |> Just

        _ ->
            Nothing
