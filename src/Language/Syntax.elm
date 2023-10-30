module Language.Syntax exposing (..)

type KeywordType
    = FnKeyword
    | ReturnKeyword
    | ModuleKeyword
    | ImportKeyword
    | VarKeyword
    | StructKeyword
    | IfKeyword
    | WhileKeyword
    | EnumKeyword
    | TypeKeyword

type LiteralType
    = NumberLiteral
    | StringLiteral
