package parser

import "Flower/util"

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
