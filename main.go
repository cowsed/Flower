package main

import (
	"Flower/lexer"
	"Flower/parser"
	"fmt"
)

var src string = `
module main

import "std"
import "math"


fn add(a: u8, b: u8) -> u16{
    return u16(a)
}

fn main(b: u16) -> u16 {
    std.println("b = {}")
    return add(2, add(1, 3))
}
`

func main() {
	toks, tok_errs := lexer.Tokenize(src)
	if len(tok_errs) != 0 {
		fmt.Println("tokenizer errors: ")
		for err := range tok_errs {
			fmt.Println(err)
			return
		}
	}
	pt := parser.Parse(toks, tok_errs, []rune(src))

	parser.Validate(&pt)
	// pt.Print([]rune(src))
}
