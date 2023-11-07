module Parser.AST exposing (..)

import Keyboard.Key exposing (Key(..))
import Language.Language as Language exposing (Identifier(..), InfixOpType(..), stringify_identifier)
import Language.Syntax
import Parser.Lexer as Lexer
import Language.Syntax as Syntax exposing (Node)




with_location : Syntax.SourceView -> a -> Node a
with_location loc thing =
    { thing = thing, loc = loc }


type alias ImportNode =
    Node String


type alias Program =
    { module_name : Maybe String
    , imports : List ImportNode
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
    { name : (Node FullName), alias_to : (Node FullName) }


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
    | NameWithArgs { base : Identifier, args : List (Node FullName) }
    | ReferenceToFullName (Node FullName)
    | Literal Language.Syntax.LiteralType String
    | Constrained (Node FullName) (Node Expression)







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


append_fullname_args : (Node FullName) -> (Node FullName) -> (Node FullName)
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


type alias IdentifierAndLocation =
    Node Identifier


type alias UnqualifiedTypeWithName =
    { name : IdentifierAndLocation, typename : (Node FullName) }


make_qualified_typewithname : UnqualifiedTypeWithName -> Language.Qualifier -> QualifiedTypeWithName
make_qualified_typewithname t q =
    QualifiedTypeWithName t.name.thing t.typename q


type alias QualifiedTypeWithName =
    { name : Identifier, typename : (Node FullName), qualifiedness : Language.Qualifier }


type alias FunctionHeader =
    { args : List QualifiedTypeWithName, return_type : Maybe (Node FullName) }


type alias FunctionDefinition =
    { name : (Node FullName)
    , header : FunctionHeader
    , statements : List Statement
    }


type alias StructDefnition =
    { name : (Node FullName)
    , fields : List UnqualifiedTypeWithName
    }


type alias EnumDefinition =
    { name : (Node FullName)
    , fields : List EnumField
    }


type alias EnumField =
    { name : String, args : List (Node FullName) }


add_arg_to_enum_field : EnumField -> (Node FullName) -> EnumField
add_arg_to_enum_field ef fn =
    { ef | args = List.append ef.args [ fn ] }


type Statement
    = CommentStatement String
    | ReturnStatement (Maybe (Node Expression))
    | InitilizationStatement QualifiedTypeWithName (Node Expression)
    | AssignmentStatement Identifier (Node Expression)
    | FunctionCallStatement FunctionCallAndLocation
    | IfStatement (Node Expression) (List Statement)
    | WhileStatement (Node Expression) (List Statement)


type Expression
    = FunctionCallExpr FunctionCallAndLocation
    | LiteralExpr Language.Syntax.LiteralType String
    | NameLookup (Node FullName)
    | Parenthesized (Node Expression)



name_of_op_function : InfixOpType -> FullName
name_of_op_function iot =
    NameWithoutArgs <|
        SingleIdentifier <|
            case iot of
                Addition ->
                    "_op_add"

                Subtraction ->
                    "_op_sub"

                Multiplication ->
                    "_op_mul"

                Division ->
                    "_op_div"

                Equality ->
                    "_op_eq"

                NotEqualTo ->
                    "_op_neq"

                LessThan ->
                    "_op_lt"

                LessThanEqualTo ->
                    "_op_lte"

                GreaterThan ->
                    "_op_gt"

                GreaterThanEqualTo ->
                    "_op_gte"

                And ->
                    "_op_and"

                Or ->
                    "_op_or"

                Xor ->
                    "_op_xor"


operator_to_function : InfixOpType -> Syntax.SourceView -> (Node Expression) -> (Node Expression) -> (Node Expression)
operator_to_function ot sv lhs rhs =
    name_of_op_function ot |> with_location sv |> (\func -> FunctionCall func [ lhs, rhs ]) |> with_location sv|> FunctionCallExpr |> with_location sv


type alias FunctionCall =
    { fname : (Node FullName)
    , args : List (Node Expression)
    }


type alias FunctionCallAndLocation =
    Node FunctionCall


stringify_expression : (Node Expression) -> String
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
