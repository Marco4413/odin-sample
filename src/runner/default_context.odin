package runner

import "core:math"

import "../parser"

global_scope_init_default :: proc(self: ^Global_Scope) {
    global_scope_init(self)

    global_scope_set_variable(self, "pi", math.π)
    global_scope_set_variable(self, "e",  math.e)

    global_scope_set_function(self, "if",  math_if)

    global_scope_set_function(self, "min", math_min)
    global_scope_set_function(self, "max", math_max)

    global_scope_set_function(self, "floor", math_floor)
    global_scope_set_function(self, "ceil",  math_ceil)
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

to_eval_array :: proc($N: int, scope: ^Fun_Scope, args: ^Fun_Args_Iterator) -> (res: [N]Result, err: Error) {
    exprs := to_node_array(N, args) or_return
    for expr, idx in exprs do res[idx] = exec_expr(scope, expr) or_return
    return
}

math_if :: proc(_: ^Fun, caller_scope: ^Fun_Scope, args_iterator: ^Fun_Args_Iterator) -> (res: Result, err: Error) {
    args      := to_node_array(3, args_iterator) or_return
    truth_val := exec_expr(caller_scope, args[0]) or_return
    if truth_val > 0 {
        res = exec_expr(caller_scope, args[1]) or_return
    } else {
        res = exec_expr(caller_scope, args[2]) or_return
    }
    return
}

math_min :: proc(_: ^Fun, caller_scope: ^Fun_Scope, args: ^Fun_Args_Iterator) -> (res: Result, err: Error) {
    res = math.INF_F64
    for arg in fun_args_iterate(args) {
        val := exec_expr(caller_scope, arg) or_return
        if val < res do res = val
    }

    return
}

math_max :: proc(_: ^Fun, caller_scope: ^Fun_Scope, args: ^Fun_Args_Iterator) -> (res: Result, err: Error) {
    res = math.NEG_INF_F64
    for arg in fun_args_iterate(args) {
        val := exec_expr(caller_scope, arg) or_return
        if val > res do res = val
    }

    return
}

math_floor :: proc(_: ^Fun, caller_scope: ^Fun_Scope, args_iterator: ^Fun_Args_Iterator) -> (res: Result, err: Error) {
    args := to_eval_array(1, caller_scope, args_iterator) or_return
    res   = math.floor(args[0])
    return
}

math_ceil :: proc(_: ^Fun, caller_scope: ^Fun_Scope, args_iterator: ^Fun_Args_Iterator) -> (res: Result, err: Error) {
    args := to_eval_array(1, caller_scope, args_iterator) or_return
    res   = math.ceil(args[0])
    return
}
