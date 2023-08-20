package main

import (
	"fmt"

	"github.com/fatih/color"
)

func Validate(pt *ProgramTree) {
	v_ctx := ValidationContext{
		pt: pt,
	}
	// name resolution phase
	for name, f := range pt.global_functions {
		fmt.Println("Validating", name, " - ", f)
	}

	if len(v_ctx.errors) != 0 {
		v_ctx.valid = false
	}
	for _, err := range v_ctx.errors {
		color.Red("Validation Error: %s", err.SourceError(pt.src))
	}
}

type ValidationContext struct {
	pt     *ProgramTree
	errors []SourceError
	valid  bool
}

func (v *ValidationContext) EmitError(err SourceError) {
	v.errors = append(v.errors, err)
}

func (v ValidationContext) HasFunction(name FullName) bool {
	// only one file rn so qualified name doesnt make sense rn
	if len(name.names) > 1 {
		return false
	}
	_, exists := v.pt.global_functions[name.names[0]]
	return exists
}

func (v ValidationContext) HasName(name FullName) bool {
	// only one file rn so qualified name doesnt make sense rn
	if len(name.names) > 1 {
		return false
	}
	_, f_exists := v.pt.global_functions[name.names[0]]
	_, glbl_exists := v.pt.globals[name.names[1]]

	return f_exists || glbl_exists
}
