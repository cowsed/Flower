package parser

import (
	"Flower/util"
	"fmt"
	"strings"

	"github.com/fatih/color"
)

var U8_Type BuiltinType = BuiltinType{
	Whichone: BuiltinU8Type,
}
var U16_Type BuiltinType = BuiltinType{
	Whichone: BuiltinU16Type,
}
var U32_Type BuiltinType = BuiltinType{
	Whichone: BuiltinU32Type,
}
var U64_Type BuiltinType = BuiltinType{
	Whichone: BuiltinU64Type,
}

var std_println_def FunctionDefinition = FunctionDefinition{
	fname: FullName{
		names: []string{"std", "println"},
	},
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
}

var builtin_functions = map[string]FunctionDefinition{
	"std.println(string)": std_println_def,
	"u8(u16)":             u8_definition_u16,
	"u8(u32)":             u8_definition_u32,
	"u8(u64)":             u8_definition_u64,
	"u16(32)":             u16_definition_u32,
	"u16(u64)":            u16_definition_u64,
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
		warnings:       []util.SourceError{},
		errors:         []util.SourceError{},
		valid:          false,
	}

	global_scope := Scope{
		vals:  map[string]Type{},
		names: map[string]string{},
	}
	for name, f := range pt.global_functions {
		global_scope.Add(FullNameFromHashKey(name), f.ftype)
	}
	for name, f := range builtin_functions {
		global_scope.Add(FullNameFromHashKey(name), f.ftype)
		fmt.Println("adding", name, "to functions")
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
	vals  map[string]Type
	names map[string]string // base name to full name
}

func extract_base_name(s string) string {
	if strings.Contains(s, "(") {
		return s[:strings.Index(s, "(")]
	}
	return s
}

func (s *Scope) Add(name FullName, t Type) util.SourceError {
	bn := extract_base_name(name.String())
	if _, exists := s.names[bn]; exists {
		return DuplicateNameError{name.where}
	}
	s.vals[name.HashKey()] = t
	s.names[bn] = name.HashKey()
	return nil
}

func (s Scope) HasName(name FullName) bool {
	base_name, exists := s.names[name.HashKey()]
	if !exists {
		return exists
	}
	_, exists = s.vals[base_name]
	return exists
}

func (s Scope) TypeOfName(name FullName) Type {
	t := s.vals[name.String()]
	return t
}

type ValidationContext struct {
	current_scopes util.Stack[Scope]

	pt       *ProgramTree
	warnings []util.SourceError
	errors   []util.SourceError
	valid    bool
}

func (v *ValidationContext) EmitError(err util.SourceError) {
	v.errors = append(v.errors, err)
	v.valid = false
}

func (v *ValidationContext) EmitWarning(err util.SourceError) {
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
