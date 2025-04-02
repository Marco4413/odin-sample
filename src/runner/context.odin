package runner

import "../parser"

Fun_Args_Iterator :: parser.Fun_Args_Iterator
fun_args_iterate  :: parser.node_fun_call_iterate_args

Fun_Call :: #type proc(self: ^Fun, ctx: ^Exec_Context, args: ^Fun_Args_Iterator) -> (res: Result, err: Error)
Fun      :: struct {
    call: Fun_Call,
    data: rawptr,
}

Fun_Map :: map[string]Fun
Var_Map :: map[string]Result

Exec_Context :: struct {
    functions: Fun_Map,
    variables: Var_Map,
}

exec_context_init :: proc(self: ^Exec_Context) {
    self.functions = make(Fun_Map)
    self.variables = make(Var_Map)
}

exec_context_destroy :: proc(self: ^Exec_Context) {
    delete(self.functions)
    delete(self.variables)
}

// The given var_name must outlive the context
exec_context_set_variable :: proc(self: ^Exec_Context, var_name: string, val: Result) {
    self.variables[var_name] = val
}

// The given fun_name must outlive the context
exec_context_set_function :: proc(self: ^Exec_Context, fun_name: string, fun_call: Fun_Call, fun_data: rawptr = nil) {
    self.functions[fun_name] = {
        call = fun_call,
        data = fun_data,
    }
}

@private clone_map :: proc(self: ^map[$K]$V) -> (clone: map[K]V) {
    clone = make(map[K]V)
    for k, v in self do clone[k] = v
    return
}

exec_context_clone :: proc(self: ^Exec_Context) -> (res: Exec_Context) {
    res.functions = clone_map(&self.functions)
    res.variables = clone_map(&self.variables)
    return
}
