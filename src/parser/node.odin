package parser

import "core:container/intrusive/list"

import lex "../lexer"

Node_Number :: f64

Node_Var :: struct {
    var_name: string,
}

Binop_Kind :: enum {
    Add, Sub, Mul, Div, Pow
}

Node_Binop :: struct {
    op: Binop_Kind,
    lhs: ^Node,
    rhs: ^Node,
}

Fun_Args_Iterator :: list.Iterator(Fun_Arg)

Fun_Arg :: struct {
    link: list.Node,
    node: ^Node,
}

Node_Fun_Call :: struct {
    func_name: string,
    args: list.List,
}

Node :: union {
    Node_Number,
    Node_Binop,
    Node_Var,
    Node_Fun_Call,
}

@(private="package")
node_fun_call_push_arg :: proc(self: ^Node_Fun_Call, node: ^Node) {
    arg      := new(Fun_Arg)
    arg.node = node
    list.push_back(&self.args, &arg.link)
}

node_fun_call_iterator_args :: proc(self: ^Node_Fun_Call) -> Fun_Args_Iterator {
    return list.iterator_head(self.args, Fun_Arg, "link")
}

node_fun_call_iterate_args :: proc(iterator: ^Fun_Args_Iterator) -> (ptr: ^Fun_Arg, ok: bool) {
    return list.iterate_next(iterator)
}

get_operator_precedence :: proc(operator: Binop_Kind) -> uint {
    switch operator {
    case .Add, .Sub: return 0
    case .Mul, .Div: return 1
    case .Pow: return 2
    case: unreachable()
    }
}

get_operator_assoc :: proc(operator: Binop_Kind) -> uint {
    switch operator {
    case .Add, .Sub,
         .Mul, .Div:
        return 0
    case .Pow: return 1
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
