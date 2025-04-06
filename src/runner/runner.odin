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

// scope may be nil if the tree represented by expr is a constant expression (operations on numbers)
exec_expr :: proc(scope: ^Fun_Scope, expr: ^parser.Node) -> (res: Result, err: Error) {
    if expr == nil {
        err = .Nil_Node
        return
    }

    switch &x in expr^ {
    case parser.Node_Number:
        res = x
    case parser.Node_Var:
        assert(scope != nil, "non const-expr passed to exec_expr with nil scope (var usage found)")
        var, found := scope.local_variables[x.var_name]
        if !found do var, found = scope.global.variables[x.var_name]
        if !found {
            err = Localized_Runner_Error{ .Undefined_Variable, x.loc }
            return
        }

        res = var
    case parser.Node_Unop:
        switch x.op {
        case .Negate: res = -(exec_expr(scope, x.expr) or_return)
        }
    case parser.Node_Binop:
        switch x.op {
        case .Add: res = (exec_expr(scope, x.lhs) or_return) + (exec_expr(scope, x.rhs) or_return)
        case .Sub: res = (exec_expr(scope, x.lhs) or_return) - (exec_expr(scope, x.rhs) or_return)
        case .Mul: res = (exec_expr(scope, x.lhs) or_return) * (exec_expr(scope, x.rhs) or_return)
        case .Div: res = (exec_expr(scope, x.lhs) or_return) / (exec_expr(scope, x.rhs) or_return)
        case .Pow: res = math.pow((exec_expr(scope, x.lhs) or_return), (exec_expr(scope, x.rhs) or_return))
        }
    case parser.Node_Fun_Call:
        assert(scope != nil, "non const-expr passed to exec_expr with nil scope (fun call found)")
        fun, found := scope.global.functions[x.func_name]
        if !found {
            err = Localized_Runner_Error{ .Undefined_Function, x.loc }
            return
        }

        args_iterator := parser.node_fun_call_iterator_args(&x)
        res, err = fun->call(scope, &args_iterator)
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

@private user_defined_fun_call :: proc(self: ^Fun, caller_scope: ^Fun_Scope, args: ^Fun_Args_Iterator) -> (res: Result, err: Error) {
    statement_fun := cast(^parser.Statement_Fun)self.data
    args_name     := parser.statement_fun_iterator_args(statement_fun)

    callee_scope: Fun_Scope
    fun_scope_init(&callee_scope, caller_scope.global)
    defer fun_scope_destroy(&callee_scope)

    for {
        next_arg_name, next_arg_name_ok := parser.statement_fun_iterate_args(&args_name)
        next_arg,      next_arg_ok      := fun_args_iterate(args)
        if next_arg_name_ok != next_arg_ok {
            err = .Arity_Mismatch
            return
        }

        if !next_arg_ok do break
        assert(len(next_arg_name) > 0)
        fun_scope_set_local_variable(&callee_scope, next_arg_name, (exec_expr(caller_scope, next_arg) or_return))
    }

    res, err = exec_expr(&callee_scope, statement_fun.expr)
    return
}

// res must be deleted by the caller
exec :: proc(_global_scope: ^Global_Scope, statements: parser.Statements, allocator := context.allocator) -> (res: []Expr_Result, err: Error) {
    context.allocator = allocator
    expr_count := 0

    root_scope: Fun_Scope
    fun_scope_init(&root_scope, _global_scope)
    defer fun_scope_destroy(&root_scope)

    statements_iterator := parser.statements_iterator(statements)
    for statement in parser.statements_iterate(&statements_iterator) {
        switch &x in statement {
        case parser.Statement_Expr:
            expr_count += 1
        case parser.Statement_Var:
            if x.var_name in root_scope.global.variables {
                err = Localized_Runner_Error{ .Variable_Redefinition, x.loc }
                return
            }

            global_scope_set_variable(root_scope.global, x.var_name, (exec_expr(&root_scope, x.expr) or_return))
        case parser.Statement_Fun:
            if x.fun_name in root_scope.global.functions {
                err = Localized_Runner_Error{ .Function_Redefinition, x.loc }
                return
            }

            global_scope_set_function(root_scope.global, x.fun_name, user_defined_fun_call, &x)
        case: unreachable()
        }
    }

    res = make([]Expr_Result, expr_count)
    res_idx := 0

    statements_iterator = parser.statements_iterator(statements)
    for statement in parser.statements_iterate(&statements_iterator) {
        #partial switch x in statement {
        case parser.Statement_Expr:
            value := exec_expr(&root_scope, x.expr) or_return
            res[res_idx].expr  = x.expr
            res[res_idx].value = value
            res_idx += 1
        }
    }

    assert(res_idx == len(res))
    return
}

// res must be deleted by the caller
exec_scopeless :: proc(statements: parser.Statements, allocator := context.allocator) -> (res: []Expr_Result, err: Error) {
    context.allocator = allocator

    global_scope: Global_Scope
    global_scope_init(&global_scope)
    defer global_scope_destroy(&global_scope)
    return exec(&global_scope, statements)
}
