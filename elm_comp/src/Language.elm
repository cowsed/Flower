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


-- make_qualified_typename : Qualifier -> UnqualifiedTypeName -> TypeName
-- make_qualified_typename q uq =
--     case q of
--         Variable ->
--             VariableTypename uq

--         Constant ->
--             ConstantTypename uq


-- type TypeName
--     = VariableTypename UnqualifiedTypeName
--     | ConstantTypename UnqualifiedTypeName
--     | NonQualified UnqualifiedTypeName


-- remove_type_qualifier : TypeName -> UnqualifiedTypeName
-- remove_type_qualifier tn =
--     case tn of
--         VariableTypename n ->
--             n

--         ConstantTypename n ->
--             n

--         NonQualified n ->
--             n


type FullName
    = NameWithoutArgs Identifier 
    | NameLookupType { base : Identifier, args : List FullName }

stringify_name_lookup_type: FullName -> String
stringify_name_lookup_type nwt =
    case nwt of
        NameWithoutArgs n ->
            stringify_name n

        NameLookupType nlt ->
            stringify_name nlt.base ++ "[" ++ (
                nlt.args |>List.map stringify_name_lookup_type |> String.join ", "
            ) ++ "]"


type UnqualifiedTypeName
    = Basic Identifier
    | Generic Identifier (List UnqualifiedTypeName)
    | ReferenceUnqual UnqualifiedTypeName


make_reference_type : UnqualifiedTypeName -> UnqualifiedTypeName
make_reference_type ut =
    ReferenceUnqual ut


append_generic_name : UnqualifiedTypeName -> UnqualifiedTypeName -> UnqualifiedTypeName
append_generic_name me tn =
    case me of
        Basic n ->
            Generic n [ tn ]

        Generic n l ->
            Generic n (List.append l [ tn ])

        ReferenceUnqual u ->
            append_generic_name u tn


type alias UnqualifiedTypeWithName =
    { name : Identifier, typename : UnqualifiedTypeName }


-- make_qualified_typewithname : UnqualifiedTypeWithName -> Qualifier -> QualifiedTypeWithName
-- make_qualified_typewithname t q =
    -- QualifiedTypeWithName t.name (make_qualified_typename q t.typename)


type alias QualifiedTypeWithName =
    { name : Identifier, typename : FullName, qualifiedness : Qualifier }


type alias ASTFunctionHeader =
    { generic_args : List FullName, args : List FullName, return_type : Maybe FullName }


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


type ASTExpression
    = FunctionCallExpr ASTFunctionCall
    | LiteralExpr LiteralType String
    | NameWithArgsLookup FullName
    | Parenthesized ASTExpression
    | InfixExpr ASTExpression ASTExpression InfixOpType


type alias ASTFunctionCall =
    { fname : Identifier
    , args : List ASTExpression
    }



-- simple to strings with no additional info


-- stringify_type_name : TypeName -> String
-- stringify_type_name tn =
--     case tn of
--         VariableTypename n ->
--             stringify_utname n

--         ConstantTypename n ->
--             stringify_utname n

--         NonQualified n ->
--             stringify_utname n


-- stringify_utname : UnqualifiedTypeName -> String
-- stringify_utname utn =
--     case utn of
--         Basic n ->
--             stringify_name n

--         Generic n l ->
--             stringify_name n ++ "[" ++ (l |> List.map (\tn -> stringify_utname tn) |> String.join ", ") ++ "]"

--         ReferenceUnqual u ->
--             "&" ++ stringify_utname u


stringify_name : Identifier -> String
stringify_name n =
    case n of
        SingleIdentifier s ->
            s

        QualifiedIdentifiers l ->
            String.join "." l
