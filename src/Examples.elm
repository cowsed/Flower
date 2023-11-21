module Examples exposing (..)


hello_world =
    """module main
import "std/console"

fn main(){
    console.puts("Hello, Flower🌸")
}
"""


arithmetic =
    """module main

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


game_input =
    """module main
import "std/console"

enum Key{
    Up
    Down
    Left
    Right
}

enum MouseButton{
    Left
    Right
    Middle
}

struct Point2d{
    x: u32
    y: u32
}

enum ButtonState{
    Pressed
    Held(u64)
    Released
}

enum InputEvent{
    Keyboard(Key, ButtonState)
    MousePress(MouseButton, ButtonState)
    MouseMove(Point2d)
}

fn main() -> i32{
    console.print("Hello")
    console.print_err("To stderr")

    a = 0b1101
}
"""

cards_example = """module main
import "std/console"

enum Suit{
    Diamond
    Heart
    Club
    Spade
}

enum Number{
    Ace
    One
    Two
    Three
    Four
    Five
    Six
    Seven
    Eight
    Nine
    Jack
    Queen
    King
}

struct Card {
    suit: Suit
    num: Number
}


"""



misc_examples = [("Game Input", game_input), ("Cards", cards_example)]
struct_example =
    """module main
// a struct of builtins
struct A{
    a: i32
    b: i32
}
// a struct of custom types 
struct B{
    a: A
    b: i32
}

"""


enum_example =
    """module main
// check out the game input example for more

// an enum of just tags
enum KeyInput{
    KeyUp
    KeyDown
    KeyLeft
    KeyRight
}
enum MouseButton{
    Left
    Right
    Middle
}

// an enum with a payload
enum InputEvent{
    Key(KeyInput)
    MousePress(MouseButton)
}


"""

alias_example = "module main\n// go bother your local compiler writer to implement this\n"


type_examples =
    [ ( "Structs", struct_example )
    , ("Enums", enum_example)
    , ("Aliases", alias_example)
    ]


recursive_type_example = 
    """module main
// infintely sized type
struct A{
    a: A
}

// solution
struct B{
    b: &B
}

"""

error_examples = 
    [("Recursive Type", recursive_type_example)]