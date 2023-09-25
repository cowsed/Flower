module Language exposing (..)

type Name
    = BaseName String
    | Qualified (List String)
stringify_name : Name -> String
stringify_name n = 
    case n of
        BaseName s -> s
        Qualified l -> (String.join "," l)


type LiteralType
    = BooleanLiteral
    | NumberLiteral
    | StringLiteral


type KeywordType
    = FnKeyword
    | ReturnKeyword
    | ModuleKeyword
    | ImportKeyword



-- sumtype, product type, list


type Integers
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
    | IntegerType Integers
    | StringType



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



type alias TypeWithName =
    { name : Name, typename : Name }



type alias FunctionHeader =
    { args : List TypeWithName, return_type : Maybe Name }

type alias FunctionDefinition =
    { name : String
    , header : FunctionHeader
    , statements : List Statement
    }


type Statement
    = CommentStatement String
    | ReturnStatement Expression
    | Initilization TypeWithName Expression
    | Assignment String Expression
    | FunctionCallStatement FunctionCall
    | IfStatement

type Expression
    = FunctionCallExpr FunctionCall
    | LiteralExpr LiteralType String
    | NameLookup Name -- InfixOperation InfixType

type alias FunctionCall =
    { fname : String
    , args : List Expression
    }
