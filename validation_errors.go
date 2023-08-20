package main

import "Flower/util"

type NameLookupFailed struct {
	name  FullName
	where util.Range
}

func (n NameLookupFailed) SourceError(src []rune) string {
	return util.HighlightedLine(src, n.where) + "\n could not find name `" + n.name.String() + "`"
}
