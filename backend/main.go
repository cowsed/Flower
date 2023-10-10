package main

import (
	"os"

	"github.com/llir/llvm/ir"
	"github.com/llir/llvm/ir/constant"
	"github.com/llir/llvm/ir/types"
)

type statement struct {
}

func main() {
	m := ir.NewModule()
	hello := constant.NewCharArrayFromString("Hello %d!\n\x00")
	str := m.NewGlobalDef("str", hello)
	puts := m.NewFunc("puts", types.I32, ir.NewParam("", types.NewPointer(types.I8)))
	printf := m.NewFunc("printf", types.I32, ir.NewParam("", types.NewPointer(types.I8)))

	main := m.NewFunc("main", types.I32)
	entry := main.NewBlock("")

	zero := constant.NewInt(types.I64, 0)
	gep := constant.NewGetElementPtr(hello.Typ, str, zero, zero)
	entry.NewCall(puts, gep)

	zero32 := constant.NewInt(types.I32, 4)
	entry.NewCall(printf, gep, zero32)

	entry.NewRet(constant.NewInt(types.I32, 0))

	module_to_file("main.ll", m)
}

func module_to_file(fname string, mod *ir.Module) {
	os.WriteFile(fname, []byte(mod.String()), 0644)
}
