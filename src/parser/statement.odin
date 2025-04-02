package parser

import "core:container/intrusive/list"

Statement_Expr :: struct {
    expr: ^Node
}

Statement_Let :: struct {
    var_name: string,
    expr: ^Node
}

Statement_Fun_Args          :: distinct list.List
Statement_Fun_Args_Iterator :: list.Iterator(Statement_Fun_Args_Item)
Statement_Fun_Args_Item     :: struct {
    link: list.Node,
    arg_name: string,
}

Statement_Fun :: struct {
    fun_name: string,
    args: Statement_Fun_Args,
    expr: ^Node
}

Statement :: union {
    Statement_Expr,
    Statement_Let,
    Statement_Fun,
}

Statements          :: distinct list.List
Statements_Iterator :: list.Iterator(Statements_Item)
Statements_Item     :: struct {
    link: list.Node,
    statement: Statement,
}

@(private="package")
statement_fun_push_arg :: proc(self: ^Statement_Fun, arg_name: string) {
    arg         := new(Statement_Fun_Args_Item)
    arg.arg_name = arg_name
    list.push_back(cast(^list.List)&self.args, &arg.link)
}

statement_fun_iterator_args :: proc(self: ^Statement_Fun) -> Statement_Fun_Args_Iterator {
    return list.iterator_head(cast(list.List)self.args, Statement_Fun_Args_Item, "link")
}

statement_fun_iterate_args :: proc(iterator: ^Statement_Fun_Args_Iterator) -> (arg_name: string, ok: bool) {
    fun_arg := list.iterate_next(iterator) or_return
    arg_name = fun_arg.arg_name
    ok       = true
    return
}

@(private="package")
statements_push :: proc(self: ^Statements, statement: Statement) {
    statement_item          := new(Statements_Item)
    statement_item.statement = statement
    list.push_back(cast(^list.List)self, &statement_item.link)
}

statements_iterator :: proc(self: Statements) -> Statements_Iterator {
    return list.iterator_head(cast(list.List)self, Statements_Item, "link")
}

statements_iterate :: proc(iterator: ^Statements_Iterator) -> (ptr: ^Statement, ok: bool) {
    statement_item := list.iterate_next(iterator) or_return
    ptr = &statement_item.statement
    ok  = true
    return
}
