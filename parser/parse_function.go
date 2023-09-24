package parser

import (
	"Flower/lexer"
)

// =============== Signature ===============
func FDef_FuncNamer(tok lexer.Token, pt *ProgramTree) ParseFunc {
	if tok.Tok != lexer.SymbolToken {
		// have to give up
		pt.EmitErrorFatal(FunctionNeedsNameError{})
		return nil
	}

	pt.workingName = tok.Str
	pt.workingFunction = FunctionDefinition{
		ftype:      FunctionType{},
		statements: []Statement{},
	}
	return FDef_TakeSigOpenningParen
}
func FDef_TakeSigOpenningParen(tok lexer.Token, pt *ProgramTree) ParseFunc {
	if tok.Tok != lexer.OpenParenToken {
		pt.EmitErrorFatal(FunctionNeedsOpenningParen{})
	}
	return FDef_GetFuncDefinitionParamName
}
func FDef_GetFuncDefinitionParamName(tok lexer.Token, pt *ProgramTree) ParseFunc {
	if tok.Tok == lexer.CloseParenToken {
		// foo()
		return FDef_ParseReturnTypeOrReadBody
	} else if tok.Tok != lexer.SymbolToken {
		pt.EmitError(ExpectedNameForFuncParam{where: tok.Where})
	}
	pt.workingFunction.ftype.args = append(pt.workingFunction.ftype.args, NamedType{
		Type: nil,
		name: tok.Str,
	})
	return FDef_ParamTypeOrEndParamList
}

func FDef_ParamTypeOrEndParamList(tok lexer.Token, pt *ProgramTree) ParseFunc {
	if tok.Tok == lexer.CommaToken {
		return FDef_GetFuncDefinitionParamName
	} else if tok.Tok == lexer.TypeSpecifierToken {
		return NewParseType(func(t Type) {
			pt.workingFunction.ftype.args[len(pt.workingFunction.ftype.args)-1].Type = t
		}, ContinueOrEndParamList)

	} else if tok.Tok == lexer.CloseParenToken {
		return FDef_ParseReturnTypeOrReadBody
	}
	pt.EmitErrorFatal(UnexpectedThingInParameterList{tok.Where})
	return nil
}

func FDef_ParseReturnTypeOrReadBody(tok lexer.Token, pt *ProgramTree) ParseFunc {
	if tok.Tok == lexer.ReturnsToken {
		return NewParseType(func(t Type) { pt.workingFunction.ftype.return_type = t }, FDef_ParseFuncBodyOpenCurly)
	} else if tok.Tok == lexer.OpenCurlyToken {
		return FDef_ParseFuncStatements
	}
	pt.EmitErrorFatal(UnexpectedThingInReturn{tok.Where})
	return nil
}

// ===============   Function Body  ===============
func FDef_ParseFuncBodyOpenCurly(tok lexer.Token, pt *ProgramTree) ParseFunc {
	if tok.Tok == lexer.OpenCurlyToken {
		return FDef_ParseFuncStatements
	}
	pt.EmitErrorFatal(UnexpectedThingInReturn{tok.Where})
	return nil
}

func FDef_ParseFuncStatements(tok lexer.Token, pt *ProgramTree) ParseFunc {
	if tok.Tok == lexer.CloseCurlyToken {
		// finished
		pt.global_functions[pt.workingName] = pt.workingFunction

		pt.workingFunction = FunctionDefinition{}
		pt.workingName = ""

		return nil // finished
	} else if tok.Tok == lexer.ReturnKeywordToken {
		return NewParseExpr(func(e Expr) ParseFunc {
			pt.workingFunction.statements = append(pt.workingFunction.statements, ReturnStatement{e})
			return FDef_ParseFuncStatements
		})
	} else if tok.Tok == lexer.NewlineToken {
		return FDef_ParseFuncStatements
	} else if tok.Tok == lexer.SymbolToken {
		return NewParseExpr(func(e Expr) ParseFunc {
			pt.workingFunction.statements = append(pt.workingFunction.statements, StandaloneExprStatement{e})
			return FDef_ParseFuncStatements
		})(tok, pt)
	}

	pt.EmitErrorFatal(UnimplementedError{
		where: tok.Where,
	})
	return FDef_ParseFuncStatements
}
