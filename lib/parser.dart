import 'compiler.dart';
import 'model.dart';

MapEntry<Parser, ErrorDelegate> make_parser({
  required final List<NaturalToken> tokens,
  required final Debug debug,
}) {
  final parser = _ParserImpl(
    tokens: tokens,
    debug: debug,
  );
  return MapEntry(parser, parser);
}

class _ParserImpl implements Parser, ErrorDelegate {
  @override
  final List<NaturalToken> tokens;
  @override
  final List<CompilerError> errors;
  @override
  final Debug debug;
  @override
  NaturalToken? current;
  @override
  NaturalToken? previous;
  @override
  int current_idx;
  @override
  bool panic_mode;

  _ParserImpl({
    required final this.tokens,
    required final this.debug,
  }) : errors = [],
      current_idx = 0,
      panic_mode = false;

  void error_at(
    final NaturalToken? token,
    final String? message,
  ) {
    if (panic_mode) {
      return;
    } else {
      panic_mode = true;
      final error = CompilerError(token!, message);
      errors.add(error);
      error.dump(debug);
    }
  }

  @override
  void error_at_previous(
    final String message,
  ) {
    error_at(previous, message);
  }

  @override
  void error_at_current(
    final String? message,
  ) {
    error_at(current, message);
  }

  @override
  void advance() {
    previous = current;
    while (current_idx < tokens.length) {
      current = tokens[current_idx++];
      // Skip invalid tokens.
      if (current!.type == TokenType.ERROR) {
        error_at_current(current!.str);
      } else if (current!.type != TokenType.COMMENT) {
        break;
      }
    }
  }

  @override
  void consume(
    final TokenType type,
    final String message,
  ) {
    if (current!.type == type) {
      advance();
    } else {
      error_at_current(message);
    }
  }

  @override
  bool check(
    final TokenType type,
  ) {
    return current!.type == type;
  }

  @override
  bool match_pair(
    final TokenType first,
    final TokenType second,
  ) {
    if (!check(first) || current_idx >= tokens.length || tokens[current_idx].type != second) {
      return false;
    } else {
      advance();
      advance();
      return true;
    }
  }

  @override
  bool match(
    final TokenType type,
  ) {
    if (check(type)) {
      advance();
      return true;
    } else {
      return false;
    }
  }
}

abstract class Parser {
  abstract final List<NaturalToken> tokens;

  abstract NaturalToken? current;

  abstract NaturalToken? previous;

  abstract int current_idx;

  abstract bool panic_mode;

  void advance();

  void consume(
    final TokenType type,
    final String message,
  );

  bool check(
    final TokenType type,
  );

  bool match_pair(
    final TokenType first,
    final TokenType second,
  );

  bool match(
    final TokenType type,
  );
}

abstract class ErrorDelegate {
  List<CompilerError> get errors;

  Debug get debug;

  void error_at_previous(
    final String message,
  );

  void error_at_current(
    final String? message,
  );
}

enum Precedence {
  NONE,
  ASSIGNMENT, // =
  OR, // or
  AND, // and
  EQUALITY, // == !=
  COMPARISON, // < > <= >=
  TERM, // + -
  FACTOR, // * / %
  POWER, // ^
  UNARY, // ! -
  CALL, // . ()
  PRIMARY,
}

Precedence get_precedence(
  final TokenType type,
) {
  switch (type) {
    case TokenType.LEFT_PAREN:
      return Precedence.CALL;
    case TokenType.RIGHT_PAREN:
      return Precedence.NONE;
    case TokenType.LEFT_BRACE:
      return Precedence.NONE;
    case TokenType.RIGHT_BRACE:
      return Precedence.NONE;
    case TokenType.LEFT_BRACK:
      return Precedence.CALL;
    case TokenType.RIGHT_BRACK:
      return Precedence.NONE;
    case TokenType.COMMA:
      return Precedence.NONE;
    case TokenType.DOT:
      return Precedence.CALL;
    case TokenType.MINUS:
      return Precedence.TERM;
    case TokenType.PLUS:
      return Precedence.TERM;
    case TokenType.SEMICOLON:
      return Precedence.NONE;
    case TokenType.SLASH:
      return Precedence.FACTOR;
    case TokenType.STAR:
      return Precedence.FACTOR;
    case TokenType.CARET:
      return Precedence.POWER;
    case TokenType.PERCENT:
      return Precedence.FACTOR;
    case TokenType.COLON:
      return Precedence.NONE;
    case TokenType.BANG:
      return Precedence.NONE;
    case TokenType.BANG_EQUAL:
      return Precedence.EQUALITY;
    case TokenType.EQUAL:
      return Precedence.NONE;
    case TokenType.EQUAL_EQUAL:
      return Precedence.EQUALITY;
    case TokenType.GREATER:
      return Precedence.COMPARISON;
    case TokenType.GREATER_EQUAL:
      return Precedence.COMPARISON;
    case TokenType.LESS:
      return Precedence.COMPARISON;
    case TokenType.LESS_EQUAL:
      return Precedence.COMPARISON;
    case TokenType.IDENTIFIER:
      return Precedence.NONE;
    case TokenType.STRING:
      return Precedence.NONE;
    case TokenType.NUMBER:
      return Precedence.NONE;
    case TokenType.OBJECT:
      return Precedence.NONE;
    case TokenType.AND:
      return Precedence.AND;
    case TokenType.CLASS:
      return Precedence.NONE;
    case TokenType.ELSE:
      return Precedence.NONE;
    case TokenType.FALSE:
      return Precedence.NONE;
    case TokenType.FOR:
      return Precedence.NONE;
    case TokenType.FUN:
      return Precedence.NONE;
    case TokenType.IF:
      return Precedence.NONE;
    case TokenType.NIL:
      return Precedence.NONE;
    case TokenType.OR:
      return Precedence.OR;
    case TokenType.PRINT:
      return Precedence.NONE;
    case TokenType.RETURN:
      return Precedence.NONE;
    case TokenType.SUPER:
      return Precedence.NONE;
    case TokenType.THIS:
      return Precedence.NONE;
    case TokenType.TRUE:
      return Precedence.NONE;
    case TokenType.VAR:
      return Precedence.NONE;
    case TokenType.WHILE:
      return Precedence.NONE;
    case TokenType.BREAK:
      return Precedence.NONE;
    case TokenType.CONTINUE:
      return Precedence.NONE;
    case TokenType.ERROR:
      return Precedence.NONE;
    case TokenType.EOF:
      return Precedence.NONE;
    case TokenType.IN:
      return Precedence.NONE;
    case TokenType.COMMENT:
      return Precedence.NONE;
  }
}

Precedence get_next_precedence(
  final TokenType type,
) {
  return Precedence.values[get_precedence(type).index + 1];
}
