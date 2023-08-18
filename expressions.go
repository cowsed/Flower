package main

type Expression interface{}

type FunctionCall struct{}

type RecordInstantiation struct{}

type InfixOp uint

const (
	InfixPlus InfixOp = iota
	InfixSub
	InfixTimes
	InfixDivide
)

type InfixExpr struct {
	OpType InfixOp
	A, B   Expression
}
