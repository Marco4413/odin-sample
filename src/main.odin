package main

import "base:runtime" // args__

import "core:fmt"
import "core:math"
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
    case parse.Statement_Let:
        fmt.print("let ", x.var_name, " = ", sep = "")
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

print_statements :: proc(statements: parse.Statements) {
    statements_iterator := parse.statements_iterator(statements)
    if first_statement, ok := parse.statements_iterate(&statements_iterator); ok {
        print_statement(first_statement^)
        for statement in parse.statements_iterate(&statements_iterator) {
            fmt.print("; ")
            print_statement(statement^)
        }
    }
}

print_cursor :: proc(loc: lex.Loc, left_pad: uint = 0) {
    fmt.printf("%*.s", left_pad + cast(uint)(loc.char+1), "^", flush=false)
    for _ in 1..<loc.span do fmt.print("~", flush=false)
    fmt.println()
}

math_min :: proc(_: ^run.Fun, ctx: ^run.Exec_Context, args: ^run.Fun_Args_Iterator) -> (res: run.Result, err: run.Error) {
    res = math.INF_F64
    for arg in run.fun_args_iterate(args) {
        val := run.exec_expr(ctx, arg) or_return
        if val < res do res = val
    }

    return
}

math_max :: proc(_: ^run.Fun, ctx: ^run.Exec_Context, args: ^run.Fun_Args_Iterator) -> (res: run.Result, err: run.Error) {
    res = math.NEG_INF_F64
    for arg in run.fun_args_iterate(args) {
        val := run.exec_expr(ctx, arg) or_return
        if val > res do res = val
    }

    return
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

    res, run_err := run.exec(&exec_ctx, statements)
    switch x in run_err {
    case run.Runner_Error:
        fmt.printfln("Runner Error: {}", x)
        return
    case run.Localized_Runner_Error:
        fmt.printfln("Runner Error: {}", x.err)
        // FIXME: Not handling multiple lines, though it's not necessary
        fmt.printfln("'{}'", expr_source)
        print_cursor(x.loc, 1)
        return
    }

    print_statements(statements)
    fmt.printfln("\n-> {}", res)
}
