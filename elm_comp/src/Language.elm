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


type Type
    = BooleanType
    | IntegerType
    | StringType
    | ConstrainedType Type Expression


type Expression
    = Expression
    | LiteralExpression
    | NameLookupExpression
    | FunctionCallExoression
