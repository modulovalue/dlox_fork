// ignore_for_file: no_default_cases

import 'compiler.dart';
import 'models/ast.dart';
import 'models/errors.dart';

MapEntry<Parser, ErrorDelegate> make_parser({
  required final List<NaturalToken> tokens,
  required final Debug debug,
}) {
  final parser = _ParserImpl(
    tokens: tokens,
    debug: debug,
  );
  parser.advance();
  return MapEntry(parser, parser);
}

class _ParserImpl implements Parser, ErrorDelegate {
  final List<NaturalToken> tokens;
  @override
  final Debug debug;
  NaturalToken? current;
  NaturalToken? previous;
  int current_idx;
  bool panic_mode;

  _ParserImpl({
    required final this.tokens,
    required final this.debug,
  })  : current_idx = 0,
        panic_mode = false;

  @override
  int get previous_line {
    return previous!.loc.line;
  }

  void error_at(
    final NaturalToken? token,
    final String? message,
  ) {
    if (panic_mode) {
      return;
    } else {
      panic_mode = true;
      final error = CompilerError(
        token: token!,
        msg: message,
      );
      debug.errors.add(error);
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
        error_at_current(current!.lexeme);
      } else if (current!.type != TokenType.COMMENT) {
        break;
      }
    }
  }

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

  List<Expr> parse_argument_list(
    final Expr Function() parse_expression,
  ) {
    final args = <Expr>[];
    if (!check(TokenType.RIGHT_PAREN)) {
      do {
        args.add(parse_expression());
        if (args.length == 256) {
          error_at_previous("Can't have more than 255 arguments");
        }
      } while (match(TokenType.COMMA));
    }
    consume(TokenType.RIGHT_PAREN, "Expect ')' after arguments");
    return args;
  }

  @override
  Declaration parse_declaration({
    required final Compiler compiler,
  }) {
    final _compile_expr = compiler.compile_expr;
    Expr parse_expression() {
      Expr parse_precedence(
        final Precedence precedence,
      ) {
        final can_assign = precedence.index <= Precedence.ASSIGNMENT.index;
        advance();
        final Expr? prefix_rule = () {
          switch (previous!.type) {
            case TokenType.LEFT_PAREN:
              final expr = parse_expression();
              consume(TokenType.RIGHT_PAREN, "Expect ')' after expression");
              return expr;
            case TokenType.STRING:
              return _compile_expr(
                ExprString(
                  token: previous!,
                ),
              );
            case TokenType.NUMBER:
              return _compile_expr(
                ExprNumber(
                  value: previous!,
                ),
              );
            case TokenType.OBJECT:
              return _compile_expr(
                const ExprObject(),
              );
            case TokenType.THIS:
              return _compile_expr(
                ExprSelf(
                  previous: previous!,
                ),
              );
            case TokenType.FALSE:
              return _compile_expr(
                const ExprFalsity(),
              );
            case TokenType.NIL:
              return _compile_expr(
                const ExprNil(),
              );
            case TokenType.TRUE:
              return _compile_expr(
                const ExprTruth(),
              );
            case TokenType.MINUS:
              return _compile_expr(
                ExprNegated(
                  child: parse_precedence(Precedence.UNARY),
                ),
              );
            case TokenType.BANG:
              return _compile_expr(
                ExprNot(
                  child: parse_precedence(Precedence.UNARY),
                ),
              );
            // TODO
            case TokenType.IDENTIFIER:
              final name = previous!;
              if (can_assign) {
                if (match(TokenType.EQUAL)) {
                  return _compile_expr(
                    ExprSet2(
                      name: name,
                      arg: parse_expression(),
                    ),
                  );
                } else {
                  return _compile_expr(
                    ExprGetSet2(
                      name: name,
                      arg_maker: () {
                        Expr expression() {
                          advance();
                          advance();
                          return parse_expression();
                        }

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
                              return true;
                            }
                          } else {
                            return false;
                          }
                        }

                        // TODO try some late final trick until the cycle has been migrated.
                        if (match_pair(TokenType.PLUS, TokenType.EQUAL)) {
                          return () => ExprPluseq(child: expression());
                        } else if (match_pair(TokenType.MINUS, TokenType.EQUAL)) {
                          return () => ExprMinuseq(child: expression());
                        } else if (match_pair(TokenType.STAR, TokenType.EQUAL)) {
                          return () => ExprStareq(child: expression());
                        } else if (match_pair(TokenType.SLASH, TokenType.EQUAL)) {
                          return () => ExprSlasheq(child: expression());
                        } else if (match_pair(TokenType.PERCENT, TokenType.EQUAL)) {
                          return () => ExprModeq(child: expression());
                        } else if (match_pair(TokenType.CARET, TokenType.EQUAL)) {
                          return () => ExprPoweq(child: expression());
                        } else {
                          return null;
                        }
                      }(),
                    ),
                  );
                }
              } else {
                return _compile_expr(
                  ExprGet2(
                    name: name,
                  ),
                );
              }
            case TokenType.LEFT_BRACE:
              final entries = <MapEntry<Expr, Expr>>[];
              if (!check(TokenType.RIGHT_BRACE)) {
                for (;;) {
                  final key = parse_expression();
                  consume(TokenType.COLON, "Expect ':' between map key-value pairs");
                  final value = parse_expression();
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
              return _compile_expr(
                ExprMap(
                  entries: entries,
                ),
              );
            case TokenType.LEFT_BRACK:
              int val_count = 0;
              final values = <Expr>[];
              if (!check(TokenType.RIGHT_BRACK)) {
                values.add(parse_expression());
                val_count += 1;
                if (match(TokenType.COLON)) {
                  values.add(parse_expression());
                  val_count = -1;
                } else {
                  while (match(TokenType.COMMA)) {
                    values.add(parse_expression());
                    val_count++;
                  }
                }
              }
              consume(TokenType.RIGHT_BRACK, "Expect ']' after list initializer");
              return _compile_expr(
                ExprList(
                  values: values,
                  val_count: val_count,
                ),
              );
            case TokenType.SUPER:
              consume(TokenType.DOT, "Expect '.' after 'super'");
              consume(TokenType.IDENTIFIER, 'Expect superclass method name');
              final name_token = previous!;
              return _compile_expr(
                ExprSuperaccess(
                  kw: name_token,
                  make_args: () {
                    if (match(TokenType.LEFT_PAREN)) {
                      return () => parse_argument_list(parse_expression);
                    } else {
                      return null;
                    }
                  }(),
                ),
              );
            default:
              return null;
          }
        }();
        if (prefix_rule == null) {
          return _compile_expr(
            const ExprExpected(),
          );
        } else {
          return _compile_expr(
            ExprComposite(
              exprs: () {
                final exprs = <Expr>[
                  prefix_rule,
                ];
                while (precedence.index <= get_precedence(current!.type).index) {
                  advance();
                  exprs.add(
                    () {
                      switch (previous!.type) {
                        case TokenType.LEFT_BRACK:
                          return compiler.visit_bracket<Expr>(
                            () => match(TokenType.COLON),
                            () {
                              if (match(TokenType.RIGHT_BRACK)) {
                                return null;
                              } else {
                                final expr = parse_expression();
                                consume(TokenType.RIGHT_BRACK, "Expect ']' after list indexing");
                                return expr;
                              }
                            },
                            () {
                              consume(TokenType.RIGHT_BRACK, "Expect ']' after list indexing");
                              if (can_assign || match(TokenType.EQUAL)) {
                                return parse_expression();
                              } else {
                                return null;
                              }
                            },
                            parse_expression,
                            (final f, final s) => ExprListGetter(
                              first: f,
                              second: s,
                            ),
                            (final f, final s) => ExprListSetter(
                              first: f,
                              second: s,
                            ),
                          );
                        case TokenType.LEFT_PAREN:
                          return _compile_expr(
                            ExprCall(
                              args: parse_argument_list(parse_expression),
                            ),
                          );
                        case TokenType.DOT:
                          consume(TokenType.IDENTIFIER, "Expect property name after '.'");
                          final name_token = previous!;
                          if (can_assign && match(TokenType.EQUAL)) {
                            return _compile_expr(
                              ExprSet(
                                name: name_token,
                                arg: parse_expression(),
                              ),
                            );
                          } else if (match(TokenType.LEFT_PAREN)) {
                            return _compile_expr(
                              ExprInvoke(
                                name: name_token,
                                args: parse_argument_list(parse_expression),
                              ),
                            );
                          } else {
                            return _compile_expr(
                              ExprGet(
                                name: name_token,
                              ),
                            );
                          }
                        case TokenType.MINUS:
                          return _compile_expr(
                            ExprMinus(
                              child: parse_precedence(get_next_precedence(TokenType.MINUS)),
                            ),
                          );
                        case TokenType.PLUS:
                          return _compile_expr(
                            ExprPlus(
                              child: parse_precedence(get_next_precedence(TokenType.PLUS)),
                            ),
                          );
                        case TokenType.SLASH:
                          return _compile_expr(
                            ExprSlash(
                              child: parse_precedence(get_next_precedence(TokenType.SLASH)),
                            ),
                          );
                        case TokenType.STAR:
                          return _compile_expr(
                            ExprStar(
                              child: parse_precedence(get_next_precedence(TokenType.STAR)),
                            ),
                          );
                        case TokenType.CARET:
                          return _compile_expr(
                            ExprPow(
                              child: parse_precedence(get_next_precedence(TokenType.CARET)),
                            ),
                          );
                        case TokenType.PERCENT:
                          return _compile_expr(
                            ExprModulo(
                              child: parse_precedence(get_next_precedence(TokenType.PERCENT)),
                            ),
                          );
                        case TokenType.BANG_EQUAL:
                          return _compile_expr(
                            ExprNeq(
                              child: parse_precedence(get_next_precedence(TokenType.BANG_EQUAL)),
                            ),
                          );
                        case TokenType.EQUAL_EQUAL:
                          return _compile_expr(
                            ExprEq(
                              child: parse_precedence(get_next_precedence(TokenType.EQUAL_EQUAL)),
                            ),
                          );
                        case TokenType.GREATER:
                          return _compile_expr(
                            ExprG(
                              child: parse_precedence(get_next_precedence(TokenType.GREATER)),
                            ),
                          );
                        case TokenType.GREATER_EQUAL:
                          return _compile_expr(
                            ExprGeq(
                              child: parse_precedence(get_next_precedence(TokenType.GREATER_EQUAL)),
                            ),
                          );
                        case TokenType.LESS:
                          return _compile_expr(
                            ExprL(
                              child: parse_precedence(get_next_precedence(TokenType.LESS)),
                            ),
                          );
                        case TokenType.LESS_EQUAL:
                          return _compile_expr(
                            ExprLeq(
                              child: parse_precedence(get_next_precedence(TokenType.LESS_EQUAL)),
                            ),
                          );
                        case TokenType.AND:
                          return  _compile_expr(
                            ExprAnd(
                              child_maker: () => parse_precedence(
                                get_precedence(TokenType.AND),
                              ),
                            ),
                          );
                        case TokenType.OR:
                          return _compile_expr(
                            ExprOr(
                              child_maker: () => parse_precedence(
                                get_precedence(
                                  TokenType.OR,
                                ),
                              ),
                            ),
                          );
                        default:
                          throw Exception("Invalid State");
                      }
                    }(),
                  );
                }
                if (can_assign) {
                  if (match(TokenType.EQUAL)) {
                    error_at_previous('Invalid assignment target');
                  }
                }
                return exprs;
              }(),
            ),
          );
        }
      }
      return parse_precedence(Precedence.ASSIGNMENT);
    }

    Expr expression() {
      // TODO parse expression
      // TODO compile_expression
      final expr =  parse_expression();
      // return compile_expr(expr, compiler);
      return expr;
    }

    DeclarationVari var_declaration() {
      return DeclarationVari(
        exprs: () {
          final exprs = compiler.visit_var_decl<Expr>(
            () sync* {
              for (;;) {
                consume(TokenType.IDENTIFIER, 'Expect variable name');
                yield MapEntry(
                  previous!,
                  () {
                    if (match(TokenType.EQUAL)) {
                      return expression();
                    } else {
                      compiler.visit_nil_post();
                      return const ExprNil();
                    }
                  },
                );
                if (match(TokenType.COMMA)) {
                  continue;
                } else {
                  break;
                }
              }
            },
          );
          consume(TokenType.SEMICOLON, 'Expect a newline after variable declaration');
          return exprs;
        }(),
      );
    }

    Stmt statement() {
      if (match(TokenType.PRINT)) {
        final expr = expression();
        consume(TokenType.SEMICOLON, 'Expect a newline after value');
        compiler.visit_print_post();
        return StmtOutput(
          expr: expr,
        );
      } else if (match(TokenType.FOR)) {
        if (match(TokenType.LEFT_PAREN)) {
          return compiler.visit_classic_for<LoopLeft, Expr, Stmt, StmtLoop>(
            () {
              if (match(TokenType.SEMICOLON)) {
                return null;
              } else if (match(TokenType.VAR)) {
                return LoopLeftVari(
                  decl: var_declaration(),
                );
              } else {
                final expr = expression();
                consume(TokenType.SEMICOLON, 'Expect a newline after expression');
                compiler.pop();
                return LoopLeftExpr(
                  expr: expr,
                );
              }
            },
            () {
              if (match(TokenType.SEMICOLON)) {
                return null;
              } else {
                final expr = expression();
                consume(TokenType.SEMICOLON, "Expect ';' after loop condition");
                return expr;
              }
            },
            () {
              if (match(TokenType.RIGHT_PAREN)) {
                return null;
              } else {
                return () {
                  final expr = expression();
                  consume(TokenType.RIGHT_PAREN, "Expect ')' after for clauses");
                  return expr;
                };
              }
            },
            statement,
            (final a, final b, final c, final d) => StmtLoop(
              left: a,
              center: b,
              right: c,
              body: d,
            ),
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
          return compiler.visit_iter_for<Expr, Stmt, StmtLoop2>(
            key_name: key_name,
            value_name: value_name,
            iterable: expression,
            body: statement,
            make: (final iterable, final body) => StmtLoop2(
              key_name: key_name,
              value_name: value_name,
              center: iterable,
              body: body,
            ),
          );
        }
      } else if (match(TokenType.IF)) {
        return compiler.visit_if<Expr, Stmt, StmtConditional>(
          expression,
          statement,
          () {
            if (match(TokenType.ELSE)) {
              return statement();
            } else {
              return null;
            }
          },
          (final a, final b, final c) => StmtConditional(
            expr: a,
            stmt: b,
            other: c,
          ),
        );
      } else if (match(TokenType.RETURN)) {
        if (match(TokenType.SEMICOLON)) {
          compiler.visit_return_empty_post();
          return const StmtRet(
            expr: null,
          );
        } else {
          return StmtRet(
            expr: compiler.visit_return_expr(
              () {
                final expr = expression();
                consume(TokenType.SEMICOLON, 'Expect a newline after return value');
                return expr;
              },
            ),
          );
        }
      } else if (match(TokenType.WHILE)) {
        return compiler.visit_while<Expr, Stmt, Stmt>(
          expression,
          statement,
          (final expr, final stmt) => StmtWhil(
            expr: expr,
            stmt: stmt,
          ),
        );
      } else if (match(TokenType.LEFT_BRACE)) {
        return StmtBlock(
          block: Block(
            decls: compiler.visit_block(
              () sync* {
                while (!check(TokenType.RIGHT_BRACE) && !check(TokenType.EOF)) {
                  yield parse_declaration(
                    compiler: compiler,
                  );
                }
                consume(TokenType.RIGHT_BRACE, 'Unterminated block');
              },
            ),
          ),
        );
      } else {
        final expr = expression();
        consume(TokenType.SEMICOLON, 'Expect a newline after expression');
        // region emitter
        compiler.visit_expr_stmt_post();
        // endregion
        return StmtExpr(
          expr: expr,
        );
      }
    }

    Block function_block(
      final FunctionType type,
    ) {
      return compiler.visit_fn<Declaration, Block>(
        () => previous!.lexeme,
        type,
        () {
          consume(TokenType.LEFT_PAREN, "Expect '(' after function name");
          final args = <NaturalToken>[];
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
          return args;
        },
        (final declaration) {
          consume(TokenType.LEFT_BRACE, 'Expect function body');
          return Block(
            decls: () {
              final decls = <Declaration>[];
              while (!check(TokenType.RIGHT_BRACE) && !check(TokenType.EOF)) {
                final decl = declaration();
                decls.add(decl);
              }
              consume(TokenType.RIGHT_BRACE, 'Unterminated block');
              return decls;
            }(),
          );
        },
        (final compiler) => parse_declaration(
          compiler: compiler,
        ),
      );
    }

    Declaration parse_decl() {
      if (match(TokenType.CLASS)) {
        consume(TokenType.IDENTIFIER, 'Expect class name');
        final class_name = previous!;
        final functions = compiler.visit_class<Method, Block>(
          class_name,
          () => previous!,
          () {
            if (match(TokenType.LESS)) {
              consume(TokenType.IDENTIFIER, 'Expect superclass name');
              return previous!;
            } else {
              return null;
            }
          },
          (final fn) {
            consume(TokenType.LEFT_BRACE, 'Expect class body');
            final functions = <Method>[];
            while (!check(TokenType.RIGHT_BRACE) && !check(TokenType.EOF)) {
              consume(TokenType.IDENTIFIER, 'Expect method name');
              functions.add(
                fn(
                  previous!,
                  (final true_init_false_method) => function_block(
                    () {
                      if (true_init_false_method) {
                        return FunctionType.INITIALIZER;
                      } else {
                        return FunctionType.METHOD;
                      }
                    }(),
                  ),
                ),
              );
            }
            consume(TokenType.RIGHT_BRACE, 'Unterminated class body');
            return functions;
          },
          (final a, final b) => Method(
            name: a,
            block: b,
          ),
        );
        return DeclarationClazz(
          name: class_name,
          functions: functions,
        );
      } else if (match(TokenType.FUN)) {
        consume(TokenType.IDENTIFIER, 'Expect function name');
        final name = previous!;
        final block = compiler.visit_fun(
          name,
          () => function_block(FunctionType.FUNCTION),
        );
        return DeclarationFun(
          block: block,
          name: name,
        );
      } else if (match(TokenType.VAR)) {
        return var_declaration();
      } else {
        return DeclarationStmt(
          stmt: statement(),
        );
      }
    }

    final decl = parse_decl();
    if (panic_mode) {
      panic_mode = false;
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
    return decl;
  }

  @override
  bool is_eof() {
    return match(TokenType.EOF);
  }
}

abstract class Parser {
  int get previous_line;

  void advance();

  bool is_eof();

  Declaration parse_declaration({
    required final Compiler compiler,
  });
}

abstract class ErrorDelegate {
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
  switch (get_precedence(type)) {
    case Precedence.NONE:
      return Precedence.ASSIGNMENT;
    case Precedence.ASSIGNMENT:
      return Precedence.OR;
    case Precedence.OR:
      return Precedence.AND;
    case Precedence.AND:
      return Precedence.EQUALITY;
    case Precedence.EQUALITY:
      return Precedence.COMPARISON;
    case Precedence.COMPARISON:
      return Precedence.TERM;
    case Precedence.TERM:
      return Precedence.FACTOR;
    case Precedence.FACTOR:
      return Precedence.POWER;
    case Precedence.POWER:
      return Precedence.UNARY;
    case Precedence.UNARY:
      return Precedence.CALL;
    case Precedence.CALL:
      return Precedence.PRIMARY;
    case Precedence.PRIMARY:
      throw Exception("Invalid State");
  }
}
