package main

import (
	"fmt"
	"unicode"

	"github.com/fatih/color"
)

type Token struct {
	tok   TokenType
	str   string
	where Range
}

func (t Token) Print() string {
	if checkKeyword(t.str) != UnknownToken {
		return color.BlueString("%s", t.str)
	}
	return t.str
}

func Tokenize(str string) (chan Token, chan error) {
	tokens := make(chan Token)
	errors := make(chan error, 10)

	go func() {
		l := LexerInternals{[]rune(str), 0, 0, &tokens, &errors}
		for state := FindingState; state != nil; {
			state = state(&l)
		}
	}()

	return tokens, errors
}

type LexerInternals struct {
	src      []rune
	position int
	start    int
	toks     *chan Token
	errs     *chan error
}

func (l *LexerInternals) Take() rune {
	l.position++
	return l.src[l.position-1]
}

func (l *LexerInternals) Skip() rune {
	l.position++
	l.start = l.position
	return l.src[l.position-1]
}

func (l *LexerInternals) Peek() rune {
	return l.src[l.position]
}
func (l *LexerInternals) Emit(t TokenType) {
	*l.toks <- Token{t, l.Get(), Range{l.start, l.position}}
	l.start = l.position
}
func (l *LexerInternals) EmitError(err error) {
	*l.errs <- err
}

func (l *LexerInternals) Get() string {
	return string(l.src[l.start:l.position])
}

type StateFn func(*LexerInternals) StateFn

type TokenType uint

const (
	UnknownToken TokenType = iota
	EOFToken
	NewlineToken

	ImportToken // import
	ModuleToken // module

	CommentToken // // plus all text after

	SymbolToken // word and such

	ComptimeToken // comptime
	VarToken      // var
	ConstToken    // const

	FnToken            // fn
	ReturnsToken       // ->
	ReturnKeywordToken // return
	TypeSpecifierToken // :
	DotToken           // .
	CommaToken         // .

	AssignmentToken // =
	NotToken        // !

	PlusToken     // +
	MinusToken    // -
	MultiplyToken // *
	DivideToken   // /

	EqualityToken    // ==
	NotEqualityToken // !=

	LessThanToken      // <
	GreaterThanToken   // >
	LessThanEqToken    // <=
	GreaterThanEqToken // >=

	PipeToken // |

	OrToken  // ||
	AndToken // &&

	OpenCurlyToken  // {
	CloseCurlyToken // }

	OpenParenToken  // (
	CloseParenToken // )

	OpenSquareToken  // [
	CloseSquareToken // ]

	StringLiteralToken  // "anything"
	NumberLiteralToken  // -1234e123213, 0x20020
	BooleanLiteralToken // true, false

)

func FindingState(l *LexerInternals) StateFn {
	// We're done :)
	if l.position == len(l.src) {
		close(*l.toks)
		close(*l.errs)
		return nil
	}
	// fmt.Println("looking at: ", string(l.Peek()))

	if l.Peek() == ' ' || l.Peek() == '\t' {
		l.Skip()
	}
	if unicode.IsLetter(l.Peek()) {
		l.Take()
		return WordState
	}
	if l.Peek() == '\n' {
		l.Take()
		l.Emit(NewlineToken)
		return FindingState
	}
	if l.Peek() == '"' {
		l.Take()
		return StringLiteralState
	}
	if isPunctuation(l.Peek()) {
		return PunctState
	}
	if unicode.IsNumber(l.Peek()) {
		return NumberState
	}
	l.Take()
	l.EmitError(UnknwownCharacterError{Range{l.start, l.position}, l})
	l.Emit(UnknownToken)
	return FindingState
}

func isPunctuation(r rune) bool {
	switch r {
	case '(', ')', '[', ']', '{', '}':
		return true
	case '=', '!', '>', '<':
		return true
	case '+', '-', '*', '/':
		return true
	case '&', '|':
		return true
	case '.', ',', ':':
		return true
	}
	return false
}

func isEndOfSymbol(r rune) bool {
	switch r {
	case ' ', '\t', '\n':
		return true
	case '\'', '"', ':', '.', ',':
		return true
	case '=', '+', '-', '*', '/':
		return true
	case '(', ')', '[', ']', '{', '}':
		return true
	case '!', '@', '#', '$', '%', '^', '&':
		return true
	}
	return false
}

func PunctState(l *LexerInternals) StateFn {
	r := l.Take()
	switch r {
	case '.':
		l.Emit(DotToken)
	case ',':
		l.Emit(CommaToken)
	case '*':
		l.Emit(MultiplyToken)
	case '/':
		return DivideOrCommentState
	case '{':
		l.Emit(OpenCurlyToken)
	case '}':
		l.Emit(CloseCurlyToken)
	case '[':
		l.Emit(OpenSquareToken)
	case ']':
		l.Emit(CloseSquareToken)
	case '(':
		l.Emit(OpenParenToken)
	case ')':
		l.Emit(CloseParenToken)
	case '=':
		return EqualState
	case '!':
		return NotState
	case '-':
		return ReturnOrNegativeOrMinusState
	case '+':
		l.Emit(PlusToken)
	case ':':
		l.Emit(TypeSpecifierToken)
	default:
		l.EmitError(UnknwownCharacterError{Range{l.start, l.position}, l})
		l.Emit(UnknownToken)

	}

	return FindingState
}

func DivideOrCommentState(l *LexerInternals) StateFn {
	if l.Peek() == '/' {
		l.Take()
		return ConsumeLineCommentState
	}
	l.Emit(DivideToken)
	return FindingState
}
func ConsumeLineCommentState(l *LexerInternals) StateFn {
	if l.Peek() == '\n' {
		l.Emit(CommentToken)
		return FindingState
	}
	l.Take()
	return ConsumeLineCommentState
}

func StringLiteralState(l *LexerInternals) StateFn {
	if l.Peek() == '"' {
		l.Take()
		l.Emit(StringLiteralToken)
		return FindingState
	} else if l.Peek() == '\n' {
		l.EmitError(UnclosedStringLiteral{l.start, l.position, l})
		l.Emit(StringLiteralToken)
		return FindingState
	}
	l.Take()
	return StringLiteralState

}
func NumberState(l *LexerInternals) StateFn {
	// minus sign already handled
	if unicode.IsNumber(l.Peek()) || l.Peek() == 'x' {
		l.Take()
		return NumberState

	}
	return FindingState
}
func ReturnOrNegativeOrMinusState(l *LexerInternals) StateFn {
	if unicode.IsNumber(l.Peek()) {
		l.Take()
		return NumberState
	} else if l.Peek() == '>' {
		l.Take()
		l.Take()
		l.Emit(ReturnsToken)
		return FindingState
	}
	l.Emit(MinusToken)
	return FindingState
}

func NotState(l *LexerInternals) StateFn {
	if l.Peek() == '=' {
		l.Take()
		l.Emit(NotEqualityToken)
	} else {
		l.Emit(NotToken)
	}
	return FindingState
}

func EqualState(l *LexerInternals) StateFn {
	if l.Peek() == '=' {
		l.Take()
		l.Emit(EqualityToken)
	} else {
		l.Emit(AssignmentToken)
	}
	return FindingState
}
func checkKeyword(name string) TokenType {
	switch name {
	case "module":
		return ModuleToken
	case "import":
		return ImportToken
	case "fn":
		return FnToken
	case "return":
		return ReturnKeywordToken
	}
	return UnknownToken
}

func WordState(l *LexerInternals) StateFn {
	if isEndOfSymbol(l.Peek()) {
		keyword_token := checkKeyword(l.Get())
		if keyword_token != UnknownToken {
			l.Emit(keyword_token)
			return FindingState
		}
		l.Emit(SymbolToken)
		return FindingState
	}
	l.Take()
	return WordState
}

type UnclosedStringLiteral struct {
	start int
	end   int
	li    *LexerInternals
}

func (ucl UnclosedStringLiteral) Error() string {
	return fmt.Sprintf("Unclosed string literal '''%s''' at %d %d", string(ucl.li.src[ucl.start:ucl.end]), ucl.start, ucl.end)
}

type UnknwownCharacterError struct {
	where Range
	li    *LexerInternals
}

func (uc UnknwownCharacterError) Error() string {
	return fmt.Sprintf("%s\nUnknown Character '%s'", HighlightedLine(uc.li.src, uc.where), string(uc.li.src[uc.where.Lo:uc.where.Hi]))
}
