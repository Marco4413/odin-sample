package runner

import "../parser"

Fun_Args_Iterator :: parser.Fun_Args_Iterator
fun_args_iterate  :: parser.node_fun_call_iterate_args

// Any node in args should be evaluated against caller_scope
Fun_Call :: #type proc(self: ^Fun, caller_scope: ^Fun_Scope, args: ^Fun_Args_Iterator) -> (res: Result, err: Error)
Fun      :: struct {
    call: Fun_Call,
    data: rawptr,
}

Fun_Map :: map[string]Fun
Var_Map :: map[string]Result

Global_Scope :: struct {
    functions: Fun_Map,
    variables: Var_Map,
}

global_scope_init :: proc(self: ^Global_Scope, allocator := context.allocator) {
    context.allocator = allocator
    self.functions = make(Fun_Map)
    self.variables = make(Var_Map)
}

global_scope_destroy :: proc(self: ^Global_Scope) {
    delete(self.functions)
    delete(self.variables)
}

// The given var_name must outlive the context
global_scope_set_variable :: proc(self: ^Global_Scope, var_name: string, val: Result) {
    self.variables[var_name] = val
}

// The given fun_name must outlive the context
global_scope_set_function :: proc(self: ^Global_Scope, fun_name: string, fun_call: Fun_Call, fun_data: rawptr = nil) {
    self.functions[fun_name] = {
        call = fun_call,
        data = fun_data,
    }
}

Fun_Scope :: struct {
    global: ^Global_Scope,
    local_variables: Var_Map,
}

fun_scope_init :: proc(self: ^Fun_Scope, global: ^Global_Scope, allocator := context.allocator) {
    context.allocator = allocator
    assert(global != nil)
    self.global = global
    self.local_variables = make(Var_Map)
}

fun_scope_destroy :: proc(self: ^Fun_Scope) {
    self.global = nil
    delete(self.local_variables)
}

// The given var_name must outlive the context
fun_scope_set_local_variable :: proc(self: ^Fun_Scope, var_name: string, val: Result) {
    self.local_variables[var_name] = val
}
