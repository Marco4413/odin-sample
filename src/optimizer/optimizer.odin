package optimizer

import "core:reflect"

import "../parser"
import "../runner"

Optimization_Settings :: struct {
    double_negation_elision: bool,
    sum_inherits_unary_sign: bool,
    precompute_const_expr: bool,
}

Optimize_All :: Optimization_Settings{
    double_negation_elision = true,
    sum_inherits_unary_sign = true,
    precompute_const_expr   = true,
}

needs_optimizing :: proc(settings: Optimization_Settings) -> bool {
    // Using reflection to iterate over all fields and checking if one of them is true
    settings := settings
    for struct_field in reflect.struct_fields_zipped(Optimization_Settings) {
        assert(struct_field.type != nil, "type field of struct_field is nil")
        assert(struct_field.type.id == bool, "field in Optimization_Settings is not bool")
        field_ref := cast(^bool)(cast(uintptr)(&settings) + struct_field.offset)
        if field_ref^ do return true
    }
    return false
}

// expr must not be a cyclic graph (the default parser does not create one).
optimize_expr :: proc(expr: ^parser.Node, settings: Optimization_Settings) {
    switch &x in expr {
    case parser.Node_Number:
    case parser.Node_Unop:
        optimize_expr(x.expr, settings)
        if settings.double_negation_elision {
            if x.op == .Negate {
                #partial switch y in x.expr {
                case parser.Node_Unop:
                    if y.op == .Negate {
                        // --foo == foo
                        expr^ = y.expr^
                    }
                }
            }
        }

        if settings.precompute_const_expr {
            if x.op == .Negate {
                #partial switch y in x.expr {
                case parser.Node_Number:
                    res, err := runner.exec_expr(nil, expr)
                    assert(err == nil, "exec_expr failed when computing const-expr")
                    expr^ = res
                }
            }
        }
    case parser.Node_Binop:
        optimize_expr(x.lhs, settings)
        optimize_expr(x.rhs, settings)
        if settings.precompute_const_expr {
            _, is_lhs_const := x.lhs.(parser.Node_Number)
            _, is_rhs_const := x.rhs.(parser.Node_Number)
            if is_lhs_const && is_rhs_const {
                res, err := runner.exec_expr(nil, expr)
                assert(err == nil, "exec_expr failed when computing const-expr")
                expr^ = res
            }
        }

        if settings.sum_inherits_unary_sign {
            if x.op == .Add || x.op == .Sub {
                #partial switch y in x.rhs {
                case parser.Node_Unop:
                    if y.op == .Negate {
                        x.op  = .Add if x.op == .Sub else .Sub
                        x.rhs = y.expr
                    }
                }
            }
        }
    case parser.Node_Var:
    case parser.Node_Fun_Call:
    }
}

optimize_statement :: proc(statement: ^parser.Statement, settings: Optimization_Settings) {
    switch &x in statement {
    case parser.Statement_Expr:
        optimize_expr(x.expr, settings)
    case parser.Statement_Var:
        optimize_expr(x.expr, settings)
    case parser.Statement_Fun:
        optimize_expr(x.expr, settings)
    }
}

optimize_statements :: proc(statement: ^parser.Statements, settings: Optimization_Settings) {
    iterator := parser.statements_iterator(statement^)
    for statement in parser.statements_iterate(&iterator) {
        optimize_statement(statement, settings)
    }
}

optimize :: proc {
    optimize_expr,
    optimize_statement,
    optimize_statements,
}
