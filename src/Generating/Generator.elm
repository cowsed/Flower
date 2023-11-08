module Generating.Generator exposing (..)

import Analysis.Analyzer exposing (GoodProgram)
import Language.Language as Language exposing (FunctionHeader, Identifier(..), IntegerSize(..), QualifiedTypeName, TypeName(..), values_type)


type alias LLVM =
    { src : String
    }


generate : GoodProgram -> LLVM
generate gp =
    let
        forward_declarations_header =
            "; Forward Declarations\n\n"

        definitions_header =
            "\n\n; Function Definitions\n"

        add_if_func_def : Language.Named Language.Value -> List { name : String, fheader : FunctionHeader } -> List { name : String, fheader : FunctionHeader }
        add_if_func_def name_and_val l =
            case name_and_val.value |> values_type of
                FunctionType fheader ->
                    List.append l [ { name = mangle_name name_and_val.name, fheader = fheader } ]

                _ ->
                    l

        forward_declarations =
            "odfl"

        -- forward_declarations_header ++ (List.map llvm_forward_declaration func_headers |> String.join "\n")
    in
    LLVM (forward_declarations ++ definitions_header)


mangle_name : Identifier -> String
mangle_name id =
    case id of
        SingleIdentifier s ->
            s

        QualifiedIdentifiers ls ->
            String.join "_" ls


llvm_forward_declaration : { name : String, fheader : FunctionHeader } -> String
llvm_forward_declaration nf =
    let
        name =
            nf.name

        fheader =
            nf.fheader

        args =
            nf.fheader.args |> List.map llvm_qualled_type |> String.join ","
    in
    "declare " ++ llvm_ret_type_name fheader.rtype ++ " @" ++ name ++ "(" ++ args ++ ")"


llvm_type_declaration : TypeName -> String
llvm_type_declaration typ =
    case typ of
        Language.IntegerType _ ->
            Debug.log "Declaring builting type, shoudlnt happen" ""

        Language.FloatingPointType _ ->
            Debug.log "Declaring builting type, shoudlnt happen" ""

        _ ->
            Debug.todo "Other Type Declarations"


llvm_ret_type_name : Maybe TypeName -> String
llvm_ret_type_name mtyp =
    case mtyp of
        Just typ ->
            llvm_type_name typ

        Nothing ->
            "void"


llvm_type_name : TypeName -> String
llvm_type_name typ =
    case typ of
        IntegerType size ->
            llvm_integer_size size

        _ ->
            "SOME TYPE IDK MAN"


llvm_integer_size : Language.IntegerSize -> String
llvm_integer_size size =
    case size of
        Language.U8 ->
            "u8"

        Language.U16 ->
            "u16"

        Language.U32 ->
            "u32"

        Language.U64 ->
            "u64"

        Language.I8 ->
            "i8"

        Language.I16 ->
            "i16"

        Language.I32 ->
            "i32"

        Language.I64 ->
            "i64"

        Language.Uint ->
            "u64"

        Language.Int ->
            "i64"


llvm_qualled_type : QualifiedTypeName -> String
llvm_qualled_type qt =
    llvm_type_name qt.typ
