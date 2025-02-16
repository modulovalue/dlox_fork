import '../../domains/tokens.dart';

List<Token<TokenAug>> source_to_tokens({
  required final String source,
}) {
  final lexer = _Lexer._(
    source: source,
  );
  final tokens = <Token<TokenAug>>[];
  for (;;) {
    tokens.add(lexer.scan_token());
    if (tokens.last.type == TokenType.EOF) {
      return tokens;
    } else {
      continue;
    }
  }
}

class _Lexer {
  String source;
  int start;
  int current;
  int line;
  bool line_is_comment;

  _Lexer._({
    required final this.source,
  })  : start = 0,
        current = 0,
        line = 0,
        line_is_comment = false;

  static bool is_digit(
    final String? c,
  ) {
    if (c == null) {
      return false;
    } else {
      return '0'.compareTo(c) <= 0 && '9'.compareTo(c) >= 0;
    }
  }

  static bool is_alpha(
    final String? c,
  ) {
    if (c == null) {
      return false;
    } else {
      return ('a'.compareTo(c) <= 0 && 'z'.compareTo(c) >= 0) ||
          ('A'.compareTo(c) <= 0 && 'Z'.compareTo(c) >= 0) ||
          (c == '_');
    }
  }

  void new_line() {
    line = line + 1;
    line_is_comment = false;
  }

  bool get is_at_end {
    return current >= source.length;
  }

  String? get peek {
    if (is_at_end) {
      return null;
    } else {
      return char_at(current);
    }
  }

  String? get peek_next {
    if (current >= source.length - 1) {
      return null;
    } else {
      return char_at(current + 1);
    }
  }

  String char_at(
    final int index,
  ) {
    return source.substring(index, index + 1);
  }

  String advance() {
    current++;
    return char_at(current - 1);
  }

  bool match(
    final String expected,
  ) {
    if (is_at_end) {
      return false;
    } else if (peek != expected) {
      return false;
    } else {
      current++;
      return true;
    }
  }

  Token<TokenAug> make_token(
    final TokenType type,
  ) {
    String str = source.substring(start, current);
    if (type == TokenType.STRING) {
      str = str.substring(1, str.length - 1);
    }
    final token = TokenImpl(
      type: type,
      aug: TokenAug(line: line, lexeme: str),
    );
    return token;
  }

  Token<TokenAug> error_token(
    final String message,
  ) {
    return TokenImpl(
      type: TokenType.ERROR,
      aug: TokenAug(line: line, lexeme: message),
    );
  }

  void skip_whitespace() {
    for (;;) {
      switch (peek) {
        case ' ':
        case '\r':
        case '\t':
          advance();
          break;
        case '\n':
          new_line();
          advance();
          break;
        default:
          return;
      }
    }
  }

  TokenType check_keyword(
    final int start,
    final String rest,
    final TokenType type,
  ) {
    if (current - this.start == start + rest.length &&
        source.substring(this.start + start, this.start + start + rest.length) == rest) {
      return type;
    } else {
      return TokenType.IDENTIFIER;
    }
  }

  TokenType identifier_type() {
    switch (char_at(start)) {
      case 'a':
        return check_keyword(1, 'nd', TokenType.AND);
      case 'c':
        if (current - start > 1) {
          switch (char_at(start + 1)) {
            case 'l':
              return check_keyword(2, 'ass', TokenType.CLASS);
          }
        }
        break;
      case 'e':
        return check_keyword(1, 'lse', TokenType.ELSE);
      case 'f':
        if (current - start > 1) {
          switch (char_at(start + 1)) {
            case 'a':
              return check_keyword(2, 'lse', TokenType.FALSE);
            case 'o':
              return check_keyword(2, 'r', TokenType.FOR);
            case 'u':
              return check_keyword(2, 'n', TokenType.FUN);
          }
        }
        break;
      case 'i':
        if (current - start > 1) {
          switch (char_at(start + 1)) {
            case 'f':
              return check_keyword(2, '', TokenType.IF);
            case 'n':
              return check_keyword(2, '', TokenType.IN);
          }
        }
        break;
      case 'n':
        return check_keyword(1, 'il', TokenType.NIL);
      case 'o':
        return check_keyword(1, 'r', TokenType.OR);
      case 'p':
        return check_keyword(1, 'rint', TokenType.PRINT);
      case 'r':
        return check_keyword(1, 'eturn', TokenType.RETURN);
      case 's':
        return check_keyword(1, 'uper', TokenType.SUPER);
      case 't':
        if (current - start > 1) {
          switch (char_at(start + 1)) {
            case 'h':
              return check_keyword(2, 'is', TokenType.THIS);
            case 'r':
              return check_keyword(2, 'ue', TokenType.TRUE);
          }
        }
        break;
      case 'v':
        return check_keyword(1, 'ar', TokenType.VAR);
      case 'w':
        return check_keyword(1, 'hile', TokenType.WHILE);
    }
    return TokenType.IDENTIFIER;
  }

  Token<TokenAug> identifier() {
    while (is_alpha(peek) || is_digit(peek)) {
      advance();
    }
    return make_token(identifier_type());
  }

  Token<TokenAug> number() {
    while (is_digit(peek)) {
      advance();
    }
    // Look for a fractional part.
    if (peek == '.' && is_digit(peek_next)) {
      // Consume the '.'.
      advance();
      while (is_digit(peek)) {
        advance();
      }
    }
    return make_token(TokenType.NUMBER);
  }

  Token<TokenAug> string() {
    while (peek != '"' && !is_at_end) {
      if (peek == '\n') {
        new_line();
      }
      advance();
    }
    if (is_at_end) {
      return error_token('Unterminated string.');
    } else {
      // The closing quote.
      advance();
      return make_token(TokenType.STRING);
    }
  }

  Token<TokenAug> comment() {
    for (;;) {
      if (peek != "\n") {
        if (is_at_end) {
          break;
        } else {
          advance();
        }
      } else {
        break;
      }
    }
    return make_token(TokenType.COMMENT);
  }

  Token<TokenAug> scan_token() {
    skip_whitespace();
    start = current;
    if (is_at_end) {
      return make_token(TokenType.EOF);
    } else {
      final c = advance();
      if (c == '/' && match('/')) {
        // Consume comment.
        line_is_comment = true;
        return scan_token();
      } else {
        if (line_is_comment) {
          return comment();
        } else if (is_alpha(c)) {
          return identifier();
        } else if (is_digit(c)) {
          return number();
        } else {
          switch (c) {
            case '(':
              return make_token(TokenType.LEFT_PAREN);
            case ')':
              return make_token(TokenType.RIGHT_PAREN);
            case '[':
              return make_token(TokenType.LEFT_BRACK);
            case ']':
              return make_token(TokenType.RIGHT_BRACK);
            case '{':
              return make_token(TokenType.LEFT_BRACE);
            case '}':
              return make_token(TokenType.RIGHT_BRACE);
            case ';':
              return make_token(TokenType.SEMICOLON);
            case ',':
              return make_token(TokenType.COMMA);
            case '.':
              return make_token(TokenType.DOT);
            case '-':
              return make_token(TokenType.MINUS);
            case '+':
              return make_token(TokenType.PLUS);
            case '/':
              return make_token(TokenType.SLASH);
            case '*':
              return make_token(TokenType.STAR);
            case '!':
              return make_token(match('=') ? TokenType.BANG_EQUAL : TokenType.BANG);
            case '=':
              return make_token(match('=') ? TokenType.EQUAL_EQUAL : TokenType.EQUAL);
            case '<':
              return make_token(match('=') ? TokenType.LESS_EQUAL : TokenType.LESS);
            case '>':
              return make_token(match('=') ? TokenType.GREATER_EQUAL : TokenType.GREATER);
            case '"':
              return string();
            case ':':
              return make_token(TokenType.COLON);
            case '%':
              return make_token(TokenType.PERCENT);
            case '^':
              return make_token(TokenType.CARET);
            default:
              return error_token('Unexpected character: $c.');
          }
        }
      }
    }
  }
}
