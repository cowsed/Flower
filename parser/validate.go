package parser

import (
	"Flower/util"
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
		f.Validate(&v_ctx)
	}

	if len(v_ctx.errors) != 0 {
		v_ctx.valid = false
	}
	for _, err := range v_ctx.errors {
		color.Red("Validation Error: \n%s", err.SourceError(pt.src))
	}
}

type Scope struct {
	vals map[string]Type
}

func (s Scope) HasName(name FullName) bool {
	_, exists := s.vals[name.String()]
	return exists
}

func (s Scope) TypeOfName(name FullName) Type {
	t := s.vals[name.String()]
	return t
}

type ValidationContext struct {
	current_scopes util.Stack[Scope]

	pt       *ProgramTree
	warnings []SourceError
	errors   []SourceError
	valid    bool
}

func (v *ValidationContext) EmitError(err SourceError) {
	v.errors = append(v.errors, err)
}

func (v *ValidationContext) EmitWarning(err SourceError) {
	v.warnings = append(v.warnings, err)
}

func (v ValidationContext) HasName(name FullName) bool {
	// only one file rn so qualified name doesnt make sense rn
	if len(name.names) > 1 {
		return false
	}
	_, f_exists := v.pt.global_functions[name.names[0]]
	_, glbl_exists := v.pt.globals[name.names[0]]

	return f_exists || glbl_exists
}

func (v *ValidationContext) TypeOfName(name FullName) Type {
	// only one file rn so qualified name doesnt make sense rn
	if len(name.names) > 1 {
		return nil
	}

	// try scopes
	for _, scop := range v.current_scopes.Reversed() {
		for val_name, typ := range scop.vals {
			if val_name == name.names[0] {
				return typ
			}
		}
	}

	// try globals
	g, glbl_exists := v.pt.globals[name.names[0]]
	if glbl_exists {
		return g.Type(v)
	}
	f, f_exists := v.pt.global_functions[name.names[0]]
	if f_exists {
		return f.ftype
	}
	return nil

}
