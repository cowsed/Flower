module Language exposing (..)


type Name
    = BaseName String
    | Qualified (List String)


append_name : Name -> String -> Name
append_name n new =
    case n of
        BaseName s ->
            Qualified [ s, new ]

        Qualified l ->
            Qualified (List.append l [ new ])


append_maybe_name : Maybe Name -> String -> Name
append_maybe_name n new =
    case n of
        Just nam ->
            append_name nam new

        Nothing ->
            BaseName new


stringify_name : Name -> String
stringify_name n =
    case n of
        BaseName s ->
            s

        Qualified l ->
            String.join "." l


stringify_utname : UnqualifiedTypeName -> String
stringify_utname utn =
    case utn of
        Basic n ->
            stringify_name n

        Generic _ _ ->
            Debug.todo "branch 'Generic _ _' not implemented"


stringify_type_name : TypeName -> String
stringify_type_name tn =
    case tn of
        VariableTypename n ->
            stringify_utname n

        ConstantTypename n ->
            stringify_utname n

        NonQualified n ->
            stringify_utname n


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
    | StructKeyword



-- sumtype, product type, list


type InfixOpType
    = Addition
    | Subtraction
    | Multiplication
    | Division


precedence : InfixOpType -> Int
precedence op =
    case op of
        Addition ->
            2

        Subtraction ->
            2

        Multiplication ->
            3

        Division ->
            3


stringify_infix_op : InfixOpType -> String
stringify_infix_op op =
    case op of
        Addition ->
            "+"

        Subtraction ->
            "-"

        Multiplication ->
            "*"

        Division ->
            "/"


type alias InfixOp =
    { op : InfixOpType, precedence : Int }


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


make_qualified_typename : Qualifier -> UnqualifiedTypeName -> TypeName
make_qualified_typename q uq =
    case q of
        Variable ->
            VariableTypename uq

        Constant ->
            ConstantTypename uq


type TypeName
    = VariableTypename UnqualifiedTypeName
    | ConstantTypename UnqualifiedTypeName
    | NonQualified UnqualifiedTypeName


remove_type_qualifier : TypeName -> UnqualifiedTypeName
remove_type_qualifier tn =
    case tn of
        VariableTypename n ->
            n

        ConstantTypename n ->
            n

        NonQualified n ->
            n


type UnqualifiedTypeName
    = Basic Name
    | Generic Name (List TypeName)


type alias TypeWithName =
    { name : Name, typename : TypeName }


type alias ASTFunctionHeader =
    { args : List TypeWithName, return_type : Maybe TypeName }


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
    | NameLookup Name
    | Parenthesized ASTExpression
    | InfixExpr ASTExpression ASTExpression InfixOpType


type alias ASTFunctionCall =
    { fname : Name
    , args : List ASTExpression
    }
