package runner

import "core:math"

import "../parser"

Runner_Error :: enum {
    None,
    Nil_Node,
    Undefined_Variable,
    Undefined_Function,
}

Result :: parser.Node_Number
Error  :: Runner_Error

exec :: proc(ctx: ^Exec_Context, expr: ^parser.Node) -> (res: Result, err: Error) {
    if expr == nil {
        err = .Nil_Node
        return
    }

    switch &x in expr^ {
    case parser.Node_Number:
        res = x
    case parser.Node_Var:
        var, found := ctx.variables[x.var_name]
        if !found {
            err = .Undefined_Variable
            return
        }

        res = var
    case parser.Node_Binop:
        switch x.op {
        case .Add: res = (exec(ctx, x.lhs) or_return) + (exec(ctx, x.rhs) or_return)
        case .Sub: res = (exec(ctx, x.lhs) or_return) - (exec(ctx, x.rhs) or_return)
        case .Mul: res = (exec(ctx, x.lhs) or_return) * (exec(ctx, x.rhs) or_return)
        case .Div: res = (exec(ctx, x.lhs) or_return) / (exec(ctx, x.rhs) or_return)
        case .Pow: res = math.pow((exec(ctx, x.lhs) or_return), (exec(ctx, x.rhs) or_return))
        }
    case parser.Node_Fun_Call:
        fun, found := ctx.functions[x.func_name]
        if !found {
            err = .Undefined_Function
            return
        }

        args_iterator := parser.node_fun_call_iterator_args(&x)
        res = fun(ctx, &args_iterator) or_return
    }

    return
}

exec_contextless :: proc(expr: ^parser.Node) -> (res: Result, err: Error) {
    ctx: Exec_Context
    exec_context_init(&ctx)
    defer exec_context_destroy(&ctx)
    return exec(&ctx, expr)
}
