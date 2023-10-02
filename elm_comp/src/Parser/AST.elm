module Parser.AST exposing (..)

import Language exposing (InfixOpType(..), LiteralType(..), stringify_infix_op)
import Parser.Lexer as Lexer


type alias Program =
    { module_name : Maybe String
    , imports : List String
    , global_structs : List StructDefnition
    , global_enums : List EnumDefinition
    , global_functions : List FunctionDefinition
    , needs_more : Maybe String
    , src_tokens : List Lexer.Token
    }


type Identifier
    = SingleIdentifier String -- name
    | QualifiedIdentifiers (List String) -- name.b.c


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


type IntegerSize
    = U8
    | U16
    | U32
    | U64
    | I8
    | I16
    | I32
    | I64


type Type
    = BooleanType
    | IntegerType IntegerSize
    | StringType


builtin_type_from_name : String -> Maybe Type
builtin_type_from_name s =
    case s of
        "u8" ->
            IntegerType U8 |> Just

        _ ->
            Nothing


builtin_types : List Type
builtin_types =
    [ BooleanType
    , StringType
    , IntegerType U8
    , IntegerType U16
    , IntegerType U32
    , IntegerType U64
    , IntegerType I8
    , IntegerType I16
    , IntegerType I32
    , IntegerType I64
    ]


type Qualifier
    = Variable
    | Constant


type FullName
    = NameWithoutArgs Identifier
    | NameLookupType { base : Identifier, args : List FullName }
    | ReferenceToFullName FullName
    | Literal Language.LiteralType String
    | Constrained FullName Expression


stringify_fullname : FullName -> String
stringify_fullname nwt =
    case nwt of
        NameWithoutArgs n ->
            stringify_identifier n

        NameLookupType nlt ->
            stringify_identifier nlt.base
                ++ "["
                ++ (nlt.args |> List.map stringify_fullname |> String.join ", ")
                ++ "]"

        ReferenceToFullName fn ->
            "&" ++ stringify_fullname fn

        Literal _ s ->
            s

        Constrained typ constraint ->
            (stringify_fullname typ )++" | "++(stringify_expression constraint)


append_fullname_args : FullName -> FullName -> FullName
append_fullname_args me tn =
    case me of
        NameWithoutArgs n ->
            NameLookupType { base = n, args = [ tn ] }

        NameLookupType nl ->
            NameLookupType { nl | args = List.append nl.args [ tn ] }

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
add_arg_to_enum_field: EnumField -> FullName -> EnumField
add_arg_to_enum_field ef fn = 
    {ef | args = List.append ef.args [fn]}


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


stringify_identifier : Identifier -> String
stringify_identifier n =
    case n of
        SingleIdentifier s ->
            s

        QualifiedIdentifiers l ->
            String.join "." l

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

