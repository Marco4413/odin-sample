package lexer

import "core:io"
import "core:mem"
import "core:strings"

Lexer :: struct {
    ident_allocator: mem.Dynamic_Arena,
    source: string,
    source_reader: strings.Reader,
    loc: Loc
}

Lexer_Error :: enum {
    None,
    Unknown_Token
}

Error :: union #shared_nil {
    Lexer_Error,
    io.Error
}

lexer_init :: proc(self: ^Lexer, source_view: string, allocator := context.allocator) {
    context.allocator = allocator
    mem.dynamic_arena_init(&self.ident_allocator)
    self.source = source_view
    strings.reader_init(&self.source_reader, self.source)
}

lexer_destroy :: proc(self: ^Lexer) {
    mem.dynamic_arena_destroy(&self.ident_allocator)
}

@private lexer_prev_char :: proc(self: ^Lexer) -> Error {
    strings.reader_unread_rune(&self.source_reader) or_return
    self.loc.char -= 1
    return nil
}

@private lexer_next_char :: proc(self: ^Lexer) -> (rr: rune, err: Error) {
    rr, _ = strings.reader_read_rune(&self.source_reader) or_return
    if rr == '\n' {
        self.loc.line += 1
        self.loc.char  = 0
    } else {
        self.loc.char += 1
    }
    return
}

@private lexer_get_current_byte :: proc(self: ^Lexer) -> (cur: i64, err: Error) {
    return strings.reader_seek(&self.source_reader, 0, .Current)
}

@private lexer_go_back_to_byte :: proc(self: ^Lexer, cur: i64) -> (err: Error) {
    _, err = strings.reader_seek(&self.source_reader, cur, .Start)
    return
}

@private lexer_has_next_rune :: proc(self: ^Lexer) -> bool {
    return strings.reader_length(&self.source_reader) > 0
}

@private lexer_trim_left :: proc(self: ^Lexer) -> (err: Error) {
    for lexer_has_next_rune(self) {
        rr := lexer_next_char(self) or_return
        if !strings.is_space(rr) {
            lexer_prev_char(self)
            break
        }
    }

    return
}

@private is_digit :: proc(r: rune) -> bool {
    return r >= '0' && r <= '9'
}

@private is_alpha :: proc(r: rune) -> bool {
    return (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z')
}

@private is_alpha_numeric :: proc(r: rune) -> bool {
    return is_alpha(r) || is_digit(r)
}

@private lexer_parse_number :: proc(self: ^Lexer) -> (num: f64, err: Error) {
    num_start := lexer_get_current_byte(self) or_return
    rr        := lexer_next_char(self) or_return
    if !is_digit(rr) {
        lexer_prev_char(self) or_return
        err = .Unknown_Token
        return
    }

    cur_err: Error
    for is_digit(rr) && cur_err == nil {
        num *= 10
        num += cast(f64)rr - '0'
        rr, cur_err = lexer_next_char(self)
    }

    if cur_err == nil && !strings.is_separator(rr) {
        lexer_go_back_to_byte(self, num_start) or_return
        err = .Unknown_Token
        return
    }

    lexer_prev_char(self)
    return
}

@private lexer_parse_ident :: proc(self: ^Lexer) -> (ident: string, err: Error) {
    context.allocator = mem.dynamic_arena_allocator(&self.ident_allocator)

    ident_start := lexer_get_current_byte(self) or_return

    rr := lexer_next_char(self) or_return
    if !is_alpha(rr) {
        err = .Unknown_Token
        lexer_prev_char(self)
        return
    }

    cur_err: Error
    for is_alpha_numeric(rr) && cur_err == nil {
        rr, cur_err = lexer_next_char(self)
    }
    lexer_prev_char(self)

    ident_end := lexer_get_current_byte(self) or_return
    ident = strings.clone(self.source[ident_start:ident_end])

    return
}

lexer_next :: proc(self: ^Lexer) -> (tok: Token, err: Error) {
    lexer_trim_left(self) or_return
    tok.loc = self.loc

    rr := lexer_next_char(self) or_return
    tok.loc.span = 1
    switch rr {
    case '+': tok.kind = .Add; return
    case '-': tok.kind = .Sub; return
    case '*': tok.kind = .Mul; return
    case '/': tok.kind = .Div; return
    case '^': tok.kind = .Pow; return
    case '(': tok.kind = .Open_Parenth;  return
    case ')': tok.kind = .Close_Parenth; return
    case ',': tok.kind = .Comma;         return
    case: lexer_prev_char(self)
    }
    tok.loc.span = 0

    // Reader errors should propagate
    tok.value, err = lexer_parse_number(self)
    if err == nil do tok.kind = .Number
    else if _, is_lexer_error := err.(Lexer_Error); is_lexer_error {
        tok.ident, err = lexer_parse_ident(self)
        if err == nil do tok.kind = .Ident
    }

    if self.loc.line == tok.loc.line {
        assert(self.loc.char >= tok.loc.char)
        tok.loc.span = self.loc.char - tok.loc.char
    }

    return
}
