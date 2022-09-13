// ignore_for_file: no_default_cases

import 'compiler.dart';
import 'models/ast.dart';
import 'models/errors.dart';

MapEntry<Parser, ErrorDelegate> make_parser({
  required final List<Token> tokens,
  required final Debug debug,
}) {
  final parser = _ParserImpl(
    tokens: tokens,
    debug: debug,
  );
  return MapEntry(
    parser,
    parser,
  );
}

class _ParserImpl implements Parser, ErrorDelegate {
  final List<Token> tokens;
  @override
  final Debug debug;
  Token? current;
  Token? previous;
  int current_idx;
  bool panic_mode;

  _ParserImpl({
    required final this.tokens,
    required final this.debug,
  })  : current_idx = 0,
        panic_mode = false {
    advance();
  }

  @override
  int get previous_line {
    return previous!.loc.line;
  }

  @override
  void error_at(
    final Token token,
    final String? message,
  ) {
    if (!panic_mode) {
      panic_mode = true;
      final error = CompilerError(
        token: token,
        msg: message,
      );
      debug.errors.add(error);
      error.dump(debug);
    }
  }

  void advance() {
    previous = current;
    while (current_idx < tokens.length) {
      current = tokens[current_idx++];
      if (current!.type == TokenType.ERROR) {
        error_at(current!, current!.lexeme);
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
      error_at(current!, message);
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

  Expr parse_expression() {
    final self = parse_expression;
    List<Expr> parse_argument_list() {
      final args = <Expr>[];
      if (!check(TokenType.RIGHT_PAREN)) {
        do {
          args.add(self());
          if (args.length == 256) {
            error_at(previous!, "Can't have more than 255 arguments");
          }
        } while (match(TokenType.COMMA));
      }
      consume(TokenType.RIGHT_PAREN, "Expect ')' after arguments");
      return args;
    }

    Expr parse_precedence(
      final Precedence precedence,
    ) {
      final can_assign = precedence.index <= Precedence.ASSIGNMENT.index;
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
              line: previous_line,
            );
          case TokenType.NUMBER:
            return ExprNumber(
              value: previous!,
              line: previous_line,
            );
          case TokenType.OBJECT:
            return ExprObject(
              token: previous!,
              line: previous_line,
            );
          case TokenType.THIS:
            return ExprSelf(
              previous: previous!,
              line: previous_line,
            );
          case TokenType.FALSE:
            return ExprFalsity(
              line: previous_line,
            );
          case TokenType.NIL:
            return ExprNil(
              line: previous_line,
            );
          case TokenType.TRUE:
            return ExprTruth(
              line: previous_line,
            );
          case TokenType.MINUS:
            return ExprNegated(
              child: parse_precedence(Precedence.UNARY),
              line: previous_line,
            );
          case TokenType.BANG:
            return ExprNot(
              child: parse_precedence(Precedence.UNARY),
              line: previous_line,
            );
          case TokenType.IDENTIFIER:
            final name = previous!;
            if (can_assign) {
              if (match(TokenType.EQUAL)) {
                return ExprSet2(
                  name: name,
                  arg: self(),
                  line: previous_line,
                );
              } else {
                return ExprGetSet2(
                  name: name,
                  child: (){
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
                  line: previous_line,
                );
              }
            } else {
              return ExprGetSet2(
                name: name,
                child: null,
                line: previous_line,
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
              line: previous_line,
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
              line: previous_line,
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
              line: previous_line,
            );
          default:
            return null;
        }
      }();
      if (prefix_rule == null) {
        error_at(previous!, 'Expect expression');
        return const ExprExpected();
      } else {
        return ExprComposite(
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
                          line: previous_line,
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
                          line: previous_line,
                        );
                      }
                    case TokenType.LEFT_PAREN:
                      return ExprCall(
                        args: parse_argument_list(),
                        line: previous_line,
                      );
                    case TokenType.DOT:
                      consume(TokenType.IDENTIFIER, "Expect property name after '.'");
                      final name_token = previous!;
                      if (can_assign && match(TokenType.EQUAL)) {
                        return ExprSet(
                          name: name_token,
                          arg: self(),
                          line: previous_line,
                        );
                      } else if (match(TokenType.LEFT_PAREN)) {
                        return ExprInvoke(
                          name: name_token,
                          args: parse_argument_list(),
                          line: previous_line,
                        );
                      } else {
                        return ExprGet(
                          name: name_token,
                          line: previous_line,
                        );
                      }
                    case TokenType.MINUS:
                      return ExprMinus(
                        child: parse_precedence(get_next_precedence(TokenType.MINUS)),
                        line: previous_line,
                      );
                    case TokenType.PLUS:
                      return ExprPlus(
                        child: parse_precedence(get_next_precedence(TokenType.PLUS)),
                        line: previous_line,
                      );
                    case TokenType.SLASH:
                      return ExprSlash(
                        child: parse_precedence(get_next_precedence(TokenType.SLASH)),
                        line: previous_line,
                      );
                    case TokenType.STAR:
                      return ExprStar(
                        child: parse_precedence(get_next_precedence(TokenType.STAR)),
                        line: previous_line,
                      );
                    case TokenType.CARET:
                      return ExprPow(
                        child: parse_precedence(get_next_precedence(TokenType.CARET)),
                        line: previous_line,
                      );
                    case TokenType.PERCENT:
                      return ExprModulo(
                        child: parse_precedence(get_next_precedence(TokenType.PERCENT)),
                        line: previous_line,
                      );
                    case TokenType.BANG_EQUAL:
                      return ExprNeq(
                        child: parse_precedence(get_next_precedence(TokenType.BANG_EQUAL)),
                        line: previous_line,
                      );
                    case TokenType.EQUAL_EQUAL:
                      return ExprEq(
                        child: parse_precedence(get_next_precedence(TokenType.EQUAL_EQUAL)),
                        line: previous_line,
                      );
                    case TokenType.GREATER:
                      return ExprG(
                        child: parse_precedence(get_next_precedence(TokenType.GREATER)),
                        line: previous_line,
                      );
                    case TokenType.GREATER_EQUAL:
                      return ExprGeq(
                        child: parse_precedence(get_next_precedence(TokenType.GREATER_EQUAL)),
                        line: previous_line,
                      );
                    case TokenType.LESS:
                      return ExprL(
                        child: parse_precedence(get_next_precedence(TokenType.LESS)),
                        line: previous_line,
                      );
                    case TokenType.LESS_EQUAL:
                      return ExprLeq(
                        child: parse_precedence(get_next_precedence(TokenType.LESS_EQUAL)),
                        line: previous_line,
                      );
                    case TokenType.AND:
                      return ExprAnd(
                        token: previous!,
                        child: parse_precedence(
                          get_precedence(TokenType.AND),
                        ),
                        line: previous_line,
                      );
                    case TokenType.OR:
                      return ExprOr(
                        token: previous!,
                        child: parse_precedence(
                          get_precedence(
                            TokenType.OR,
                          ),
                        ),
                        line: previous_line,
                      );
                    default:
                      throw Exception("Invalid State");
                  }
                }(),
              );
            }
            if (can_assign) {
              if (match(TokenType.EQUAL)) {
                error_at(previous!, 'Invalid assignment target');
              }
            }
            return exprs;
          }(),
        );
      }
    }

    return parse_precedence(Precedence.ASSIGNMENT);
  }

  DeclarationVari parse_var_declaration() {
    return DeclarationVari(
      exprs: () {
        final exprs = () sync* {
          for (;;) {
            consume(TokenType.IDENTIFIER, 'Expect variable name');
            yield MapEntry(
              previous!,
              () {
                if (match(TokenType.EQUAL)) {
                  return parse_expression();
                } else {
                  return ExprNil(
                    line: previous_line,
                  );
                }
              }(),
            );
            if (match(TokenType.COMMA)) {
              continue;
            } else {
              break;
            }
          }
        }()
            .toList();
        consume(TokenType.SEMICOLON, 'Expect a newline after variable declaration');
        return exprs;
      }(),
      line: previous_line,
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
          line: previous_line,
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
          line: previous_line,
        );
      }
    } else if (match(TokenType.IF)) {
      final expr = parse_expression();
      final stmt = parse_statement();
      final if_kw = previous!;
      final else_kw = previous!;
      final line = previous_line;
      return StmtConditional(
        expr: expr,
        stmt: stmt,
        if_kw: if_kw,
        line: line,
        else_kw: else_kw,
        other_maker: () {
          if (match(TokenType.ELSE)) {
            return parse_statement();
          } else {
            return null;
          }
        },
      );
    } else if (match(TokenType.WHILE)) {
      return StmtWhil(
        expr: parse_expression(),
        stmt: parse_statement(),
        exit_kw: previous!,
        line: previous_line,
      );
    } else if (match(TokenType.LEFT_BRACE)) {
      return StmtBlock(
        block_maker: parse_decls,
        line: previous_line,
      );
    } else if (match(TokenType.PRINT)) {
      return StmtOutput(
        expr: () {
          final expr = parse_expression();
          consume(TokenType.SEMICOLON, 'Expect a newline after value');
          return expr;
        }(),
        line: previous_line,
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
        line: previous_line,
      );
    } else {
      return StmtExpr(
        expr: () {
          final expr = parse_expression();
          consume(TokenType.SEMICOLON, 'Expect a newline after expression');
          return expr;
        }(),
        line: previous_line,
      );
    }
  }

  Functiony parse_function_block() {
    return Functiony(
      name: () {
        final name = previous!.lexeme;
        consume(TokenType.LEFT_PAREN, "Expect '(' after function name");
        return name;
      }(),
      args: () {
        final args = <Token>[];
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
      make_decls: (final new_compiler) => parse_decls(new_compiler).toList(),
    );
  }

  Iterable<Declaration> parse_decls(
    final Compiler compiler,
  ) sync* {
    for (;;) {
      if (!check(TokenType.RIGHT_BRACE)) {
        if (match(TokenType.EOF)) {
          break;
        } else {
          yield parse_declaration(
            compiler: compiler,
          );
        }
      } else {
        break;
      }
    }
    consume(TokenType.RIGHT_BRACE, 'Unterminated block');
  }

  Declaration parse_decl(
    final Compiler compiler,
  ) {
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
        make_functions: (final compiler) {
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
                line: previous_line,
              );
              compiler.visit_method(method);
              methods.add(method);
            }
          }
          // TODO why can't i do this instead of above.
          // for (final method in methods) {
          //   compiler.visit_method(method);
          // }
          consume(TokenType.RIGHT_BRACE, 'Unterminated class body');
          return methods;
        },
        line: previous_line,
      );
    } else if (match(TokenType.FUN)) {
      consume(TokenType.IDENTIFIER, 'Expect function name');
      return DeclarationFun(
        name: previous!,
        make_block: (final compiler) {
          final functiony = parse_function_block();
          compiler.visit_fn(
            FunctionType.FUNCTION,
            functiony,
            previous_line,
          );
          return Block(
            decls: functiony.decls,
          );
        },
        line: previous_line,
      );
    } else if (match(TokenType.VAR)) {
      return parse_var_declaration();
    } else {
      return DeclarationStmt(
        stmt: parse_statement(),
      );
    }
  }

  Declaration parse_declaration({
    required final Compiler compiler,
  }) {
    final decl = parse_decl(compiler);
    // TODO why can't I compile after synchronization?
    compiler.compile_declaration(decl);
    synchronize();
    return decl;
  }

  // TODO remove ast late fields once all split properly
  @override
  CompilationUnit parse_compilation_unit({
    required final Compiler compiler,
  }) {
    return CompilationUnit(
      decls: () sync* {
        for (;;) {
          if (match(TokenType.EOF)) {
            break;
          } else {
            yield parse_declaration(
              compiler: compiler,
            );
          }
        }
      }()
          .toList(),
    );
  }

  void synchronize() {
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
  }
}

abstract class Parser {
  int get previous_line;

  CompilationUnit parse_compilation_unit({
    required final Compiler compiler,
  });
}

abstract class ErrorDelegate {
  Debug get debug;

  // TODO replace token with line?
  void error_at(
    final Token token,
    final String message,
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
