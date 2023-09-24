package parser

import (
	"Flower/util"
	"fmt"
	"strings"
)

type Expr interface {
	Indent(ident string) string
	Type(ctx *ValidationContext) Type
	Validate(ctx *ValidationContext)
	Where() util.Range
}

var _ Expr = LiteralExpr{}
var _ Expr = FunctionCall{}
var _ Expr = NameLookup{}

type FullName struct {
	names []string
	where util.Range
}

func FullNameFromHashKey(str string) FullName {
	names := strings.Count(str, ".") + 1
	fn := FullName{
		names: make([]string, 0, names),
		where: util.Range{},
	}

	fn.names = append(fn.names, strings.Split(str, ".")...)
	return fn

}

func (fn FullName) HashKey() string {
	return fn.String()
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
	name        FullName
	looking_for NameLookupType
}

func (nl NameLookup) Where() util.Range {
	return nl.name.where
}

func (nl NameLookup) Indent(indent string) string {
	return indent + "NameLookup{ " + nl.name.String() + " }"
}

func (nl NameLookup) Validate(ctx *ValidationContext) {
	if !ctx.HasName(nl.name) {
		ctx.EmitError(NameLookupFailed{
			looking_for: nl.looking_for,
			name:        nl.name,
			where:       nl.name.where,
		})
	}
}

func (nl NameLookup) Type(ctx *ValidationContext) Type {
	if !ctx.HasName(nl.name) {
		ctx.EmitError(NameLookupFailed{
			looking_for: nl.looking_for,
			name:        nl.name,
			where:       nl.name.where,
		})
	}
	return ctx.TypeOfName(nl.name)

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
	where       util.Range
}

func (l LiteralExpr) Where() util.Range {
	return l.where
}

func (l LiteralExpr) Type(ctx *ValidationContext) Type {
	switch l.literalType {
	case NumberLiteralType:
		return BuiltinType{
			Whichone: BuiltinUnconstrainedIntType,
		}
	case StringLiteralType:
		return BuiltinType{
			Whichone: BuiltinStringType,
		}
	}
	return BuiltinType{UnknownBuiltinType}
}

func (l LiteralExpr) Validate(v *ValidationContext) {}

func (l LiteralExpr) Indent(ident string) string {
	return fmt.Sprintf(ident+"Literal Expr{ Type; %s, %s}", l.literalType.String(), l.str)
}

type FunctionCall struct {
	name   FullName
	args   []Expr
	closed bool

	where util.Range
}

func (fc FunctionCall) Where() util.Range {
	return fc.where
}

func (fc FunctionCall) Type(ctx *ValidationContext) Type {
	if !ctx.HasName(fc.name) {
		ctx.EmitError(NameLookupFailed{
			looking_for: FunctionLookupType,
			name:        fc.name,
			where:       fc.name.where,
		})
	}
	typ := ctx.TypeOfName(fc.name)
	ft := typ.(FunctionType)

	return ft.return_type
}

func is_builtin_cast(f FullName) bool {
	if len(f.names) > 1 {
		return false
	}
	switch f.names[0] {
	case "u8", "u16", "u32", "u64":
		return true
	case "i8", "i16", "i32", "i64":
		return true
	case "f32", "f64":
		return true
	}
	return false
}

func (func_call FunctionCall) Validate(ctx *ValidationContext) {

	if !ctx.HasName(func_call.name) {
		ctx.EmitError(NameLookupFailed{
			looking_for: FunctionLookupType,
			name:        func_call.name,
			where:       func_call.name.where,
		})
		return
	}

	typ := ctx.TypeOfName(func_call.name)
	if typ == nil {
		panic("has name and type of name contradict, compiler error")
	}
	func_typ := typ.(FunctionType)

	if len(func_call.args) != len(func_typ.args) {
		ctx.EmitError(WrongNumberFunctionArguments{
			expected:  len(func_typ.args),
			got:       len(func_call.args),
			where:     func_call.Where(),
			func_name: func_call.name,
			func_typ:  func_typ,
		})
		return
	}

	for i, arg := range func_call.args {
		arg.Validate(ctx)

		canbe, operation, err, warning := CanBeImplicitlyConvertedToType(arg.Type(ctx), func_typ.args[i].Type, arg, ctx)
		if warning != nil {
			ctx.EmitWarning(warning)
		}
		if err != nil {
			ctx.EmitError(err)
		}
		if operation != nil {
			// apply operation
		}
		if !canbe {
			ctx.EmitError(WrongTypeForFunctionArgument{
				where:  arg.Where(),
				wanted: func_typ.args[i].Type,
				actual: arg.Type(ctx),
			})
		}

	}
}

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
