module Language exposing (..)

type Name
    = EmptyName
    | BaseName String
    | Qualified (List String)

append_name: Name -> String -> Name
append_name n new =
    case n of
        EmptyName -> BaseName new
        BaseName s -> Qualified [s, new]
        Qualified l -> Qualified (List.append l [new])
stringify_name : Name -> String
stringify_name n = 
    case n of
        EmptyName -> Debug.log "stringify empty name should never happen, signals a compiler error" ""
        BaseName s -> s
        Qualified l -> (String.join "." l)


type LiteralType
    = BooleanLiteral
    | NumberLiteral
    | StringLiteral


type KeywordType
    = FnKeyword
    | ReturnKeyword
    | ModuleKeyword
    | ImportKeyword
    | VarKeyword



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

builtin_type_from_name: String -> Maybe Type
builtin_type_from_name s = 
    case s of
        "u8" -> IntegerType U8 |> Just 
        _ -> Nothing

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


type TypeName
    = Basic Name
    | ConstName TypeName

type alias TypeWithName =
    { name : Name, typename : Name }



type alias ASTFunctionHeader =
    { args : List TypeWithName, return_type : Maybe Name }

type alias ASTFunctionDefinition =
    { name : String
    , header : ASTFunctionHeader
    , statements : List ASTStatement
    }


type ASTStatement
    = CommentStatement String
    | ReturnStatement ASTExpression
    | InitilizationStatement TypeWithName ASTExpression
    | AssignmentStatement Name ASTExpression
    | FunctionCallStatement ASTFunctionCall
    | IfStatement

type ASTExpression
    = FunctionCallExpr ASTFunctionCall
    | LiteralExpr LiteralType String
    | NameLookup Name -- InfixOperation InfixType

type alias ASTFunctionCall =
    { fname : Name
    , args : List ASTExpression
    }
