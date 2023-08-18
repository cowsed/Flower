package main

import (
	"Flower/lexer"
	"fmt"

	"github.com/fatih/color"
)

type ReturnStatement struct {
	value Expression
}

type Statement interface{}

type FunctionDefinition struct {
	ftype      FunctionType
	statements []Statement
}

type AssignmentStatement struct {
	to   string
	from Expression
}

type ProgramTree struct {
	valid       bool
	module_name string
	imports     []string

	// All globals are order independent
	globals          map[string]Expression
	global_structs   map[string]RecordType
	global_functions map[string]FunctionDefinition

	workingName     string
	workingFunction FunctionDefinition

	fatal  bool
	errors []SourceError
}

func (pt ProgramTree) Print(src []rune) {
	if !pt.valid {
		fmt.Println("Invalid Program")
		fmt.Println("errs:")
		for _, e := range pt.errors {
			color.Red("- %s", e.SourceError(src))
		}
		return
	}
	fmt.Print("Valid Program:\n\n")
	fmt.Println("module:", pt.module_name)
	fmt.Println("\nImports:")
	for _, im := range pt.imports {
		fmt.Println("-", im)
	}
	fmt.Println("\nFunctions:")
	for name, function := range pt.global_functions {
		fmt.Println("- ", name, ": ", function)
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

func Parse(toks chan lexer.Token, lex_errs chan error) ProgramTree {
	var pt ProgramTree = ProgramTree{
		valid:            true,
		module_name:      "",
		imports:          []string{},
		globals:          map[string]Expression{},
		global_structs:   map[string]RecordType{},
		global_functions: map[string]FunctionDefinition{},
		workingName:      "",
		workingFunction:  FunctionDefinition{},
		fatal:            false,
		errors:           []SourceError{},
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
		return FuncNamer
	}
	return nil
}

// Function Parsing ====================================================================================

// Signature
func FuncNamer(tok lexer.Token, pt *ProgramTree) ParseFunc {
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
	return TakeSigOpenningParen
}
func TakeSigOpenningParen(tok lexer.Token, pt *ProgramTree) ParseFunc {
	if tok.Tok != lexer.OpenParenToken {
		pt.EmitErrorFatal(FunctionNeedsOpenningParen{})
	}
	return GetFuncParamName
}
func GetFuncParamName(tok lexer.Token, pt *ProgramTree) ParseFunc {
	// little foo()
	if tok.Tok == lexer.CloseParenToken {
		return ParseReturnOrReadBody
	} else if tok.Tok != lexer.SymbolToken {
		pt.EmitError(ExpectedNameForFuncParam{where: tok.Where})
	}
	pt.workingFunction.ftype.args = append(pt.workingFunction.ftype.args, NamedType{
		Type: nil,
		name: tok.Str,
	})
	return ParamTypeOrNot
}

func ParamTypeOrNot(tok lexer.Token, pt *ProgramTree) ParseFunc {
	color.Green("ParamTypeOrNot %v", tok)

	if tok.Tok == lexer.CommaToken {
		return GetFuncParamName
	} else if tok.Tok == lexer.TypeSpecifierToken {
		return NewParseType(func(t Type) {
			pt.workingFunction.ftype.args[len(pt.workingFunction.ftype.args)-1].Type = t
		}, ContinueOrEndParamList)

	} else if tok.Tok == lexer.CloseParenToken {
		return ParseReturnOrReadBody
	}
	pt.EmitErrorFatal(UnexpectedThingInParameterList{tok.Where})
	return nil
}

func ParseReturnOrReadBody(tok lexer.Token, pt *ProgramTree) ParseFunc {
	if tok.Tok == lexer.ReturnsToken {
		return NewParseType(func(t Type) { pt.workingFunction.ftype.return_type = t }, ParseFuncBodyOpenCurly)
	} else if tok.Tok == lexer.OpenCurlyToken {
		return ParseFuncStatements
	}
	pt.EmitErrorFatal(UnexpectedThingInReturn{tok.Where})
	return nil
}

func ParseFuncBodyOpenCurly(tok lexer.Token, pt *ProgramTree) ParseFunc {
	if tok.Tok == lexer.OpenCurlyToken {
		return ParseFuncStatements
	}
	pt.EmitErrorFatal(UnexpectedThingInReturn{tok.Where})
	return nil
}

func ParseFuncStatements(tok lexer.Token, pt *ProgramTree) ParseFunc {
	if tok.Tok != lexer.CloseCurlyToken {
		pt.EmitErrorFatal(UnimplementedError{tok.Where})
		return nil
	}
	// finished
	pt.global_functions[pt.workingName] = pt.workingFunction
	pt.workingFunction = FunctionDefinition{}
	return nil
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
		return GetFuncParamName
	} else if tok.Tok == lexer.CloseParenToken {
		return ParseReturnOrReadBody
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
