// region lexer
import 'model.dart';

List<NaturalToken> lex(
  final String source,
) {
  final lexer = _Lexer._(source);
  final tokens = <NaturalToken>[];
  do {
    tokens.add(lexer.scanToken());
  } while (tokens.last.type != TokenType.EOF);
  if (lexer.traceScanner) {
    int line = -1;
    for (final token in tokens) {
      if (token.loc.line != line) {
        line = token.loc.line;
      }
    }
  }
  return tokens;
}

class _Lexer {
  String source;
  int start = 0;
  int current = 0;
  Loc loc = const LocImpl(0, 0);

  // Mark line as comment
  bool commentLine = false;
  bool traceScanner = false;

  _Lexer._(this.source);

  static bool isDigit(final String? c) {
    if (c == null) return false;
    return '0'.compareTo(c) <= 0 && '9'.compareTo(c) >= 0;
  }

  static bool isAlpha(final String? c) {
    if (c == null) return false;
    return ('a'.compareTo(c) <= 0 && 'z'.compareTo(c) >= 0) ||
        ('A'.compareTo(c) <= 0 && 'Z'.compareTo(c) >= 0) ||
        (c == '_');
  }

  void newLine() {
    loc = LocImpl(loc.line + 1, 0);
    commentLine = false;
  }

  bool get isAtEnd {
    return current >= source.length;
  }

  String? get peek {
    if (isAtEnd) return null;
    return charAt(current);
  }

  String? get peekNext {
    if (current >= source.length - 1) return null;
    return charAt(current + 1);
  }

  String charAt(final int index) {
    return source.substring(index, index + 1);
  }

  String advance() {
    current++;
    return charAt(current - 1);
  }

  bool match(final String expected) {
    if (isAtEnd) return false;
    if (peek != expected) return false;
    current++;
    return true;
  }

  NaturalToken makeToken(final TokenType type) {
    var str = source.substring(start, current);
    if (type == TokenType.STRING) str = str.substring(1, str.length - 1);
    final token = NaturalTokenImpl(type: type, loc: loc, str: str);
    loc = LocImpl(loc.line, loc.line_token_counter + 1);
    return token;
  }

  NaturalToken errorToken(final String message) {
    return NaturalTokenImpl(type: TokenType.ERROR, loc: loc, str: message);
  }

  void skipWhitespace() {
    for (;;) {
      final c = peek;
      switch (c) {
        case ' ':
        case '\r':
        case '\t':
          advance();
          break;

        case '\n':
          newLine();
          advance();
          break;

        default:
          return;
      }
    }
  }

  TokenType checkKeyword(final int start, final String rest, final TokenType type) {
    if (current - this.start == start + rest.length &&
        source.substring(this.start + start, this.start + start + rest.length) == rest) {
      return type;
    }
    return TokenType.IDENTIFIER;
  }

  TokenType identifierType() {
    switch (charAt(start)) {
      case 'a':
        return checkKeyword(1, 'nd', TokenType.AND);
      case 'b':
        return checkKeyword(1, 'reak', TokenType.BREAK);
      case 'c':
        if (current - start > 1) {
          switch (charAt(start + 1)) {
            case 'l':
              return checkKeyword(2, 'ass', TokenType.CLASS);
            case 'o':
              return checkKeyword(2, 'ntinue', TokenType.CONTINUE);
          }
        }
        break;
      case 'e':
        return checkKeyword(1, 'lse', TokenType.ELSE);
      case 'f':
        if (current - start > 1) {
          switch (charAt(start + 1)) {
            case 'a':
              return checkKeyword(2, 'lse', TokenType.FALSE);
            case 'o':
              return checkKeyword(2, 'r', TokenType.FOR);
            case 'u':
              return checkKeyword(2, 'n', TokenType.FUN);
          }
        }
        break;
      case 'i':
        if (current - start > 1) {
          switch (charAt(start + 1)) {
            case 'f':
              return checkKeyword(2, '', TokenType.IF);
            case 'n':
              return checkKeyword(2, '', TokenType.IN);
          }
        }
        break;
      case 'n':
        return checkKeyword(1, 'il', TokenType.NIL);
      case 'o':
        return checkKeyword(1, 'r', TokenType.OR);
      case 'p':
        return checkKeyword(1, 'rint', TokenType.PRINT);
      case 'r':
        return checkKeyword(1, 'eturn', TokenType.RETURN);
      case 's':
        return checkKeyword(1, 'uper', TokenType.SUPER);
      case 't':
        if (current - start > 1) {
          switch (charAt(start + 1)) {
            case 'h':
              return checkKeyword(2, 'is', TokenType.THIS);
            case 'r':
              return checkKeyword(2, 'ue', TokenType.TRUE);
          }
        }
        break;
      case 'v':
        return checkKeyword(1, 'ar', TokenType.VAR);
      case 'w':
        return checkKeyword(1, 'hile', TokenType.WHILE);
    }
    return TokenType.IDENTIFIER;
  }

  NaturalToken identifier() {
    while (isAlpha(peek) || isDigit(peek)) {
      advance();
    }

    return makeToken(identifierType());
  }

  NaturalToken number() {
    while (isDigit(peek)) {
      advance();
    }
    // Look for a fractional part.
    if (peek == '.' && isDigit(peekNext)) {
      // Consume the '.'.
      advance();
      while (isDigit(peek)) {
        advance();
      }
    }
    return makeToken(TokenType.NUMBER);
  }

  NaturalToken string() {
    while (peek != '"' && !isAtEnd) {
      if (peek == '\n') {
        newLine();
      }
      advance();
    }
    if (isAtEnd) {
      return errorToken('Unterminated string.');
    } else {
      // The closing quote.
      advance();
      return makeToken(TokenType.STRING);
    }
  }

  NaturalToken comment() {
    while (peek != ' ' && peek != '\n' && !isAtEnd) {
      advance();
    }
    return makeToken(TokenType.COMMENT);
  }

  NaturalToken scanToken() {
    skipWhitespace();
    start = current;
    if (isAtEnd) return makeToken(TokenType.EOF);
    final c = advance();
    if (c == '/' && match('/')) {
      // Consume comment
      commentLine = true;
      return scanToken();
    }
    if (commentLine) return comment();
    if (isAlpha(c)) return identifier();
    if (isDigit(c)) return number();
    switch (c) {
      case '(':
        return makeToken(TokenType.LEFT_PAREN);
      case ')':
        return makeToken(TokenType.RIGHT_PAREN);
      case '[':
        return makeToken(TokenType.LEFT_BRACK);
      case ']':
        return makeToken(TokenType.RIGHT_BRACK);
      case '{':
        return makeToken(TokenType.LEFT_BRACE);
      case '}':
        return makeToken(TokenType.RIGHT_BRACE);
      case ';':
        return makeToken(TokenType.SEMICOLON);
      case ',':
        return makeToken(TokenType.COMMA);
      case '.':
        return makeToken(TokenType.DOT);
      case '-':
        return makeToken(TokenType.MINUS);
      case '+':
        return makeToken(TokenType.PLUS);
      case '/':
        return makeToken(TokenType.SLASH);
      case '*':
        return makeToken(TokenType.STAR);
      case '!':
        return makeToken(match('=') ? TokenType.BANG_EQUAL : TokenType.BANG);
      case '=':
        return makeToken(match('=') ? TokenType.EQUAL_EQUAL : TokenType.EQUAL);
      case '<':
        return makeToken(match('=') ? TokenType.LESS_EQUAL : TokenType.LESS);
      case '>':
        return makeToken(match('=') ? TokenType.GREATER_EQUAL : TokenType.GREATER);
      case '"':
        return string();
      case ':':
        return makeToken(TokenType.COLON);
      case '%':
        return makeToken(TokenType.PERCENT);
      case '^':
        return makeToken(TokenType.CARET);
    }
    return errorToken('Unexpected character: $c.');
  }
}
// endregion
