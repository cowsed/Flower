package parser

import (
	"Flower/util"
	"fmt"

	"github.com/fatih/color"
)

var builtin_functions = map[string]FunctionDefinition{
	"std.println": {
		ftype: FunctionType{
			args: []NamedType{{
				Type: BuiltinType{
					Whichone: BuiltinStringType,
				},
				name: "str",
			}},
			return_type: BuiltinType{
				Whichone: BuiltinVoidType,
			},
		},
		statements: []Statement{},
	},
}

func Validate(pt *ProgramTree) {
	for _, e := range pt.errors {
		color.Red("%s", e.SourceError(pt.src))
	}
	if pt.fatal || len(pt.errors) > 0 {
		return
	}
	v_ctx := ValidationContext{
		current_scopes: util.Stack[Scope]{},
		pt:             pt,
		warnings:       []SourceError{},
		errors:         []SourceError{},
		valid:          false,
	}

	global_scope := Scope{
		vals: map[string]Type{},
	}
	for name, f := range pt.global_functions {
		global_scope.Add(FullNameFromHashKey(name), f.ftype)
	}
	for name, f := range builtin_functions {
		global_scope.Add(FullNameFromHashKey(name), f.ftype)
	}

	for name, glbl := range pt.globals {
		global_scope.Add(FullNameFromHashKey(name), glbl.Type(&v_ctx))
	}

	for name, typ := range pt.global_type_defs {
		global_scope.Add(FullNameFromHashKey(name), TypeDefinition{typ})
	}

	fmt.Println("Global Scope: ", global_scope)

	v_ctx.current_scopes.Push(global_scope)

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

func (s *Scope) Add(name FullName, t Type) SourceError {
	if _, exists := s.vals[name.String()]; exists {
		return DuplicateNameError{name.where}
	}
	s.vals[name.String()] = t
	return nil
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
	v.valid = false
}

func (v *ValidationContext) EmitWarning(err SourceError) {
	v.warnings = append(v.warnings, err)
}

func (v ValidationContext) HasName(name FullName) bool {
	for _, scope := range v.current_scopes.Reversed() {
		if scope.HasName(name) {
			return true
		}

	}
	return false
}

func (v *ValidationContext) TypeOfName(name FullName) Type {
	for _, scop := range v.current_scopes.Reversed() {
		for val_name, typ := range scop.vals {
			if val_name == name.String() {
				return typ
			}
		}
	}

	return nil

}
