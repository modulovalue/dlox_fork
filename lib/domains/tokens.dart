abstract class Token {
  TokenType get type;

  Loc get loc;

  String get lexeme;
}

class TokenImpl implements Token {
  @override
  final TokenType type;
  @override
  final String lexeme;
  @override
  final Loc loc;

  const TokenImpl({
    required final this.type,
    required final this.lexeme,
    required final this.loc,
  });

  @override
  String toString() {
    switch (type) {
      case TokenType.LEFT_PAREN:
        return '(';
      case TokenType.RIGHT_PAREN:
        return ')';
      case TokenType.LEFT_BRACE:
        return '{';
      case TokenType.RIGHT_BRACE:
        return '}';
      case TokenType.LEFT_BRACK:
        return '[';
      case TokenType.RIGHT_BRACK:
        return ']';
      case TokenType.COMMA:
        return ',';
      case TokenType.DOT:
        return '.';
      case TokenType.SEMICOLON:
        return ';';
      case TokenType.COLON:
        return ':';
      case TokenType.BANG:
        return '!';
      case TokenType.MINUS:
        return '-';
      case TokenType.PLUS:
        return '+';
      case TokenType.SLASH:
        return '/';
      case TokenType.STAR:
        return '*';
      case TokenType.PERCENT:
        return '%';
      case TokenType.CARET:
        return '^';
      case TokenType.EQUAL:
        return '=';
      case TokenType.AND:
        return 'and';
      case TokenType.OR:
        return 'or';
      case TokenType.BANG_EQUAL:
        return '!=';
      case TokenType.EQUAL_EQUAL:
        return '==';
      case TokenType.GREATER:
        return '>';
      case TokenType.GREATER_EQUAL:
        return '>=';
      case TokenType.LESS:
        return '<';
      case TokenType.LESS_EQUAL:
        return '<=';
      case TokenType.OBJECT:
        return '<obj>';
      case TokenType.CLASS:
        return 'class';
      case TokenType.ELSE:
        return 'else';
      case TokenType.FALSE:
        return 'false';
      case TokenType.FOR:
        return 'for';
      case TokenType.FUN:
        return 'fun';
      case TokenType.IF:
        return 'if';
      case TokenType.NIL:
        return 'nil';
      case TokenType.PRINT:
        return 'print';
      case TokenType.RETURN:
        return 'rtn';
      case TokenType.SUPER:
        return 'super';
      case TokenType.THIS:
        return 'this';
      case TokenType.TRUE:
        return 'true';
      case TokenType.VAR:
        return 'var';
      case TokenType.WHILE:
        return 'while';
      case TokenType.IN:
        return 'in';
      case TokenType.COMMENT:
        return '<//>';
      case TokenType.ERROR:
        return '<error>';
      case TokenType.EOF:
        return '';
      case TokenType.NUMBER:
        return lexeme;
      case TokenType.STRING:
        return lexeme;
      case TokenType.IDENTIFIER:
        return lexeme;
    }
  }

  @override
  bool operator ==(
    final Object o,
  ) {
    return o is Token && o.type == type && o.loc == loc && o.lexeme == lexeme;
  }

  @override
  int get hashCode {
    return type.hashCode ^ loc.hashCode ^ lexeme.hashCode;
  }
}

enum TokenType {
  LEFT_PAREN,
  RIGHT_PAREN,
  LEFT_BRACE,
  RIGHT_BRACE,
  LEFT_BRACK,
  RIGHT_BRACK,
  COMMA,
  DOT,
  MINUS,
  PLUS,
  SEMICOLON,
  SLASH,
  STAR,
  COLON,
  PERCENT,
  CARET,
  BANG,
  BANG_EQUAL,
  EQUAL,
  EQUAL_EQUAL,
  GREATER,
  GREATER_EQUAL,
  LESS,
  LESS_EQUAL,
  AND,
  CLASS,
  ELSE,
  FALSE,
  FOR,
  FUN,
  IF,
  NIL,
  OR,
  PRINT,
  RETURN,
  SUPER,
  THIS,
  TRUE,
  VAR,
  WHILE,
  IN,
  IDENTIFIER,
  STRING,
  NUMBER,
  OBJECT,
  ERROR,
  COMMENT,
  EOF,
}

abstract class Loc {
  int get line;
}

class LocImpl implements Loc {
  @override
  final int line;

  const LocImpl({
    required final this.line,
  });
}
