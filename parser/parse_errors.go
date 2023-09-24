package parser

import (
	"Flower/util"
	"fmt"
)

type UnexpectedEOF struct{}

func (u UnexpectedEOF) SourceError(src []rune) string {
	return "File ended where I did not expect it ¯\\_(ツ)_/¯"
}

type TooManyExpressions struct {
	where util.Range
}

func (t TooManyExpressions) SourceError(src []rune) string {
	return util.HighlightedLine(src, t.where) + "\nFinished parsing line but ended up with more than one expression, not really sure what to do here"
}

type ExtraneousClosingParen struct {
	where util.Range
}

func (e ExtraneousClosingParen) SourceError(src []rune) string {
	return util.HighlightedLine(src, e.where) + "\nClosing paren (end of function call) but no open function"
}

type UnfinishedFullName struct {
	where util.Range
}

func (u UnfinishedFullName) SourceError(src []rune) string {
	return util.HighlightedLine(src, u.where) + "\nI thought I was parsing a name like std.thing.a but stopped after `.`"
}

type NoFunctionToAddArgsTo struct {
	where util.Range
}

func (n NoFunctionToAddArgsTo) SourceError(src []rune) string {
	return util.HighlightedLine(src, n.where) + "\nI thought I was parsing a function call but there isnt one here"
}

type UnimplementedError struct {
	where util.Range
}

func (u UnimplementedError) SourceError(src []rune) string {
	return util.HighlightedLine(src, u.where) + "\n" + "I havent implemented that yet"
}

type UnexpectedThingInReturn struct {
	where util.Range
}

func (u UnexpectedThingInReturn) SourceError(src []rune) string {
	return util.HighlightedLine(src, u.where) + "\n" + "I dont know whats going on here help. I was tryna parse a function return header tho"
}

type UnexpectedThingInParameterList struct {
	where util.Range
}

func (u UnexpectedThingInParameterList) SourceError(src []rune) string {
	return util.HighlightedLine(src, u.where) + "\n" + "I dont know whats going on here help. I was tryna parse a function header tho"
}

type TypeMustBeAName struct {
	where util.Range
}

func (t TypeMustBeAName) SourceError(src []rune) string {
	return util.HighlightedLine(src, t.where) + "\n" + "type must be a name not whatever this is. like fn foo(a: Baz)"
}

type ExpectedNameForFuncParam struct {
	where util.Range
}

func (e ExpectedNameForFuncParam) SourceError(src []rune) string {
	return util.HighlightedLine(src, e.where) + "\n" + "expected parameter name like `fn foo(name: type)"
}

type FunctionNeedsOpenningParen struct{}

func (f FunctionNeedsOpenningParen) SourceError(src []rune) string {
	return "function needs openning paren `fn foo()"
}

type FunctionNeedsNameError struct{}

func (f FunctionNeedsNameError) SourceError(src []rune) string {
	return "function needs name"
}

type ExpectedEndOfLine struct {
	reason string
}

func (e ExpectedEndOfLine) SourceError(src []rune) string {
	return fmt.Sprintf("Expected end of line, not this stuff because %s", e.reason)
}

type ImportMustBeStringError struct{}

func (i ImportMustBeStringError) SourceError(src []rune) string {
	return "Input must be a string literal like \"std\""
}

type ImportNeedsNameError struct{}

func (i ImportNeedsNameError) SourceError(src []rune) string {
	return "Import Needs a name. should look like `import \"std\"`"
}

type ModuleNeedsNameError struct {
	where util.Range
}

func (m ModuleNeedsNameError) SourceError(src []rune) string {
	return util.HighlightedLine(src, m.where) + "\nModule Needs a name. If this is the main module try `module main`"
}

type ModuleNameMustBeWordError struct{}

func (m ModuleNameMustBeWordError) SourceError(src []rune) string {
	return "Module Needs a name that is a word not a number or other symbol."
}

type MultipleDefinitionsOfModuleError struct{}

func (m MultipleDefinitionsOfModuleError) SourceError(src []rune) string {
	return "the module keyword can only be used in one place since modules can only have one name"
}
