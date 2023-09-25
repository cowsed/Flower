module Language exposing (..)


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
    | ConstrainedType Type Expression


type Expression
    = Expression
    | LiteralExpression
    | NameLookupExpression
    | FunctionCallExoression
