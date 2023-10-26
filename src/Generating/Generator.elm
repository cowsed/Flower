module Generating.Generator exposing (..)

import Analysis.Analyzer exposing (GoodProgram)
import Language.Language as Language exposing (FunctionHeader, Identifier(..), QualifiedType, Type(..))


type alias LLVM =
    { src : String
    }


generate : GoodProgram -> LLVM
generate gp =
    let
        forward_declarations_header =
            "; Forward Declarations\n"

        definitions_header =
            "; Function Definitions\n"

        add_if_func_def : Language.ValueNameAndType -> List { name : String, fheader : FunctionHeader } -> List { name : String, fheader : FunctionHeader }
        add_if_func_def name_and_val l =
            case name_and_val.typ of
                FunctionType fheader ->
                    List.append l [ { name = mangle_name name_and_val.name, fheader = fheader } ]

                _ ->
                    l

        func_headers =
            List.foldl add_if_func_def [] gp.outer_scope.values

        forward_declarations =
            forward_declarations_header ++ (List.map llvm_forward_declaration func_headers |> String.join "\n")
    in
    LLVM (forward_declarations ++ definitions_header)


mangle_name : Identifier -> String
mangle_name id =
    case id of
        SingleIdentifier s ->
            s

        QualifiedIdentifiers ls ->
            Debug.todo "branch 'QualifiedIdentifiers _' not implemented"


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
    "declare " ++ llvm_ret_type fheader.rtype ++ " @" ++ name ++ "(" ++ args ++ ")"


llvm_ret_type : Maybe Type -> String
llvm_ret_type mtyp =
    case mtyp of
        Just typ ->
            llvm_type typ

        Nothing ->
            "void"


llvm_type : Type -> String
llvm_type typ =
    case typ of 
        IntegerType size -> llvm_integer_size size
        _ -> Debug.todo "Implement this"



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



llvm_qualled_type : QualifiedType -> String
llvm_qualled_type qt =
    llvm_type qt.typ
