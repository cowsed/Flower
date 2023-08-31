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
	// add function arguments
	func_scope := Scope{
		vals: map[string]Type{},
	}

	// TODO make arg.name a FullName
	for _, arg := range f.ftype.args {
		fmt.Println("Arg", arg)
		func_scope.vals[arg.name] = arg.Type
		func_scope.Add(FullName{
			names: []string{arg.name},
			where: util.Range{},
		}, arg.Type)
	}
	num_scopes_before := ctx.current_scopes.Size()
	ctx.current_scopes.Push(func_scope)

	fmt.Println("func scope: ", func_scope)
	for _, statement := range f.statements {
		statement.Validate(ctx)
	}
	ctx.current_scopes.Pop()
	if num_scopes_before != ctx.current_scopes.Size() {
		panic("Terrible terrible news")
	}

	// TODO  insure type of return statement matches that of function signature
}

type ProgramTree struct {
	module_name string
	imports     []string

	// All globals are order independent
	globals          map[string]Expr
	global_type_defs map[string]RecordType
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
	fcall_range := where
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
				fcall_range.Add(end.Where())

			} else {
				e.args = args
				e.closed = true
				pt.workingExpression.Push(e)
				e.where = fcall_range
				fmt.Println("end")
				return
			}
		default:
			args = append([]Expr{end}, args...)
			fcall_range.Add(end.Where())

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
		global_type_defs:  map[string]RecordType{},
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

		// fmt.Println("Token:", tok)

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

// Function Parsing ====================================================================================

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
			where:       tok.Where,
		})
		return NewContinueOrEndExpression(setter)

	// string
	case lexer.StringLiteralToken:

		pt.workingExpression.Push(LiteralExpr{
			literalType: StringLiteralType,
			str:         tok.Str,
			where:       tok.Where,
		})
		return NewContinueOrEndExpression(setter)

	case lexer.BooleanLiteralToken:
		pt.workingExpression.Push(LiteralExpr{
			literalType: BooleanLiteralType,
			str:         tok.Str,
			where:       tok.Where,
		})
		return NewContinueOrEndExpression(setter)
	case lexer.SymbolToken:
		color.Cyan("saw symbol")
		return NewValueLookupOrFunctionCall(FullName{
			names: []string{tok.Str},
			where: tok.Where,
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
			where:  name_so_far.where,
		})
		return NewParseExpr(
			func(e Expr) ParseFunc {
				pt.workingExpression.Push(e)
				return NewContinueOrEndExpression(setter)
			})
	} else if tok.Tok == lexer.DotToken {
		// continue taking name
		name_so_far.where.Add(tok.Where)
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
		name_so_far.where.Add(tok.Where)
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
	} else if is_builtin_type, whichone := IsBuiltinType(tok); is_builtin_type {
		setter(BuiltinType{whichone})
	} else {
		setter(TypeName{tok.Str})
	}
	return after

}

func IsBuiltinType(tok lexer.Token) (bool, BuiltinTypeType) {
	switch tok.Str {
	case "u8":
		return true, BuiltinU8Type
	case "u16":
		return true, BuiltinU8Type
	case "u32":
		return true, BuiltinU8Type
	case "u64":
		return true, BuiltinU8Type

	case "i8":
		return true, BuiltinU8Type
	case "i16":
		return true, BuiltinU8Type
	case "i32":
		return true, BuiltinU8Type
	case "i64":
		return true, BuiltinU8Type

	}
	return false, UnknownBuiltinType
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
