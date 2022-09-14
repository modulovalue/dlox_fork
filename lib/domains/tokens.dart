abstract class Token {
  TokenType get type;

  Loc get loc;

  String get lexeme;

  String get info;
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
  String get info {
    return '<${toString()} at $loc>';
  }

  @override
  String toString() {
    if (!_TOKEN_REPR.containsKey(type)) {
      throw Exception('Representation not found: $type');
    } else {
      if (type == TokenType.EOF) {
        return '';
      } else if (type == TokenType.NUMBER || type == TokenType.STRING || type == TokenType.IDENTIFIER) {
        return lexeme;
      } else {
        return _TOKEN_REPR[type]!;
      }
    }
  }

  @override
  bool operator ==(
    final Object o,
  ) =>
      o is Token && o.type == type && o.loc == loc && o.lexeme == lexeme;

  @override
  int get hashCode => type.hashCode ^ loc.hashCode ^ lexeme.hashCode;

  static const _TOKEN_REPR = {
    // Symbols
    TokenType.LEFT_PAREN: '(',
    TokenType.RIGHT_PAREN: ')',
    TokenType.LEFT_BRACE: '{',
    TokenType.RIGHT_BRACE: '}',
    TokenType.LEFT_BRACK: '[',
    TokenType.RIGHT_BRACK: ']',
    TokenType.COMMA: ',',
    TokenType.DOT: '.',
    TokenType.SEMICOLON: ';',
    TokenType.COLON: ':',
    TokenType.BANG: '!',

    // Operators
    TokenType.MINUS: '-',
    TokenType.PLUS: '+',
    TokenType.SLASH: '/',
    TokenType.STAR: '*',
    TokenType.PERCENT: '%',
    TokenType.CARET: '^',
    TokenType.EQUAL: '=',
    TokenType.AND: 'and',
    TokenType.OR: 'or',

    // Comparators
    TokenType.BANG_EQUAL: '!=',
    TokenType.EQUAL_EQUAL: '==',
    TokenType.GREATER: '>',
    TokenType.GREATER_EQUAL: '>=',
    TokenType.LESS: '<',
    TokenType.LESS_EQUAL: '<=',

    // Literals
    TokenType.IDENTIFIER: '<identifier>',
    TokenType.STRING: '<str>',
    TokenType.NUMBER: '<num>',
    TokenType.OBJECT: '<obj>',

    // Keywords
    TokenType.CLASS: 'class',
    TokenType.ELSE: 'else',
    TokenType.FALSE: 'false',
    TokenType.FOR: 'for',
    TokenType.FUN: 'fun',
    TokenType.IF: 'if',
    TokenType.NIL: 'nil',
    TokenType.PRINT: 'print',
    TokenType.RETURN: 'rtn',
    TokenType.SUPER: 'super',
    TokenType.THIS: 'this',
    TokenType.TRUE: 'true',
    TokenType.VAR: 'var',
    TokenType.WHILE: 'while',
    TokenType.IN: 'in',

    // Editor syntactic sugar (dummy tokens)
    TokenType.COMMENT: '<//>',
    TokenType.EOF: 'eof',
    TokenType.ERROR: '<error>',
  };
}

enum TokenType {
  // Single-char tokens.
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

  // One or two char tokens.
  BANG,
  BANG_EQUAL,
  EQUAL,
  EQUAL_EQUAL,
  GREATER,
  GREATER_EQUAL,
  LESS,
  LESS_EQUAL,

  // Literals.
  IDENTIFIER,
  STRING,
  NUMBER,
  OBJECT,

  // Keywords.
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

  // Editor syntactic sugar & helpers (dummy tokens)
  ERROR,
  COMMENT,
  EOF,
}

// TODO migrate to an absolute offset and no line information.
abstract class Loc {
  int get line;
}

class LocImpl implements Loc {
  @override
  final int line;

  const LocImpl(
    final this.line,
  );

  @override
  String toString() => line.toString();

  @override
  bool operator ==(
    final Object other,
  ) {
    return (other is Loc) && other.line == line;
  }

  @override
  int get hashCode {
    return line.hashCode;
  }
}
