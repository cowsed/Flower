package parser

import (
	"Flower/lexer"
	"Flower/util"
	"fmt"

	"github.com/fatih/color"
)

type FunctionDefinition struct {
	ftype      FunctionType
	statements []Statement
}

func (fd FunctionDefinition) String() string {
	s := "Function " + fd.ftype.String() + "\n"
	for _, statement := range fd.statements {
		s += statement.String() + "\n"
	}
	return s
}

func (f FunctionDefinition) Validate(ctx *ValidationContext) {
	for _, statement := range f.statements {
		statement.Validate(ctx)
	}
	// insure type of return statement matches that of function signature
}

type ProgramTree struct {
	module_name string
	imports     []string

	// All globals are order independent
	globals          map[string]Expr
	global_structs   map[string]RecordType
	global_functions map[string]FunctionDefinition

	workingName     string
	workingFunction FunctionDefinition

	workingExpression util.Stack[Expr]

	src []rune

	fatal  bool
	errors []SourceError
	valid  bool
}

func (pt *ProgramTree) FinishFuncCall(where util.Range) {
	args := []Expr{}
	for {
		if pt.workingExpression.Size() == 0 {
			pt.EmitErrorFatal(ExtraneousClosingParen{where})
			return
		}

		end := pt.workingExpression.Pop()
		fmt.Printf("Arg: %T: %+v\n", end, end)
		switch e := end.(type) {
		case FunctionCall:
			if e.closed {
				args = append([]Expr{end}, args...)
			} else {
				e.args = args
				e.closed = true
				pt.workingExpression.Push(e)
				fmt.Println("end")
				return
			}
		default:
			args = append([]Expr{end}, args...)
		}
	}

}

func (pt ProgramTree) Print(src []rune) {
	if !pt.valid {
		fmt.Println("Invalid Program")
		fmt.Println("errs:")
		for _, e := range pt.errors {
			color.Red("%s", e.SourceError(src))
		}
		return
	}
	fmt.Print("Parsed Program:\n\n")
	fmt.Println("module:", pt.module_name)
	fmt.Println("\nImports:")
	for _, im := range pt.imports {
		fmt.Println(im)
	}
	fmt.Println("\nFunctions:")
	for name, function := range pt.global_functions {
		fmt.Printf("%s: %++v\n", name, function)
	}
}

func (pt *ProgramTree) EmitError(err SourceError) {
	pt.errors = append(pt.errors, err)
	pt.valid = false
}
func (pt *ProgramTree) EmitErrorFatal(err SourceError) {
	pt.errors = append(pt.errors, err)
	pt.valid = false
	pt.fatal = true
}

type ParseFunc func(tok lexer.Token, pt *ProgramTree) ParseFunc

func Parse(toks chan lexer.Token, lex_errs chan error, src []rune) ProgramTree {
	var pt ProgramTree = ProgramTree{
		module_name:       "",
		imports:           []string{},
		globals:           map[string]Expr{},
		global_structs:    map[string]RecordType{},
		global_functions:  map[string]FunctionDefinition{},
		workingName:       "",
		workingFunction:   FunctionDefinition{},
		workingExpression: util.Stack[Expr]{},
		src:               src,
		fatal:             false,
		errors:            []SourceError{},
		valid:             true,
	}

	var state ParseFunc = nil

	for tok := range toks {
		// Read lex errors
		if len(lex_errs) != 0 {
			e := <-lex_errs
			color.Red("Lex Error: %s", e.Error())
			pt.valid = false
			return pt
		}

		if pt.fatal {
			color.Red("FATAL PARSE ERROR")
			break
		}

		fmt.Println("Token:", tok)

		if tok.Tok == lexer.EOFToken && state != nil {
			// ended halfway through
		} else if state != nil {
			state = state(tok, &pt)
		} else {
			state = FindingParse(tok, &pt)
		}

	}
	return pt
}
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

// Function Parsing ====================================================================================

// Signature
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

func FDef_ParseFuncBodyOpenCurly(tok lexer.Token, pt *ProgramTree) ParseFunc {
	if tok.Tok == lexer.OpenCurlyToken {
		color.Green("start func body")
		return FDef_ParseFuncStatements
	}
	pt.EmitErrorFatal(UnexpectedThingInReturn{tok.Where})
	return nil
}

func FDef_ParseFuncStatements(tok lexer.Token, pt *ProgramTree) ParseFunc {
	if tok.Tok == lexer.CloseCurlyToken {
		// finished
		pt.global_functions[pt.workingName] = pt.workingFunction
		color.Green("finished parsing func %s", pt.workingName)

		pt.workingFunction = FunctionDefinition{}
		pt.workingName = ""

		return nil // finished
	} else if tok.Tok == lexer.ReturnKeywordToken {
		color.Green("return Statement")
		return NewParseExpr(func(e Expr) ParseFunc {
			color.Green("return Expr over")
			pt.workingFunction.statements = append(pt.workingFunction.statements, ReturnStatement{e})
			return FDef_ParseFuncStatements
		})
	} else if tok.Tok == lexer.NewlineToken {
		color.Green("Newline")
		return FDef_ParseFuncStatements
	} else if tok.Tok == lexer.SymbolToken {
		color.Cyan("Just a standalone expression")
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

func NewParseExpr(setter func(e Expr) ParseFunc) ParseFunc {
	return func(tok lexer.Token, pt *ProgramTree) ParseFunc {
		return ParseExpr(tok, pt, setter)
	}
}

func ParseExpr(tok lexer.Token, pt *ProgramTree, setter func(e Expr) ParseFunc) ParseFunc {
	switch tok.Tok {
	// number
	case lexer.NumberLiteralToken:
		color.Yellow("saw Number Literal")
		pt.workingExpression.Push(LiteralExpr{
			literalType: NumberLiteralType,
			str:         tok.Str,
		})
		return NewContinueOrEndExpression(setter)

	// string
	case lexer.StringLiteralToken:

		pt.workingExpression.Push(LiteralExpr{
			literalType: StringLiteralType,
			str:         tok.Str,
		})
		return NewContinueOrEndExpression(setter)

	case lexer.BooleanLiteralToken:
		pt.workingExpression.Push(LiteralExpr{
			literalType: BooleanLiteralType,
			str:         tok.Str,
		})
		return NewContinueOrEndExpression(setter)
	case lexer.SymbolToken:
		color.Cyan("saw symbol")
		return NewValueLookupOrFunctionCall(FullName{
			names: []string{tok.Str},
		}, setter)
	}

	pt.EmitErrorFatal(UnimplementedError{tok.Where})
	return nil
}

func NewValueLookupOrFunctionCall(name_so_far FullName, setter func(e Expr) ParseFunc) ParseFunc {
	return func(tok lexer.Token, pt *ProgramTree) ParseFunc {
		return ValueLookupOrFunctionCall(tok, pt, name_so_far, setter)
	}
}

func ValueLookupOrFunctionCall(tok lexer.Token, pt *ProgramTree, name_so_far FullName, setter func(e Expr) ParseFunc) ParseFunc {
	if tok.Tok == lexer.OpenParenToken {
		color.Yellow("was function call")
		pt.workingExpression.Push(FunctionCall{
			name:   name_so_far,
			args:   []Expr{},
			closed: false,
		})
		return NewParseExpr(
			func(e Expr) ParseFunc {
				pt.workingExpression.Push(e)
				return NewContinueOrEndExpression(setter)
			})
	} else if tok.Tok == lexer.DotToken {
		// continue taking name
		return NewGrowFullName(name_so_far, setter)

	}
	color.Cyan("Finished looking at name. not function or longer")
	pt.workingExpression.Push(NameLookup{name_so_far})
	return NewContinueOrEndExpression(setter)(tok, pt)
}

func NewGrowFullName(name_so_far FullName, setter func(e Expr) ParseFunc) ParseFunc {
	return func(tok lexer.Token, pt *ProgramTree) ParseFunc {
		if tok.Tok != lexer.SymbolToken {
			pt.EmitError(UnfinishedFullName{where: tok.Where})
			return ValueLookupOrFunctionCall(tok, pt, name_so_far, setter)
		}
		name_so_far.names = append(name_so_far.names, tok.Str)
		return NewValueLookupOrFunctionCall(name_so_far, setter)
	}
}

func NewContinueOrEndExpression(setter func(e Expr) ParseFunc) ParseFunc {
	return func(tok lexer.Token, pt *ProgramTree) ParseFunc {
		return ContinueOrEndExpression(tok, pt, setter)
	}
}

func ContinueOrEndExpression(tok lexer.Token, pt *ProgramTree, setter func(e Expr) ParseFunc) ParseFunc {
	if tok.Tok == lexer.CommentToken || tok.Tok == lexer.NewlineToken {
		if pt.workingExpression.Size() != 1 {
			pt.EmitError(TooManyExpressions{tok.Where})
		}
		return setter(pt.workingExpression.Pop())(tok, pt)
	} else if tok.Tok == lexer.CloseParenToken {
		pt.FinishFuncCall(tok.Where)
		return NewContinueOrEndExpression(setter)
	} else if tok.Tok == lexer.CommaToken {
		return NewParseExpr(func(e Expr) ParseFunc {
			pt.workingExpression.Push(e)
			return NewContinueOrEndExpression(setter)
		})
	}
	// } else if isInfixOp(tok.Tok) {
	// }
	return NewContinueOrEndExpression(setter)

}

func isInfixOp(tok lexer.TokenType) bool {
	switch tok {
	case lexer.PlusToken, lexer.MinusToken, lexer.MultiplyToken, lexer.DivideToken:
		return true
	case lexer.AndToken, lexer.OrToken:
		return true
	}
	return false
}

func convertToInfixOp(tok lexer.Token) InfixOp {
	switch tok.Tok {
	case lexer.PlusToken:
		return InfixPlus
	case lexer.MinusToken:
		return InfixSub

	case lexer.MultiplyToken:
		return InfixTimes
	case lexer.DivideToken:
		return InfixDivide
	}
	return UnknownInfixOp
}

func NewParseType(setter func(Type), after ParseFunc) ParseFunc {
	return func(tok lexer.Token, pt *ProgramTree) ParseFunc {
		return ParseType(tok, pt, setter, after)
	}
}
func ParseType(tok lexer.Token, pt *ProgramTree, setter func(Type), after ParseFunc) ParseFunc {
	if tok.Tok != lexer.SymbolToken {
		pt.EmitError(TypeMustBeAName{tok.Where})
		setter(BuiltinType{UnknownBuiltinType})
	} else {
		setter(TypeName{tok.Str})
	}
	return after

}

func ContinueOrEndParamList(tok lexer.Token, pt *ProgramTree) ParseFunc {
	if tok.Tok == lexer.CommaToken {
		return FDef_GetFuncDefinitionParamName
	} else if tok.Tok == lexer.CloseParenToken {
		return FDef_ParseReturnTypeOrReadBody
	}
	color.Blue("ContinueOrEnd")
	pt.EmitErrorFatal(UnexpectedThingInParameterList{tok.Where})
	return nil
}

func DisregardRestOfLine(tok lexer.Token, pt *ProgramTree) ParseFunc {
	if tok.Tok == lexer.NewlineToken {
		return FindingParse
	}
	return DisregardRestOfLine
}

func ModuleNamer(tok lexer.Token, pt *ProgramTree) ParseFunc {
	if pt.module_name != "" {
		pt.EmitError(MultipleDefinitionsOfModuleError{})
		return DisregardRestOfLine
	}

	if tok.Tok == lexer.NewlineToken {
		pt.EmitError(ModuleNeedsNameError{})
		return FindingParse
	}
	if tok.Tok != lexer.SymbolToken {
		pt.EmitError(ModuleNameMustBeWordError{})
		return IgnoreRestOfLine
	}
	pt.module_name = tok.Str
	return NewInsureEndOfLine("name of module must be the end of the line")
}

func ImportNamer(tok lexer.Token, pt *ProgramTree) ParseFunc {
	if tok.Tok == lexer.NewlineToken {
		pt.EmitError(ImportNeedsNameError{})
		return FindingParse
	}
	if tok.Tok != lexer.StringLiteralToken {
		pt.EmitError(ImportMustBeStringError{})
		return IgnoreRestOfLine
	}

	import_name := tok.Str
	pt.imports = append(pt.imports, import_name)
	return NewInsureEndOfLine("name of import must be the end of the line")
}

func NewInsureEndOfLine(why string) ParseFunc {
	return func(tok lexer.Token, pt *ProgramTree) ParseFunc {
		return InsureEndofLine(tok, pt, why)
	}
}

func InsureEndofLine(tok lexer.Token, pt *ProgramTree, reason string) ParseFunc {
	if tok.Tok != lexer.NewlineToken {
		pt.EmitError(ExpectedEndOfLine{reason})
		return IgnoreRestOfLine
	}
	return nil
}

func IgnoreRestOfLine(tok lexer.Token, pt *ProgramTree) ParseFunc {
	if tok.Tok == lexer.NewlineToken {
		return nil
	}
	return IgnoreRestOfLine
}
