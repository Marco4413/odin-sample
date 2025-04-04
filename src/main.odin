package main

import "base:runtime" // args__

import "core:fmt"
import "core:mem"
import "core:strings"

import lex   "lexer"
import parse "parser"
import run   "runner"

print_node :: proc(node: ^parse.Node, current_precedence: uint = ~cast(uint)0) {
    is_ambiguous_operator :: proc(op: parse.Binop_Kind) -> bool {
        return op == .Pow
    }

    switch &x in node {
    case parse.Node_Number:
        fmt.print(x)
    case parse.Node_Var:
        fmt.print(x.var_name)
    case parse.Node_Binop:
        new_precedence := parse.get_operator_precedence(x.op)
        is_ambiguous   := new_precedence > current_precedence || is_ambiguous_operator(x.op)
        if is_ambiguous do fmt.print("(")
        print_node(x.lhs, new_precedence)
        switch x.op {
        case .Add: fmt.print(" + ")
        case .Sub: fmt.print(" - ")
        case .Div: fmt.print(" / ")
        case .Mul: fmt.print(" * ")
        case .Pow: fmt.print(" ^ ")
        }
        print_node(x.rhs, new_precedence)
        if is_ambiguous do fmt.print(")")
    case parse.Node_Fun_Call:
        fmt.print(x.func_name, "(", sep = "")

        args_iterator := parse.node_fun_call_iterator_args(&x)
        if first_arg, ok := parse.node_fun_call_iterate_args(&args_iterator); ok {
            print_node(first_arg)
            for arg in parse.node_fun_call_iterate_args(&args_iterator) {
                fmt.print(", ")
                print_node(arg)
            }
        }

        fmt.print(")")
    }
}

print_statement :: proc(statement: parse.Statement) {
    switch &x in statement {
    case parse.Statement_Expr:
        print_node(x.expr)
    case parse.Statement_Var:
        fmt.print("var ", x.var_name, " = ", sep = "")
        print_node(x.expr)
    case parse.Statement_Fun:
        fmt.print("fun ", x.fun_name, "(", sep = "")

        arg_names_iterator := parse.statement_fun_iterator_args(&x)
        if first_arg_name, ok := parse.statement_fun_iterate_args(&arg_names_iterator); ok {
            fmt.print(first_arg_name)
            for arg_name in parse.statement_fun_iterate_args(&arg_names_iterator) {
                fmt.print(", ", arg_name, sep = "")
            }
        }

        fmt.print(") = ", sep = "")
        print_node(x.expr)
    }
}

println_statements :: proc(statements: parse.Statements) {
    statements_iterator := parse.statements_iterator(statements)
    for statement in parse.statements_iterate(&statements_iterator) {
        print_statement(statement^)
        fmt.println(";")
    }
}

get_line :: proc(text: string, line: u32) -> string {
    cur_idx, new_line_offset, new_line_width: int

    for _ in 0..=line {
        cur_idx += new_line_offset + new_line_width
        new_line_offset, new_line_width = strings.index_multi(text[cur_idx:], []string{ "\r\n", "\n" })
        if new_line_offset < 0 do return text[cur_idx:]
    }

    return text[cur_idx:cur_idx+new_line_offset]
}

print_cursor :: proc(loc: lex.Loc, left_pad: uint = 0) {
    fmt.printf("%*.s", left_pad + cast(uint)(loc.char+1), "^", flush=false)
    for _ in 1..<loc.span do fmt.print("~", flush=false)
    fmt.println()
}

make_os_args :: proc() -> (argv: []string) {
    // See https://github.com/odin-lang/Odin/pull/4680
    // And https://github.com/odin-lang/Odin/pull/4680#issuecomment-2585475395
    argv = make([]string, len(runtime.args__))
    for _, i in argv do argv[i] = string(runtime.args__[i])
    return
}

main :: proc() {
    os_args := make_os_args()
    defer delete(os_args)

    if len(os_args) <= 1 {
        fmt.println("ERROR: No expression provided.")
        return
    }

    expr_source := strings.join(os_args[1:], " ")
    defer delete(expr_source)

    parser: parse.Parser
    parse.parser_init(&parser, expr_source)
    defer parse.parser_destroy(&parser)

    expr_allocator: mem.Dynamic_Arena
    mem.dynamic_arena_init(&expr_allocator)
    defer mem.dynamic_arena_destroy(&expr_allocator)

    statements, parse_err := parse.parser_parse(&parser, &expr_allocator)
    if parse_err != nil {
        tok, _ := parse.parser_current_token(&parser)
        fmt.printfln("Parse Error: {}({}:{})", parse_err, tok.loc.line+1, tok.loc.char+1)
        fmt.printfln("'{}'", get_line(expr_source, tok.loc.line))
        print_cursor(tok.loc, 1)
        return
    }

    exec_ctx: run.Exec_Context
    // See 'runner/default_context.odin'
    run.exec_context_init_default(&exec_ctx)
    defer run.exec_context_destroy(&exec_ctx)

    res, run_err := run.exec(&exec_ctx, statements)
    defer delete(res)

    switch x in run_err {
    case run.Runner_Error:
        fmt.printfln("Runner Error: {}", x)
        return
    case run.Localized_Runner_Error:
        fmt.printfln("Runner Error: {}({}:{})", x.err, x.loc.line+1, x.loc.char+1)
        fmt.printfln("'{}'", get_line(expr_source, x.loc.line))
        print_cursor(x.loc, 1)
        return
    }

    // println_statements(statements)
    for x in res {
        print_node(x.expr)
        fmt.printfln(" = {}", x.value)
    }
}
