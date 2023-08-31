package parser

import (
	"Flower/util"
	"fmt"
)

type SourceErrorAdaptor struct {
	err error
}

func (s SourceErrorAdaptor) SourceError(src []rune) string {
	return s.err.Error()
}

type WrongNumberFunctionArguments struct {
	expected  int
	got       int
	where     util.Range
	func_name FullName
	func_typ  FunctionType
}

func (w WrongNumberFunctionArguments) SourceError(src []rune) string {
	return util.HighlightedLine(src, w.where) + fmt.Sprintf("\nI expected %d arguments to %s but I got %d. %s%s", w.expected, w.func_name.String(), w.got, w.func_name.String(), w.func_typ.String())
}

type DuplicateNameError struct {
	where util.Range
}

func (d DuplicateNameError) SourceError(src []rune) string {
	return util.HighlightedLine(src, d.where) + "\nDuplicate name defined secondly here"
}

type WrongTypeForFunctionArgument struct {
	where          util.Range
	wanted, actual Type
}

func (w WrongTypeForFunctionArgument) SourceError(src []rune) string {
	return util.HighlightedLine(src, w.where) + "\nWrong type for function application. Wanted `" + w.wanted.String() + "` but got `" + w.actual.String() + "`"
}

type NameLookupFailed struct {
	name  FullName
	where util.Range
}

func (n NameLookupFailed) SourceError(src []rune) string {
	return util.HighlightedLine(src, n.where) + "\ncould not find name `" + n.name.String() + "`"
}
