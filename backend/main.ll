@str = global [11 x i8] c"Hello %d!\0A\00"

declare i32 @puts(i8* %0)

declare i32 @printf()

define i32 @main() {
0:
	%1 = call i32 @printf(i8* getelementptr ([11 x i8], [11 x i8]* @str, i64 0, i64 0), i32 4)
	ret i32 0
}
