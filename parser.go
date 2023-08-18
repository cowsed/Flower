package main

import (
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

type ParseFunc func(tok Token, pt *ProgramTree) ParseFunc

func Parse(toks chan Token, lex_errs chan error) ProgramTree {
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

		if tok.tok == EOFToken && state != nil {
			// ended halfway through
		} else if state != nil {
			state = state(tok, &pt)
		} else {
			state = FindingParse(tok, &pt)
		}

	}
	return pt
}
func FindingParse(tok Token, pt *ProgramTree) ParseFunc {
	if tok.tok == ModuleToken {
		return ModuleNamer
	}
	if tok.tok == ImportToken {
		return ImportNamer
	}
	if tok.tok == FnToken {
		return FuncNamer
	}
	return nil
}

// Function Parsing ====================================================================================

// Signature
func FuncNamer(tok Token, pt *ProgramTree) ParseFunc {
	if tok.tok != SymbolToken {
		// have to give up
		pt.EmitErrorFatal(FunctionNeedsNameError{})
		return nil
	}

	pt.workingName = tok.str
	pt.workingFunction = FunctionDefinition{
		ftype:      FunctionType{},
		statements: []Statement{},
	}
	return TakeSigOpenningParen
}
func TakeSigOpenningParen(tok Token, pt *ProgramTree) ParseFunc {
	if tok.tok != OpenParenToken {
		pt.EmitErrorFatal(FunctionNeedsOpenningParen{})
	}
	return GetFuncParamName
}
func GetFuncParamName(tok Token, pt *ProgramTree) ParseFunc {
	// little foo()
	if tok.tok == CloseParenToken {
		return ParseReturnOrReadBody
	} else if tok.tok != SymbolToken {
		pt.EmitError(ExpectedNameForFuncParam{where: tok.where})
	}
	pt.workingFunction.ftype.args = append(pt.workingFunction.ftype.args, NamedType{
		Type: nil,
		name: tok.str,
	})
	return ParamTypeOrNot
}

func ParamTypeOrNot(tok Token, pt *ProgramTree) ParseFunc {
	color.Green("ParamTypeOrNot %v", tok)

	if tok.tok == CommaToken {
		return GetFuncParamName
	} else if tok.tok == TypeSpecifierToken {
		return NewParseType(func(t Type) {
			pt.workingFunction.ftype.args[len(pt.workingFunction.ftype.args)-1].Type = t
		}, ContinueOrEndParamList)

	} else if tok.tok == CloseParenToken {
		return ParseReturnOrReadBody
	}
	pt.EmitErrorFatal(UnexpectedThingInParameterList{tok.where})
	return nil
}

func ParseReturnOrReadBody(tok Token, pt *ProgramTree) ParseFunc {
	if tok.tok == ReturnsToken {
		return NewParseType(func(t Type) { pt.workingFunction.ftype.return_type = t }, ParseFuncBodyOpenCurly)
	} else if tok.tok == OpenCurlyToken {
		return ParseFuncStatements
	}
	pt.EmitErrorFatal(UnexpectedThingInReturn{tok.where})
	return nil
}

func ParseFuncBodyOpenCurly(tok Token, pt *ProgramTree) ParseFunc {
	if tok.tok == OpenCurlyToken {
		return ParseFuncStatements
	}
	pt.EmitErrorFatal(UnexpectedThingInReturn{tok.where})
	return nil
}

func ParseFuncStatements(tok Token, pt *ProgramTree) ParseFunc {
	if tok.tok != CloseCurlyToken {
		pt.EmitErrorFatal(UnimplementedError{tok.where})
		return nil
	}
	// finished
	pt.global_functions[pt.workingName] = pt.workingFunction
	pt.workingFunction = FunctionDefinition{}
	return nil
}

func NewParseType(setter func(Type), after ParseFunc) ParseFunc {
	return func(tok Token, pt *ProgramTree) ParseFunc {
		return ParseType(tok, pt, setter, after)
	}
}
func ParseType(tok Token, pt *ProgramTree, setter func(Type), after ParseFunc) ParseFunc {
	if tok.tok != SymbolToken {
		pt.EmitError(TypeMustBeAName{tok.where})
		setter(BuiltinType{UnknownBuiltinType})
	} else {
		setter(TypeName{tok.str})
	}
	return after

}

func ContinueOrEndParamList(tok Token, pt *ProgramTree) ParseFunc {
	if tok.tok == CommaToken {
		return GetFuncParamName
	} else if tok.tok == CloseParenToken {
		return ParseReturnOrReadBody
	}
	color.Blue("ContinueOrEnd")
	pt.EmitErrorFatal(UnexpectedThingInParameterList{tok.where})
	return nil
}

func DisregardRestOfLine(tok Token, pt *ProgramTree) ParseFunc {
	if tok.tok == NewlineToken {
		return FindingParse
	}
	return DisregardRestOfLine
}

func ModuleNamer(tok Token, pt *ProgramTree) ParseFunc {
	if pt.module_name != "" {
		pt.EmitError(MultipleDefinitionsOfModuleError{})
		return DisregardRestOfLine
	}

	if tok.tok == NewlineToken {
		pt.EmitError(ModuleNeedsNameError{})
		return FindingParse
	}
	if tok.tok != SymbolToken {
		pt.EmitError(ModuleNameMustBeWordError{})
		return IgnoreRestOfLine
	}
	pt.module_name = tok.str
	return NewInsureEndOfLine("name of module must be the end of the line")
}

func ImportNamer(tok Token, pt *ProgramTree) ParseFunc {
	if tok.tok == NewlineToken {
		pt.EmitError(ImportNeedsNameError{})
		return FindingParse
	}
	if tok.tok != StringLiteralToken {
		pt.EmitError(ImportMustBeStringError{})
		return IgnoreRestOfLine
	}

	import_name := tok.str
	pt.imports = append(pt.imports, import_name)
	return NewInsureEndOfLine("name of import must be the end of the line")
}

func NewInsureEndOfLine(why string) ParseFunc {
	return func(tok Token, pt *ProgramTree) ParseFunc {
		return InsureEndofLine(tok, pt, why)
	}
}

func InsureEndofLine(tok Token, pt *ProgramTree, reason string) ParseFunc {
	if tok.tok != NewlineToken {
		pt.EmitError(ExpectedEndOfLine{reason})
		return IgnoreRestOfLine
	}
	return nil
}

func IgnoreRestOfLine(tok Token, pt *ProgramTree) ParseFunc {
	if tok.tok == NewlineToken {
		return nil
	}
	return IgnoreRestOfLine
}
