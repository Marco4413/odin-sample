package parser

import "core:container/intrusive/list"

import lex "../lexer"

Node_Number :: f64

Node_Var :: struct {
    loc: lex.Loc,
    var_name: string,
}

Unop_Kind :: enum {
    Negate
}

Node_Unop :: struct {
    op: Unop_Kind,
    expr: ^Node,
}

Binop_Kind :: enum {
    Add, Sub, Mul, Div, Pow
}

Node_Binop :: struct {
    op: Binop_Kind,
    lhs: ^Node,
    rhs: ^Node,
}

Fun_Args :: distinct list.List
Fun_Args_Iterator :: list.Iterator(Fun_Args_Item)
Fun_Args_Item :: struct {
    link: list.Node,
    node: ^Node,
}

Node_Fun_Call :: struct {
    loc: lex.Loc,
    func_name: string,
    args: Fun_Args,
}

Node :: union {
    Node_Number,
    Node_Unop,
    Node_Binop,
    Node_Var,
    Node_Fun_Call,
}

@(private="package")
node_fun_call_push_arg :: proc(self: ^Node_Fun_Call, node: ^Node) {
    arg     := new(Fun_Args_Item)
    arg.node = node
    list.push_back(cast(^list.List)&self.args, &arg.link)
}

node_fun_call_iterator_args :: proc(self: ^Node_Fun_Call) -> Fun_Args_Iterator {
    return list.iterator_head(cast(list.List)self.args, Fun_Args_Item, "link")
}

node_fun_call_iterate_args :: proc(iterator: ^Fun_Args_Iterator) -> (ptr: ^Node, ok: bool) {
    fun_arg := list.iterate_next(iterator) or_return
    ptr = fun_arg.node
    ok  = true
    return
}

get_operator_precedence :: proc(operator: Binop_Kind) -> uint {
    // NOTE: 0 should not be used by any operator
    switch operator {
    case .Add, .Sub: return 1
    case .Mul, .Div: return 2
    case .Pow: return 3
    case: unreachable()
    }
}

tok_to_binop_type :: proc(tok_kind: lex.Token_Kind) -> (op: Binop_Kind, ok: bool) {
    ok = true

    #partial switch tok_kind {
    case .Add: op = .Add
    case .Sub: op = .Sub
    case .Mul: op = .Mul
    case .Div: op = .Div
    case .Pow: op = .Pow
    case: ok = false
    }

    return
}
