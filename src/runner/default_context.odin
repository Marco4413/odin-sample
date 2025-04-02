package runner

import "core:math"

import "../parser"

exec_context_init_default :: proc(self: ^Exec_Context) {
    exec_context_init(self)

    exec_context_set_variable(self, "pi", math.π)
    exec_context_set_variable(self, "e",  math.e)

    exec_context_set_function(self, "if",  math_if)

    exec_context_set_function(self, "min", math_min)
    exec_context_set_function(self, "max", math_max)

    exec_context_set_function(self, "floor", math_floor)
    exec_context_set_function(self, "ceil",  math_ceil)
}

to_node_array :: proc($N: int, args: ^Fun_Args_Iterator) -> (res: [N]^parser.Node, err: Error) {
    cur_idx := 0
    for arg in fun_args_iterate(args) {
        if cur_idx >= len(res) {
            err = .Arity_Mismatch
            return
        }

        res[cur_idx] = arg
        cur_idx += 1
    }

    if cur_idx < len(res) {
        err = .Arity_Mismatch
        return
    }

    return
}

math_if :: proc(_: ^Fun, ctx: ^Exec_Context, args_iterator: ^Fun_Args_Iterator) -> (res: Result, err: Error) {
    args      := to_node_array(3, args_iterator) or_return
    truth_val := exec_expr(ctx, args[0]) or_return
    if truth_val > 0 {
        res = exec_expr(ctx, args[1]) or_return
    } else {
        res = exec_expr(ctx, args[2]) or_return
    }
    return
}

math_min :: proc(_: ^Fun, ctx: ^Exec_Context, args: ^Fun_Args_Iterator) -> (res: Result, err: Error) {
    res = math.INF_F64
    for arg in fun_args_iterate(args) {
        val := exec_expr(ctx, arg) or_return
        if val < res do res = val
    }

    return
}

math_max :: proc(_: ^Fun, ctx: ^Exec_Context, args: ^Fun_Args_Iterator) -> (res: Result, err: Error) {
    res = math.NEG_INF_F64
    for arg in fun_args_iterate(args) {
        val := exec_expr(ctx, arg) or_return
        if val > res do res = val
    }

    return
}

math_floor :: proc(_: ^Fun, ctx: ^Exec_Context, args_iterator: ^Fun_Args_Iterator) -> (res: Result, err: Error) {
    args := to_node_array(1, args_iterator) or_return
    res   = math.floor(exec_expr(ctx, args[0]) or_return)
    return
}

math_ceil :: proc(_: ^Fun, ctx: ^Exec_Context, args_iterator: ^Fun_Args_Iterator) -> (res: Result, err: Error) {
    args := to_node_array(1, args_iterator) or_return
    res   = math.ceil(exec_expr(ctx, args[0]) or_return)
    return
}
