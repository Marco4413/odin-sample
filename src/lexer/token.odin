package lexer

Loc :: struct {
    char: u32,
    line: u32,
    span: u32,
}

Token_Kind :: enum {
    None,
    Add, Sub, Mul, Div, Pow,
    Open_Parenth, Close_Parenth,
    Comma, Equal, Semi_Colon,
    Ident, Number,
    Keyword_Var,
    Keyword_Fun,
}

Token :: struct {
    loc: Loc,
    kind: Token_Kind,
    ident: string,
    value: f64,
}
