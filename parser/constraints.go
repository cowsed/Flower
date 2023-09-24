package parser

type ConstrainedType struct {
	typ        Type
	constraint Expr
}

func (ct *ConstrainedType) String() string {

	return ct.typ.String() + " | _ ><><><"
}
