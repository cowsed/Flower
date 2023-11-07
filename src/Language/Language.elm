module Language.Language exposing (..)

import Json.Decode exposing (Value)


type Identifier
    = SingleIdentifier String -- name
    | QualifiedIdentifiers (List String) -- name.b.c


si : String -> Identifier
si s =
    SingleIdentifier s


stringify_identifier : Identifier -> String
stringify_identifier n =
    case n of
        SingleIdentifier s ->
            s

        QualifiedIdentifiers l ->
            String.join "." l


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
    | Uint -- crash on overflow/underflow
    | Int -- crash on overflow/underflow


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


type Qualifier
    = Variable
    | Constant


type alias GenericTypeDefinition =
    List TypeName -> Result ReasonForUninstantiable TypeDefinition



-- like what you would use as a type of a function argument, type of a structure field, etc


type alias Named a =
    { name : Identifier, value : a }


type alias SimpleNamed a =
    { name : String, value : a }


named_get : Named a -> a
named_get nt =
    nt.value


named_name : Named a -> Identifier
named_name nt =
    nt.name


snamed_get : SimpleNamed a -> a
snamed_get nt =
    nt.value


snamed_name : SimpleNamed a -> String
snamed_name nt =
    nt.name


type Value
    = IntegerValue IntegerSize Int
    | FloatingPointValue FloatingPointSize Float
    | StructValue { definition : TypeDefinition, fields : List (Named Value) }
    | EnumValue


values_type : Value -> TypeName
values_type v =
    case v of
        IntegerValue is _ ->
            IntegerType is

        FloatingPointValue _ _ ->
            Debug.todo "branch 'FloatingPointValue _ _' not implemented"

        StructValue _ ->
            Debug.todo "branch 'StructValue _' not implemented"

        EnumValue ->
            Debug.todo "branch 'EnumValue' not implemented"


type TypeName
    = IntegerType IntegerSize
    | FloatingPointType FloatingPointSize
    | FunctionType FunctionHeader
    | CustomTypeName Identifier
    | GenericInstantiation Identifier (List TypeName)


type alias QualifiedTypeName =
    { qual : Qualifier, typ : TypeName }


type TypeOfCustomType
    = StructType
    | EnumType
    | AliasType


type ReasonForUninstantiable
    = WrongNumber


type
    TypeType
    -- analagous to c++ concepts. constrain on type
    = Any String


is_generic_instantiable_with : TypeDefinition -> List TypeType -> List TypeName -> Maybe ReasonForUninstantiable
is_generic_instantiable_with _ gen_args used_args =
    if List.length gen_args /= List.length used_args then
        Just WrongNumber

    else
        Nothing


type TypeDefinition
    = IntegerDefinitionType IntegerSize
    | StructDefinitionType StructDefinition
    | EnumDefinitionType (List EnumTagDefinition)
    | AliasDefinitionType AliasDefinition


type alias AliasDefinition =
    { to : TypeName }


type alias StructDefinition =
    { fields : List (SimpleNamed TypeDefinition)
    }


type EnumTagDefinition
    = JustTag String
    | TagAndTypes String (List TypeName)


type alias FunctionHeader =
    { args : List QualifiedTypeName, rtype : Maybe TypeName }


qualify_vnt_name : String -> Named TypeName -> Named TypeName
qualify_vnt_name s vnt =
    { vnt | name = prepend_identifier s vnt.name }



-- qualify_type_name : String -> CustomOuterType -> CustomOuterType
-- qualify_type_name s ot =
--     case ot of
--         Generic id t args ->
--             Generic (prepend_identifier s id) t args
--         StructOuterType id ->
--             StructOuterType (prepend_identifier s id)
--         EnumOuterType id ->
--             EnumOuterType (prepend_identifier s id)
--         AliasOuterType id t ->
--             AliasOuterType (prepend_identifier s id) t


prepend_identifier : String -> Identifier -> Identifier
prepend_identifier s i =
    case i of
        SingleIdentifier n ->
            QualifiedIdentifiers [ s, n ]

        QualifiedIdentifiers l ->
            QualifiedIdentifiers (s :: l)


builtin_type_from_name : String -> Maybe TypeName
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

        "int" ->
            IntegerType Int |> Just

        "uint" ->
            IntegerType Uint |> Just

        "f32" ->
            FloatingPointType F32 |> Just

        "f64" ->
            FloatingPointType F64 |> Just

        _ ->
            Nothing


integer_size_name : IntegerSize -> String
integer_size_name i =
    case i of
        U8 ->
            "u8"

        U16 ->
            "u16"

        U32 ->
            "u32"

        U64 ->
            "u64"

        I8 ->
            "i8"

        I16 ->
            "i16"

        I32 ->
            "i32"

        I64 ->
            "i64"

        Int ->
            "int"

        Uint ->
            "uint"


integers_types : { i8 : TypeDefinition, i16 : TypeDefinition, i32 : TypeDefinition, i64 : TypeDefinition, u8 : TypeDefinition, u16 : TypeDefinition, u32 : TypeDefinition, u64 : TypeDefinition }
integers_types =
    { i8 = IntegerDefinitionType I8
    , i16 = IntegerDefinitionType I16
    , i32 = IntegerDefinitionType I32
    , i64 = IntegerDefinitionType I64
    , u8 = IntegerDefinitionType U8
    , u16 = IntegerDefinitionType U16
    , u32 = IntegerDefinitionType U32
    , u64 = IntegerDefinitionType U64
    }


integer_sizes : List IntegerSize
integer_sizes =
    [ U8, U16, U32, U64, Uint, I8, I16, I32, I64, Int ]



-- bunch of types aliased to themselves cuz theyre builtin. Definition is in the language




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
