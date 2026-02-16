BITS 64
DEFAULT REL

section .data
error_no_args db 'Usage: ./tyche <input.ty> <output>', 10, 0
error_syntax db 'Syntax error at line ', 0
error_undefined_var db 'Error: undefined variable at line ', 0
success db 'Compiled! Run: chmod +x <output> && ./<output>', 10, 0
line_num_str db '000', 10, 0

TYPE_INT equ 1
TYPE_STRING equ 2

OP_EQ equ 1
OP_NE equ 2
OP_GT equ 3
OP_LT equ 4
OP_GE equ 5
OP_LE equ 6

BLOCK_GLOBAL equ 0
BLOCK_IF equ 1
BLOCK_ELSE equ 2

elf_header:
    db 0x7F, 'E', 'L', 'F'
    db 2, 1, 1, 0
    times 8 db 0
    dw 2
    dw 0x3E
    dd 1
    dq 0x400078
    dq 64
    dq 0
    dd 0
    dw 64
    dw 56
    dw 1
    dw 0, 0, 0

phdr:
    dd 1
    dd 7
    dq 0
    dq 0x400000
    dq 0x400000
    dq 0x300
    dq 0x300
    dq 0x1000

msg times 256 db 0
msg_len dq 0

kw_print db 'print', 0
kw_let db 'let', 0
kw_if db 'if', 0
kw_int db 'int', 0
kw_string db 'string', 0
kw_else db 'else', 0

current_token times 64 db 0

sym_names times 32*32 db 0
sym_values times 32 dq 0
sym_types times 32 dq 0
sym_count dq 0

header_size equ 120
entry_vaddr dq 0x400000 + header_size

section .bss
input_file resq 1
output_file resq 1
input_fd resq 1
output_fd resq 1
file_buffer resb 8192

src_ptr resq 1
line_number resd 1
had_parentheses resb 1
current_block resb 1

cond_left resq 1
cond_right resq 1
cond_operator resb 1
if_jump_patch resq 1
else_jump_patch resq 1

code_buffer resb 8192
data_buffer resb 8192
code_ptr resq 1
data_ptr resq 1
code_size resq 1
data_size resq 1

patch_addrs resb 512
patch_offsets resb 512
patch_count resq 1

section .text
global _start

_start:
    pop rax
    cmp rax, 3
    jl .show_usage
    
    pop rdi
    pop rdi
    mov [input_file], rdi
    pop rdi
    mov [output_file], rdi
    
    call read_input_file
    test rax, rax
    jnz .file_error
    
    call compile_program
    
    call write_output_file
    
    mov rax, 1
    mov rdi, 1
    mov rsi, success
    mov rdx, 50
    syscall
    
    mov rax, 60
    xor rdi, rdi
    syscall

.show_usage:
    mov rax, 1
    mov rdi, 1
    mov rsi, error_no_args
    mov rdx, 40
    syscall
    mov rax, 60
    mov rdi, 1
    syscall

.file_error:
    mov rax, 60
    mov rdi, 1
    syscall

read_input_file:
    mov rax, 2
    mov rdi, [input_file]
    xor rsi, rsi
    syscall
    cmp rax, 0
    jl .error
    mov [input_fd], rax
    
    mov rax, 0
    mov rdi, [input_fd]
    mov rsi, file_buffer
    mov rdx, 8192
    syscall
    
    push rax
    mov rax, 3
    mov rdi, [input_fd]
    syscall
    pop rax
    
    mov rbx, file_buffer
    add rbx, rax
    mov byte [rbx], 0
    
    mov qword [src_ptr], file_buffer
    mov dword [line_number], 1
    
    xor rax, rax
    ret

.error:
    mov rax, -1
    ret

parse_condition:
    mov rsi, [src_ptr]
    call skip_whitespace
    mov [src_ptr], rsi
    
    mov al, [rsi]
    cmp al, '0'
    jb .cond_var
    cmp al, '9'
    ja .cond_var

.cond_number:
    xor rax, rax
    
.parse_num:
    mov cl, [rsi]
    cmp cl, '0'
    jb .num_done
    cmp cl, '9'
    ja .num_done
    sub cl, '0'
    imul rax, 10
    add rax, rcx
    inc rsi
    jmp .parse_num
    
.num_done:
    mov [src_ptr], rsi
    mov [cond_left], rax
    jmp .cond_get_operator

.cond_var:
    mov rdi, current_token
    xor rcx, rcx
    
.copy_var_cond:
    mov al, [rsi]
    cmp al, ' '
    je .var_cond_done
    cmp al, 9
    je .var_cond_done
    cmp al, 10
    je .var_cond_done
    cmp al, '='
    je .var_cond_done
    cmp al, '!'
    je .var_cond_done
    cmp al, '>'
    je .var_cond_done
    cmp al, '<'
    je .var_cond_done
    cmp al, 0
    je .var_cond_done
    
    mov [rdi], al
    inc rsi
    inc rdi
    inc rcx
    cmp rcx, 63
    jge .var_cond_done
    jmp .copy_var_cond
    
.var_cond_done:
    mov byte [rdi], 0
    mov [src_ptr], rsi
    
    mov rdi, current_token
    call find_symbol
    cmp rax, -1
    je .cond_error
    
    mov rcx, rax
    shl rcx, 3
    mov rax, [sym_values + rcx]
    mov [cond_left], rax
    
.cond_get_operator:
    mov rsi, [src_ptr]
    call skip_whitespace
    mov [src_ptr], rsi
    
    mov al, [rsi]
    cmp al, '='
    je .op_eq_check
    cmp al, '!'
    je .op_ne_check
    cmp al, '>'
    je .op_gt_check
    cmp al, '<'
    je .op_lt_check
    jmp .cond_error

.op_eq_check:
    inc rsi
    cmp byte [rsi], '='
    jne .cond_error
    inc rsi
    mov byte [cond_operator], OP_EQ
    jmp .cond_get_right

.op_ne_check:
    inc rsi
    cmp byte [rsi], '='
    jne .cond_error
    inc rsi
    mov byte [cond_operator], OP_NE
    jmp .cond_get_right

.op_gt_check:
    inc rsi
    cmp byte [rsi], '='
    je .op_ge
    mov byte [cond_operator], OP_GT
    jmp .cond_get_right
.op_ge:
    inc rsi
    mov byte [cond_operator], OP_GE
    jmp .cond_get_right

.op_lt_check:
    inc rsi
    cmp byte [rsi], '='
    je .op_le
    mov byte [cond_operator], OP_LT
    jmp .cond_get_right
.op_le:
    inc rsi
    mov byte [cond_operator], OP_LE
    
.cond_get_right:
    mov [src_ptr], rsi
    call skip_whitespace
    mov [src_ptr], rsi
    
    mov al, [rsi]
    cmp al, '0'
    jb .right_var
    cmp al, '9'
    ja .right_var
    
.right_number:
    xor rax, rax
    
.parse_right:
    mov cl, [rsi]
    cmp cl, '0'
    jb .right_num_done
    cmp cl, '9'
    ja .right_num_done
    sub cl, '0'
    imul rax, 10
    add rax, rcx
    inc rsi
    jmp .parse_right
    
.right_num_done:
    mov [src_ptr], rsi
    mov [cond_right], rax
    jmp .cond_check_close

.right_var:
    mov rdi, current_token
    xor rcx, rcx
    
.copy_var_right:
    mov al, [rsi]
    cmp al, ' '
    je .var_right_done
    cmp al, 9
    je .var_right_done
    cmp al, 10
    je .var_right_done
    cmp al, ')'
    je .var_right_done
    cmp al, 0
    je .var_right_done
    
    mov [rdi], al
    inc rsi
    inc rdi
    inc rcx
    cmp rcx, 63
    jge .var_right_done
    jmp .copy_var_right
    
.var_right_done:
    mov byte [rdi], 0
    mov [src_ptr], rsi
    
    mov rdi, current_token
    call find_symbol
    cmp rax, -1
    je .cond_error
    
    mov rcx, rax
    shl rcx, 3
    mov rax, [sym_values + rcx]
    mov [cond_right], rax

.cond_check_close:
    mov rsi, [src_ptr]
    call skip_whitespace
    mov [src_ptr], rsi
    
    cmp byte [rsi], ')'
    jne .cond_error
    inc rsi
    mov [src_ptr], rsi
    mov rax, 1
    ret

.cond_error:
    xor rax, rax
    ret

compile_program:
    mov qword [code_ptr], code_buffer
    mov qword [data_ptr], data_buffer
    mov qword [patch_count], 0
    mov qword [sym_count], 0

.compile_loop:
    mov rsi, [src_ptr]
    call skip_whitespace
    mov [src_ptr], rsi
    cmp byte [rsi], 0
    je .compile_done
    
    cmp byte [rsi], '}'
    je .handle_close_brace
    
    call parse_token
    
    mov rdi, current_token
    
    mov rsi, kw_print
    call compare_string
    cmp rax, 1
    je .handle_print_wrapper
    
    mov rdi, current_token
    mov rsi, kw_let
    call compare_string
    cmp rax, 1
    je .handle_let_wrapper
    
    mov rdi, current_token
    mov rsi, kw_int
    call compare_string
    cmp rax, 1
    je .handle_let_wrapper
    
    mov rdi, current_token
    mov rsi, kw_string
    call compare_string
    cmp rax, 1
    je .handle_let
    
    mov rdi, current_token
    mov rsi, kw_if
    call compare_string
    cmp rax, 1
    je .handle_if
    
    jmp .syntax_error

.handle_print_wrapper:
    call .handle_print
    jmp .compile_loop

.handle_print:
    mov rsi, [src_ptr]
    call skip_whitespace
    mov [src_ptr], rsi
    
    mov byte [had_parentheses], 0
    cmp byte [rsi], '('
    jne .print_no_paren
    
    mov byte [had_parentheses], 1
    inc rsi
    call skip_whitespace

.print_no_paren:
    mov [src_ptr], rsi
    cmp byte [rsi], '"'
    je .handle_string
    
    mov rdi, current_token
    xor rcx, rcx

.copy_var_name_print:
    mov al, [rsi]
    cmp al, ' '
    je .var_name_done
    cmp al, 9
    je .var_name_done
    cmp al, 10
    je .var_name_done
    cmp al, 13
    je .var_name_done
    cmp al, ')'
    je .var_name_done
    cmp al, ';'
    je .var_name_done
    cmp al, 0
    je .var_name_done
    
    mov [rdi], al
    inc rsi
    inc rdi
    inc rcx
    cmp rcx, 63
    jge .var_name_done
    jmp .copy_var_name_print

.var_name_done:
    mov byte [rdi], 0
    mov [src_ptr], rsi
    
    mov rdi, current_token
    call find_symbol
    cmp rax, -1
    je .undefined_var_error
    
    mov rcx, rax
    shl rcx, 3
    mov rax, [sym_values + rcx]
    
    call number_to_string
    
    mov byte [rdi + rcx], 10
    inc rcx
    mov [msg_len], rcx
    
    push rsi
    mov rsi, rdi
    mov rdi, [data_ptr]
    mov r8, [data_ptr]
    sub r8, data_buffer
    mov r9, [msg_len]
    mov rcx, r9
    rep movsb
    mov [data_ptr], rdi
    
    call generate_write
    
    pop rsi
    mov [src_ptr], rsi
    call skip_whitespace
    mov [src_ptr], rsi
    jmp .print_end

.handle_string:
    inc rsi
    mov rdi, msg
    xor rcx, rcx

.copy_string:
    mov al, [rsi]
    cmp al, '"'
    je .string_end
    test al, al
    jz .syntax_error
    mov [rdi], al
    inc rsi
    inc rdi
    inc rcx
    jmp .copy_string

.string_end:
    mov byte [rdi], 10
    inc rcx
    mov [msg_len], rcx
    
    inc rsi
    push rsi
    
    mov rsi, msg
    mov rdi, [data_ptr]
    mov r8, [data_ptr]
    sub r8, data_buffer
    mov r9, [msg_len]
    mov rcx, r9
    rep movsb
    mov [data_ptr], rdi
    
    call generate_write
    
    pop rsi
    mov [src_ptr], rsi

.print_end:
    mov rsi, [src_ptr]
    call skip_whitespace
    mov [src_ptr], rsi
    
    cmp byte [had_parentheses], 1
    jne .check_semicolon
    
    cmp byte [rsi], ')'
    jne .syntax_error
    inc rsi
    call skip_whitespace
    mov [src_ptr], rsi

.check_semicolon:
    cmp byte [rsi], ';'
    jne .syntax_error
    inc rsi
    
    mov [src_ptr], rsi
    
    ret

.handle_let_wrapper:
    call .handle_let
    jmp .compile_loop

.handle_let:
    mov rsi, [src_ptr]
    call skip_whitespace
    mov [src_ptr], rsi
    
    mov rdi, current_token
    xor rcx, rcx

.copy_var_name:
    mov al, [rsi]
    
    cmp al, ' '
    je .name_done
    cmp al, 9
    je .name_done
    cmp al, 10
    je .name_done
    cmp al, 13
    je .name_done
    cmp al, '='
    je .name_done
    cmp al, ';'
    je .name_done
    cmp al, 0
    je .name_done
    
    mov [rdi], al
    inc rsi
    inc rdi
    inc rcx
    cmp rcx, 63
    jge .name_done
    jmp .copy_var_name

.name_done:
    mov byte [rdi], 0
    mov [src_ptr], rsi
    
    mov rdi, current_token
    call add_symbol
    mov rbx, rax
    
    mov rcx, rbx
    shl rcx, 3
    mov qword [sym_types + rcx], TYPE_INT
    
    mov rsi, [src_ptr]
    call skip_whitespace
    mov [src_ptr], rsi
    
    cmp byte [rsi], '='
    jne .syntax_error
    inc rsi
    call skip_whitespace
    mov [src_ptr], rsi
    
    xor rax, rax
    xor rcx, rcx

.parse_number:
    mov cl, [rsi]
    cmp cl, '0'
    jb .number_done
    cmp cl, '9'
    ja .number_done
    
    sub cl, '0'
    imul rax, 10
    add rax, rcx
    inc rsi
    jmp .parse_number

.number_done:
    mov rdi, sym_values
    mov rcx, rbx
    shl rcx, 3
    mov [rdi + rcx], rax
    
    mov [src_ptr], rsi
    call skip_whitespace
    mov [src_ptr], rsi
    
    cmp byte [rsi], ';'
    jne .syntax_error
    inc rsi
    
    mov [src_ptr], rsi
    
    cmp byte [current_block], BLOCK_IF
    je .if_body_loop
    cmp byte [current_block], BLOCK_ELSE
    je .else_body_loop
    jmp .compile_loop

.handle_if:
    mov rsi, [src_ptr]
    call skip_whitespace
    mov [src_ptr], rsi
    
    cmp byte [rsi], '('
    jne .syntax_error
    inc rsi
    call skip_whitespace
    mov [src_ptr], rsi
    
    call parse_condition
    test rax, rax
    jz .syntax_error
    
    mov r13b, [cond_operator]
    
    mov rdi, [code_ptr]
    
    ; mov rax, value
    mov byte [rdi], 0x48
    mov byte [rdi + 1], 0xb8
    mov rax, [cond_left]
    mov [rdi + 2], rax
    add rdi, 10
    
    ; mov rbx, value
    mov byte [rdi], 0x48
    mov byte [rdi + 1], 0xbb
    mov rax, [cond_right]
    mov [rdi + 2], rax
    add rdi, 10
    
    ; cmp rax, rbx
    mov byte [rdi], 0x48
    mov byte [rdi + 1], 0x39
    mov byte [rdi + 2], 0xd8
    add rdi, 3
    
    cmp r13b, OP_EQ
    je .if_jne_skip
    cmp r13b, OP_NE
    je .if_je_skip
    cmp r13b, OP_GT
    je .if_jle_skip
    cmp r13b, OP_LT
    je .if_jge_skip
    cmp r13b, OP_GE
    je .if_jl_skip
    cmp r13b, OP_LE
    je .if_jg_skip
    jmp .if_jne_skip

.if_jne_skip:
    mov byte [rdi], 0x0f
    mov byte [rdi + 1], 0x85
    add rdi, 2
    jmp .if_patch_placeholder

.if_je_skip:
    mov byte [rdi], 0x0f
    mov byte [rdi + 1], 0x84
    add rdi, 2
    jmp .if_patch_placeholder

.if_jle_skip:
    mov byte [rdi], 0x0f
    mov byte [rdi + 1], 0x8e
    add rdi, 2
    jmp .if_patch_placeholder

.if_jge_skip:
    mov byte [rdi], 0x0f
    mov byte [rdi + 1], 0x8d
    add rdi, 2
    jmp .if_patch_placeholder

.if_jl_skip:
    mov byte [rdi], 0x0f
    mov byte [rdi + 1], 0x8c
    add rdi, 2
    jmp .if_patch_placeholder

.if_jg_skip:
    mov byte [rdi], 0x0f
    mov byte [rdi + 1], 0x8f
    add rdi, 2

.if_patch_placeholder:
    mov [if_jump_patch], rdi
    mov dword [rdi], 0
    add rdi, 4
    mov [code_ptr], rdi
    
    mov rsi, [src_ptr]
    call skip_whitespace
    mov [src_ptr], rsi
    
    cmp byte [rsi], '{'
    jne .syntax_error
    inc rsi
    mov [src_ptr], rsi

.if_body_loop:
    mov rsi, [src_ptr]
    call skip_whitespace
    mov [src_ptr], rsi
    
    cmp byte [rsi], '}'
    je .if_body_end
    cmp byte [rsi], 0
    je .compile_done
    
    call parse_token
    mov rdi, current_token
    
    mov rsi, kw_print
    call compare_string
    cmp rax, 1
    je .if_body_print
    
    mov rsi, kw_let
    call compare_string
    cmp rax, 1
    je .if_body_let
    
    mov rsi, kw_int
    call compare_string
    cmp rax, 1
    je .if_body_let
    
    mov rsi, kw_if
    call compare_string
    cmp rax, 1
    je .handle_if
    
    jmp .if_body_loop

.if_body_print:
    call .handle_print
    jmp .if_body_loop

.if_body_let:
    call .handle_let
    jmp .if_body_loop

.if_body_end:
    mov rsi, [src_ptr]
    inc rsi
    mov [src_ptr], rsi
    call skip_whitespace
    mov [src_ptr], rsi
    
    call parse_token
    
    mov rdi, current_token
    mov rsi, kw_else
    call compare_string
    cmp rax, 1
    je .if_body_else
    
    mov rdi, [if_jump_patch]
    mov rax, [code_ptr]
    sub rax, rdi
    sub rax, 4
    mov dword [rdi], eax
    
    mov rdi, current_token
    
    mov rsi, kw_print
    call compare_string
    cmp rax, 1
    je .if_body_print
    
    mov rsi, kw_let
    call compare_string
    cmp rax, 1
    je .if_body_let
    
    mov rsi, kw_int
    call compare_string
    cmp rax, 1
    je .if_body_let
    
    mov rsi, kw_if
    call compare_string
    cmp rax, 1
    je .handle_if
    
    jmp .compile_loop

.if_body_else:
    mov rdi, [code_ptr]
    mov byte [rdi], 0xe9
    mov [else_jump_patch], rdi
    mov dword [rdi + 1], 0
    add rdi, 5
    mov [code_ptr], rdi
    
    mov rdi, [if_jump_patch]
    mov rax, [code_ptr]
    sub rax, rdi
    sub rax, 4
    mov dword [rdi], eax
    
    mov rsi, [src_ptr]
    call skip_whitespace
    mov [src_ptr], rsi
    
    cmp byte [rsi], '{'
    jne .syntax_error
    inc rsi
    mov [src_ptr], rsi

.else_body_loop:
    mov rsi, [src_ptr]
    call skip_whitespace
    mov [src_ptr], rsi
    
    cmp byte [rsi], '}'
    je .else_body_end
    cmp byte [rsi], 0
    je .compile_done
    
    call parse_token
    mov rdi, current_token
    
    mov rsi, kw_print
    call compare_string
    cmp rax, 1
    je .else_body_print
    
    mov rsi, kw_let
    call compare_string
    cmp rax, 1
    je .else_body_let
    
    mov rsi, kw_int
    call compare_string
    cmp rax, 1
    je .else_body_let
    
    jmp .else_body_loop

.else_body_print:
    call .handle_print
    jmp .else_body_loop

.else_body_let:
    call .handle_let
    jmp .else_body_loop

.else_body_end:
    mov rsi, [src_ptr]
    inc rsi
    mov [src_ptr], rsi
    
    mov rdi, [else_jump_patch]
    mov rax, [code_ptr]
    sub rax, rdi
    sub rax, 5
    mov dword [rdi + 1], eax
    
    jmp .compile_loop

.handle_close_brace:
    mov rsi, [src_ptr]
    inc rsi
    mov [src_ptr], rsi
    jmp .compile_loop

.compile_done:
    call generate_exit
    
    mov rax, [code_ptr]
    sub rax, code_buffer
    mov [code_size], rax
    
    mov rax, [data_ptr]
    sub rax, data_buffer
    mov [data_size], rax
    
    mov rbx, [entry_vaddr]
    add rbx, [code_size]
    
    mov rcx, [patch_count]
    test rcx, rcx
    jz .patch_done
    
    xor r10, r10

.patch_loop:
    mov rdi, [patch_addrs + r10 * 8]
    mov rax, [patch_offsets + r10 * 8]
    add rax, rbx
    mov [rdi], rax
    
    inc r10
    cmp r10, rcx
    jb .patch_loop

.patch_done:
    ret

.syntax_error:
    mov rax, 1
    mov rdi, 1
    mov rsi, error_syntax
    mov rdx, 22
    syscall
    jmp .print_line_and_exit

.undefined_var_error:
    mov rax, 1
    mov rdi, 1
    mov rsi, error_undefined_var
    mov rdx, 35
    syscall
    
.print_line_and_exit:
    mov eax, [line_number]
    mov rdi, line_num_str + 2
    mov ecx, 3

.convert_loop:
    xor edx, edx
    mov ebx, 10
    div ebx
    add dl, '0'
    mov [rdi], dl
    dec rdi
    loop .convert_loop
    
    mov rax, 1
    mov rdi, 1
    mov rsi, line_num_str
    mov rdx, 4
    syscall
    
    mov rax, 60
    mov rdi, 1
    syscall

number_to_string:
    push rbx
    push rdx
    
    mov rdi, msg + 255
    mov byte [rdi], 0
    mov rbx, 10
    xor rcx, rcx
    
    cmp rax, 0
    jne .conv_loop
    dec rdi
    mov byte [rdi], '0'
    mov rcx, 1
    jmp .conv_done

.conv_loop:
    test rax, rax
    jz .conv_done
    
    xor rdx, rdx
    div rbx
    add dl, '0'
    dec rdi
    mov [rdi], dl
    inc rcx
    jmp .conv_loop

.conv_done:
    pop rdx
    pop rbx
    ret

skip_whitespace:
    mov al, [rsi]
    cmp al, ' '
    je .skip
    cmp al, 9
    je .skip
    cmp al, 10
    je .newline
    cmp al, 13
    je .skip
    ret

.skip:
    inc rsi
    jmp skip_whitespace

.newline:
    inc rsi
    inc dword [line_number]
    jmp skip_whitespace

parse_token:
    mov rsi, [src_ptr]
    mov rdi, current_token
    xor ecx, ecx

.copy_token:
    mov al, [rsi]
    
    cmp al, ' '
    je .token_end
    cmp al, 9
    je .token_end
    cmp al, 10
    je .token_end
    cmp al, 13
    je .token_end
    cmp al, '('
    je .token_end
    cmp al, ')'
    je .token_end
    cmp al, ';'
    je .token_end
    cmp al, '{'
    je .token_end
    cmp al, '}'
    je .token_end
    cmp al, '='
    je .token_end
    cmp al, 0
    je .token_end
    
    mov [rdi], al
    inc rsi
    inc rdi
    inc ecx
    cmp ecx, 63
    jge .token_end
    jmp .copy_token

.token_end:
    mov byte [rdi], 0
    mov [src_ptr], rsi
    ret

compare_string:
    mov al, [rdi]
    mov bl, [rsi]
    cmp al, bl
    jne .not_equal
    test al, al
    jz .equal
    inc rdi
    inc rsi
    jmp compare_string

.equal:
    mov rax, 1
    ret

.not_equal:
    xor rax, rax
    ret

add_symbol:
    mov rcx, [sym_count]
    test rcx, rcx
    jz .add_new
    
    mov rsi, sym_names
    xor rdx, rdx

.search_loop:
    push rdi
    push rsi
    call compare_string
    pop rsi
    pop rdi
    
    cmp rax, 1
    je .found
    
    add rsi, 32
    inc rdx
    cmp rdx, rcx
    jb .search_loop

.add_new:
    mov rsi, sym_names
    mov rcx, [sym_count]
    imul rcx, 32
    add rsi, rcx
    
.copy_name:
    mov al, [rdi]
    mov [rsi], al
    inc rdi
    inc rsi
    test al, al
    jnz .copy_name
    
    mov rax, [sym_count]
    inc qword [sym_count]
    ret

.found:
    mov rax, rdx
    ret

find_symbol:
    mov rcx, [sym_count]
    test rcx, rcx
    jz .not_found
    
    mov rsi, sym_names
    xor rdx, rdx

.search_loop:
    push rdi
    push rsi
    call compare_string
    pop rsi
    pop rdi
    
    cmp rax, 1
    je .found
    
    add rsi, 32
    inc rdx
    cmp rdx, rcx
    jb .search_loop

.not_found:
    mov rax, -1
    ret

.found:
    mov rax, rdx
    ret

generate_write:
    mov rdi, [code_ptr]
    
    mov byte [rdi], 0x48
    mov byte [rdi + 1], 0xb8
    mov qword [rdi + 2], 1
    add rdi, 10
    
    mov byte [rdi], 0x48
    mov byte [rdi + 1], 0xbf
    mov qword [rdi + 2], 1
    add rdi, 10
    
    mov byte [rdi], 0x48
    mov byte [rdi + 1], 0xbe
    add rdi, 2
    
    mov rax, [patch_count]
    mov [patch_addrs + rax * 8], rdi
    mov [patch_offsets + rax * 8], r8
    inc qword [patch_count]
    
    mov qword [rdi], 0
    add rdi, 8
    
    mov byte [rdi], 0x48
    mov byte [rdi + 1], 0xba
    mov qword [rdi + 2], r9
    add rdi, 10
    
    mov byte [rdi], 0x0f
    mov byte [rdi + 1], 0x05
    add rdi, 2
    
    mov [code_ptr], rdi
    ret

generate_exit:
    mov rdi, [code_ptr]
    
    mov byte [rdi], 0x48
    mov byte [rdi + 1], 0xb8
    mov qword [rdi + 2], 60
    add rdi, 10
    
    mov byte [rdi], 0x48
    mov byte [rdi + 1], 0x31
    mov byte [rdi + 2], 0xff
    add rdi, 3
    
    mov byte [rdi], 0x0f
    mov byte [rdi + 1], 0x05
    add rdi, 2
    
    mov [code_ptr], rdi
    ret

write_output_file:
    mov rax, 2
    mov rdi, [output_file]
    mov rsi, 0x241
    mov rdx, 0755o
    syscall
    mov [output_fd], rax
    
    mov rax, header_size
    add rax, [code_size]
    add rax, [data_size]
    mov [phdr + 32], rax
    mov [phdr + 40], rax
    
    mov rax, 1
    mov rdi, [output_fd]
    mov rsi, elf_header
    mov rdx, 64
    syscall
    
    mov rax, 1
    mov rdi, [output_fd]
    mov rsi, phdr
    mov rdx, 56
    syscall
    
    mov rax, 1
    mov rdi, [output_fd]
    mov rsi, code_buffer
    mov rdx, [code_size]
    syscall
    
    mov rax, 1
    mov rdi, [output_fd]
    mov rsi, data_buffer
    mov rdx, [data_size]
    syscall
    
    mov rax, 3
    mov rdi, [output_fd]
    syscall
    
    ret
