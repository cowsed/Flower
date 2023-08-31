package parser

type ReturnStatement struct {
	value Expr
}

func (r ReturnStatement) Validate(ctx *ValidationContext) {
	r.value.Validate(ctx)
	// TODO check that r.value's type matches current function
}

func (r ReturnStatement) String() string {
	return "  ReturnStatement {\n" + r.value.Indent("    ") + "\n  }"
}

type StandaloneExprStatement struct {
	e Expr
}

func (s StandaloneExprStatement) String() string {
	return "  StandaloneExpr {\n" + s.e.Indent("    ") + "\n  }"

}

func (s StandaloneExprStatement) Validate(ctx *ValidationContext) {
	s.e.Validate(ctx)
}

type AssignmentStatement struct {
	to   string
	from Expr
}

type InitilizationStatment struct {
	to   string
	from Expr
}

type Statement interface {
	String() string
	Validate(ctx *ValidationContext)
}
