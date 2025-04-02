package runner

import "core:math"

import lex "../lexer"
import     "../parser"

Runner_Error :: enum {
    None,
    Nil_Node,
    Undefined_Variable,
    Undefined_Function,
    Arity_Mismatch,
    Variable_Redefinition,
    Function_Redefinition,
}

Localized_Runner_Error :: struct {
    err: Runner_Error,
    loc: lex.Loc,
}

Result :: parser.Node_Number
Error  :: union {
    Runner_Error,
    Localized_Runner_Error,
}

Expr_Result :: struct {
    expr: ^parser.Node,
    value: Result,
}

exec_expr :: proc(ctx: ^Exec_Context, expr: ^parser.Node) -> (res: Result, err: Error) {
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
            err = Localized_Runner_Error{ .Undefined_Variable, x.loc }
            return
        }

        res = var
    case parser.Node_Binop:
        switch x.op {
        case .Add: res = (exec_expr(ctx, x.lhs) or_return) + (exec_expr(ctx, x.rhs) or_return)
        case .Sub: res = (exec_expr(ctx, x.lhs) or_return) - (exec_expr(ctx, x.rhs) or_return)
        case .Mul: res = (exec_expr(ctx, x.lhs) or_return) * (exec_expr(ctx, x.rhs) or_return)
        case .Div: res = (exec_expr(ctx, x.lhs) or_return) / (exec_expr(ctx, x.rhs) or_return)
        case .Pow: res = math.pow((exec_expr(ctx, x.lhs) or_return), (exec_expr(ctx, x.rhs) or_return))
        }
    case parser.Node_Fun_Call:
        fun, found := ctx.functions[x.func_name]
        if !found {
            err = Localized_Runner_Error{ .Undefined_Function, x.loc }
            return
        }

        args_iterator := parser.node_fun_call_iterator_args(&x)
        res, err = fun->call(ctx, &args_iterator)
        if err != nil {
            if unloc_err, is_unlocalized_err := err.(Runner_Error); is_unlocalized_err {
                err = Localized_Runner_Error{
                    err = unloc_err,
                    loc = x.loc,
                }
            }

            return
        }
    }

    return
}

@private user_defined_fun_call :: proc(self: ^Fun, ctx: ^Exec_Context, args: ^Fun_Args_Iterator) -> (res: Result, err: Error) {
    statement_fun := cast(^parser.Statement_Fun)self.data
    args_name     := parser.statement_fun_iterator_args(statement_fun)
    child_ctx     := exec_context_clone(ctx)
    defer exec_context_destroy(&child_ctx)

    for {
        next_arg_name, next_arg_name_ok := parser.statement_fun_iterate_args(&args_name)
        next_arg,      next_arg_ok      := fun_args_iterate(args)
        if next_arg_name_ok != next_arg_ok {
            err = .Arity_Mismatch
            return
        }

        if !next_arg_ok do break
        assert(len(next_arg_name) > 0)
        exec_context_set_variable(&child_ctx, next_arg_name, (exec_expr(ctx, next_arg) or_return))
    }

    res, err = exec_expr(&child_ctx, statement_fun.expr)
    return
}

// res must be deleted by the calling frame
exec :: proc(ctx: ^Exec_Context, statements: parser.Statements) -> (res: [dynamic]Expr_Result, err: Error) {
    res = make([dynamic]Expr_Result)

    statements_iterator := parser.statements_iterator(statements)
    for statement in parser.statements_iterate(&statements_iterator) {
        switch &x in statement {
        case parser.Statement_Expr:
            value := exec_expr(ctx, x.expr) or_return
            append(&res, Expr_Result{
                expr  = x.expr,
                value = value,
            })
        case parser.Statement_Var:
            if x.var_name in ctx.variables {
                err = Localized_Runner_Error{ .Variable_Redefinition, x.loc }
                return
            }

            exec_context_set_variable(ctx, x.var_name, (exec_expr(ctx, x.expr) or_return))
        case parser.Statement_Fun:
            if x.fun_name in ctx.functions {
                err = Localized_Runner_Error{ .Function_Redefinition, x.loc }
                return
            }

            exec_context_set_function(ctx, x.fun_name, user_defined_fun_call, &x)
        case: unreachable()
        }
    }

    return
}

// res must be deleted by the calling frame
exec_contextless :: proc(statements: parser.Statements) -> (res: [dynamic]Expr_Result, err: Error) {
    ctx: Exec_Context
    exec_context_init(&ctx)
    defer exec_context_destroy(&ctx)
    return exec(&ctx, statements)
}
