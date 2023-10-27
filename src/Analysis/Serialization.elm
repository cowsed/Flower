module Analysis.Serialization exposing (..)

import Analysis.Explanations exposing (stringify_floating_size, stringify_integer_size)
import Json.Decode as JD
import Json.Encode as JE
import Language.Language as Language exposing (FloatingPointSize, IntegerSize(..), TypeName(..))


encode_boolean : JE.Value
encode_boolean =
    JE.object [ ( "type_type", JE.string "boolean" ) ]


encode_integer : IntegerSize -> JE.Value
encode_integer s = 
    JE.object [ ( "type_type", JE.string "integer" ), ( "width", JE.string (stringify_integer_size s) ) ]


encode_floating_point : FloatingPointSize -> JE.Value
encode_floating_point s =
    JE.object [ ( "type_type", JE.string "floting_point" ), ( "width", JE.string (stringify_floating_size s) ) ]


encode_type : TypeName -> JE.Value
encode_type t =
    case t of

        IntegerType s ->
            encode_integer s

        FloatingPointType s ->
            encode_floating_point s

        _ ->
            Debug.todo "encode other types"


integer_from_size : String -> JD.Decoder TypeName
integer_from_size s =
    case s of
        "u8" ->
            U8 |> IntegerType |> JD.succeed

        "u16" ->
            U16 |> IntegerType |> JD.succeed

        "u32" ->
            U32 |> IntegerType |> JD.succeed

        "u64" ->
            U64 |> IntegerType |> JD.succeed

        "i8" ->
            I8 |> IntegerType |> JD.succeed

        "i16" ->
            I16 |> IntegerType |> JD.succeed

        "i32" ->
            I32 |> IntegerType |> JD.succeed

        "i64" ->
            I64 |> IntegerType |> JD.succeed

        _ ->
            JD.fail "invalid integer size"


integer_type_decoder : JD.Decoder Language.TypeName
integer_type_decoder =
    JD.field "width" JD.string |> JD.andThen (\s -> integer_from_size s)


type_from_descriminator : String -> JD.Decoder TypeName
type_from_descriminator s =
    case s of
        "integer" ->
            integer_type_decoder


        _ ->
            Debug.todo "Decode other types"


type_decoder : JD.Decoder TypeName
type_decoder =
    JD.field "type_type" JD.string
        |> JD.andThen type_from_descriminator


decode_type : String -> Result JD.Error TypeName
decode_type s =
    JD.decodeString type_decoder s


example_json : String
example_json =
    """
{
    "type_type": "integer",
    "width": "u8"
}
"""


run_test : String
run_test =
    Debug.toString (decode_type example_json)
