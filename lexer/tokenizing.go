package lexer

import (
	"Flower/util"
	"unicode"
)

type LexerInternals struct {
	src      []rune
	position int
	start    int
	toks     *chan Token
	errs     *chan error
}

type StateFn func(*LexerInternals) StateFn

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
	*l.toks <- Token{t, l.Get(), util.Range{Lo: l.start, Hi: l.position}}
	l.start = l.position
}
func (l *LexerInternals) EmitError(err error) {
	*l.errs <- err
}

func (l *LexerInternals) Get() string {
	return string(l.src[l.start:l.position])
}

// Lexing

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
	l.EmitError(UnknwownCharacterError{util.Range{l.start, l.position}, l})
	l.Emit(UnknownToken)
	return FindingState
}

// Helpers

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
		l.EmitError(UnknwownCharacterError{util.Range{Lo: l.start, Hi: l.position}, l})
		l.Emit(UnknownToken)

	}

	return FindingState
}
