module Language exposing (..)


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
    | IfKeyword



-- sumtype, product type, list


type InfixOpType
    = Addition
    | Subtraction
    | Multiplication
    | Division
    | Equality
    | NotEqualTo
    | LessThan
    | LessThanEqualTo
    | GreaterThan
    | GreaterThanEqualTo


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

        Equality ->
            1

        NotEqualTo ->
            1

        LessThan ->
            1

        LessThanEqualTo ->
            1

        GreaterThan ->
            1

        GreaterThanEqualTo ->
            1


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

        Equality ->
            "=="

        NotEqualTo ->
            "≠"

        LessThan ->
            "<"

        LessThanEqualTo ->
            "≤"

        GreaterThan ->
            ">"

        GreaterThanEqualTo ->
            ">="


type alias InfixOp =
    { op : InfixOpType, precedence : Int }


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
    | Literal LiteralType String


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



--


type alias UnqualifiedTypeWithName =
    { name : Identifier, typename : FullName }


make_qualified_typewithname : UnqualifiedTypeWithName -> Qualifier -> QualifiedTypeWithName
make_qualified_typewithname t q =
    QualifiedTypeWithName t.name t.typename q


type alias QualifiedTypeWithName =
    { name : Identifier, typename : FullName, qualifiedness : Qualifier }


type alias ASTFunctionHeader =
    { generic_args : List FullName, args : List QualifiedTypeWithName, return_type : Maybe FullName }


type alias ASTFunctionDefinition =
    { name : String
    , header : ASTFunctionHeader
    , statements : List ASTStatement
    }


type ASTStatement
    = CommentStatement String
    | ReturnStatement ASTExpression
    | InitilizationStatement QualifiedTypeWithName ASTExpression
    | AssignmentStatement Identifier ASTExpression
    | FunctionCallStatement ASTFunctionCall
    | IfStatement ASTExpression (List ASTStatement)



-- | WhileStatement ASTExpression (List ASTStatement)


type ASTExpression
    = FunctionCallExpr ASTFunctionCall
    | LiteralExpr LiteralType String
    | NameLookup FullName
    | Parenthesized ASTExpression
    | InfixExpr ASTExpression ASTExpression InfixOpType


type alias ASTFunctionCall =
    { fname : FullName
    , args : List ASTExpression
    }


stringify_identifier : Identifier -> String
stringify_identifier n =
    case n of
        SingleIdentifier s ->
            s

        QualifiedIdentifiers l ->
            String.join "." l
