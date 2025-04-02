package parser

import "core:mem"
import "core:strings"

import lex "../lexer"

Parser :: struct {
    lexer: lex.Lexer,
    cur_tok: lex.Token,
    cur_tok_err: lex.Error,
}

Parser_Error :: enum {
    None,
    Unexpected_Token
}

Error :: union #shared_nil {
    Parser_Error,
    mem.Allocator_Error,
    lex.Error,
}

parser_init :: proc(self: ^Parser, source_view: string, allocator := context.allocator) {
    lex.lexer_init(&self.lexer, source_view, allocator = allocator)
    self.cur_tok, _ = lex.lexer_next(&self.lexer)
}

parser_destroy :: proc(self: ^Parser) {
    lex.lexer_destroy(&self.lexer)
}

parser_current_token :: proc(self: ^Parser) -> (tok: lex.Token, err: lex.Error) {
    return self.cur_tok, self.cur_tok_err
}

@private parser_consume_token :: proc(self: ^Parser) {
    self.cur_tok, self.cur_tok_err = lex.lexer_next(&self.lexer)
}

@private parser_parse_atom :: proc(self: ^Parser) -> (node: ^Node, err: Error) {
    // Check for parentheses
    open_parenth := parser_current_token(self) or_return
    if open_parenth.kind == .Open_Parenth {
        parser_consume_token(self)
        node = parser_parse_expr(self, 0) or_return
        close_parenth := parser_current_token(self) or_return
        if close_parenth.kind == .Close_Parenth {
            parser_consume_token(self)
        } else {
            err = .Unexpected_Token
        }
    } else if open_parenth.kind == .Ident {
        func_node: Node_Fun_Call
        func_node.loc       = open_parenth.loc
        func_node.func_name = strings.clone(open_parenth.ident)
        parser_consume_token(self)

        lex_err: lex.Error
        open_parenth, lex_err = parser_current_token(self)
        if lex_err == .EOF || open_parenth.kind != .Open_Parenth {
            // It's a variable
            var_node: Node_Var
            var_node.loc      = func_node.loc
            var_node.var_name = func_node.func_name
            node  = new(Node) or_return
            node^ = var_node
            return
        } else if lex_err != nil {
            err = lex_err
            return
        }

        parser_consume_token(self)
        close_parenth_or_comma := parser_current_token(self) or_return

        for {
            if close_parenth_or_comma.kind == .Close_Parenth do break

            arg := parser_parse_expr(self, 0) or_return
            node_fun_call_push_arg(&func_node, arg)

            close_parenth_or_comma = parser_current_token(self) or_return
            if close_parenth_or_comma.kind != .Comma do break
            parser_consume_token(self) // Consume comma
        }

        if close_parenth_or_comma.kind != .Close_Parenth {
            err = .Unexpected_Token
            return
        }

        // Consume close parenth
        parser_consume_token(self)
        node  = new(Node) or_return
        node^ = func_node
    } else {
        number := parser_current_token(self) or_return
        if number.kind != .Number {
            err = .Unexpected_Token
            return
        }
    
        parser_consume_token(self)
        node  = new(Node) or_return
        node^ = number.value
        return
    }
    return
}

@private parser_parse_expr :: proc(self: ^Parser, current_precedence: uint) -> (node: ^Node, err: Error) {
    // https://en.wikipedia.org/wiki/Operator-precedence_parser#Precedence_climbing_method
    binop := Node_Binop{}
    binop.lhs = parser_parse_atom(self) or_return

    for {
        tok_operator, lex_error := parser_current_token(self)
        if lex_error == .EOF do break
        // Any other error is to be treated as fatal
        lex_error or_return
    
        // On invalid operator stop parsing
        binop.op        = tok_to_binop_type(tok_operator.kind) or_break
        new_precedence := get_operator_precedence(binop.op)
        // If new prec. is lower or equal to the current one go back to the parent call
        // Going back to the previous call on equal allows us to reduce the call stack's depth
        // Moreover, this allows In-Order Visits of the tree to go from left to right by default
        if new_precedence <= current_precedence do break

        // Consume operator
        parser_consume_token(self)
        binop.rhs = parser_parse_expr(self, new_precedence) or_return

        next_lhs := new(Node)
        next_lhs^ = binop
        binop     = Node_Binop{}
        binop.lhs = next_lhs
    }

    node = binop.lhs
    return
}

@private parser_parse_stmt :: proc(self: ^Parser) -> (statement: Statement, err: Error) {
    statement_keyword := parser_current_token(self) or_return
    statement = Statement_Expr{ expr = nil }

    #partial switch statement_keyword.kind {
    case .Keyword_Var: statement = Statement_Var{ }
    case .Keyword_Fun: statement = Statement_Fun{ }
    }

    switch &x in statement {
    case Statement_Expr:
        x.expr = parser_parse_expr(self, 0) or_return
    case Statement_Var:
        parser_consume_token(self)
        ident_name := parser_current_token(self) or_return
        if ident_name.kind != .Ident {
            err = .Unexpected_Token
            return
        }

        parser_consume_token(self)
        x.var_name = strings.clone(ident_name.ident)
        equal := parser_current_token(self) or_return

        if equal.kind != .Equal {
            err = .Unexpected_Token
            return
        }

        parser_consume_token(self)
        x.expr = parser_parse_expr(self, 0) or_return
    case Statement_Fun:
        parser_consume_token(self)
        ident_name := parser_current_token(self) or_return
        if ident_name.kind != .Ident {
            err = .Unexpected_Token
            return
        }

        parser_consume_token(self)
        x.fun_name = strings.clone(ident_name.ident)

        open_parenth := parser_current_token(self) or_return
        if open_parenth.kind != .Open_Parenth {
            err = .Unexpected_Token
            return
        }

        parser_consume_token(self)
        close_parenth_or_comma := parser_current_token(self) or_return

        for {
            if close_parenth_or_comma.kind == .Close_Parenth do break

            arg_ident := parser_current_token(self) or_return
            if arg_ident.kind != .Ident {
                err = .Unexpected_Token
                return
            }

            statement_fun_push_arg(&x, strings.clone(arg_ident.ident))
            parser_consume_token(self)

            close_parenth_or_comma = parser_current_token(self) or_return
            if close_parenth_or_comma.kind != .Comma do break
            parser_consume_token(self) // Consume comma
        }

        if close_parenth_or_comma.kind != .Close_Parenth {
            err = .Unexpected_Token
            return
        }

        parser_consume_token(self)
        equal := parser_current_token(self) or_return
        if equal.kind != .Equal {
            err = .Unexpected_Token
            return
        }

        parser_consume_token(self)
        x.expr = parser_parse_expr(self, 0) or_return
    }

    return
}

parser_parse :: proc(self: ^Parser, expr_allocator: ^mem.Dynamic_Arena) -> (statements: Statements, err: Error) {
    context.allocator = mem.dynamic_arena_allocator(expr_allocator)
    for {
        semi_colon, tok_err := parser_current_token(self)
        if tok_err == .EOF do return
        if semi_colon.kind == .Semi_Colon {
            // Skip empty statement
            parser_consume_token(self)
            continue
        }

        statement := parser_parse_stmt(self) or_return
        statements_push(&statements, statement)

        semi_colon, tok_err = parser_current_token(self)
        if tok_err != nil {
            assert(tok_err == .EOF)
            return
        }

        // Require ; after a statement
        if semi_colon.kind != .Semi_Colon {
            err = .Unexpected_Token
            return
        }
    }
}
