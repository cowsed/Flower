module Parser.AST exposing (..)

import Language exposing (InfixOpType(..), LiteralType(..), stringify_infix_op, Identifier(..), stringify_identifier)
import Parser.Lexer as Lexer
import Util


type alias ThingAndLocation a =
    { thing : a
    , loc : Util.SourceView
    }

type alias ImportAndLocation = ThingAndLocation String

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
    { name : FullName, alias_to : FullName }




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


type Qualifier
    = Variable
    | Constant


type FullName
    = NameWithoutArgs Identifier
    | NameWithArgs { base : Identifier, args : List FullName }
    | ReferenceToFullName FullName
    | Literal Language.LiteralType String
    | Constrained FullName Expression


stringify_fullname : FullName -> String
stringify_fullname nwt =
    case nwt of
        NameWithoutArgs n ->
            stringify_identifier n

        NameWithArgs nlt ->
            stringify_identifier nlt.base
                ++ "["
                ++ (nlt.args |> List.map stringify_fullname |> String.join ", ")
                ++ "]"

        ReferenceToFullName fn ->
            "&" ++ stringify_fullname fn

        Literal _ s ->
            s

        Constrained typ constraint ->
            stringify_fullname typ ++ " | " ++ stringify_expression constraint


append_fullname_args : FullName -> FullName -> FullName
append_fullname_args me tn =
    case me of
        NameWithoutArgs n ->
            NameWithArgs { base = n, args = [ tn ] }

        NameWithArgs nl ->
            NameWithArgs { nl | args = List.append nl.args [ tn ] }

        ReferenceToFullName _ ->
            Debug.todo "IDK WHAT TO DO HERE"

        Literal _ _ ->
            Debug.todo "IDK WHAT TO DO HERE"

        Constrained _ _ ->
            Debug.todo "IDK WHAT TO DO HERE"



--


type alias UnqualifiedTypeWithName =
    { name : Identifier, typename : FullName }


make_qualified_typewithname : UnqualifiedTypeWithName -> Qualifier -> QualifiedTypeWithName
make_qualified_typewithname t q =
    QualifiedTypeWithName t.name t.typename q


type alias QualifiedTypeWithName =
    { name : Identifier, typename : FullName, qualifiedness : Qualifier }


type alias FunctionHeader =
    { args : List QualifiedTypeWithName, return_type : Maybe FullName }


type alias FunctionDefinition =
    { name : FullName
    , header : FunctionHeader
    , statements : List Statement
    }


type alias StructDefnition =
    { name : FullName
    , fields : List UnqualifiedTypeWithName
    }


type alias EnumDefinition =
    { name : FullName
    , fields : List EnumField
    }


type alias EnumField =
    { name : String, args : List FullName }


add_arg_to_enum_field : EnumField -> FullName -> EnumField
add_arg_to_enum_field ef fn =
    { ef | args = List.append ef.args [ fn ] }


type Statement
    = CommentStatement String
    | ReturnStatement (Maybe Expression)
    | InitilizationStatement QualifiedTypeWithName Expression
    | AssignmentStatement Identifier Expression
    | FunctionCallStatement FunctionCall
    | IfStatement Expression (List Statement)
    | WhileStatement Expression (List Statement)


type Expression
    = FunctionCallExpr FunctionCall
    | LiteralExpr LiteralType String
    | NameLookup FullName
    | Parenthesized Expression
    | InfixExpr Expression Expression InfixOpType


type alias FunctionCall =
    { fname : FullName
    , args : List Expression
    }




stringify_expression : Expression -> String
stringify_expression expr =
    case expr of
        NameLookup n ->
            stringify_fullname n

        FunctionCallExpr fc ->
            stringify_fullname fc.fname ++ "(" ++ (fc.args |> List.map stringify_expression |> String.join ", ") ++ ")"

        LiteralExpr _ s ->
            s

        Parenthesized e ->
            stringify_expression e

        InfixExpr lhs rhs op ->
            stringify_expression lhs ++ stringify_infix_op op ++ stringify_expression rhs
