package main

import "base:runtime" // args__

import "core:flags"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"
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
    case parse.Node_Unop:
        switch x.op {
        case .Negate: fmt.print("-")
        }
        print_node(x.expr)
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
    os.exit(cli_main())
}

// I don't know how to feel about this:
// https://odin-lang.org/docs/overview/#struct-field-tags
CLI_Options :: struct {
    expr: [dynamic]string `args:"name=varg,required,variadic" usage:"The expression to be ran."`,
    optimize_unary: bool `args:"name=opt-unary" usage:"Optimizes unary expressions like '--foo' to 'foo'."`,
}

cli_main :: proc() -> int {
    stderr := os.stream_from_handle(os.stderr)
    stdout := os.stream_from_handle(os.stdout)

    os_args := make_os_args()
    defer delete(os_args)

    cli_options: CLI_Options
    defer delete(cli_options.expr)

    assert(len(os_args) > 0, "Missing program path.")
    program := filepath.base(os_args[0])
    flags_style := flags.Parsing_Style.Unix

    // Some code taken from flags.print_errors()
    switch error in flags.parse(&cli_options, os_args[1:], flags_style, true, true) {
    case flags.Parse_Error:
        // I hate this flags parser
        // I hate this flags parser
        // I hate this flags parser
        // I hate this flags parser
        // I hate this flags parser
        // I hate this flags parser
        correct_message, was_allocated := strings.replace(error.message, "`varg`", "`expr`", -1)
        fmt.wprintfln(stderr, "%s", correct_message)
        if was_allocated do delete(correct_message)
        return 1
    case flags.Open_File_Error:
        fmt.wprintfln(stderr, "[%i] Unable to open file with perms 0o%o in mode 0x%x: %s",
            error.errno, error.perms, error.mode, error.filename)
        return 1
    case flags.Validation_Error:
        fmt.wprintfln(stderr, "%s", error.message)
        return 1
    case flags.Help_Request:
        fmt.wprintln(stdout, "A math expression parser and interpreter.")
        flags.write_usage(stdout, CLI_Options, program, flags_style)
        return 0
    }

    return app_main(cli_options)
}

app_main :: proc(cli_options: CLI_Options) -> int {
    expr_source := strings.join(cli_options.expr[:], " ")
    defer delete(expr_source)

    parser: parse.Parser
    parse.parser_init(&parser, expr_source)
    defer parse.parser_destroy(&parser)
    parser.optimize_unary_operators = cli_options.optimize_unary

    expr_allocator: mem.Dynamic_Arena
    mem.dynamic_arena_init(&expr_allocator)
    defer mem.dynamic_arena_destroy(&expr_allocator)

    statements, parse_err := parse.parser_parse(&parser, &expr_allocator)
    if parse_err != nil {
        tok, _ := parse.parser_current_token(&parser)
        fmt.printfln("Parse Error: {}({}:{})", parse_err, tok.loc.line+1, tok.loc.char+1)
        fmt.printfln("'{}'", get_line(expr_source, tok.loc.line))
        print_cursor(tok.loc, 1)
        return 1
    }

    global_scope: run.Global_Scope
    // See 'runner/default_context.odin'
    run.global_scope_init_default(&global_scope)
    defer run.global_scope_destroy(&global_scope)

    res, run_err := run.exec(&global_scope, statements)
    defer delete(res)

    switch x in run_err {
    case run.Runner_Error:
        fmt.printfln("Runner Error: {}", x)
        return 1
    case run.Localized_Runner_Error:
        fmt.printfln("Runner Error: {}({}:{})", x.err, x.loc.line+1, x.loc.char+1)
        fmt.printfln("'{}'", get_line(expr_source, x.loc.line))
        print_cursor(x.loc, 1)
        return 1
    }

    Result_Info :: struct {
        // Includes the sign
        int_digits: int,
        // Includes the dot
        fractional_digits: int,
    }

    res_max: Result_Info
    res_infos := make([]Result_Info, len(res))
    defer delete(res_infos)

    {
        builder: strings.Builder
        strings.builder_init(&builder)
        defer strings.builder_destroy(&builder)

        fi: fmt.Info
        fi.writer = strings.to_stream(&builder)

        for x, idx in res {
            strings.builder_reset(&builder)
            fmt.fmt_float(&fi, x.value, 8 * size_of(x.value), 'w')

            formatted := strings.to_string(builder)
            full_len  := len(formatted)

            int_digits, fractional_digits: int

            dp_idx := strings.index_byte(formatted, '.')
            if dp_idx < 0 {
                int_digits = full_len
            } else {
                fractional_digits = full_len - dp_idx
                int_digits        = full_len - fractional_digits
            }

            res_infos[idx].int_digits        = int_digits
            res_infos[idx].fractional_digits = fractional_digits

            if int_digits > res_max.int_digits do res_max.int_digits = int_digits
            if fractional_digits > res_max.fractional_digits do res_max.fractional_digits = fractional_digits
        }
    }

    // println_statements(statements)
    for x, idx in res {
        res_info := res_infos[idx]

        int_padding        := res_max.int_digits - res_info.int_digits
        fractional_padding := res_max.fractional_digits - res_info.fractional_digits

        fmt.printf("%*s%w%*s = ",
            int_padding, "",
            x.value,
            fractional_padding, "")
        print_node(x.expr)
        fmt.println()
    }

    return 0
}
