package main

import "core:fmt"
import "core:math"
import "core:mem"
import "core:os"
import "core:strings"

import lex   "lexer"
import parse "parser"
import run   "runner"

print_node :: proc(node: ^parse.Node, current_precedence: uint = ~cast(uint)0) {
    switch &x in node {
    case parse.Node_Number:
        fmt.print(x)
    case parse.Node_Var:
        fmt.print(x.var_name)
    case parse.Node_Binop:
        assoc          := parse.get_operator_assoc(x.op)
        new_precedence := parse.get_operator_precedence(x.op)
        is_ambiguous   := new_precedence > current_precedence || assoc != .Right
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
            print_node(first_arg.node)
            for arg in parse.node_fun_call_iterate_args(&args_iterator) {
                fmt.print(", ")
                print_node(arg.node)
            }
        }

        fmt.print(")")
    }
}

print_cursor :: proc(loc: lex.Loc, left_pad: uint = 0) {
    fmt.printf("%*.s", left_pad + cast(uint)(loc.char+1), "^", flush=false)
    for _ in 1..<loc.span do fmt.print("~", flush=false)
    fmt.println()
}

math_min :: proc(ctx: ^run.Exec_Context, args: ^run.Fun_Args_Iterator) -> (res: run.Result, err: run.Error) {
    res = math.INF_F64
    for x in run.fun_args_iterate(args) {
        val := run.exec(ctx, x.node) or_return
        if val < res do res = val
    }

    return
}

math_max :: proc(ctx: ^run.Exec_Context, args: ^run.Fun_Args_Iterator) -> (res: run.Result, err: run.Error) {
    res = math.NEG_INF_F64
    for x in run.fun_args_iterate(args) {
        val := run.exec(ctx, x.node) or_return
        if val > res do res = val
    }

    return
}

main :: proc() {
    if len(os.args) <= 1 {
        fmt.println("ERROR: No expression provided.")
        return
    }

    expr_source := strings.join(os.args[1:], " ")
    defer delete(expr_source)

    parser: parse.Parser
    parse.parser_init(&parser, expr_source)
    defer parse.parser_destroy(&parser)

    expr_allocator: mem.Dynamic_Arena
    mem.dynamic_arena_init(&expr_allocator)
    defer mem.dynamic_arena_destroy(&expr_allocator)

    expr_node, parse_err := parse.parser_parse(&parser, &expr_allocator)
    if parse_err != nil {
        tok, _ := parse.parser_current_token(&parser)
        fmt.printfln("Parse Error: {}", parse_err)
        // FIXME: Not handling multiple lines, though it's not necessary
        fmt.printfln("'{}'", expr_source)
        print_cursor(tok.loc, 1)
        return
    }

    exec_ctx: run.Exec_Context
    run.exec_context_init(&exec_ctx)
    defer run.exec_context_destroy(&exec_ctx)

    run.exec_context_set_variable(&exec_ctx, "pi", math.π)
    run.exec_context_set_variable(&exec_ctx, "e",  math.e)

    run.exec_context_set_function(&exec_ctx, "min", math_min)
    run.exec_context_set_function(&exec_ctx, "max", math_max)

    res, run_err := run.exec(&exec_ctx, expr_node)
    if run_err != nil {
        fmt.printfln("Runner Error: {}", run_err)
        return
    }

    print_node(expr_node)
    fmt.printfln(" = {}", res)
}
