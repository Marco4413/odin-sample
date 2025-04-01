package runner

import "../parser"

Fun_Args_Iterator :: parser.Fun_Args_Iterator
fun_args_iterate  :: parser.node_fun_call_iterate_args

Fun     :: #type proc(ctx: ^Exec_Context, args: ^Fun_Args_Iterator) -> (res: Result, err: Error)
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
exec_context_set_function :: proc(self: ^Exec_Context, fun_name: string, fun: Fun) {
    self.functions[fun_name] = fun
}
