module Examples exposing (..)


hello_world = """
module main
import "std/console"

fn main(){
    console.puts("Hello, Flower🌸")
}
"""

arithmetic = """module main

// importing the standard library
import "std"


fn add(a: u8, b: u8) {
    return a + b
}


fn main() -> i32{
    a: u8 = 1
    b: u8 = 2
    var res: u8 = add(a, b)
    std.println("{a} + {b} = {res}")
    return 0
}
"""
