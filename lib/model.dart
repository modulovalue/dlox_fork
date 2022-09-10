abstract class SyntheticToken {
  TokenType get type;

  String? get str;
}

abstract class NaturalToken implements SyntheticToken {
  Loc get loc;
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
  BREAK, // TODO: add in dlox?
  CONTINUE, // TODO: add in dlox?

  // Editor syntactic sugar & helpers (dummy tokens)
  ERROR,
  COMMENT,
  EOF,
}

// TODO migrate to store and absolute offset and no line information.
abstract class Loc {
  int get line;
}

class SyntheticTokenImpl implements SyntheticToken {
  @override
  final TokenType type;
  @override
  final String? str;

  const SyntheticTokenImpl({
    required final this.type,
    required final this.str,
  });

  @override
  bool operator ==(final Object other) =>
      identical(this, other) ||
      other is SyntheticTokenImpl &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          str == other.str;

  @override
  int get hashCode => type.hashCode ^ str.hashCode;
}

class NaturalTokenImpl implements NaturalToken {
  @override
  final TokenType type;
  @override
  final String str;
  @override
  final Loc loc;

  const NaturalTokenImpl({
    required final this.type,
    required final this.str,
    required final this.loc,
  });

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
        return str;
      } else {
        return _TOKEN_REPR[type]!;
      }
    }
  }

  @override
  bool operator ==(
    final Object o,
  ) => o is NaturalToken && o.type == type && o.loc == loc && o.str == str;

  @override
  int get hashCode => type.hashCode ^ loc.hashCode ^ str.hashCode;

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
    TokenType.BREAK: 'break',
    TokenType.CONTINUE: 'continue',

    // Editor syntactic sugar (dummy tokens)
    TokenType.COMMENT: '<//>',
    TokenType.EOF: 'eof',
    TokenType.ERROR: '<error>',
  };
}

class LocImpl implements Loc {
  @override
  final int line;

  const LocImpl(
    final this.line,
  );

  @override
  String toString() {
    return '$line';
  }

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
