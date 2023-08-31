package lexer

import (
	"fmt"
	"unicode"

	"Flower/util"
)

type Token struct {
	Tok   TokenType
	Str   string
	Where util.Range
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
		l.EmitError(UnclosedStringLiteral{util.Range{Lo: l.start, Hi: l.position}, l})
		l.Emit(StringLiteralToken)
		return FindingState
	}
	l.Take()
	return StringLiteralState

}
func NumberState(l *LexerInternals) StateFn {
	// minus sign already handled
	if unicode.IsNumber(l.Peek()) && l.Peek() != ',' {
		l.Take()
		return NumberState

	}
	l.Emit(NumberLiteralToken)
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
	where util.Range
	li    *LexerInternals
}

func (ucl UnclosedStringLiteral) Error() string {
	return util.HighlightedLine(ucl.li.src, ucl.where) + fmt.Sprintf("\nUnclosed string literal %s", string(ucl.li.src[ucl.where.Lo:ucl.where.Hi]))
}

type UnknwownCharacterError struct {
	where util.Range
	li    *LexerInternals
}

func (uc UnknwownCharacterError) Error() string {
	return fmt.Sprintf("%s\nUnknown Character '%s', %v", util.HighlightedLine(uc.li.src, uc.where), string(uc.li.src[uc.where.Lo:uc.where.Hi]), uc.li.src[uc.where.Lo])
}
