module Language.Language exposing (..)


type Identifier
    = SingleIdentifier String -- name
    | QualifiedIdentifiers (List String) -- name.b.c


type FloatingPointSize
    = F32
    | F64


type IntegerSize
    = U8
    | U16
    | U32
    | U64
    | I8
    | I16
    | I32
    | I64


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
    | And
    | Or
    | Xor


stringify_identifier : Identifier -> String
stringify_identifier n =
    case n of
        SingleIdentifier s ->
            s

        QualifiedIdentifiers l ->
            String.join "." l


type LiteralType
    = BooleanLiteral
    | NumberLiteral
    | StringLiteral


type Type
    = BooleanType
    | IntegerType IntegerSize
    | FloatingPointType FloatingPointSize
    | StringType
    | FunctionType FunctionHeader
    | NamedType Identifier TypeOfTypeDefinition
    | GenericInstantiation Identifier TypeOfTypeDefinition (List Type)


type Qualifier
    = Variable
    | Constant


type alias QualifiedType =
    { qual : Qualifier, typ : Type }


type OuterType
    = Generic Identifier TypeOfTypeDefinition (List TypeType)
    | StructOuterType Identifier
    | EnumOuterType Identifier
    | AliasOuterType Identifier Type


type ReasonForUninstantiable
    = WrongNumber


type TypeType -- analagous to c++ concepts. constrain on type
    = Any String


is_generic_instantiable_with : TypeOfTypeDefinition -> List TypeType -> List Type -> Maybe ReasonForUninstantiable
is_generic_instantiable_with _ gen_args used_args =
    if List.length gen_args /= List.length used_args then
        Just WrongNumber

    else
        Nothing


type_of_non_generic_outer_type : OuterType -> Maybe TypeOfTypeDefinition
type_of_non_generic_outer_type ot =
    case ot of
        Generic _ _ _ ->
            Nothing

        StructOuterType _ ->
            Just StructDefinitionType

        AliasOuterType _ _ ->
            Just AliasDefinitionType

        EnumOuterType _ ->
            Just EnumDefinitionType


get_id : OuterType -> Identifier
get_id ot =
    case ot of
        Generic id _ _ ->
            id

        StructOuterType id ->
            id

        EnumOuterType id ->
            id

        AliasOuterType id _ ->
            id


type TypeOfTypeDefinition
    = StructDefinitionType
    | EnumDefinitionType
    | AliasDefinitionType


type alias FunctionHeader =
    { args : List QualifiedType, rtype : Maybe Type }


type alias ValueNameAndType =
    { name : Identifier
    , typ : Type
    }


qualify_vnt_name : String -> ValueNameAndType -> ValueNameAndType
qualify_vnt_name s vnt =
    { vnt | name = prepend_identifier s vnt.name }


qualify_type_name : String -> OuterType -> OuterType
qualify_type_name s ot =
    case ot of
        Generic id t args ->
            Generic (prepend_identifier s id) t args

        StructOuterType id ->
            StructOuterType (prepend_identifier s id)

        EnumOuterType id ->
            EnumOuterType (prepend_identifier s id)

        AliasOuterType id t ->
            AliasOuterType (prepend_identifier s id) t


type alias StructDefinition =
    { name : Identifier
    , fields : List ValueNameAndType
    }


prepend_identifier : String -> Identifier -> Identifier
prepend_identifier s i =
    case i of
        SingleIdentifier n ->
            QualifiedIdentifiers [ s, n ]

        QualifiedIdentifiers l ->
            QualifiedIdentifiers (s :: l)


builtin_type_from_name : String -> Maybe Type
builtin_type_from_name s =
    case s of
        "u8" ->
            IntegerType U8 |> Just

        "u16" ->
            IntegerType U16 |> Just

        "u32" ->
            IntegerType U32 |> Just

        "u64" ->
            IntegerType U64 |> Just

        "i8" ->
            IntegerType I8 |> Just

        "i16" ->
            IntegerType I16 |> Just

        "i32" ->
            IntegerType I32 |> Just

        "i64" ->
            IntegerType I64 |> Just

        "string" ->
            StringType |> Just

        _ ->
            Nothing



-- bunch of types aliased to themselves cuz theyre builtin. Definition is in the language


builtin_types : List OuterType
builtin_types =
    [ AliasOuterType (SingleIdentifier "bool") BooleanType
    , AliasOuterType (SingleIdentifier "str") StringType
    , AliasOuterType (SingleIdentifier "u8") (IntegerType U8)
    , AliasOuterType (SingleIdentifier "u16") (IntegerType U16)
    , AliasOuterType (SingleIdentifier "u32") (IntegerType U32)
    , AliasOuterType (SingleIdentifier "u64") (IntegerType U64)
    , AliasOuterType (SingleIdentifier "i8") (IntegerType I8)
    , AliasOuterType (SingleIdentifier "i16") (IntegerType I16)
    , AliasOuterType (SingleIdentifier "i32") (IntegerType I32)
    , AliasOuterType (SingleIdentifier "i64") (IntegerType I64)
    , AliasOuterType (SingleIdentifier "f32") (FloatingPointType F32)
    , AliasOuterType (SingleIdentifier "f64") (FloatingPointType F64)
    ]


extract_builtins : Type -> Type
extract_builtins t =
    case t of
        NamedType id tot ->
            if tot == AliasDefinitionType then
                case id of
                    SingleIdentifier s ->
                        builtin_type_from_name s |> Maybe.withDefault t

                    _ ->
                        t

            else
                t

        _ ->
            t


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

        And ->
            0

        Or ->
            0

        Xor ->
            0


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

        And ->
            "and"

        Or ->
            "or"

        Xor ->
            "xor"
