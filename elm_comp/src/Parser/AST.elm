module Parser.AST exposing (..)

import Language exposing (Identifier(..), InfixOpType(..), LiteralType(..), stringify_identifier, stringify_infix_op)
import Parser.Lexer as Lexer
import Util


type alias ThingAndLocation a =
    { thing : a
    , loc : Util.SourceView
    }


with_location : Util.SourceView -> a -> ThingAndLocation a
with_location loc thing =
    { thing = thing, loc = loc }


type alias ImportAndLocation =
    ThingAndLocation String


type alias Program =
    { module_name : Maybe String
    , imports : List ImportAndLocation
    , global_typedefs : List TypeDefinitionType
    , global_functions : List FunctionDefinition
    , needs_more : Maybe String
    , src_tokens : List Lexer.Token
    }


type TypeDefinitionType
    = StructDefType StructDefnition
    | EnumDefType EnumDefinition
    | AliasDefType AliasDefinition


type alias AliasDefinition =
    { name : FullNameAndLocation, alias_to : FullNameAndLocation }


append_identifier : Identifier -> String -> Identifier
append_identifier n new =
    case n of
        SingleIdentifier s ->
            QualifiedIdentifiers [ s, new ]

        QualifiedIdentifiers l ->
            QualifiedIdentifiers (List.append l [ new ])


append_maybe_identifier : Maybe Identifier -> String -> Identifier
append_maybe_identifier n new =
    case n of
        Just nam ->
            append_identifier nam new

        Nothing ->
            SingleIdentifier new




type FullName
    = NameWithoutArgs Identifier
    | NameWithArgs { base : Identifier, args : List FullNameAndLocation }
    | ReferenceToFullName FullNameAndLocation
    | Literal Language.LiteralType String
    | Constrained FullNameAndLocation ExpressionAndLocation


type alias FullNameAndLocation =
    ThingAndLocation FullName


type alias ExpressionAndLocation =
    ThingAndLocation Expression


stringify_fullname : FullName -> String
stringify_fullname nwt =
    case nwt of
        NameWithoutArgs n ->
            stringify_identifier n

        NameWithArgs nlt ->
            stringify_identifier nlt.base
                ++ "["
                ++ (nlt.args |> List.map (\t -> t.thing) |> List.map stringify_fullname |> String.join ", ")
                ++ "]"

        ReferenceToFullName fn ->
            "&" ++ stringify_fullname fn.thing

        Literal _ s ->
            s

        Constrained typ constraint ->
            stringify_fullname typ.thing ++ " | " ++ stringify_expression constraint


append_fullname_args : FullNameAndLocation -> FullNameAndLocation -> FullNameAndLocation
append_fullname_args me tn =
    case me.thing of
        NameWithoutArgs n ->
            NameWithArgs { base = n, args = [ tn ] }
                |> (\fn -> { thing = fn, loc = me.loc })

        NameWithArgs nl ->
            NameWithArgs { nl | args = List.append nl.args [ tn ] }
                |> (\fn -> { thing = fn, loc = me.loc })

        ReferenceToFullName _ ->
            Debug.todo "IDK WHAT TO DO HERE"

        Literal _ _ ->
            Debug.todo "IDK WHAT TO DO HERE"

        Constrained _ _ ->
            Debug.todo "IDK WHAT TO DO HERE"



--


type alias UnqualifiedTypeWithName =
    { name : Identifier, typename : FullNameAndLocation }


make_qualified_typewithname : UnqualifiedTypeWithName -> Language.Qualifier -> QualifiedTypeWithName
make_qualified_typewithname t q =
    QualifiedTypeWithName t.name t.typename q


type alias QualifiedTypeWithName =
    { name : Identifier, typename : FullNameAndLocation, qualifiedness : Language.Qualifier }


type alias FunctionHeader =
    { args : List QualifiedTypeWithName, return_type : Maybe FullNameAndLocation }


type alias FunctionDefinition =
    { name : FullNameAndLocation
    , header : FunctionHeader
    , statements : List Statement
    }


type alias StructDefnition =
    { name : FullNameAndLocation
    , fields : List UnqualifiedTypeWithName
    }


type alias EnumDefinition =
    { name : FullNameAndLocation
    , fields : List EnumField
    }


type alias EnumField =
    { name : String, args : List FullNameAndLocation }


add_arg_to_enum_field : EnumField -> FullNameAndLocation -> EnumField
add_arg_to_enum_field ef fn =
    { ef | args = List.append ef.args [ fn ] }


type Statement
    = CommentStatement String
    | ReturnStatement (Maybe ExpressionAndLocation)
    | InitilizationStatement QualifiedTypeWithName ExpressionAndLocation
    | AssignmentStatement Identifier ExpressionAndLocation
    | FunctionCallStatement FunctionCallAndLocation
    | IfStatement ExpressionAndLocation (List Statement)
    | WhileStatement ExpressionAndLocation (List Statement)


type Expression
    = FunctionCallExpr FunctionCallAndLocation
    | LiteralExpr LiteralType String
    | NameLookup FullNameAndLocation
    | Parenthesized ExpressionAndLocation
    | InfixExpr ExpressionAndLocation ExpressionAndLocation InfixOpType


type alias FunctionCall =
    { fname : FullNameAndLocation
    , args : List ExpressionAndLocation
    }


type alias FunctionCallAndLocation =
    ThingAndLocation FunctionCall


stringify_expression : ExpressionAndLocation -> String 
stringify_expression expr =
    case expr.thing of
        NameLookup n ->
            stringify_fullname n.thing

        FunctionCallExpr fc ->
            stringify_fullname fc.thing.fname.thing ++ "(" ++ (fc.thing.args |> List.map stringify_expression |> String.join ", ") ++ ")"

        LiteralExpr _ s ->
            s

        Parenthesized e ->
            stringify_expression e

        InfixExpr lhs rhs op ->
            stringify_expression lhs ++ stringify_infix_op op ++ stringify_expression rhs
