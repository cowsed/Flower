package main

type Type interface{}

type TypeName struct {
	name string
}

type NamedType struct {
	Type
	name string
}

type RecordType struct {
	fields []NamedType
}

type BuiltinTypeType uint

const (
	UnknownBuiltinType BuiltinTypeType = iota
	U8Type
	U16Type
	U32Type
	U64Type

	I8Type
	I16Type
	I32Type
	I64Type
)

type BuiltinType struct {
	Whichone BuiltinTypeType
}

type PointerType struct {
	To Type
}

type MutableType struct {
	base Type
}

type ConstrainedType struct {
	To         Type
	Constraint Expression
}

type InterfaceType struct{}

type FunctionType struct {
	args        []NamedType
	return_type Type
}
