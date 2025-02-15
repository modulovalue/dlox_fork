// ignore_for_file: no_default_cases

import '../../domains/ast.dart';
import '../../domains/errors.dart';
import '../../domains/tokens.dart';

// region public
// TODO See: https://craftinginterpreters.com/appendix-i.html how close does the grammar there match dlox?
MapEntry<CompilationUnit, int> tokens_to_ast({
  required final List<Token<TokenAug>> tokens,
  required final Debug debug,
}) {
  // region caretaking
  Token<TokenAug>? current;
  Token<TokenAug>? previous;
  int previous_line() {
    return previous!.aug.line;
  }

  int current_idx = 0;
  void advance() {
    previous = current;
    while (current_idx < tokens.length) {
      current = tokens[current_idx++];
      if (current!.type == TokenType.ERROR) {
        debug.error_at(current!, current!.aug.lexeme);
      } else if (current!.type != TokenType.COMMENT) {
        break;
      }
    }
  }
  advance();

  bool check(
    final TokenType type,
  ) {
    return current!.type == type;
  }

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
  // endregion

  // region actual
  Declaration parse_declaration() {
    Declaration parse_decl() {
      void consume(
        final TokenType type,
        final String message,
      ) {
        if (current!.type == type) {
          advance();
        } else {
          debug.error_at(current!, message);
        }
      }

      Expr parse_expression() {
        final self = parse_expression;
        List<Expr> parse_argument_list() {
          final args = <Expr>[];
          if (!check(TokenType.RIGHT_PAREN)) {
            do {
              args.add(self());
              if (args.length == 256) {
                debug.error_at(previous!, "Can't have more than 255 arguments");
              }
            } while (match(TokenType.COMMA));
          }
          consume(TokenType.RIGHT_PAREN, "Expect ')' after arguments");
          return args;
        }

        Expr parse_precedence(
          final _DloxPrecedence precedence,
        ) {
          final can_assign = precedence.index <= _DloxPrecedence.ASSIGNMENT.index;
          advance();
          final Expr? prefix_rule = () {
            switch (previous!.type) {
              case TokenType.LEFT_PAREN:
                final expr = self();
                consume(TokenType.RIGHT_PAREN, "Expect ')' after expression");
                return expr;
              case TokenType.STRING:
                return ExprString(
                  token: previous!,
                  aug: previous_line(),
                );
              case TokenType.NUMBER:
                return ExprNumber(
                  value: previous!,
                  aug: previous_line(),
                );
              case TokenType.OBJECT:
                return ExprObject(
                  token: previous!,
                  aug: previous_line(),
                );
              case TokenType.THIS:
                return ExprSelf(
                  previous: previous!,
                  aug: previous_line(),
                );
              case TokenType.FALSE:
                return ExprFalsity(
                  aug: previous_line(),
                );
              case TokenType.NIL:
                return ExprNil(
                  aug: previous_line(),
                );
              case TokenType.TRUE:
                return ExprTruth(
                  aug: previous_line(),
                );
              case TokenType.MINUS:
                return ExprNegated(
                  child: parse_precedence(_DloxPrecedence.UNARY),
                  aug: previous_line(),
                );
              case TokenType.BANG:
                return ExprNot(
                  child: parse_precedence(_DloxPrecedence.UNARY),
                  aug: previous_line(),
                );
              case TokenType.IDENTIFIER:
                final name = previous!;
                if (can_assign) {
                  if (match(TokenType.EQUAL)) {
                    return ExprSet2(
                      name: name,
                      arg: self(),
                      aug: previous_line(),
                    );
                  } else {
                    return ExprGetSet2(
                      name: name,
                      child: () {
                        bool match_pair(
                          final TokenType first,
                          final TokenType second,
                        ) {
                          if (check(first)) {
                            if (current_idx >= tokens.length) {
                              return false;
                            } else if (tokens[current_idx].type != second) {
                              return false;
                            } else {
                              advance();
                              advance();
                              return true;
                            }
                          } else {
                            return false;
                          }
                        }

                        if (match_pair(TokenType.PLUS, TokenType.EQUAL)) {
                          return Getset(
                            type: GetsetType.pluseq,
                            child: self(),
                          );
                        } else if (match_pair(TokenType.MINUS, TokenType.EQUAL)) {
                          return Getset(
                            type: GetsetType.minuseq,
                            child: self(),
                          );
                        } else if (match_pair(TokenType.STAR, TokenType.EQUAL)) {
                          return Getset(
                            type: GetsetType.stareq,
                            child: self(),
                          );
                        } else if (match_pair(TokenType.SLASH, TokenType.EQUAL)) {
                          return Getset(
                            type: GetsetType.slasheq,
                            child: self(),
                          );
                        } else if (match_pair(TokenType.PERCENT, TokenType.EQUAL)) {
                          return Getset(
                            type: GetsetType.modeq,
                            child: self(),
                          );
                        } else if (match_pair(TokenType.CARET, TokenType.EQUAL)) {
                          return Getset(
                            type: GetsetType.poweq,
                            child: self(),
                          );
                        } else {
                          return null;
                        }
                      }(),
                      aug: previous_line(),
                    );
                  }
                } else {
                  return ExprGetSet2(
                    name: name,
                    child: null,
                    aug: previous_line(),
                  );
                }
              case TokenType.LEFT_BRACE:
                final entries = <MapEntry<Expr, Expr>>[];
                if (!check(TokenType.RIGHT_BRACE)) {
                  for (;;) {
                    final key = self();
                    consume(TokenType.COLON, "Expect ':' between map key-value pairs");
                    final value = self();
                    entries.add(
                      MapEntry(
                        key,
                        value,
                      ),
                    );
                    if (match(TokenType.COMMA)) {
                      continue;
                    } else {
                      break;
                    }
                  }
                }
                consume(TokenType.RIGHT_BRACE, "Expect '}' after map initializer");
                return ExprMap(
                  entries: entries,
                  aug: previous_line(),
                );
              case TokenType.LEFT_BRACK:
                int val_count = 0;
                final values = <Expr>[];
                if (!check(TokenType.RIGHT_BRACK)) {
                  values.add(self());
                  val_count += 1;
                  if (match(TokenType.COLON)) {
                    values.add(self());
                    val_count = -1;
                  } else {
                    while (match(TokenType.COMMA)) {
                      values.add(self());
                      val_count++;
                    }
                  }
                }
                consume(TokenType.RIGHT_BRACK, "Expect ']' after list initializer");
                return ExprList(
                  values: values,
                  val_count: val_count,
                  aug: previous_line(),
                );
              case TokenType.SUPER:
                consume(TokenType.DOT, "Expect '.' after 'super'");
                consume(TokenType.IDENTIFIER, 'Expect superclass method name');
                return ExprSuperaccess(
                  kw: previous!,
                  args: () {
                    if (match(TokenType.LEFT_PAREN)) {
                      return parse_argument_list();
                    } else {
                      return null;
                    }
                  }(),
                  aug: previous_line(),
                );
              default:
                return null;
            }
          }();
          if (prefix_rule == null) {
            debug.error_at(previous!, 'Expect expression');
            return const ExprExpected();
          } else {
            return ExprComposite(
              exprs: () {
                final exprs = <Expr>[
                  prefix_rule,
                ];
                while (precedence.index <= _get_precedence(current!.type).index) {
                  advance();
                  exprs.add(
                    () {
                      switch (previous!.type) {
                        case TokenType.LEFT_BRACK:
                          final first = () {
                            if (match(TokenType.COLON)) {
                              return null;
                            } else {
                              return self();
                            }
                          }();
                          final getter_ish = () {
                            if (first == null) {
                              return true;
                            } else {
                              return match(TokenType.COLON);
                            }
                          }();
                          if (getter_ish) {
                            return ExprListGetter(
                              first_token: previous!,
                              second_token: previous!,
                              first: first,
                              second: () {
                                if (match(TokenType.RIGHT_BRACK)) {
                                  return null;
                                } else {
                                  final expr = self();
                                  consume(TokenType.RIGHT_BRACK, "Expect ']' after list indexing");
                                  return expr;
                                }
                              }(),
                              aug: previous_line(),
                            );
                          } else {
                            return ExprListSetter(
                              token: previous!,
                              first: first,
                              second: () {
                                consume(TokenType.RIGHT_BRACK, "Expect ']' after list indexing");
                                if (can_assign || match(TokenType.EQUAL)) {
                                  return self();
                                } else {
                                  return null;
                                }
                              }(),
                              aug: previous_line(),
                            );
                          }
                        case TokenType.LEFT_PAREN:
                          return ExprCall(
                            args: parse_argument_list(),
                            aug: previous_line(),
                          );
                        case TokenType.DOT:
                          consume(TokenType.IDENTIFIER, "Expect property name after '.'");
                          final name_token = previous!;
                          if (can_assign && match(TokenType.EQUAL)) {
                            return ExprSet(
                              name: name_token,
                              arg: self(),
                              aug: previous_line(),
                            );
                          } else if (match(TokenType.LEFT_PAREN)) {
                            return ExprInvoke(
                              name: name_token,
                              args: parse_argument_list(),
                              aug: previous_line(),
                            );
                          } else {
                            return ExprGet(
                              name: name_token,
                              aug: previous_line(),
                            );
                          }
                        case TokenType.MINUS:
                          return ExprMinus(
                            child: parse_precedence(_get_next_precedence(TokenType.MINUS)),
                            aug: previous_line(),
                          );
                        case TokenType.PLUS:
                          return ExprPlus(
                            child: parse_precedence(_get_next_precedence(TokenType.PLUS)),
                            aug: previous_line(),
                          );
                        case TokenType.SLASH:
                          return ExprSlash(
                            child: parse_precedence(_get_next_precedence(TokenType.SLASH)),
                            aug: previous_line(),
                          );
                        case TokenType.STAR:
                          return ExprStar(
                            child: parse_precedence(_get_next_precedence(TokenType.STAR)),
                            aug: previous_line(),
                          );
                        case TokenType.CARET:
                          return ExprPow(
                            child: parse_precedence(_get_next_precedence(TokenType.CARET)),
                            aug: previous_line(),
                          );
                        case TokenType.PERCENT:
                          return ExprModulo(
                            child: parse_precedence(_get_next_precedence(TokenType.PERCENT)),
                            aug: previous_line(),
                          );
                        case TokenType.BANG_EQUAL:
                          return ExprNeq(
                            child: parse_precedence(_get_next_precedence(TokenType.BANG_EQUAL)),
                            aug: previous_line(),
                          );
                        case TokenType.EQUAL_EQUAL:
                          return ExprEq(
                            child: parse_precedence(_get_next_precedence(TokenType.EQUAL_EQUAL)),
                            aug: previous_line(),
                          );
                        case TokenType.GREATER:
                          return ExprG(
                            child: parse_precedence(_get_next_precedence(TokenType.GREATER)),
                            aug: previous_line(),
                          );
                        case TokenType.GREATER_EQUAL:
                          return ExprGeq(
                            child: parse_precedence(_get_next_precedence(TokenType.GREATER_EQUAL)),
                            aug: previous_line(),
                          );
                        case TokenType.LESS:
                          return ExprL(
                            child: parse_precedence(_get_next_precedence(TokenType.LESS)),
                            aug: previous_line(),
                          );
                        case TokenType.LESS_EQUAL:
                          return ExprLeq(
                            child: parse_precedence(_get_next_precedence(TokenType.LESS_EQUAL)),
                            aug: previous_line(),
                          );
                        case TokenType.AND:
                          return ExprAnd(
                            token: previous!,
                            child: parse_precedence(
                              _get_precedence(TokenType.AND),
                            ),
                            aug: previous_line(),
                          );
                        case TokenType.OR:
                          return ExprOr(
                            token: previous!,
                            child: parse_precedence(
                              _get_precedence(
                                TokenType.OR,
                              ),
                            ),
                            aug: previous_line(),
                          );
                        default:
                          throw Exception("Invalid State");
                      }
                    }(),
                  );
                }
                if (can_assign) {
                  if (match(TokenType.EQUAL)) {
                    debug.error_at(previous!, 'Invalid assignment target');
                  }
                }
                return exprs;
              }(),
            );
          }
        }

        return parse_precedence(_DloxPrecedence.ASSIGNMENT);
      }

      DeclarationVari parse_var_declaration() {
        return DeclarationVari(
          exprs: () {
            final exprs = () {
              final exprs = <MapEntry<Token<TokenAug>, Expr>>[];
              for (;;) {
                consume(TokenType.IDENTIFIER, 'Expect variable name');
                exprs.add(
                  MapEntry(
                    previous!,
                    () {
                      if (match(TokenType.EQUAL)) {
                        return parse_expression();
                      } else {
                        return ExprNil(
                          aug: previous_line(),
                        );
                      }
                    }(),
                  ),
                );
                if (match(TokenType.COMMA)) {
                  continue;
                } else {
                  break;
                }
              }
              return exprs;
            }();
            consume(TokenType.SEMICOLON, 'Expect a newline after variable declaration');
            return exprs;
          }(),
          aug: previous_line(),
        );
      }

      List<Declaration> parse_decls() {
        final decls = <Declaration>[];
        for (;;) {
          if (!check(TokenType.RIGHT_BRACE)) {
            if (match(TokenType.EOF)) {
              break;
            } else {
              decls.add(parse_declaration());
            }
          } else {
            break;
          }
        }
        consume(TokenType.RIGHT_BRACE, 'Unterminated block');
        return decls;
      }

      Functiony parse_function_block() {
        return Functiony(
          name: () {
            final name = previous!.aug.lexeme;
            consume(TokenType.LEFT_PAREN, "Expect '(' after function name");
            return name;
          }(),
          args: () {
            final args = <Token<TokenAug>>[];
            if (!check(TokenType.RIGHT_PAREN)) {
              argloop:
              for (;;) {
                consume(TokenType.IDENTIFIER, 'Expect parameter name');
                args.add(previous!);
                if (match(TokenType.COMMA)) {
                  continue argloop;
                } else {
                  break argloop;
                }
              }
            }
            consume(TokenType.RIGHT_PAREN, "Expect ')' after parameters");
            consume(TokenType.LEFT_BRACE, 'Expect function body');
            return args;
          }(),
          decls: parse_decls(),
        );
      }

      Stmt parse_statement() {
        if (match(TokenType.FOR)) {
          if (match(TokenType.LEFT_PAREN)) {
            return StmtLoop(
              left: () {
                if (match(TokenType.SEMICOLON)) {
                  return null;
                } else if (match(TokenType.VAR)) {
                  final decl = parse_var_declaration();
                  return LoopLeftVari(
                    decl: decl,
                  );
                } else {
                  final expr = parse_expression();
                  consume(TokenType.SEMICOLON, 'Expect a newline after expression');
                  return LoopLeftExpr(
                    expr: expr,
                  );
                }
              }(),
              center: () {
                if (match(TokenType.SEMICOLON)) {
                  return null;
                } else {
                  final expr = parse_expression();
                  consume(TokenType.SEMICOLON, "Expect ';' after loop condition");
                  return expr;
                }
              }(),
              right_kw: previous!,
              right: () {
                if (match(TokenType.RIGHT_PAREN)) {
                  return null;
                } else {
                  final expr = parse_expression();
                  consume(TokenType.RIGHT_PAREN, "Expect ')' after for clauses");
                  return expr;
                }
              }(),
              end_kw: previous!,
              body: parse_statement(),
              aug: previous_line(),
            );
          } else {
            final key_name = () {
              consume(TokenType.IDENTIFIER, 'Expect variable name');
              return previous!;
            }();
            final value_name = () {
              if (match(TokenType.COMMA)) {
                consume(TokenType.IDENTIFIER, 'Expect variable name');
                return previous!;
              } else {
                return null;
              }
            }();
            consume(TokenType.IN, "Expect 'in' after loop variables");
            return StmtLoop2(
              key_name: key_name,
              value_name: value_name,
              center: parse_expression(),
              exit_token: previous!,
              body: parse_statement(),
              aug: previous_line(),
            );
          }
        } else if (match(TokenType.IF)) {
          final expr = parse_expression();
          final stmt = parse_statement();
          final if_kw = previous!;
          final else_kw = previous!;
          final line = previous_line();
          return StmtConditional(
            expr: expr,
            stmt: stmt,
            if_kw: if_kw,
            aug: line,
            else_kw: else_kw,
            other: () {
              if (match(TokenType.ELSE)) {
                return parse_statement();
              } else {
                return null;
              }
            }(),
          );
        } else if (match(TokenType.WHILE)) {
          return StmtWhil(
            expr: parse_expression(),
            stmt: parse_statement(),
            exit_kw: previous!,
            aug: previous_line(),
          );
        } else if (match(TokenType.LEFT_BRACE)) {
          return StmtBlock(
            block: parse_decls(),
            aug: previous_line(),
          );
        } else if (match(TokenType.PRINT)) {
          return StmtOutput(
            expr: () {
              final expr = parse_expression();
              consume(TokenType.SEMICOLON, 'Expect a newline after value');
              return expr;
            }(),
            aug: previous_line(),
          );
        } else if (match(TokenType.RETURN)) {
          return StmtRet(
            kw: previous!,
            expr: () {
              if (match(TokenType.SEMICOLON)) {
                return null;
              } else {
                final expr = parse_expression();
                consume(TokenType.SEMICOLON, 'Expect a newline after return value');
                return expr;
              }
            }(),
            aug: previous_line(),
          );
        } else {
          return StmtExpr(
            expr: () {
              final expr = parse_expression();
              consume(TokenType.SEMICOLON, 'Expect a newline after expression');
              return expr;
            }(),
            aug: previous_line(),
          );
        }
      }

      if (match(TokenType.CLASS)) {
        consume(TokenType.IDENTIFIER, 'Expect class name');
        return DeclarationClazz(
          name: previous!,
          superclass_name: () {
            if (match(TokenType.LESS)) {
              consume(TokenType.IDENTIFIER, 'Expect superclass name');
              return previous!;
            } else {
              return null;
            }
          }(),
          functions: () {
            consume(TokenType.LEFT_BRACE, 'Expect class body');
            final methods = <Method>[];
            for (;;) {
              if (check(TokenType.RIGHT_BRACE)) {
                break;
              } else if (check(TokenType.EOF)) {
                break;
              } else {
                consume(TokenType.IDENTIFIER, 'Expect method name');
                final name = previous!;
                final functiony = parse_function_block();
                final method = Method(
                  name: name,
                  block: functiony,
                  aug: previous_line(),
                );
                methods.add(method);
              }
            }
            consume(TokenType.RIGHT_BRACE, 'Unterminated class body');
            return methods;
          }(),
          aug: previous_line(),
        );
      } else if (match(TokenType.FUN)) {
        consume(TokenType.IDENTIFIER, 'Expect function name');
        return DeclarationFun(
          name: previous!,
          block: parse_function_block(),
          aug: previous_line(),
        );
      } else if (match(TokenType.VAR)) {
        return parse_var_declaration();
      } else {
        return DeclarationStmt(
          stmt: parse_statement(),
        );
      }
    }

    void synchronize() {
      if (debug.panic_mode) {
        debug.panic_mode = false;
        outer:
        while (current!.type != TokenType.EOF) {
          if (previous!.type == TokenType.SEMICOLON) {
            break outer;
          } else {
            switch (current!.type) {
              case TokenType.CLASS:
              case TokenType.FUN:
              case TokenType.VAR:
              case TokenType.FOR:
              case TokenType.IF:
              case TokenType.WHILE:
              case TokenType.PRINT:
              case TokenType.RETURN:
                break outer;
              default:
                advance();
                continue outer;
            }
          }
        }
      }
    }

    final decl = parse_decl();
    synchronize();
    return decl;
  }

  return MapEntry(
    CompilationUnit(
      decls: [
        for (;!match(TokenType.EOF);)
          parse_declaration(),
      ],
    ),
    previous_line(),
  );
  // endregion
}
// endregion

// region internal
enum _DloxPrecedence {
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

_DloxPrecedence _get_precedence(
  final TokenType type,
) {
  switch (type) {
    case TokenType.LEFT_PAREN:
      return _DloxPrecedence.CALL;
    case TokenType.RIGHT_PAREN:
      return _DloxPrecedence.NONE;
    case TokenType.LEFT_BRACE:
      return _DloxPrecedence.NONE;
    case TokenType.RIGHT_BRACE:
      return _DloxPrecedence.NONE;
    case TokenType.LEFT_BRACK:
      return _DloxPrecedence.CALL;
    case TokenType.RIGHT_BRACK:
      return _DloxPrecedence.NONE;
    case TokenType.COMMA:
      return _DloxPrecedence.NONE;
    case TokenType.DOT:
      return _DloxPrecedence.CALL;
    case TokenType.MINUS:
      return _DloxPrecedence.TERM;
    case TokenType.PLUS:
      return _DloxPrecedence.TERM;
    case TokenType.SEMICOLON:
      return _DloxPrecedence.NONE;
    case TokenType.SLASH:
      return _DloxPrecedence.FACTOR;
    case TokenType.STAR:
      return _DloxPrecedence.FACTOR;
    case TokenType.CARET:
      return _DloxPrecedence.POWER;
    case TokenType.PERCENT:
      return _DloxPrecedence.FACTOR;
    case TokenType.COLON:
      return _DloxPrecedence.NONE;
    case TokenType.BANG:
      return _DloxPrecedence.NONE;
    case TokenType.BANG_EQUAL:
      return _DloxPrecedence.EQUALITY;
    case TokenType.EQUAL:
      return _DloxPrecedence.NONE;
    case TokenType.EQUAL_EQUAL:
      return _DloxPrecedence.EQUALITY;
    case TokenType.GREATER:
      return _DloxPrecedence.COMPARISON;
    case TokenType.GREATER_EQUAL:
      return _DloxPrecedence.COMPARISON;
    case TokenType.LESS:
      return _DloxPrecedence.COMPARISON;
    case TokenType.LESS_EQUAL:
      return _DloxPrecedence.COMPARISON;
    case TokenType.IDENTIFIER:
      return _DloxPrecedence.NONE;
    case TokenType.STRING:
      return _DloxPrecedence.NONE;
    case TokenType.NUMBER:
      return _DloxPrecedence.NONE;
    case TokenType.OBJECT:
      return _DloxPrecedence.NONE;
    case TokenType.AND:
      return _DloxPrecedence.AND;
    case TokenType.CLASS:
      return _DloxPrecedence.NONE;
    case TokenType.ELSE:
      return _DloxPrecedence.NONE;
    case TokenType.FALSE:
      return _DloxPrecedence.NONE;
    case TokenType.FOR:
      return _DloxPrecedence.NONE;
    case TokenType.FUN:
      return _DloxPrecedence.NONE;
    case TokenType.IF:
      return _DloxPrecedence.NONE;
    case TokenType.NIL:
      return _DloxPrecedence.NONE;
    case TokenType.OR:
      return _DloxPrecedence.OR;
    case TokenType.PRINT:
      return _DloxPrecedence.NONE;
    case TokenType.RETURN:
      return _DloxPrecedence.NONE;
    case TokenType.SUPER:
      return _DloxPrecedence.NONE;
    case TokenType.THIS:
      return _DloxPrecedence.NONE;
    case TokenType.TRUE:
      return _DloxPrecedence.NONE;
    case TokenType.VAR:
      return _DloxPrecedence.NONE;
    case TokenType.WHILE:
      return _DloxPrecedence.NONE;
    case TokenType.ERROR:
      return _DloxPrecedence.NONE;
    case TokenType.EOF:
      return _DloxPrecedence.NONE;
    case TokenType.IN:
      return _DloxPrecedence.NONE;
    case TokenType.COMMENT:
      return _DloxPrecedence.NONE;
  }
}

_DloxPrecedence _get_next_precedence(
  final TokenType type,
) {
  switch (_get_precedence(type)) {
    case _DloxPrecedence.NONE:
      return _DloxPrecedence.ASSIGNMENT;
    case _DloxPrecedence.ASSIGNMENT:
      return _DloxPrecedence.OR;
    case _DloxPrecedence.OR:
      return _DloxPrecedence.AND;
    case _DloxPrecedence.AND:
      return _DloxPrecedence.EQUALITY;
    case _DloxPrecedence.EQUALITY:
      return _DloxPrecedence.COMPARISON;
    case _DloxPrecedence.COMPARISON:
      return _DloxPrecedence.TERM;
    case _DloxPrecedence.TERM:
      return _DloxPrecedence.FACTOR;
    case _DloxPrecedence.FACTOR:
      return _DloxPrecedence.POWER;
    case _DloxPrecedence.POWER:
      return _DloxPrecedence.UNARY;
    case _DloxPrecedence.UNARY:
      return _DloxPrecedence.CALL;
    case _DloxPrecedence.CALL:
      return _DloxPrecedence.PRIMARY;
    case _DloxPrecedence.PRIMARY:
      throw Exception("Invalid State");
  }
}
// endregion
