package parser

import "Flower/util"

// u8
var u8_definition_u16 FunctionDefinition = FunctionDefinition{
	fname: FullName{
		names: []string{"u8"},
	},
	ftype: FunctionType{args: []NamedType{{Type: &ConstrainedType{
		typ: U16_Type,
		constraint: LiteralExpr{
			literalType: BooleanLiteralType,
			str:         "true",
			where:       util.Range{},
		},
	},
		name: "v"}}, return_type: U8_Type},
	statements: []Statement{},
}
var u8_definition_u32 FunctionDefinition = FunctionDefinition{
	fname: FullName{
		names: []string{"u8"},
	},
	ftype: FunctionType{
		args: []NamedType{{
			Type: U32_Type,
			name: "v",
		}},
		return_type: U8_Type,
	},
	statements: []Statement{},
}
var u8_definition_u64 FunctionDefinition = FunctionDefinition{
	fname: FullName{
		names: []string{"u8"},
	},
	ftype: FunctionType{
		args: []NamedType{{
			Type: U64_Type,
			name: "v",
		}},
		return_type: U8_Type,
	},
	statements: []Statement{},
}

// u16
var u16_definition_u32 FunctionDefinition = FunctionDefinition{
	fname: FullName{
		names: []string{"u16"},
	},
	ftype: FunctionType{
		args: []NamedType{{
			Type: U32_Type,
			name: "v",
		}},
		return_type: U16_Type,
	},
	statements: []Statement{},
}
var u16_definition_u64 FunctionDefinition = FunctionDefinition{
	fname: FullName{
		names: []string{"u16"},
	},
	ftype: FunctionType{
		args: []NamedType{{
			Type: U64_Type,
			name: "v",
		}},
		return_type: U16_Type,
	},
	statements: []Statement{},
}
