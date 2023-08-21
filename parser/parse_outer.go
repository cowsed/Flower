package parser

import "Flower/lexer"

func FindingParse(tok lexer.Token, pt *ProgramTree) ParseFunc {
	if tok.Tok == lexer.ModuleToken {
		return ModuleNamer
	}
	if tok.Tok == lexer.ImportToken {
		return ImportNamer
	}
	if tok.Tok == lexer.FnToken {
		return FDef_FuncNamer
	}
	return nil
}
