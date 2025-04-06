package main

import "base:runtime" // args__

import "core:flags"
import "core:fmt"
import "core:io"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strings"

import lex   "lexer"
import       "optimizer"
import parse "parser"
import run   "runner"

print_node :: proc(w: io.Writer, node: ^parse.Node, current_precedence: uint = ~cast(uint)0) {
    is_ambiguous_operator :: proc(op: parse.Binop_Kind) -> bool {
        return op == .Pow
    }

    switch &x in node {
    case parse.Node_Number:
        fmt.wprint(w, x)
    case parse.Node_Var:
        fmt.wprint(w, x.var_name)
    case parse.Node_Unop:
        switch x.op {
        case .Negate: fmt.wprint(w, "-")
        }
        print_node(w, x.expr)
    case parse.Node_Binop:
        new_precedence := parse.get_operator_precedence(x.op)
        is_ambiguous   := new_precedence > current_precedence || is_ambiguous_operator(x.op)
        if is_ambiguous do fmt.wprint(w, "(")
        print_node(w, x.lhs, new_precedence)
        switch x.op {
        case .Add: fmt.wprint(w, " + ")
        case .Sub: fmt.wprint(w, " - ")
        case .Div: fmt.wprint(w, " / ")
        case .Mul: fmt.wprint(w, " * ")
        case .Pow: fmt.wprint(w, " ^ ")
        }
        print_node(w, x.rhs, new_precedence)
        if is_ambiguous do fmt.wprint(w, ")")
    case parse.Node_Fun_Call:
        fmt.wprint(w, x.func_name, "(", sep = "")

        args_iterator := parse.node_fun_call_iterator_args(&x)
        if first_arg, ok := parse.node_fun_call_iterate_args(&args_iterator); ok {
            print_node(w, first_arg)
            for arg in parse.node_fun_call_iterate_args(&args_iterator) {
                fmt.wprint(w, ", ")
                print_node(w, arg)
            }
        }

        fmt.wprint(w, ")")
    }
}

print_statement :: proc(w: io.Writer, statement: parse.Statement) {
    switch &x in statement {
    case parse.Statement_Expr:
        print_node(w, x.expr)
    case parse.Statement_Var:
        fmt.wprint(w, "var ", x.var_name, " = ", sep = "")
        print_node(w, x.expr)
    case parse.Statement_Fun:
        fmt.wprint(w, "fun ", x.fun_name, "(", sep = "")

        arg_names_iterator := parse.statement_fun_iterator_args(&x)
        if first_arg_name, ok := parse.statement_fun_iterate_args(&arg_names_iterator); ok {
            fmt.wprint(w, first_arg_name)
            for arg_name in parse.statement_fun_iterate_args(&arg_names_iterator) {
                fmt.wprint(w, ", ", arg_name, sep = "")
            }
        }

        fmt.wprint(w, ") = ", sep = "")
        print_node(w, x.expr)
    }
}

println_statements :: proc(w: io.Writer, statements: parse.Statements) {
    statements_iterator := parse.statements_iterator(statements)
    for statement in parse.statements_iterate(&statements_iterator) {
        print_statement(w, statement^)
        fmt.wprintln(w, ";")
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

print_cursor :: proc(w: io.Writer, loc: lex.Loc, left_pad: uint = 0) {
    fmt.wprintf(w, "%*.s", left_pad + cast(uint)(loc.char+1), "^", flush=false)
    for _ in 1..<loc.span do fmt.wprint(w, "~", flush=false)
    fmt.wprintln(w)
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
    print_statements: bool `usage:"Print all statements to stdout without running (useful to check optimizations)."`,
    optimize_all: bool `args:"name=opt-all" usage:"Enables all optimizations."`,
    optimize_double_negation_elision: bool `args:"name=opt-double-negation-elision" usage:"Optimizes '--foo' to 'foo'."`,
    optimize_sum_inherits_unary_sign: bool `args:"name=opt-sum-inherits-unary-sign" usage:"Optimizes 'a + -b' to 'a - b'."`,
    optimize_precompute_const_expr: bool `args:"name=opt-constexpr" usage:"Optimizes constant expressions by precomputing them."`,
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
    stderr := os.stream_from_handle(os.stderr)
    stdout := os.stream_from_handle(os.stdout)

    expr_source := strings.join(cli_options.expr[:], " ")
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
        fmt.wprintfln(stderr, "Parse Error: {}({}:{})", parse_err, tok.loc.line+1, tok.loc.char+1)
        fmt.wprintfln(stderr, "'{}'", get_line(expr_source, tok.loc.line))
        print_cursor(stderr, tok.loc, 1)
        return 1
    }

    optimizations: optimizer.Optimization_Settings
    if cli_options.optimize_all {
        optimizations = optimizer.Optimize_All
    } else {
        // TODO: Use reflection?
        optimizations.double_negation_elision = cli_options.optimize_double_negation_elision
        optimizations.sum_inherits_unary_sign = cli_options.optimize_sum_inherits_unary_sign
        optimizations.precompute_const_expr   = cli_options.optimize_precompute_const_expr
    }
    if optimizer.needs_optimizing(optimizations) {
        optimizer.optimize(&statements, optimizations)
    }

    if cli_options.print_statements {
        println_statements(stdout, statements)
        return 0
    }

    global_scope: run.Global_Scope
    // See 'runner/default_context.odin'
    run.global_scope_init_default(&global_scope)
    defer run.global_scope_destroy(&global_scope)

    res, run_err := run.exec(&global_scope, statements)
    defer delete(res)

    switch x in run_err {
    case run.Runner_Error:
        fmt.wprintfln(stderr, "Runner Error: {}", x)
        return 1
    case run.Localized_Runner_Error:
        fmt.wprintfln(stderr, "Runner Error: {}({}:{})", x.err, x.loc.line+1, x.loc.char+1)
        fmt.wprintfln(stderr, "'{}'", get_line(expr_source, x.loc.line))
        print_cursor(stderr, x.loc, 1)
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

        fmt.wprintf(stdout, "%*s%w%*s = ",
            int_padding, "",
            x.value,
            fractional_padding, "")
        print_node(stdout, x.expr)
        fmt.wprintln(stdout)
    }

    return 0
}
