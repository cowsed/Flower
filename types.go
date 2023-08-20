package main

type Type interface {
	String() string
}

type TypeName struct {
	tname string
}

func (t TypeName) String() string {
	return t.tname
}

type NamedType struct {
	Type
	name string
}

func (n NamedType) String() string {
	return n.name + ": " + n.Type.String()
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

func (b BuiltinType) String() string {
	return []string{"UnknownBuiltinType ", "U8Type", "U16Type", "U32Type", "U64Type", "I8Type", "I16Type", "I32Type", "I64Type"}[b.Whichone]
}

type PointerType struct {
	To Type
}

type MutableType struct {
	base Type
}

type ConstrainedType struct {
	To         Type
	Constraint Expr
}

type InterfaceType struct{}

type FunctionType struct {
	args        []NamedType
	return_type Type
}

func (ft FunctionType) String() string {
	s := "("
	for i, arg := range ft.args {
		if i != 0 {
			s += ", "
		}
		s += arg.String()
	}
	s += ") -> "
	if ft.return_type == nil {
		s += "no return"
	} else {
		s += ft.return_type.String()
	}
	return s
}
