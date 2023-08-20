package parser

import (
	"Flower/util"
	"fmt"
)

type Expr interface {
	Indent(ident string) string
	Validate(ctx *ValidationContext)
}

var _ Expr = LiteralExpr{}
var _ Expr = FunctionCall{}
var _ Expr = NameLookup{}

type FullName struct {
	names []string
	where util.Range
}

func (fn FullName) String() string {
	s := fn.names[0]
	for i := 1; i < len(fn.names); i++ {
		s += "."
		s += fn.names[i]
	}
	return s

}

type NameLookup struct {
	name FullName
}

func (nl NameLookup) Indent(indent string) string {
	return indent + "NameLookup{ " + nl.name.String() + " }"
}

func (nl NameLookup) Validate(ctx *ValidationContext) {
	if !ctx.HasName(nl.name) {
		ctx.EmitError(NameLookupFailed{
			name:  FullName{},
			where: util.Range{},
		})
	}
}

type LiteralType uint

const (
	UnknownLiteralType LiteralType = iota
	NumberLiteralType
	StringLiteralType
	BooleanLiteralType
)

func (l LiteralType) String() string {
	return []string{"UnknownLiteralType", "NumberLiteralType", "StringLiteralType", "BooleanLiteralType"}[l]

}

type LiteralExpr struct {
	literalType LiteralType
	str         string
}

func (l LiteralExpr) Validate(v *ValidationContext) {}

func (l LiteralExpr) Indent(ident string) string {
	return fmt.Sprintf(ident+"Literal Expr{ Type; %s, %s}", l.literalType.String(), l.str)
}

type FunctionCall struct {
	name   FullName
	args   []Expr
	closed bool
}

func (fc FunctionCall) Validate(v *ValidationContext) {}

func (fc FunctionCall) Indent(ident string) string {
	s := fmt.Sprintf(ident+"Function Call `%s` {\n", fc.name.String())
	for _, arg := range fc.args {
		s += arg.Indent(ident+"  ") + "\n"
	}
	s += ident + "}"
	return s
}

type RecordInstantiation struct{}

type InfixOp uint

const (
	UnknownInfixOp InfixOp = iota
	InfixPlus
	InfixSub
	InfixTimes
	InfixDivide
)

type InfixExpr struct {
	OpType InfixOp
	A, B   Expr
}
