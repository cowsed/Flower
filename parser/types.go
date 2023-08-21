package parser

import (
	"Flower/util"
)

type Type interface {
	String() string
}

func CanBeImplicitlyConvertedToType(from Type, to Type, from_expr Expr, ctx *ValidationContext) (bool, Expr, SourceError, SourceError) {
	from_builtin, from_is := from.(BuiltinType)
	to_builtin, to_is := to.(BuiltinType)

	if from_is && to_is {
		return BuiltinCanBeConvertedTo(from_builtin, to_builtin, from_expr)
	}

	// check for cast functions
	return false, nil, nil, nil
}

func BuiltinCanBeConvertedTo(from BuiltinType, to BuiltinType, from_expr Expr) (bool, Expr, SourceError, SourceError) {
	if from.Whichone == to.Whichone {
		return true, nil, nil, nil
	}
	if from.Whichone == BuiltinUnconstrainedIntType {
		if to.Whichone == BuiltinU8Type {
			return true, IntLiteralToIntType{}, nil, nil
		}
	}

	return false, nil, nil, nil
}

type IntLiteralToIntType struct {
	going_to BuiltinTypeType
	expr     LiteralExpr
}

// Indent implements Expr.
func (IntLiteralToIntType) Indent(ident string) string {
	panic("unimplemented")
}

// Type implements Expr.
func (i IntLiteralToIntType) Type(ctx *ValidationContext) Type {
	return BuiltinType{i.going_to}
}

// Validate implements Expr.
func (IntLiteralToIntType) Validate(ctx *ValidationContext) {
	panic("unimplemented")
}

// Where implements Expr.
func (i IntLiteralToIntType) Where() util.Range {
	return i.expr.Where()
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

	BuiltinBooleanType

	BuiltinU8Type
	BuiltinU16Type
	BuiltinU32Type
	BuiltinU64Type

	BuiltinI8Type
	BuiltinI16Type
	BuiltinI32Type
	BuiltinI64Type

	BuiltinUnconstrainedIntType

	BuiltinStringType
)

type BuiltinType struct {
	Whichone BuiltinTypeType
}

func (b BuiltinType) String() string {
	return []string{"UnknownBuiltinType", "BuiltinBooleanType", "BuiltinU8Type", "BuiltinU16Type", "BuiltinU32Type", "BuiltinU64Type", "BuiltinI8Type", "BuiltinI16Type", "BuiltinI32Type", "BuiltinI64Type", "BuiltinUnconstrainedIntType", "BuiltinStringType"}[b.Whichone]

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
