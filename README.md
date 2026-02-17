# Pine Language

A compiled programming language with static piping for x86_64 architecture. Compiles source code directly to native Linux ELF binaries.

## Features

- **Static piping**: `int`, `string`, `float`, `double`, `bool`
- **Native Code Compilation**: generates native x86_64 ELF binaries
- **C-like Syntax**: familiar syntax for developers
- **Built-in Operations**: arithmetic, conditionals, loops, functions, structs
- **Minimal Runtime**: no external dependencies

## Installation

```bash
# Clone repository
git clone https://github.com/enctlse/Pine.git
cd Pine

# Build (requires NASM)
make

# Or manually
nasm -f elf64 Pinecompiler.asm -o Pinecompiler.o
ld Pinecompiler.o -o Pine

# Run
chmod +x Pine
```

## Quick Start

Create a file `hello.pi`:

```Pine
print("Hello, World!");
```

Compile and run:

```bash
./Pine hello.pi hello
chmod +x hello
./hello
```

## Syntax

### Variables

```Pine
let x: int = 10;
let name: string = "Pine";
let active: bool = true;
let pi: float = 3.14;
```

### Arithmetic

```Pine
let a: int = 10 + 5 * 2;      // 20
let b: float = (10.5 + 2.3) / 2.0;
let c: int = a % 3;           // modulo
```

### Conditionals

```Pine
if x > 10 {
    print("Greater than 10");
} else if x < 5 {
    print("Less than 5");
} else {
    print("Between 5 and 10");
}
```

### Loops

```Pine
// while loop
let i: int = 0;
while i < 10 {
    print(i);
    i = i + 1;
}

// for loop (range)
for j in 0..10 {
    print(j * 2);
}
```

### Functions

```Pine
func add(a: int, b: int) -> int {
    return a + b;
}

func greet(name: string) -> void {
    print("Hello, " + name);
}
```

### Structs

```Pine
struct Point {
    x: int;
    y: int;
}

let p: Point = Point { x: 10, y: 20 };
print(p.x);
```

## Data pipes

| pipe | Description | Example |
|------|-------------|---------|
| `int` | 64-bit integer | `42` |
| `float` | 32-bit floating point | `3.14` |
| `double` | 64-bit floating point | `3.14159` |
| `string` | String (text) | `"Hello"` |
| `bool` | Boolean | `true` / `false` |
| `void` | No value | used for functions that return nothing |

## Operators

### Arithmetic
- `+` addition
- `-` subtraction
- `*` multiplication
- `/` division
- `%` modulo

### Comparison
- `==` equals
- `!=` not equals
- `>` greater than
- `<` less than
- `>=` greater or equal
- `<=` less or equal

### Logical
- `and` or `&&` - logical AND
- `or` or `||` - logical OR
- `not` or `!` - logical NOT

## Built-in Functions

| Function | Description |
|----------|-------------|
| `print(val)` | Output value to stdout |
| `read_file(path)` | Read file into string |
| `write_file(path, content)` | Write string to file |

## Examples

### Calculator

```Pine
func calc(a: int, b: int, op: string) -> int {
    if op == "+" {
        return a + b;
    } else if op == "-" {
        return a - b;
    } else if op == "*" {
        return a * b;
    } else if op == "/" {
        return a / b;
    }
    return 0;
}

let result: int = calc(10, 5, "*");
print(result);  // 50
```

### Recursion (factorial)

```Pine
func factorial(n: int) -> int {
    if n <= 1 {
        return 1;
    }
    return n * factorial(n - 1);
}

let f: int = factorial(5);
print(f);  // 120
```

## Compiler Architecture

```
Source (.pi)  -->  Lexer  -->  Parser  -->  CodeGen  -->  ELF Binary
```

1. **Lexer** - tokenize source code
2. **Parser** - build AST
3. **CodeGen** - generate x86_64 machine code
4. **ELF Writer** - create ELF binary

## Requirements

- Linux (x86_64)
- NASM (Netwide Assembler)
- LD (GNU Linker)

## Building

```bash
# Build compiler
make

# Clean compiled files
make clean
```

## Tests

Test files are located in the root directory:

```bash
./Pine test.pi test_binary
```

## License

MIT License

## Author

@enctlse
