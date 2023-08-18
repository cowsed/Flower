package main

import (
	"Flower/lexer"
	"fmt"
)

var src string = `
module main

import "std"
import "math"

fn add(a: u8, b: u8) -> u8{}

fn main(b: u16) -> u16 {}
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
	pt := Parse(toks, tok_errs)
	// pt.Validate()
	pt.Print([]rune(src))
}
