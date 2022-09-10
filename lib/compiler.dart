import 'dart:collection';
import 'dart:math';

import 'package:sprintf/sprintf.dart';

import 'ast.dart';
import 'model.dart';

// region compiler
CompilerResult compile(
  final List<NaturalToken> tokens, {
  final bool silent = false,
  final bool traceBytecode = false,
}) {
  // Compile script
  final parser = Parser(
    tokens,
    silent: silent,
  );
  final compiler = Compiler(
    type: FunctionType.SCRIPT,
    parser: parser,
    debug_trace_bytecode: traceBytecode,
  );
  parser.advance();
  while (!compiler.match(TokenType.EOF)) {
    compiler.declaration();
  }
  final function = compiler.end_compiler();
  return CompilerResult(
    function,
    parser.errors,
    parser.debug,
  );
}

class Compiler with CompilerMixin {
  @override
  final List<Local> locals;
  @override
  final List<Upvalue> upvalues;
  @override
  final Parser parser;
  @override
  final FunctionType type;
  @override
  int scope_depth;
  @override
  bool debug_trace_bytecode;
  @override
  ClassCompiler? current_class;
  @override
  ObjFunction function;

  @override
  Compiler? get enclosing => null;

  Compiler({
    required final this.type,
    required final this.parser,
    final this.debug_trace_bytecode = false,
  })  : scope_depth = 0,
        function = (() {
          final function = ObjFunction();
          switch (type) {
            case FunctionType.FUNCTION:
              function.name = parser.previous!.str;
              break;
            case FunctionType.INITIALIZER:
              function.name = parser.previous!.str;
              break;
            case FunctionType.METHOD:
              function.name = parser.previous!.str;
              break;
            case FunctionType.SCRIPT:
              break;
          }
          return function;
        }()),
        locals = [
          Local(
            SyntheticTokenImpl(
              type: TokenType.FUN,
              str: () {
                if (type != FunctionType.FUNCTION) {
                  return 'this';
                } else {
                  return '';
                }
              }(),
            ),
            depth: 0,
          ),
        ],
        upvalues = [];
}

class CompilerWrapped with CompilerMixin {
  @override
  final List<Local> locals;
  @override
  final List<Upvalue> upvalues;
  @override
  final Parser parser;
  @override
  final FunctionType type;
  @override
  final CompilerMixin enclosing;
  @override
  int scope_depth;
  @override
  bool debug_trace_bytecode;
  @override
  ClassCompiler? current_class;
  @override
  ObjFunction function;

  CompilerWrapped({
    required final this.type,
    required final this.enclosing,
  })  : function = (() {
          final function = ObjFunction();
          switch (type) {
            case FunctionType.FUNCTION:
              function.name = enclosing.parser.previous!.str;
              break;
            case FunctionType.INITIALIZER:
              function.name = enclosing.parser.previous!.str;
              break;
            case FunctionType.METHOD:
              function.name = enclosing.parser.previous!.str;
              break;
            case FunctionType.SCRIPT:
              break;
          }
          return function;
        }()),
        parser = enclosing.parser,
        current_class = enclosing.current_class,
        scope_depth = enclosing.scope_depth + 1,
        debug_trace_bytecode = enclosing.debug_trace_bytecode,
        locals = [
          Local(
            SyntheticTokenImpl(
              type: TokenType.FUN,
              str: () {
                if (type != FunctionType.FUNCTION) {
                  return 'this';
                } else {
                  return '';
                }
              }(),
            ),
            depth: 0,
          ),
        ],
        upvalues = [];
}

// TODO convert this to a two phase process:
// TODO  * parse to an ast first
// TODO  * compile to bytecode.
mixin CompilerMixin {
  List<Local> get locals;

  List<Upvalue> get upvalues;

  abstract int scope_depth;
  abstract ClassCompiler? current_class;
  abstract ObjFunction function;

  Parser get parser;

  FunctionType get type;

  CompilerMixin? get enclosing;

  bool get debug_trace_bytecode;

  ObjFunction end_compiler() {
    emit_return();
    if (parser.errors.isEmpty && debug_trace_bytecode) {
      parser.debug.disassemble_chunk(current_chunk, function.name ?? '<script>');
    }
    return function;
  }

  Chunk get current_chunk {
    return function.chunk;
  }

  bool match(
    final TokenType type,
  ) {
    return parser.match(type);
  }

  void emit_op(
    final OpCode op,
  ) {
    emit_byte(op.index);
  }

  void emit_byte(
    final int byte,
  ) {
    current_chunk.write(byte, parser.previous!);
  }

  void emit_bytes(
    final int byte1,
    final int byte2,
  ) {
    emit_byte(byte1);
    emit_byte(byte2);
  }

  void emit_loop(
    final int loopStart,
  ) {
    emit_op(OpCode.LOOP);
    final offset = current_chunk.count - loopStart + 2;
    if (offset > UINT16_MAX) parser.error('Loop body too large');
    emit_byte((offset >> 8) & 0xff);
    emit_byte(offset & 0xff);
  }

  int emit_jump(
    final OpCode instruction,
  ) {
    emit_op(instruction);
    emit_byte(0xff);
    emit_byte(0xff);
    return current_chunk.count - 2;
  }

  void emit_return() {
    if (type == FunctionType.INITIALIZER) {
      emit_bytes(OpCode.GET_LOCAL.index, 0);
    } else {
      emit_op(OpCode.NIL);
    }
    emit_op(OpCode.RETURN);
  }

  int make_constant(
    final Object? value,
  ) {
    final constant = current_chunk.add_constant(value);
    if (constant > UINT8_MAX) {
      parser.error('Too many constants in one chunk');
      return 0;
    } else {
      return constant;
    }
  }

  void emit_constant(
    final Object? value,
  ) {
    emit_bytes(OpCode.CONSTANT.index, make_constant(value));
  }

  void patch_jump(
    final int offset,
  ) {
    // -2 to adjust for the bytecode for the jump offset itself.
    final jump = current_chunk.count - offset - 2;
    if (jump > UINT16_MAX) {
      parser.error('Too much code to jump over');
    }
    current_chunk.code[offset] = (jump >> 8) & 0xff;
    current_chunk.code[offset + 1] = jump & 0xff;
  }

  int identifier_constant(
    final SyntheticToken name,
  ) {
    return make_constant(name.str);
  }

  bool identifiers_equal(
    final SyntheticToken a,
    final SyntheticToken b,
  ) {
    return a.str == b.str;
  }

  int resolve_local(
    final SyntheticToken? name,
  ) {
    for (int i = locals.length - 1; i >= 0; i--) {
      final local = locals[i];
      if (identifiers_equal(name!, local.name!)) {
        if (!local.initialized) {
          parser.error('Can\'t read local variable in its own initializer');
        }
        return i;
      } else {
        continue;
      }
    }
    return -1;
  }

  int add_upvalue(
    final SyntheticToken? name,
    final int index,
    final bool is_local,
  ) {
    assert(upvalues.length == function.upvalueCount, "");
    for (var i = 0; i < upvalues.length; i++) {
      final upvalue = upvalues[i];
      if (upvalue.index == index && upvalue.is_local == is_local) {
        return i;
      }
    }
    if (upvalues.length == UINT8_COUNT) {
      parser.error('Too many closure variables in function');
      return 0;
    } else {
      upvalues.add(Upvalue(name, index, is_local));
      return function.upvalueCount++;
    }
  }

  int resolve_upvalue(
    final SyntheticToken? name,
  ) {
    if (enclosing == null) {
      return -1;
    } else {
      final local_idx = enclosing!.resolve_local(name);
      if (local_idx != -1) {
        final local = enclosing!.locals[local_idx];
        local.is_captured = true;
        return add_upvalue(local.name, local_idx, true);
      } else {
        final upvalueIdx = enclosing!.resolve_upvalue(name);
        if (upvalueIdx != -1) {
          final upvalue = enclosing!.upvalues[upvalueIdx];
          return add_upvalue(upvalue.name, upvalueIdx, false);
        } else {
          return -1;
        }
      }
    }
  }

  void add_local(
    final SyntheticToken? name,
  ) {
    if (locals.length >= UINT8_COUNT) {
      parser.error('Too many local variables in function');
    } else {
      locals.add(Local(name));
    }
  }

  void delare_local_variable() {
    // Global variables are implicitly declared.
    if (scope_depth != 0) {
      final name = parser.previous;
      for (var i = locals.length - 1; i >= 0; i--) {
        final local = locals[i];
        if (local.depth != -1 && local.depth < scope_depth) {
          break; // [negative]
        }
        if (identifiers_equal(name!, local.name!)) {
          parser.error('Already variable with this name in this scope');
        }
      }
      add_local(name);
    }
  }

  int parse_variable(
    final String error_message,
  ) {
    parser.consume(TokenType.IDENTIFIER, error_message);
    if (scope_depth > 0) {
      delare_local_variable();
      return 0;
    } else {
      return identifier_constant(parser.previous!);
    }
  }

  void mark_local_variable_initialized() {
    if (scope_depth != 0) {
      locals.last.depth = scope_depth;
    }
  }

  void define_variable(
    final int global, {
    final NaturalToken? token,
    final int peek_dist = 0,
  }) {
    final is_local = scope_depth > 0;
    if (is_local) {
      mark_local_variable_initialized();
    } else {
      emit_bytes(OpCode.DEFINE_GLOBAL.index, global);
    }
  }

  List<Expr> argument_list() {
    final args = <Expr>[];
    if (!parser.check(TokenType.RIGHT_PAREN)) {
      do {
        args.add(expression());
        if (args.length == 256) {
          parser.error("Can't have more than 255 arguments");
        }
      } while (match(TokenType.COMMA));
    }
    parser.consume(TokenType.RIGHT_PAREN, "Expect ')' after arguments");
    return args;
  }

  void get_or_set_variable(
    final SyntheticToken? name,
    final bool can_assign,
  ) {
    bool matchPair(
      final TokenType first,
      final TokenType second,
    ) {
      return parser.matchPair(first, second);
    }

    int arg = resolve_local(name);
    OpCode get_op;
    OpCode set_op;
    if (arg != -1) {
      get_op = OpCode.GET_LOCAL;
      set_op = OpCode.SET_LOCAL;
    } else if ((arg = resolve_upvalue(name)) != -1) {
      get_op = OpCode.GET_UPVALUE;
      set_op = OpCode.SET_UPVALUE;
    } else {
      arg = identifier_constant(name!);
      get_op = OpCode.GET_GLOBAL;
      set_op = OpCode.SET_GLOBAL;
    }
    // Special mathematical assignment
    final assign_op = () {
      if (can_assign) {
        if (matchPair(TokenType.PLUS, TokenType.EQUAL)) {
          return OpCode.ADD;
        } else if (matchPair(TokenType.MINUS, TokenType.EQUAL)) {
          return OpCode.SUBTRACT;
        } else if (matchPair(TokenType.STAR, TokenType.EQUAL)) {
          return OpCode.MULTIPLY;
        } else if (matchPair(TokenType.SLASH, TokenType.EQUAL)) {
          return OpCode.DIVIDE;
        } else if (matchPair(TokenType.PERCENT, TokenType.EQUAL)) {
          return OpCode.MOD;
        } else if (matchPair(TokenType.CARET, TokenType.EQUAL)) {
          return OpCode.POW;
        } else {
          return null;
        }
      } else {
        return null;
      }
    }();
    if (can_assign && (assign_op != null || match(TokenType.EQUAL))) {
      if (assign_op != null) emit_bytes(get_op.index, arg);
      expression();
      if (assign_op != null) emit_op(assign_op);
      emit_bytes(set_op.index, arg);
    } else {
      emit_bytes(get_op.index, arg);
    }
  }

  SyntheticTokenImpl synthetic_token(
    final String str,
  ) {
    return SyntheticTokenImpl(
      type: TokenType.IDENTIFIER,
      str: str,
    );
  }

  Expr? parse_precedence(
    final Precedence precedence,
  ) {
    parser.advance();
    final can_assign = precedence.index <= Precedence.ASSIGNMENT.index;
    final Expr? Function()? prefix_rule = () {
      switch (parser.previous!.type) {
        case TokenType.LEFT_PAREN:
          return () {
            final expr = expression();
            parser.consume(TokenType.RIGHT_PAREN, "Expect ')' after expression");
            return expr;
          };
        case TokenType.LEFT_BRACE:
          return () {
            int val_count = 0;
            final entries = <ExprmapMapEntry>[];
            if (!parser.check(TokenType.RIGHT_BRACE)) {
              do {
                final key = expression();
                parser.consume(TokenType.COLON, "Expect ':' between map key-value pairs");
                final value = expression();
                entries.add(
                  ExprmapMapEntry(
                    key: key,
                    value: value,
                  ),
                );
                val_count++;
              } while (match(TokenType.COMMA));
            }
            parser.consume(TokenType.RIGHT_BRACE, "Expect '}' after map initializer");
            emit_bytes(OpCode.MAP_INIT.index, val_count);
            return ExprMap(
              entries: entries,
            );
          };
        case TokenType.LEFT_BRACK:
          return () {
            int val_count = 0;
            final values = <Expr>[];
            if (!parser.check(TokenType.RIGHT_BRACK)) {
              values.add(expression());
              val_count += 1;
              if (parser.match(TokenType.COLON)) {
                values.add(expression());
                val_count = -1;
              } else {
                while (match(TokenType.COMMA)) {
                  values.add(expression());
                  val_count++;
                }
              }
            }
            parser.consume(TokenType.RIGHT_BRACK, "Expect ']' after list initializer");
            if (val_count >= 0) {
              emit_bytes(OpCode.LIST_INIT.index, val_count);
            } else {
              emit_byte(OpCode.LIST_INIT_RANGE.index);
            }
            return ExprList(
              values: values,
            );
          };
        case TokenType.MINUS:
          return () {
            parse_precedence(Precedence.UNARY);
            emit_op(OpCode.NEGATE);
          };
        case TokenType.BANG:
          return () {
            parse_precedence(Precedence.UNARY);
            emit_op(OpCode.NOT);
          };
        case TokenType.IDENTIFIER:
          return () {
            get_or_set_variable(parser.previous, can_assign);
          };
        case TokenType.STRING:
          return () {
            final str = parser.previous!.str;
            emit_constant(str);
          };
        case TokenType.NUMBER:
          return () {
            final value = double.tryParse(parser.previous!.str!);
            if (value == null) {
              parser.error('Invalid number');
            } else {
              emit_constant(value);
            }
          };
        case TokenType.OBJECT:
          return () {
            emit_constant(null);
          };
        case TokenType.FALSE:
          return () {
            emit_op(OpCode.FALSE);
          };
        case TokenType.NIL:
          return () {
            emit_op(OpCode.NIL);
          };
        case TokenType.SUPER:
          return () {
            if (current_class == null) {
              parser.error("Can't use 'super' outside of a class");
            } else if (!current_class!.has_superclass) {
              parser.error("Can't use 'super' in a class with no superclass");
            }
            parser.consume(TokenType.DOT, "Expect '.' after 'super'");
            parser.consume(TokenType.IDENTIFIER, 'Expect superclass method name');
            final name = identifier_constant(parser.previous!);
            get_or_set_variable(synthetic_token('this'), false);
            if (match(TokenType.LEFT_PAREN)) {
              final argCount = argument_list();
              get_or_set_variable(synthetic_token('super'), false);
              emit_bytes(OpCode.SUPER_INVOKE.index, name);
              emit_byte(argCount.length);
            } else {
              get_or_set_variable(synthetic_token('super'), false);
              emit_bytes(OpCode.GET_SUPER.index, name);
            }
          };
        case TokenType.THIS:
          return () {
            if (current_class == null) {
              parser.error("Can't use 'this' outside of a class");
            } else {
              get_or_set_variable(parser.previous, false);
            }
          };
        case TokenType.TRUE:
          return () {
            emit_op(OpCode.TRUE);
          };
        // ignore: no_default_cases
        default:
          return null;
      }
    }();
    if (prefix_rule == null) {
      parser.error('Expect expression');
      return null;
    } else {
      // ignore: unused_local_variable
      final prefix_expr = prefix_rule();
      while (precedence.index <= get_precedence(parser.current!.type).index) {
        parser.advance();
        // ignore: unused_local_variable
        final infix_expr = () {
          switch (parser.previous!.type) {
            case TokenType.LEFT_PAREN:
              final args = argument_list();
              emit_bytes(OpCode.CALL.index, args.length);
              return ExprCall(
                args: args,
              );
            case TokenType.LEFT_BRACK:
              bool get_range = match(TokenType.COLON);
              // Left hand side operand
              if (get_range) {
                emit_constant(Nil);
              } else {
                expression();
                get_range = match(TokenType.COLON);
              }
              // Right hand side operand
              if (match(TokenType.RIGHT_BRACK)) {
                if (get_range) {
                  emit_constant(Nil);
                }
              } else {
                if (get_range) {
                  expression();
                }
                parser.consume(TokenType.RIGHT_BRACK, "Expect ']' after list indexing");
              }
              // Emit operation
              if (get_range) {
                emit_op(OpCode.CONTAINER_GET_RANGE);
              } else if (can_assign && match(TokenType.EQUAL)) {
                expression();
                emit_op(OpCode.CONTAINER_SET);
              } else {
                emit_op(OpCode.CONTAINER_GET);
              }
              break;
            case TokenType.DOT:
              parser.consume(TokenType.IDENTIFIER, "Expect property name after '.'");
              final name_token = parser.previous!;
              final name = identifier_constant(name_token);
              if (can_assign && match(TokenType.EQUAL)) {
                final expr = expression();
                emit_bytes(OpCode.SET_PROPERTY.index, name);
                return ExprSet(arg: expr, name: name_token);
              } else if (match(TokenType.LEFT_PAREN)) {
                final args = argument_list();
                emit_bytes(OpCode.INVOKE.index, name);
                emit_byte(args.length);
                return ExprInvoke(args: args, name: name_token);
              } else {
                emit_bytes(OpCode.GET_PROPERTY.index, name);
                return ExprGet(name: name_token);
              }
            case TokenType.MINUS:
              parse_precedence(get_next_precedence(TokenType.MINUS));
              emit_op(OpCode.SUBTRACT);
              break;
            case TokenType.PLUS:
              parse_precedence(get_next_precedence(TokenType.PLUS));
              emit_op(OpCode.ADD);
              break;
            case TokenType.SLASH:
              parse_precedence(get_next_precedence(TokenType.SLASH));
              emit_op(OpCode.DIVIDE);
              break;
            case TokenType.STAR:
              parse_precedence(get_next_precedence(TokenType.STAR));
              emit_op(OpCode.MULTIPLY);
              break;
            case TokenType.CARET:
              parse_precedence(get_next_precedence(TokenType.CARET));
              emit_op(OpCode.POW);
              break;
            case TokenType.PERCENT:
              parse_precedence(get_next_precedence(TokenType.PERCENT));
              emit_op(OpCode.MOD);
              break;
            case TokenType.BANG_EQUAL:
              parse_precedence(get_next_precedence(TokenType.BANG_EQUAL));
              emit_bytes(OpCode.EQUAL.index, OpCode.NOT.index);
              break;
            case TokenType.EQUAL_EQUAL:
              parse_precedence(get_next_precedence(TokenType.EQUAL_EQUAL));
              emit_op(OpCode.EQUAL);
              break;
            case TokenType.GREATER:
              parse_precedence(get_next_precedence(TokenType.GREATER));
              emit_op(OpCode.GREATER);
              break;
            case TokenType.GREATER_EQUAL:
              parse_precedence(get_next_precedence(TokenType.GREATER_EQUAL));
              emit_bytes(OpCode.LESS.index, OpCode.NOT.index);
              break;
            case TokenType.LESS:
              parse_precedence(get_next_precedence(TokenType.LESS));
              emit_op(OpCode.LESS);
              break;
            case TokenType.LESS_EQUAL:
              parse_precedence(get_next_precedence(TokenType.LESS_EQUAL));
              emit_bytes(OpCode.GREATER.index, OpCode.NOT.index);
              break;
            case TokenType.AND:
              final end_jump = emit_jump(OpCode.JUMP_IF_FALSE);
              emit_op(OpCode.POP);
              parse_precedence(get_precedence(TokenType.AND));
              patch_jump(end_jump);
              break;
            case TokenType.OR:
              final else_jump = emit_jump(OpCode.JUMP_IF_FALSE);
              final end_jump = emit_jump(OpCode.JUMP);
              patch_jump(else_jump);
              emit_op(OpCode.POP);
              parse_precedence(get_precedence(TokenType.OR));
              patch_jump(end_jump);
              break;
            // ignore: no_default_cases
            default:
              throw Exception("Invalid State");
          }
        }();
      }
      if (can_assign && match(TokenType.EQUAL)) {
        parser.error('Invalid assignment target');
      }
    }
  }

  Expr expression() {
    parse_precedence(Precedence.ASSIGNMENT);
    return Expr();
  }

  Declaration declaration() {
    void begin_scope() {
      scope_depth++;
    }

    void end_scope() {
      scope_depth--;
      while (locals.isNotEmpty && locals.last.depth > scope_depth) {
        if (locals.last.is_captured) {
          emit_op(OpCode.CLOSE_UPVALUE);
        } else {
          emit_op(OpCode.POP);
        }
        locals.removeLast();
      }
    }

    DeclarationVari var_declaration() {
      final exprs = <Expr>[];
      do {
        final global = parse_variable('Expect variable name');
        final token = parser.previous;
        if (match(TokenType.EQUAL)) {
          exprs.add(expression());
        } else {
          emit_op(OpCode.NIL);
        }
        define_variable(global, token: token);
      } while (match(TokenType.COMMA));
      parser.consume(TokenType.SEMICOLON, 'Expect a newline after variable declaration');
      return DeclarationVari(
        exprs: exprs,
      );
    }

    Stmt statement() {
      if (match(TokenType.PRINT)) {
        // print statement
        final expr = expression();
        parser.consume(TokenType.SEMICOLON, 'Expect a newline after value');
        emit_op(OpCode.PRINT);
        return StmtOutput(
          expr: expr,
        );
      } else if (match(TokenType.FOR)) {
        // for statement check
        if (match(TokenType.LEFT_PAREN)) {
          // legacy for statement
          // Deprecated
          begin_scope();
          final left = () {
            if (match(TokenType.SEMICOLON)) {
              // No initializer.
              return null;
            } else if (match(TokenType.VAR)) {
              final decl = var_declaration();
              return LoopLeftVari(
                decl: decl,
              );
            } else {
              final expr = expression();
              parser.consume(TokenType.SEMICOLON, 'Expect a newline after expression');
              emit_op(OpCode.POP);
              return LoopLeftExpr(
                expr: expr,
              );
            }
          }();
          int loop_start = current_chunk.count;
          int exit_jump = -1;
          final center = () {
            if (!match(TokenType.SEMICOLON)) {
              final expr = expression();
              parser.consume(TokenType.SEMICOLON, "Expect ';' after loop condition");
              exit_jump = emit_jump(OpCode.JUMP_IF_FALSE);
              emit_op(OpCode.POP); // Condition.
              return expr;
            } else {
              return null;
            }
          }();
          final right = () {
            if (!match(TokenType.RIGHT_PAREN)) {
              final body_jump = emit_jump(OpCode.JUMP);
              final increment_start = current_chunk.count;
              final expr = expression();
              emit_op(OpCode.POP);
              parser.consume(TokenType.RIGHT_PAREN, "Expect ')' after for clauses");
              emit_loop(loop_start);
              loop_start = increment_start;
              patch_jump(body_jump);
              return expr;
            } else {
              return null;
            }
          }();
          final stmt = statement();
          emit_loop(loop_start);
          if (exit_jump != -1) {
            patch_jump(exit_jump);
            emit_op(OpCode.POP); // Condition.
          }
          end_scope();
          return StmtLoop(
            left: left,
            center: center,
            right: right,
            body: stmt,
          );
        } else {
          // for statement
          begin_scope();
          // Key variable
          parse_variable('Expect variable name'); // Streamline those operations
          emit_op(OpCode.NIL);
          define_variable(0, token: parser.previous); // Remove 0
          final stack_idx = locals.length - 1;
          if (match(TokenType.COMMA)) {
            // Value variable
            parse_variable('Expect variable name');
            emit_op(OpCode.NIL);
            define_variable(0, token: parser.previous);
          } else {
            // Create dummy value slot
            add_local(synthetic_token('_for_val_'));
            emit_constant(0); // Emit a zero to permute val & key
            mark_local_variable_initialized();
          }
          // Now add two dummy local variables. Idx & entries
          add_local(synthetic_token('_for_idx_'));
          emit_op(OpCode.NIL);
          mark_local_variable_initialized();
          add_local(synthetic_token('_for_iterable_'));
          emit_op(OpCode.NIL);
          mark_local_variable_initialized();
          // Rest of the loop
          parser.consume(TokenType.IN, "Expect 'in' after loop variables");
          final condition = expression(); // Iterable
          // Iterator
          final loop_start = current_chunk.count;
          emit_bytes(OpCode.CONTAINER_ITERATE.index, stack_idx);
          final exit_jump = emit_jump(OpCode.JUMP_IF_FALSE);
          emit_op(OpCode.POP); // Condition
          // Body
          final body = statement();
          emit_loop(loop_start);
          // Exit
          patch_jump(exit_jump);
          emit_op(OpCode.POP); // Condition
          end_scope();
          return StmtLoop2(
            center: condition,
            body: body,
          );
        }
      } else if (match(TokenType.IF)) {
        // if statement
        final expr = expression();
        final then_jump = emit_jump(OpCode.JUMP_IF_FALSE);
        emit_op(OpCode.POP);
        final stmt = statement();
        final else_jump = emit_jump(OpCode.JUMP);
        patch_jump(then_jump);
        emit_op(OpCode.POP);
        if (match(TokenType.ELSE)) statement();
        patch_jump(else_jump);
        return StmtConditional(
          expr: expr,
          stmt: stmt,
        );
      } else if (match(TokenType.RETURN)) {
        if (match(TokenType.SEMICOLON)) {
          emit_return();
          return const StmtRet(
            expr: null,
          );
        } else {
          if (type == FunctionType.INITIALIZER) {
            parser.error("Can't return a value from an initializer");
          }
          final expr = expression();
          parser.consume(TokenType.SEMICOLON, 'Expect a newline after return value');
          emit_op(OpCode.RETURN);
          return StmtRet(
            expr: expr,
          );
        }
      } else if (match(TokenType.WHILE)) {
        final loop_start = current_chunk.count;
        final expr = expression();
        final exit_jump = emit_jump(OpCode.JUMP_IF_FALSE);
        emit_op(OpCode.POP);
        final stmt = statement();
        emit_loop(loop_start);
        patch_jump(exit_jump);
        emit_op(OpCode.POP);
        return StmtWhil(
          expr: expr,
          stmt: stmt,
        );
      } else if (match(TokenType.LEFT_BRACE)) {
        begin_scope();
        final block = parser.block(declaration);
        end_scope();
        return StmtBlock(
          block: block,
        );
      } else {
        final expr = expression();
        parser.consume(TokenType.SEMICOLON, 'Expect a newline after expression');
        emit_op(OpCode.POP);
        return StmtExpr(
          expr: expr,
        );
      }
    }

    Block function_block(
      final FunctionType type,
    ) {
      final compiler = CompilerWrapped(
        type: type,
        enclosing: this,
      );
      // beginScope(); // [no-end-scope]
      // not needed because of wrapped compiler scope propagation

      // Compile the parameter list.
      // final functionToken = parser.previous;
      compiler.parser.consume(TokenType.LEFT_PAREN, "Expect '(' after function name");
      final args = <NaturalToken?>[];
      if (!compiler.parser.check(TokenType.RIGHT_PAREN)) {
        do {
          compiler.function.arity++;
          if (compiler.function.arity > 255) {
            compiler.parser.error_at_current("Can't have more than 255 parameters");
          }
          compiler.parse_variable('Expect parameter name');
          compiler.mark_local_variable_initialized();
          args.add(compiler.parser.previous);
        } while (compiler.match(TokenType.COMMA));
      }
      for (var k = 0; k < args.length; k++) {
        compiler.define_variable(0, token: args[k], peek_dist: args.length - 1 - k);
      }
      compiler.parser.consume(TokenType.RIGHT_PAREN, "Expect ')' after parameters");
      // The body.
      compiler.parser.consume(TokenType.LEFT_BRACE, 'Expect function body');
      final block = compiler.parser.block(compiler.declaration);
      // Create the function object.
      final function = compiler.end_compiler();
      emit_bytes(OpCode.CLOSURE.index, make_constant(function));
      for (var i = 0; i < compiler.upvalues.length; i++) {
        emit_byte(compiler.upvalues[i].is_local ? 1 : 0);
        emit_byte(compiler.upvalues[i].index);
      }
      return block;
    }

    final Declaration decl = () {
      if (match(TokenType.CLASS)) {
        // class declaration
        parser.consume(TokenType.IDENTIFIER, 'Expect class name');
        final class_name = parser.previous;
        final name_constant = identifier_constant(parser.previous!);
        delare_local_variable();
        emit_bytes(OpCode.CLASS.index, name_constant);
        define_variable(name_constant);
        final class_compiler = ClassCompiler(current_class, parser.previous, false);
        current_class = class_compiler;
        if (match(TokenType.LESS)) {
          parser.consume(TokenType.IDENTIFIER, 'Expect superclass name');
          get_or_set_variable(parser.previous, false);
          if (identifiers_equal(class_name!, parser.previous!)) {
            parser.error("A class can't inherit from itself");
          }
          begin_scope();
          add_local(synthetic_token('super'));
          define_variable(0);
          get_or_set_variable(class_name, false);
          emit_op(OpCode.INHERIT);
          class_compiler.has_superclass = true;
        }
        get_or_set_variable(class_name, false);
        parser.consume(TokenType.LEFT_BRACE, 'Expect class body');
        while (!parser.check(TokenType.RIGHT_BRACE) && !parser.check(TokenType.EOF)) {
          // parse method
          parser.consume(TokenType.IDENTIFIER, 'Expect method name');
          final identifier = parser.previous!;
          final constant = identifier_constant(identifier);
          FunctionType type = FunctionType.METHOD;
          if (identifier.str == 'init') {
            type = FunctionType.INITIALIZER;
          }
          function_block(type);
          emit_bytes(OpCode.METHOD.index, constant);
        }
        parser.consume(TokenType.RIGHT_BRACE, 'Unterminated class body');
        emit_op(OpCode.POP);
        if (class_compiler.has_superclass) {
          end_scope();
        }
        current_class = current_class!.enclosing;
        return const DeclarationClazz();
      } else if (match(TokenType.FUN)) {
        // fun declaration
        final global = parse_variable('Expect function name');
        final token = parser.previous!;
        mark_local_variable_initialized();
        final block = function_block(FunctionType.FUNCTION);
        define_variable(global, token: token);
        return DeclarationFun(
          block: block,
          name: token,
        );
      } else if (match(TokenType.VAR)) {
        return var_declaration();
      } else {
        return DeclarationStmt(
          stmt: statement(),
        );
      }
    }();
    if (parser.panic_mode) {
      // synchronize
      parser.panic_mode = false;
      outer:
      while (parser.current!.type != TokenType.EOF) {
        if (parser.previous!.type == TokenType.SEMICOLON) {
          break outer;
        } else {
          switch (parser.current!.type) {
            case TokenType.CLASS:
            case TokenType.FUN:
            case TokenType.VAR:
            case TokenType.FOR:
            case TokenType.IF:
            case TokenType.WHILE:
            case TokenType.PRINT:
            case TokenType.RETURN:
              break outer;
            // ignore: no_default_cases
            default:
            // Do nothing.
          }
          parser.advance();
        }
      }
    }
    return decl;
  }
}

const UINT8_COUNT = 256;
const UINT8_MAX = UINT8_COUNT - 1;
const UINT16_MAX = 65535;

class Local {
  final SyntheticToken? name;
  int depth;
  bool is_captured = false;

  Local(
    final this.name, {
    final this.depth = -1,
    final this.is_captured = false,
  });

  bool get initialized {
    return depth >= 0;
  }
}

class Upvalue {
  final SyntheticToken? name;
  final int index;
  final bool is_local;

  const Upvalue(
    final this.name,
    final this.index,
    final this.is_local,
  );
}

enum FunctionType {
  FUNCTION,
  INITIALIZER,
  METHOD,
  SCRIPT,
}

class ClassCompiler {
  final ClassCompiler? enclosing;
  final NaturalToken? name;
  bool has_superclass;

  ClassCompiler(
    final this.enclosing,
    final this.name,
    final this.has_superclass,
  );
}

class CompilerResult {
  final ObjFunction function;
  final List<CompilerError> errors;
  final Debug? debug;

  const CompilerResult(
    final this.function,
    final this.errors,
    final this.debug,
  );
}
// endregion

// region parser
class Parser {
  final List<NaturalToken> tokens;
  final List<CompilerError> errors;
  final Debug debug;
  NaturalToken? current;
  NaturalToken? previous;
  NaturalToken? second_previous;
  int current_idx;
  bool panic_mode;

  Parser(
    this.tokens, {
    final bool silent = false,
  })  : debug = Debug(
          silent: silent,
        ),
        errors = [],
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

  void error(
    final String message,
  ) {
    error_at(previous, message);
  }

  void error_at_current(
    final String? message,
  ) {
    error_at(current, message);
  }

  void advance() {
    second_previous = previous; // TODO: is it needed?
    previous = current;
    while (current_idx < tokens.length) {
      current = tokens[current_idx++];
      // Skip invalid tokens
      if (current!.type == TokenType.ERROR) {
        error_at_current(current!.str);
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

  bool matchPair(
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

  // region values
  Block block(
    final Declaration Function() declaration,
  ) {
    final decls = <Declaration>[];
    while (!check(TokenType.RIGHT_BRACE) && !check(TokenType.EOF)) {
      decls.add(declaration());
    }
    consume(TokenType.RIGHT_BRACE, 'Unterminated block');
    return Block(
      decls: decls,
    );
  }
// endregion
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
// endregion

// region table
class Table {
  final Map<String?, Object?> data = <String?, Object?>{};

  Object? getVal(final String? key) {
    return data[key];
  }

  bool setVal(final String? key, final Object? val) {
    final hadKey = data.containsKey(key);
    data[key] = val;
    return !hadKey;
  }

  void delete(final String? key) {
    data.remove(key);
  }

  void addAll(final Table other) {
    data.addAll(other.data);
  }

  Object? findString(final String str) {
    // Optimisation: key on hashKeys
    return data[str];
  }
}
// endregion

// region native classes
abstract class ObjNativeClass {
  final String? name;
  final properties = <String?, Object?>{};
  final Map<String, Type>? propertiesTypes;
  final List<String> initArgKeys;

  ObjNativeClass({
    required this.initArgKeys,
    this.name,
    this.propertiesTypes,
    final List<Object?>? stack,
    final int? argIdx,
    final int? argCount,
  }) {
    if (argCount != initArgKeys.length) {
      argCountError(initArgKeys.length, argCount);
    }
    for (var k = 0; k < initArgKeys.length; k++) {
      final expected = propertiesTypes![initArgKeys[k]];
      if (expected != Object && stack![argIdx! + k].runtimeType != expected) {
        argTypeError(0, expected, stack[argIdx + k].runtimeType);
      }
      properties[initArgKeys[k]] = stack![argIdx! + k];
    }
  }

  Object call(final String? key, final List<Object?> stack, final int argIdx, final int argCount) {
    throw NativeError('Undefined function $key');
  }

  void setVal(final String? key, final Object? value) {
    if (!propertiesTypes!.containsKey(key)) {
      throw NativeError('Undefined property $key');
    }
    if (value.runtimeType != propertiesTypes![key!]) {
      throw NativeError('Invalid object type, expected <%s>, but received <%s>',
          [typeToString(propertiesTypes![key]), typeToString(value.runtimeType)]);
    }
    properties[key] = value;
  }

  Object getVal(final String? key) {
    if (!properties.containsKey(key)) {
      throw NativeError('Undefined property $key');
    }
    return properties[key] ?? Nil;
  }

  String stringRepr({final int maxChars = 100});
}

class ListNode extends ObjNativeClass {
  ListNode(final List<Object?> stack, final int argIdx, final int argCount)
      : super(
          name: 'ListNode',
          propertiesTypes: {'val': Object, 'next': ListNode},
          initArgKeys: ['val'],
          stack: stack,
          argIdx: argIdx,
          argCount: argCount,
        );

  Object? get val => properties['val'];

  ListNode? get next => properties['next'] as ListNode?;

  List<ListNode?> linkToList({final int maxLength = 100}) {
    // ignore: prefer_collection_literals
    final visited = LinkedHashSet<ListNode?>();
    ListNode? node = this;
    while (node != null && !visited.contains(node) && visited.length <= maxLength) {
      visited.add(node);
      node = node.next;
    }
    // Mark list as infinite
    if (node == this) visited.add(null);
    return visited.toList();
  }

  @override
  String stringRepr({final int maxChars = 100}) {
    final str = StringBuffer('[');
    final list = linkToList(maxLength: maxChars ~/ 2);
    for (var k = 0; k < list.length; k++) {
      final val = list[k]!.val;
      if (k > 0) str.write(' → '); // TODO: find utf-16 arrow →; test on iOS
      str.write(val == null ? '⮐' : value_to_string(val, maxChars: maxChars - str.length));
      if (str.length > maxChars) {
        str.write('...');
        break;
      }
    }
    str.write(']');
    return str.toString();
  }
}

typedef NativeClassCreator = ObjNativeClass Function(List<Object?> stack, int argIdx, int argCount);

ListNode listNode(final List<Object?> stack, final int argIdx, final int argCount) {
  return ListNode(stack, argIdx, argCount);
}

const Map<String, ObjNativeClass Function(List<Object>, int, int)> NATIVE_CLASSES =
    <String, NativeClassCreator>{
  'ListNode': listNode,
};
// endregion

// region native
class NativeError implements Exception {
  String format;
  List<Object?>? args;

  NativeError(this.format, [this.args]);
}

String typeToString(final Type? type) {
  if (type == double) return 'Number';
  return type.toString();
}

void argCountError(final int expected, final int? received) {
  throw NativeError('Expected %d arguments, but got %d', [expected, received]);
}

void argTypeError(final int index, final Type? expected, final Type? received) {
  throw NativeError('Invalid argument %d type, expected <%s>, but received <%s>',
      [index + 1, typeToString(expected), typeToString(received)]);
}

void assertTypes(final List<Object?> stack, final int argIdx, final int argCount, final List<Type> types) {
  if (argCount != types.length) argCountError(types.length, argCount);
  for (var k = 0; k < types.length; k++) {
    if (types[k] != Object && stack[argIdx + k].runtimeType != types[k]) {
      argTypeError(0, double, stack[argIdx + k] as Type?);
    }
  }
}

double assert1double(final List<Object?> stack, final int argIdx, final int argCount) {
  assertTypes(stack, argIdx, argCount, <Type>[double]);
  return (stack[argIdx] as double?)!;
}

void assert2doubles(final List<Object?> stack, final int argIdx, final int argCount) {
  assertTypes(stack, argIdx, argCount, <Type>[double, double]);
}

// Native functions
typedef NativeFunction = Object? Function(List<Object?> stack, int argIdx, int argCount);

double clockNative(final List<Object?> stack, final int argIdx, final int argCount) {
  if (argCount != 0) argCountError(0, argCount);
  return DateTime.now().millisecondsSinceEpoch.toDouble();
}

double minNative(final List<Object?> stack, final int argIdx, final int argCount) {
  assert2doubles(stack, argIdx, argCount);
  return min((stack[argIdx] as double?)!, (stack[argIdx + 1] as double?)!);
}

double maxNative(final List<Object?> stack, final int argIdx, final int argCount) {
  assert2doubles(stack, argIdx, argCount);
  return max((stack[argIdx] as double?)!, (stack[argIdx + 1] as double?)!);
}

double floorNative(final List<Object?> stack, final int argIdx, final int argCount) {
  final arg_0 = assert1double(stack, argIdx, argCount);
  return arg_0.floorToDouble();
}

double ceilNative(final List<Object?> stack, final int argIdx, final int argCount) {
  final arg_0 = assert1double(stack, argIdx, argCount);
  return arg_0.ceilToDouble();
}

double absNative(final List<Object?> stack, final int argIdx, final int argCount) {
  final arg_0 = assert1double(stack, argIdx, argCount);
  return arg_0.abs();
}

double roundNative(final List<Object?> stack, final int argIdx, final int argCount) {
  final arg_0 = assert1double(stack, argIdx, argCount);
  return arg_0.roundToDouble();
}

double sqrtNative(final List<Object?> stack, final int argIdx, final int argCount) {
  final arg_0 = assert1double(stack, argIdx, argCount);
  return sqrt(arg_0);
}

double signNative(final List<Object?> stack, final int argIdx, final int argCount) {
  final arg_0 = assert1double(stack, argIdx, argCount);
  return arg_0.sign;
}

double expNative(final List<Object?> stack, final int argIdx, final int argCount) {
  final arg_0 = assert1double(stack, argIdx, argCount);
  return exp(arg_0);
}

double logNative(final List<Object?> stack, final int argIdx, final int argCount) {
  final arg_0 = assert1double(stack, argIdx, argCount);
  return log(arg_0);
}

double sinNative(final List<Object?> stack, final int argIdx, final int argCount) {
  final arg_0 = assert1double(stack, argIdx, argCount);
  return sin(arg_0);
}

double asinNative(final List<Object?> stack, final int argIdx, final int argCount) {
  final arg_0 = assert1double(stack, argIdx, argCount);
  return asin(arg_0);
}

double cosNative(final List<Object?> stack, final int argIdx, final int argCount) {
  final arg_0 = assert1double(stack, argIdx, argCount);
  return cos(arg_0);
}

double acosNative(final List<Object?> stack, final int argIdx, final int argCount) {
  final arg_0 = assert1double(stack, argIdx, argCount);
  return acos(arg_0);
}

double tanNative(final List<Object?> stack, final int argIdx, final int argCount) {
  final arg_0 = assert1double(stack, argIdx, argCount);
  return tan(arg_0);
}

double atanNative(final List<Object?> stack, final int argIdx, final int argCount) {
  final arg_0 = assert1double(stack, argIdx, argCount);
  return atan(arg_0);
}

// ignore: non_constant_identifier_names
final NATIVE_FUNCTIONS = <ObjNative>[
  ObjNative('clock', 0, clockNative),
  ObjNative('min', 2, minNative),
  ObjNative('max', 2, maxNative),
  ObjNative('floor', 1, floorNative),
  ObjNative('ceil', 1, ceilNative),
  ObjNative('abs', 1, absNative),
  ObjNative('round', 1, roundNative),
  ObjNative('sqrt', 1, sqrtNative),
  ObjNative('sign', 1, signNative),
  ObjNative('exp', 1, expNative),
  ObjNative('log', 1, logNative),
  ObjNative('sin', 1, sinNative),
  ObjNative('asin', 1, asinNative),
  ObjNative('cos', 1, cosNative),
  ObjNative('acos', 1, acosNative),
  ObjNative('tan', 1, tanNative),
  ObjNative('atan', 1, atanNative),
];

const NATIVE_VALUES = <String, Object>{
  'π': pi,
  '𝘦': e,
  '∞': double.infinity,
};

// List native functions
double listLength(final List<dynamic> list, final List<Object?> stack, final int argIdx, final int argCount) {
  if (argCount != 0) argCountError(0, argCount);
  return list.length.toDouble();
}

void listAdd(final List<dynamic> list, final List<Object?> stack, final int argIdx, final int argCount) {
  if (argCount != 1) argCountError(1, argCount);
  final arg_0 = stack[argIdx];
  list.add(arg_0);
}

void listInsert(final List<dynamic> list, final List<Object?> stack, final int argIdx, final int argCount) {
  assertTypes(stack, argIdx, argCount, [double, Object]);
  final idx = (stack[argIdx] as double?)!.toInt();
  if (idx < 0 || idx > list.length) {
    throw NativeError('Index %d out of bounds [0, %d]', [idx, list.length]);
  }
  list.insert(idx, stack[argIdx + 1]);
}

Object? listRemove(
    final List<dynamic> list, final List<Object?> stack, final int argIdx, final int argCount) {
  assertTypes(stack, argIdx, argCount, [double]);
  final idx = (stack[argIdx] as double?)!.toInt();
  if (idx < 0 || idx > list.length) {
    throw NativeError('Index %d out of bounds [0, %d]', [idx, list.length]);
  }
  return list.removeAt(idx);
}

Object? listPop(final List<dynamic> list, final List<Object?> stack, final int argIdx, final int argCount) {
  if (argCount != 0) argCountError(0, argCount);
  return list.removeLast();
}

void listClear(final List<dynamic> list, final List<Object?> stack, final int argIdx, final int argCount) {
  if (argCount != 0) argCountError(0, argCount);
  list.clear();
}

typedef ListNativeFunction = Object? Function(
    List<dynamic> list, List<Object?> stack, int argIdx, int argCount);

const LIST_NATIVE_FUNCTIONS = <String, ListNativeFunction>{
  'length': listLength,
  'add': listAdd,
  'insert': listInsert,
  'remove': listRemove,
  'pop': listPop,
  'clear': listClear,
};

// Map native functions
double mapLength(
    final Map<dynamic, dynamic> map, final List<Object?> stack, final int argIdx, final int argCount) {
  if (argCount != 0) argCountError(0, argCount);
  return map.length.toDouble();
}

List<dynamic> mapKeys(
    final Map<dynamic, dynamic> map, final List<Object?> stack, final int argIdx, final int argCount) {
  if (argCount != 0) argCountError(0, argCount);
  return map.keys.toList();
}

List<dynamic> mapValues(
    final Map<dynamic, dynamic> map, final List<Object?> stack, final int argIdx, final int argCount) {
  if (argCount != 0) argCountError(0, argCount);
  return map.values.toList();
}

bool mapHas(
    final Map<dynamic, dynamic> map, final List<Object?> stack, final int argIdx, final int argCount) {
  if (argCount != 1) argCountError(1, argCount);
  final arg_0 = stack[argIdx];
  return map.containsKey(arg_0);
}

typedef MapNativeFunction = Object Function(
    Map<dynamic, dynamic> list, List<Object?> stack, int argIdx, int argCount);

const MAP_NATIVE_FUNCTIONS = <String, MapNativeFunction>{
  'length': mapLength,
  'keys': mapKeys,
  'values': mapValues,
  'has': mapHas,
};

// String native functions
double strLength(final String str, final List<Object?> stack, final int argIdx, final int argCount) {
  if (argCount != 0) argCountError(0, argCount);
  return str.length.toDouble();
}

typedef StringNativeFunction = Object Function(String list, List<Object?> stack, int argIdx, int argCount);

const STRING_NATIVE_FUNCTIONS = <String, StringNativeFunction>{
  'length': strLength,
};
// endregion

// region object
class ObjNative {
  String name;
  int arity;
  NativeFunction fn;

  ObjNative(this.name, this.arity, this.fn);
}

class ObjFunction {
  final Chunk chunk = Chunk();
  int arity = 0;
  int upvalueCount = 0;
  String? name;

  ObjFunction();
}

class ObjUpvalue {
  int? location;
  Object? closed = Nil;
  ObjUpvalue? next;

  ObjUpvalue(this.location);
}

class ObjClosure {
  ObjFunction function;
  late List<ObjUpvalue?> upvalues;
  late int upvalueCount;

  ObjClosure(this.function) {
    upvalues = List<ObjUpvalue?>.generate(function.upvalueCount, (final index) => null);
    upvalueCount = function.upvalueCount;
  }
}

class ObjClass {
  String? name;
  Table methods = Table();

  ObjClass(this.name);
}

class ObjInstance {
  String? klassName; // For dynamic class lookup
  ObjClass? klass;
  Table fields = Table();

  ObjInstance({this.klass, this.klassName});
}

class ObjBoundMethod {
  Object? receiver;
  ObjClosure method;

  ObjBoundMethod(this.receiver, this.method);
}

int hashString(
  final String key,
) {
  var hash = 2166136261;
  for (var i = 0; i < key.length; i++) {
    hash ^= key.codeUnitAt(i);
    hash *= 16777619;
  }
  return hash;
}

String functionToString(
  final ObjFunction function,
) {
  if (function.name == null) {
    return '<script>';
  }
  return '<fn ${function.name}>';
}

void printObject(final Object value) {
  print(objectToString(value));
}

String? objectToString(
  final Object? value, {
  final int maxChars = 100,
}) {
  if (value is ObjClass) {
    return value.name;
  } else if (value is ObjBoundMethod) {
    return functionToString(value.method.function);
  } else if (value is ObjClosure) {
    return functionToString(value.function);
  } else if (value is ObjFunction) {
    return functionToString(value);
  } else if (value is ObjInstance) {
    return '${value.klass!.name} instance';
    // return instanceToString(value, maxChars: maxChars);
  } else if (value is ObjNative) {
    return '<native fn>';
  } else if (value is ObjUpvalue) {
    return 'upvalue';
  } else if (value is ObjNativeClass) {
    return value.stringRepr(maxChars: maxChars);
  } else if (value is NativeClassCreator) {
    return '<native class>';
  }
  return value.toString();
}
// endregion

// region error
class LangError {
  final String type;
  final NaturalToken? token;
  int? line;
  final String? msg;

  LangError(
    final this.type,
    final this.msg, {
    final this.line,
    final this.token,
  });

  void dump(
    final Debug debug,
  ) {
    debug.stdwriteln(toString());
  }

  @override
  String toString() {
    final buf = StringBuffer();
    if (token != null) {
      buf.write('[${token!.loc.line + 1}] $type error');
      if (token!.type == TokenType.EOF) {
        buf.write(' at end');
      } else if (token!.type == TokenType.ERROR) {
        // Nothing.
      } else {
        buf.write(' at \'${token!.str}\'');
      }
    } else if (line != null) {
      buf.write('[$line] $type error');
    } else {
      buf.write('$type error');
    }
    buf.write(': $msg');
    return buf.toString();
  }
}

class CompilerError extends LangError {
  CompilerError(
    final NaturalToken token,
    final String? msg,
  ) : super(
          'Compile',
          msg,
          token: token,
          line: token.loc.line,
        );
}

class RuntimeError extends LangError {
  final RuntimeError? link;

  RuntimeError(
    final int line,
    final String? msg, {
    this.link,
  }) : super(
          'Runtime',
          msg,
          line: line,
        );
}
// endregion

// region debug
class Debug {
  final bool silent;
  final StringBuffer buf;

  Debug({
    required final this.silent,
  }) : buf = StringBuffer();

  String clear() {
    final str = buf.toString();
    buf.clear();
    return str;
  }

  void stdwrite(
    final String? string,
  ) {
    buf.write(string);
    if (!silent) {
      // Print buffer
      final str = clear();
      final split = str.split('\n');
      while (split.length > 1) {
        print(split[0]);
        split.removeAt(0);
      }
      buf.write(split.join(''));
    }
  }

  void stdwriteln([
    final String? string,
  ]) {
    return stdwrite((string ?? '') + '\n');
  }

  void print_value(
    final Object? value,
  ) {
    stdwrite(value_to_string(value));
  }

  void disassemble_chunk(
    final Chunk chunk,
    final String name,
  ) {
    stdwrite("==" + name + "==\n");
    int? prevLine = -1;
    for (var offset = 0; offset < chunk.code.length;) {
      offset = disassemble_instruction(prevLine, chunk, offset);
      prevLine = offset > 0 ? chunk.lines[offset - 1] : null;
    }
  }

  int constant_instruction(
    final String name,
    final Chunk chunk,
    final int offset,
  ) {
    final constant = chunk.code[offset + 1];
    stdwrite(sprintf('%-16s %4d \'', [name, constant]));
    print_value(chunk.constants[constant]);
    stdwrite('\'\n');
    return offset + 2;
  }

  int initializer_list_instruction(
    final String name,
    final Chunk chunk,
    final int offset,
  ) {
    final nArgs = chunk.code[offset + 1];
    stdwriteln(sprintf('%-16s %4d', [name, nArgs]));
    return offset + 2;
  }

  int invoke_instruction(
    final String name,
    final Chunk chunk,
    final int offset,
  ) {
    final constant = chunk.code[offset + 1];
    final argCount = chunk.code[offset + 2];
    stdwrite(sprintf('%-16s (%d args) %4d \'', [name, argCount, constant]));
    print_value(chunk.constants[constant]);
    stdwrite('\'\n');
    return offset + 3;
  }

  int simple_instruction(
    final String name,
    final int offset,
  ) {
    stdwrite(sprintf('%s\n', [name]));
    return offset + 1;
  }

  int byte_instruction(
    final String name,
    final Chunk chunk,
    final int offset,
  ) {
    final slot = chunk.code[offset + 1];
    stdwrite(sprintf('%-16s %4d\n', [name, slot]));
    return offset + 2; // [debug]
  }

  int jump_instruction(
    final String name,
    final int sign,
    final Chunk chunk,
    final int offset,
  ) {
    var jump = chunk.code[offset + 1] << 8;
    jump |= chunk.code[offset + 2];
    stdwrite(sprintf('%-16s %4d -> %d\n', [name, offset, offset + 3 + sign * jump]));
    return offset + 3;
  }

  int disassemble_instruction(
    final int? prevLine,
    final Chunk chunk,
    int offset,
  ) {
    stdwrite(sprintf('%04d ', [offset]));
    final i = chunk.lines[offset];
    // stdwrite("${chunk.trace[offset].token.info} "); // temp
    // final prevLoc = offset > 0 ? chunk.trace[offset - 1].token.loc : null;
    if (offset > 0 && i == prevLine) {
      stdwrite('   | ');
    } else {
      stdwrite(sprintf('%4d ', [i]));
    }
    final instruction = chunk.code[offset];
    switch (OpCode.values[instruction]) {
      case OpCode.CONSTANT:
        return constant_instruction('OP_CONSTANT', chunk, offset);
      case OpCode.NIL:
        return simple_instruction('OP_NIL', offset);
      case OpCode.TRUE:
        return simple_instruction('OP_TRUE', offset);
      case OpCode.FALSE:
        return simple_instruction('OP_FALSE', offset);
      case OpCode.POP:
        return simple_instruction('OP_POP', offset);
      case OpCode.GET_LOCAL:
        return byte_instruction('OP_GET_LOCAL', chunk, offset);
      case OpCode.SET_LOCAL:
        return byte_instruction('OP_SET_LOCAL', chunk, offset);
      case OpCode.GET_GLOBAL:
        return constant_instruction('OP_GET_GLOBAL', chunk, offset);
      case OpCode.DEFINE_GLOBAL:
        return constant_instruction('OP_DEFINE_GLOBAL', chunk, offset);
      case OpCode.SET_GLOBAL:
        return constant_instruction('OP_SET_GLOBAL', chunk, offset);
      case OpCode.GET_UPVALUE:
        return byte_instruction('OP_GET_UPVALUE', chunk, offset);
      case OpCode.SET_UPVALUE:
        return byte_instruction('OP_SET_UPVALUE', chunk, offset);
      case OpCode.GET_PROPERTY:
        return constant_instruction('OP_GET_PROPERTY', chunk, offset);
      case OpCode.SET_PROPERTY:
        return constant_instruction('OP_SET_PROPERTY', chunk, offset);
      case OpCode.GET_SUPER:
        return constant_instruction('OP_GET_SUPER', chunk, offset);
      case OpCode.EQUAL:
        return simple_instruction('OP_EQUAL', offset);
      case OpCode.GREATER:
        return simple_instruction('OP_GREATER', offset);
      case OpCode.LESS:
        return simple_instruction('OP_LESS', offset);
      case OpCode.ADD:
        return simple_instruction('OP_ADD', offset);
      case OpCode.SUBTRACT:
        return simple_instruction('OP_SUBTRACT', offset);
      case OpCode.MULTIPLY:
        return simple_instruction('OP_MULTIPLY', offset);
      case OpCode.DIVIDE:
        return simple_instruction('OP_DIVIDE', offset);
      case OpCode.POW:
        return simple_instruction('OP_POW', offset);
      case OpCode.NOT:
        return simple_instruction('OP_NOT', offset);
      case OpCode.NEGATE:
        return simple_instruction('OP_NEGATE', offset);
      case OpCode.PRINT:
        return simple_instruction('OP_PRINT', offset);
      case OpCode.JUMP:
        return jump_instruction('OP_JUMP', 1, chunk, offset);
      case OpCode.JUMP_IF_FALSE:
        return jump_instruction('OP_JUMP_IF_FALSE', 1, chunk, offset);
      case OpCode.LOOP:
        return jump_instruction('OP_LOOP', -1, chunk, offset);
      case OpCode.CALL:
        return byte_instruction('OP_CALL', chunk, offset);
      case OpCode.INVOKE:
        return invoke_instruction('OP_INVOKE', chunk, offset);
      case OpCode.SUPER_INVOKE:
        return invoke_instruction('OP_SUPER_INVOKE', chunk, offset);
      case OpCode.CLOSURE:
        // ignore: parameter_assignments
        offset++;
        // ignore: parameter_assignments
        final constant = chunk.code[offset++];
        stdwrite(sprintf('%-16s %4d ', ['OP_CLOSURE', constant]));
        print_value(chunk.constants[constant]);
        stdwrite('\n');
        final function = (chunk.constants[constant] as ObjFunction?)!;
        for (var j = 0; j < function.upvalueCount; j++) {
          // ignore: parameter_assignments
          final isLocal = chunk.code[offset++] == 1;
          // ignore: parameter_assignments
          final index = chunk.code[offset++];
          stdwrite(sprintf(
              '%04d      |                     %s %d\n', [offset - 2, isLocal ? 'local' : 'upvalue', index]));
        }
        return offset;
      case OpCode.CLOSE_UPVALUE:
        return simple_instruction('OP_CLOSE_UPVALUE', offset);
      case OpCode.RETURN:
        return simple_instruction('OP_RETURN', offset);
      case OpCode.CLASS:
        return constant_instruction('OP_CLASS', chunk, offset);
      case OpCode.INHERIT:
        return simple_instruction('OP_INHERIT', offset);
      case OpCode.METHOD:
        return constant_instruction('OP_METHOD', chunk, offset);
      case OpCode.LIST_INIT:
        return initializer_list_instruction('OP_LIST_INIT', chunk, offset);
      case OpCode.LIST_INIT_RANGE:
        return simple_instruction('LIST_INIT_RANGE', offset);
      case OpCode.MAP_INIT:
        return initializer_list_instruction('OP_MAP_INIT', chunk, offset);
      case OpCode.CONTAINER_GET:
        return simple_instruction('OP_CONTAINER_GET', offset);
      case OpCode.CONTAINER_SET:
        return simple_instruction('OP_CONTAINER_SET', offset);
      case OpCode.CONTAINER_GET_RANGE:
        return simple_instruction('CONTAINER_GET_RANGE', offset);
      case OpCode.CONTAINER_ITERATE:
        return simple_instruction('CONTAINER_ITERATE', offset);
      case OpCode.MOD:
        throw Exception('Unknown opcode $instruction');
    }
  }
}
// endregion

// region chunk
enum OpCode {
  CONSTANT,
  NIL,
  TRUE,
  FALSE,
  POP,
  GET_LOCAL,
  SET_LOCAL,
  GET_GLOBAL,
  DEFINE_GLOBAL,
  SET_GLOBAL,
  GET_UPVALUE,
  SET_UPVALUE,
  GET_PROPERTY,
  SET_PROPERTY,
  GET_SUPER,
  EQUAL,
  GREATER,
  LESS,
  ADD,
  SUBTRACT,
  MULTIPLY,
  DIVIDE,
  POW,
  MOD,
  NOT,
  NEGATE,
  PRINT,
  JUMP,
  JUMP_IF_FALSE,
  LOOP,
  CALL,
  INVOKE,
  SUPER_INVOKE,
  CLOSURE,
  CLOSE_UPVALUE,
  RETURN,
  CLASS,
  INHERIT,
  METHOD,
  LIST_INIT,
  LIST_INIT_RANGE,
  MAP_INIT,
  CONTAINER_GET,
  CONTAINER_SET,
  CONTAINER_GET_RANGE,
  CONTAINER_ITERATE,
}

class Chunk {
  final List<int> code = [];
  final List<Object?> constants = [];
  final _constant_map = <Object?, int>{};

  // Trace information
  final List<int> lines = [];

  Chunk();

  int get count => code.length;

  void write(
    final int byte,
    final NaturalToken token,
  ) {
    code.add(byte);
    lines.add(token.loc.line);
  }

  int add_constant(
    final Object? value,
  ) {
    final idx = _constant_map[value];
    if (idx != null) {
      return idx;
    } else {
      // Add entry
      constants.add(value);
      _constant_map[value] = constants.length - 1;
      return constants.length - 1;
    }
  }
}
// endregion

// region value
class Nil {}

Object value_clone_deep(
  final Object value,
) {
  if (value is Map) {
    return Map.fromEntries(value.entries.map((final e) => value_clone_deep(e) as MapEntry<Object, Object>));
  } else if (value is List<Object>) {
    return value.map((final e) => value_clone_deep(e)).toList();
  } else {
    // TODO: clone object instances
    return value;
  }
}

String list_to_string(
  final List<dynamic> list, {
  final int maxChars = 100,
}) {
  final buf = StringBuffer('[');
  for (var k = 0; k < list.length; k++) {
    if (k > 0) buf.write(',');
    buf.write(value_to_string(list[k], maxChars: maxChars - buf.length));
    if (buf.length > maxChars) {
      buf.write('...');
      break;
    }
  }
  buf.write(']');
  return buf.toString();
}

String map_to_string(
  final Map<dynamic, dynamic> map, {
  final int maxChars = 100,
}) {
  final buf = StringBuffer('{');
  final entries = map.entries.toList();
  for (var k = 0; k < entries.length; k++) {
    if (k > 0) buf.write(',');
    buf.write(value_to_string(entries[k].key, maxChars: maxChars - buf.length));
    buf.write(':');
    buf.write(value_to_string(
      entries[k].value,
      maxChars: maxChars - buf.length,
    ));
    if (buf.length > maxChars) {
      buf.write('...');
      break;
    }
  }
  buf.write('}');
  return buf.toString();
}

String? value_to_string(
  final Object? value, {
  final int maxChars = 100,
  final bool quoteEmpty = true,
}) {
  if (value is bool) {
    return value ? 'true' : 'false';
  } else if (value == Nil) {
    return 'nil';
  } else if (value is double) {
    if (value.isInfinite) {
      return '∞';
    } else if (value.isNaN) {
      return 'NaN';
    }
    return sprintf('%g', [value]);
  } else if (value is String) {
    return value.trim().isEmpty && quoteEmpty ? '\'$value\'' : value;
  } else if (value is List) {
    return list_to_string(value, maxChars: maxChars);
  } else if (value is Map) {
    return map_to_string(value, maxChars: maxChars);
  } else {
    return objectToString(value, maxChars: maxChars);
  }
}

// Copied from foundation.dart
bool list_equals<T>(
  final List<T>? a,
  final List<T>? b,
) {
  if (a == null) return b == null;
  if (b == null || a.length != b.length) return false;
  if (identical(a, b)) return true;
  for (var index = 0; index < a.length; index += 1) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

bool map_equals<T, U>(
  final Map<T, U>? a,
  final Map<T, U>? b,
) {
  if (a == null) return b == null;
  if (b == null || a.length != b.length) return false;
  if (identical(a, b)) return true;
  for (final key in a.keys) {
    if (!b.containsKey(key) || b[key] != a[key]) return false;
  }
  return true;
}

bool values_equal(
  final Object? a,
  final Object? b,
) {
  // TODO: confirm behavior (especially for deep equality)
  // Equality relied on this function, but not hashmap indexing
  // It might trigger strange cases where two equal lists don't have the same hashcode
  if (a is List<dynamic> && b is List<dynamic>) {
    return list_equals<dynamic>(a, b);
  } else if (a is Map<dynamic, dynamic> && b is Map<dynamic, dynamic>) {
    return map_equals<dynamic, dynamic>(a, b);
  } else {
    return a == b;
  }
}
// endregion

// region vm
class VM {
  static const INIT_STRING = 'init';
  final List<CallFrame?> frames = List<CallFrame?>.filled(FRAMES_MAX, null);
  final List<Object?> stack = List<Object?>.filled(STACK_MAX, null);

  // VM state
  final List<RuntimeError> errors = [];
  final Table globals = Table();
  final Table strings = Table();
  CompilerResult? compiler_result;
  int frame_count = 0;
  int stack_top = 0;
  ObjUpvalue? open_upvalues;

  // Debug variables
  int step_count = 0;
  int line = -1;

  // int skipLine = -1;
  bool has_op = false;

  // Debug API
  bool traceExecution = false;
  bool step_code = false;
  late Debug err_debug;
  late Debug trace_debug;
  late Debug stdout;

  VM({
    required final bool silent,
  }) {
    err_debug = Debug(
      silent: silent,
    );
    trace_debug = Debug(
      silent: silent,
    );
    stdout = Debug(
      silent: silent,
    );
    _reset();
    for (var k = 0; k < frames.length; k++) {
      frames[k] = CallFrame();
    }
  }

  RuntimeError addError(
      final String? msg, {
        final RuntimeError? link,
        final int? line,
      }) {
    // int line = -1;
    // if (frameCount > 0) {
    //   final frame = frames[frameCount - 1];
    //   final lines = frame.chunk.lines;
    //   if (frame.ip < lines.length) line = lines[frame.ip];
    // }
    final err = RuntimeError(line ?? this.line, msg, link: link);
    errors.add(err);
    err.dump(err_debug);
    return err;
  }

  InterpreterResult getResult(
      final int line, {
        final Object? returnValue,
      }) {
    return InterpreterResult(
      errors,
      line,
      step_count,
      returnValue,
    );
  }

  InterpreterResult get result {
    return getResult(line);
  }

  InterpreterResult withError(
      final String msg,
      ) {
    addError(msg);
    return result;
  }

  void _reset() {
    // Reset data
    errors.clear();
    globals.data.clear();
    strings.data.clear();
    stack_top = 0;
    frame_count = 0;
    open_upvalues = null;
    // Reset debug values
    step_count = 0;
    line = -1;
    has_op = false;
    stdout.clear();
    err_debug.clear();
    trace_debug.clear();
    // Reset flags
    step_code = false;
    // Define natives
    define_natives();
  }

  void set_function(
      final CompilerResult compiler_result,
      final FunctionParams params,
      ) {
    _reset();
    // Set compiler result
    if (compiler_result.errors.isNotEmpty) {
      throw Exception('Compiler result had errors');
    } else {
      this.compiler_result = compiler_result;
      // Set function
      ObjFunction? fun = compiler_result.function;
      if (params.function != null) {
        final found_fun = () {
          for (final x in compiler_result.function.chunk.constants) {
            if (x is ObjFunction && x.name == params.function) {
              return x;
            }
          }
          return null;
        }();
        if (found_fun == null) {
          throw Exception('Function not found ${params.function}');
        } else {
          fun = found_fun;
        }
      }
      // Set globals.
      if (params.globals != null) {
        globals.data.addAll(params.globals!);
      }
      // Init VM.
      final closure = ObjClosure(fun);
      push(closure);
      if (params.args != null) {
        params.args!.forEach(push);
      }
      callValue(closure, params.args?.length ?? 0);
    }
  }

  void define_natives() {
    for (final function in NATIVE_FUNCTIONS) {
      globals.setVal(function.name, function);
    }
    NATIVE_VALUES.forEach((final key, final value) {
      globals.setVal(key, value);
    });
    NATIVE_CLASSES.forEach((final key, final value) {
      globals.setVal(key, value);
    });
  }

  void push(
      final Object? value,
      ) {
    stack[stack_top++] = value;
  }

  Object? pop() {
    return stack[--stack_top];
  }

  Object? peek(
      final int distance,
      ) {
    return stack[stack_top - distance - 1];
  }

  bool call(
      final ObjClosure closure,
      final int argCount,
      ) {
    if (argCount != closure.function.arity) {
      runtime_error('Expected %d arguments but got %d', [closure.function.arity, argCount]);
      return false;
    } else {
      if (frame_count == FRAMES_MAX) {
        runtime_error('Stack overflow');
        return false;
      } else {
        final frame = frames[frame_count++]!;
        frame.closure = closure;
        frame.chunk = closure.function.chunk;
        frame.ip = 0;
        frame.slots_idx = stack_top - argCount - 1;
        return true;
      }
    }
  }

  bool callValue(
      final Object? callee,
      final int argCount,
      ) {
    if (callee is ObjBoundMethod) {
      stack[stack_top - argCount - 1] = callee.receiver;
      return call(callee.method, argCount);
    } else if (callee is ObjClass) {
      stack[stack_top - argCount - 1] = ObjInstance(klass: callee);
      final initializer = callee.methods.getVal(INIT_STRING);
      if (initializer != null) {
        return call(initializer as ObjClosure, argCount);
      } else if (argCount != 0) {
        runtime_error('Expected 0 arguments but got %d', [argCount]);
        return false;
      }
      return true;
    } else if (callee is ObjClosure) {
      return call(callee, argCount);
    } else if (callee is ObjNative) {
      final res = callee.fn(stack, stack_top - argCount, argCount);
      stack_top -= argCount + 1;
      push(res);
      return true;
    } else if (callee is NativeClassCreator) {
      try {
        final res = callee(stack, stack_top - argCount, argCount);
        stack_top -= argCount + 1;
        push(res);
      } on NativeError catch (e) {
        runtime_error(e.format, e.args);
        return false;
      }
      return true;
    } else {
      runtime_error('Can only call functions and classes');
      return false;
    }
  }

  bool invoke_from_class(
      final ObjClass klass,
      final String? name,
      final int argCount,
      ) {
    final method = klass.methods.getVal(name);
    if (method == null) {
      runtime_error("Undefined property '%s'", [name]);
      return false;
    } else {
      return call(method as ObjClosure, argCount);
    }
  }

  bool invokeMap(
      final Map<dynamic, dynamic> map,
      final String? name,
      final int argCount,
      ) {
    if (!MAP_NATIVE_FUNCTIONS.containsKey(name)) {
      runtime_error('Unknown method for map');
      return false;
    } else {
      final function = MAP_NATIVE_FUNCTIONS[name!]!;
      try {
        final rtn = function(map, stack, stack_top - argCount, argCount);
        stack_top -= argCount + 1;
        push(rtn);
        return true;
      } on NativeError catch (e) {
        runtime_error(e.format, e.args);
        return false;
      }
    }
  }

  bool invoke_list(
      final List<dynamic> list,
      final String? name,
      final int argCount,
      ) {
    if (!LIST_NATIVE_FUNCTIONS.containsKey(name)) {
      runtime_error('Unknown method for list');
      return false;
    } else {
      final function = LIST_NATIVE_FUNCTIONS[name!]!;
      try {
        final rtn = function(list, stack, stack_top - argCount, argCount);
        stack_top -= argCount + 1;
        push(rtn);
        return true;
      } on NativeError catch (e) {
        runtime_error(e.format, e.args);
        return false;
      }
    }
  }

  bool invoke_string(
      final String str,
      final String? name,
      final int argCount,
      ) {
    if (!STRING_NATIVE_FUNCTIONS.containsKey(name)) {
      runtime_error('Unknown method for string');
      return false;
    } else {
      final function = STRING_NATIVE_FUNCTIONS[name!]!;
      try {
        final rtn = function(str, stack, stack_top - argCount, argCount);
        stack_top -= argCount + 1;
        push(rtn);
        return true;
      } on NativeError catch (e) {
        runtime_error(e.format, e.args);
        return false;
      }
    }
  }

  bool invoke_native_class(
      final ObjNativeClass klass,
      final String? name,
      final int arg_count,
      ) {
    try {
      final rtn = klass.call(name, stack, stack_top - arg_count, arg_count);
      stack_top -= arg_count + 1;
      push(rtn);
      return true;
    } on NativeError catch (e) {
      runtime_error(e.format, e.args);
      return false;
    }
  }

  bool invoke(
      final String? name,
      final int arg_count,
      ) {
    final receiver = peek(arg_count);
    if (receiver is List) {
      return invoke_list(receiver, name, arg_count);
    } else if (receiver is Map) {
      return invokeMap(receiver, name, arg_count);
    } else if (receiver is String) {
      return invoke_string(receiver, name, arg_count);
    } else if (receiver is ObjNativeClass) {
      return invoke_native_class(receiver, name, arg_count);
    } else if (!(receiver is ObjInstance)) {
      runtime_error('Only instances have methods');
      return false;
    } else {
      final instance = receiver;
      final value = instance.fields.getVal(name);
      if (value != null) {
        stack[stack_top - arg_count - 1] = value;
        return callValue(value, arg_count);
      } else {
        if (instance.klass == null) {
          final klass = globals.getVal(instance.klassName);
          if (klass is! ObjClass) {
            runtime_error('Class ${instance.klassName} not found');
            return false;
          }
          instance.klass = klass;
        }
        return invoke_from_class(instance.klass!, name, arg_count);
      }
    }
  }

  bool bind_method(
      final ObjClass klass,
      final String? name,
      ) {
    final method = klass.methods.getVal(name);
    if (method == null) {
      runtime_error("Undefined property '%s'", [name]);
      return false;
    } else {
      final bound = ObjBoundMethod(
        peek(0),
        method as ObjClosure,
      );
      pop();
      push(bound);
      return true;
    }
  }

  ObjUpvalue capture_upvalue(
      final int localIdx,
      ) {
    ObjUpvalue? prev_upvalue;
    ObjUpvalue? upvalue = open_upvalues;
    while (upvalue != null && upvalue.location! > localIdx) {
      prev_upvalue = upvalue;
      upvalue = upvalue.next;
    }
    if (upvalue != null && upvalue.location == localIdx) {
      return upvalue;
    } else {
      final created_upvalue = ObjUpvalue(localIdx);
      created_upvalue.next = upvalue;
      if (prev_upvalue == null) {
        open_upvalues = created_upvalue;
      } else {
        prev_upvalue.next = created_upvalue;
      }
      return created_upvalue;
    }
  }

  void close_upvalues(
      final int? lastIdx,
      ) {
    while (open_upvalues != null && open_upvalues!.location! >= lastIdx!) {
      final upvalue = open_upvalues!;
      upvalue.closed = stack[upvalue.location!];
      upvalue.location = null;
      open_upvalues = upvalue.next;
    }
  }

  void define_method(
      final String? name,
      ) {
    final method = peek(0);
    final klass = (peek(1) as ObjClass?)!;
    klass.methods.setVal(name, method);
    pop();
  }

  bool is_falsey(
      final Object? value,
      ) {
    return value == Nil || (value is bool && !value);
  }

  // Repace macros (slower -> try inlining)
  int read_byte(
      final CallFrame frame,
      ) {
    return frame.chunk.code[frame.ip++];
  }

  int read_short(
      final CallFrame frame,
      ) {
    // TODO: Optimisation - remove
    frame.ip += 2;
    return frame.chunk.code[frame.ip - 2] << 8 | frame.chunk.code[frame.ip - 1];
  }

  Object? read_constant(
      final CallFrame frame,
      ) {
    return frame.closure.function.chunk.constants[read_byte(frame)];
  }

  String? read_string(
      final CallFrame frame,
      ) {
    return read_constant(frame) as String?;
  }

  bool assert_number(
      final dynamic a,
      final dynamic b,
      ) {
    if (!(a is double) || !(b is double)) {
      runtime_error('Operands must be numbers');
      return false;
    } else {
      return true;
    }
  }

  int? check_index(
      final int length,
      Object? idxObj, {
        final bool fromStart = true,
      }) {
    // ignore: parameter_assignments
    if (idxObj == Nil) idxObj = fromStart ? 0.0 : length.toDouble();
    if (!(idxObj is double)) {
      runtime_error('Index must be a number');
      return null;
    } else {
      var idx = idxObj.toInt();
      if (idx < 0) idx = length + idx;
      final max = fromStart ? length - 1 : length;
      if (idx < 0 || idx > max) {
        runtime_error('Index $idx out of bounds [0, $max]');
        return null;
      } else {
        return idx;
      }
    }
  }

  bool get done {
    return frame_count == 0;
  }

  InterpreterResult run() {
    InterpreterResult? res;
    do {
      res = step_batch();
    } while (res == null);
    return res;
  }

  InterpreterResult? step_batch({
    final int batch_count = BATCH_COUNT,
  }) {
    // Setup
    if (frame_count == 0) {
      return withError('No call frame');
    } else {
      CallFrame? frame = frames[frame_count - 1];
      final stepCountLimit = step_count + batch_count;
      // Main loop
      while (step_count++ < stepCountLimit) {
        // Setup current line
        final frameLine = frame!.chunk.lines[frame.ip];
        // Step code helper
        if (step_code) {
          final instruction = frame.chunk.code[frame.ip];
          final op = OpCode.values[instruction];
          // Pause execution on demand
          if (frameLine != line && has_op) {
            // Newline detected, return
            // No need to set line to frameLine thanks to hasOp
            has_op = false;
            return getResult(line);
          }
          // A line is worth stopping on if it has one of those opts
          has_op |= op != OpCode.POP && op != OpCode.LOOP && op != OpCode.JUMP;
        }
        // Update line
        final prevLine = line;
        line = frameLine;
        // Trace execution if needed
        if (traceExecution) {
          trace_debug.stdwrite('          ');
          for (var k = 0; k < stack_top; k++) {
            trace_debug.stdwrite('[ ');
            trace_debug.print_value(stack[k]);
            trace_debug.stdwrite(' ]');
          }
          trace_debug.stdwrite('\n');
          trace_debug.disassemble_instruction(prevLine, frame.closure.function.chunk, frame.ip);
        }
        final instruction = read_byte(frame);
        switch (OpCode.values[instruction]) {
          case OpCode.CONSTANT:
            final constant = read_constant(frame);
            push(constant);
            break;
          case OpCode.NIL:
            push(Nil);
            break;
          case OpCode.TRUE:
            push(true);
            break;
          case OpCode.FALSE:
            push(false);
            break;
          case OpCode.POP:
            pop();
            break;
          case OpCode.GET_LOCAL:
            final slot = read_byte(frame);
            push(stack[frame.slots_idx + slot]);
            break;
          case OpCode.SET_LOCAL:
            final slot = read_byte(frame);
            stack[frame.slots_idx + slot] = peek(0);
            break;
          case OpCode.GET_GLOBAL:
            final name = read_string(frame);
            final value = globals.getVal(name);
            if (value == null) {
              return runtime_error("Undefined variable '%s'", [name]);
            }
            push(value);
            break;
          case OpCode.DEFINE_GLOBAL:
            final name = read_string(frame);
            globals.setVal(name, peek(0));
            pop();
            break;
          case OpCode.SET_GLOBAL:
            final name = read_string(frame);
            if (globals.setVal(name, peek(0))) {
              globals.delete(name); // [delete]
              return runtime_error("Undefined variable '%s'", [name]);
            } else {
              break;
            }
          case OpCode.GET_UPVALUE:
            final slot = read_byte(frame);
            final upvalue = frame.closure.upvalues[slot]!;
            push(upvalue.location != null ? stack[upvalue.location!] : upvalue.closed);
            break;
          case OpCode.SET_UPVALUE:
            final slot = read_byte(frame);
            final upvalue = frame.closure.upvalues[slot]!;
            if (upvalue.location != null) {
              stack[upvalue.location!] = peek(0);
            } else {
              upvalue.closed = peek(0);
            }
            break;
          case OpCode.GET_PROPERTY:
            Object? value;
            if (peek(0) is ObjInstance) {
              final ObjInstance instance = (peek(0) as ObjInstance?)!;
              final name = read_string(frame);
              value = instance.fields.getVal(name);
              if (value == null && !bind_method(instance.klass!, name)) {
                return result;
              }
            } else if (peek(0) is ObjNativeClass) {
              final ObjNativeClass instance = (peek(0) as ObjNativeClass?)!;
              final name = read_string(frame);
              try {
                value = instance.getVal(name);
              } on NativeError catch (e) {
                return runtime_error(e.format, e.args);
              }
            } else {
              return runtime_error('Only instances have properties');
            }
            if (value != null) {
              pop(); // Instance.
              push(value);
            }
            break;
          case OpCode.SET_PROPERTY:
            if (peek(1) is ObjInstance) {
              final ObjInstance instance = (peek(1) as ObjInstance?)!;
              instance.fields.setVal(read_string(frame), peek(0));
            } else if (peek(1) is ObjNativeClass) {
              final ObjNativeClass instance = (peek(1) as ObjNativeClass?)!;
              instance.setVal(read_string(frame), peek(0));
            } else {
              return runtime_error('Only instances have fields');
            }
            final value = pop();
            pop();
            push(value);
            break;
          case OpCode.GET_SUPER:
            final name = read_string(frame);
            final ObjClass superclass = (pop() as ObjClass?)!;
            if (!bind_method(superclass, name)) {
              return result;
            }
            break;
          case OpCode.EQUAL:
            final b = pop();
            final a = pop();
            push(values_equal(a, b));
            break;
        // Optimisation create greater_or_equal
          case OpCode.GREATER:
            final b = pop();
            final a = pop();
            if (a is String && b is String) {
              push(a.compareTo(b));
            } else if (a is double && b is double) {
              push(a > b);
            } else {
              return runtime_error('Operands must be numbers or strings');
            }
            break;
        // Optimisation create less_or_equal
          case OpCode.LESS:
            final b = pop();
            final a = pop();
            if (a is String && b is String) {
              push(b.compareTo(a));
            } else if (a is double && b is double) {
              push(a < b);
            } else {
              return runtime_error('Operands must be numbers or strings');
            }
            break;
          case OpCode.ADD:
            final b = pop();
            final a = pop();
            if ((a is double) && (b is double)) {
              push(a + b);
            } else if ((a is String) && (b is String)) {
              push(a + b);
            } else if ((a is List) && (b is List)) {
              push(a + b);
            } else if ((a is Map) && (b is Map)) {
              final res = <dynamic, dynamic>{};
              res.addAll(a);
              res.addAll(b);
              push(res);
            } else if ((a is String) || (b is String)) {
              push(value_to_string(a, quoteEmpty: false)! + value_to_string(b, quoteEmpty: false)!);
            } else {
              return runtime_error('Operands must numbers, strings, lists or maps');
            }
            break;
          case OpCode.SUBTRACT:
            final b = pop();
            final a = pop();
            if (!assert_number(a, b)) return result;
            push((a as double?)! - (b as double?)!);
            break;
          case OpCode.MULTIPLY:
            final b = pop();
            final a = pop();
            if (!assert_number(a, b)) return result;
            push((a as double?)! * (b as double?)!);
            break;
          case OpCode.DIVIDE:
            final b = pop();
            final a = pop();
            if (!assert_number(a, b)) return result;
            push((a as double?)! / (b as double?)!);
            break;
          case OpCode.POW:
            final b = pop();
            final a = pop();
            if (!assert_number(a, b)) return result;
            push(pow((a as double?)!, (b as double?)!));
            break;
          case OpCode.MOD:
            final b = pop();
            final a = pop();
            if (!assert_number(a, b)) return result;
            push((a as double?)! % (b as double?)!);
            break;
          case OpCode.NOT:
            push(is_falsey(pop()));
            break;
          case OpCode.NEGATE:
            if (!(peek(0) is double)) {
              return runtime_error('Operand must be a number');
            } else {
              push(-(pop() as double?)!);
              break;
            }
          case OpCode.PRINT:
            final val = value_to_string(pop());
            stdout.stdwriteln(val);
            break;
          case OpCode.JUMP:
            final offset = read_short(frame);
            frame.ip += offset;
            break;
          case OpCode.JUMP_IF_FALSE:
            final offset = read_short(frame);
            if (is_falsey(peek(0))) frame.ip += offset;
            break;
          case OpCode.LOOP:
            final offset = read_short(frame);
            frame.ip -= offset;
            break;
          case OpCode.CALL:
            final argCount = read_byte(frame);
            if (!callValue(peek(argCount), argCount)) {
              return result;
            } else {
              frame = frames[frame_count - 1];
              break;
            }
          case OpCode.INVOKE:
            final method = read_string(frame);
            final arg_count = read_byte(frame);
            if (!invoke(method, arg_count)) {
              return result;
            } else {
              frame = frames[frame_count - 1];
              break;
            }
          case OpCode.SUPER_INVOKE:
            final method = read_string(frame);
            final arg_count = read_byte(frame);
            final superclass = (pop() as ObjClass?)!;
            if (!invoke_from_class(superclass, method, arg_count)) {
              return result;
            } else {
              frame = frames[frame_count - 1];
              break;
            }
          case OpCode.CLOSURE:
            final function = (read_constant(frame) as ObjFunction?)!;
            final closure = ObjClosure(function);
            push(closure);
            for (int i = 0; i < closure.upvalueCount; i++) {
              final isLocal = read_byte(frame);
              final index = read_byte(frame);
              if (isLocal == 1) {
                closure.upvalues[i] = capture_upvalue(frame.slots_idx + index);
              } else {
                closure.upvalues[i] = frame.closure.upvalues[index];
              }
            }
            break;
          case OpCode.CLOSE_UPVALUE:
            close_upvalues(stack_top - 1);
            pop();
            break;
          case OpCode.RETURN:
            final res = pop();
            close_upvalues(frame.slots_idx);
            frame_count--;
            // ignore: invariant_booleans
            if (frame_count == 0) {
              pop();
              return getResult(line, returnValue: res);
            } else {
              stack_top = frame.slots_idx;
              push(res);
              frame = frames[frame_count - 1];
              break;
            }
          case OpCode.CLASS:
            push(ObjClass(read_string(frame)));
            break;
          case OpCode.INHERIT:
            final sup = peek(1);
            if (!(sup is ObjClass)) {
              return runtime_error('Superclass must be a class');
            } else {
              final ObjClass superclass = sup;
              final ObjClass subclass = (peek(0) as ObjClass?)!;
              subclass.methods.addAll(superclass.methods);
              pop(); // Subclass.
              break;
            }
          case OpCode.METHOD:
            define_method(read_string(frame));
            break;
          case OpCode.LIST_INIT:
            final valCount = read_byte(frame);
            final arr = <dynamic>[];
            for (var k = 0; k < valCount; k++) {
              arr.add(peek(valCount - k - 1));
            }
            stack_top -= valCount;
            push(arr);
            break;
          case OpCode.LIST_INIT_RANGE:
            if (!(peek(0) is double) || !(peek(1) is double)) {
              return runtime_error('List initializer bounds must be number');
            } else {
              final start = (peek(1) as double?)!;
              final end = (peek(0) as double?)!;
              if (end - start == double.infinity) {
                return runtime_error('Invalid list initializer');
              } else {
                final arr = <dynamic>[];
                for (var k = start; k < end; k++) {
                  arr.add(k);
                }
                stack_top -= 2;
                push(arr);
                break;
              }
            }
          case OpCode.MAP_INIT:
            final valCount = read_byte(frame);
            final map = <dynamic, dynamic>{};
            for (var k = 0; k < valCount; k++) {
              map[peek((valCount - k - 1) * 2 + 1)] = peek((valCount - k - 1) * 2);
            }
            stack_top -= 2 * valCount;
            push(map);
            break;
          case OpCode.CONTAINER_GET:
            final idxObj = pop();
            final container = pop();
            if (container is List) {
              final idx = check_index(container.length, idxObj);
              if (idx == null) return result;
              push(container[idx]);
            } else if (container is Map) {
              push(container[idxObj]);
            } else if (container is String) {
              final idx = check_index(container.length, idxObj);
              if (idx == null) return result;
              push(container[idx]);
            } else {
              return runtime_error(
                'Indexing targets must be Strings, Lists or Maps',
              );
            }
            break;
          case OpCode.CONTAINER_SET:
            final val = pop();
            final idx_obj = pop();
            final container = pop();
            if (container is List) {
              final idx = check_index(container.length, idx_obj);
              if (idx == null) return result;
              container[idx] = val;
            } else if (container is Map) {
              container[idx_obj] = val;
            } else {
              return runtime_error('Indexing targets must be Lists or Maps');
            }
            push(val);
            break;
          case OpCode.CONTAINER_GET_RANGE:
            var bIdx = pop();
            var aIdx = pop();
            final container = pop();
            var length = 0;
            if (container is List) {
              length = container.length;
            } else if (container is String) {
              length = container.length;
            } else {
              return runtime_error('Range indexing targets must be Lists or Strings');
            }
            aIdx = check_index(length, aIdx);
            bIdx = check_index(length, bIdx, fromStart: false);
            if (aIdx == null || bIdx == null) return result;
            if (container is List) {
              push(container.sublist(aIdx as int, bIdx as int?));
            } else if (container is String) {
              push(container.substring(aIdx as int, bIdx as int?));
            }
            break;
          case OpCode.CONTAINER_ITERATE:
          // Init stack indexes
            final valIdx = read_byte(frame);
            final keyIdx = valIdx + 1;
            final idxIdx = valIdx + 2;
            final iterableIdx = valIdx + 3;
            final containerIdx = valIdx + 4;
            // Retreive data
            var idxObj = stack[frame.slots_idx + idxIdx];
            // Initialize
            if (idxObj == Nil) {
              final container = stack[frame.slots_idx + containerIdx];
              idxObj = 0.0;
              if (container is String) {
                stack[frame.slots_idx + iterableIdx] = container.split('');
              } else if (container is List) {
                stack[frame.slots_idx + iterableIdx] = container;
              } else if (container is Map) {
                stack[frame.slots_idx + iterableIdx] = container.entries.toList();
              } else {
                return runtime_error('Iterable must be Strings, Lists or Maps');
              }
              // Pop container from stack
              pop();
            }
            // Iterate
            final idx = (idxObj as double?)!;
            final iterable = (stack[frame.slots_idx + iterableIdx] as List?)!;
            if (idx >= iterable.length) {
              // Return early
              push(false);
              break;
            } else {
              // Populate key & value
              final dynamic item = iterable[idx.toInt()];
              if (item is MapEntry) {
                stack[frame.slots_idx + keyIdx] = item.key;
                stack[frame.slots_idx + valIdx] = item.value;
              } else {
                stack[frame.slots_idx + keyIdx] = idx;
                stack[frame.slots_idx + valIdx] = item;
              }
              // Increment index
              stack[frame.slots_idx + idxIdx] = idx + 1;
              push(true);
              break;
            }
        }
      }
      return null;
    }
  }

  InterpreterResult runtime_error(
      final String format, [
        final List<Object?>? args,
      ]) {
    RuntimeError error = addError(sprintf(format, args ?? []));
    for (int i = frame_count - 2; i >= 0; i--) {
      final frame = frames[i]!;
      final function = frame.closure.function;
      // frame.ip is sitting on the next instruction
      final line = function.chunk.lines[frame.ip - 1];
      final fun = function.name == null ? '<script>' : '<${function.name}>';
      final msg = 'during $fun execution';
      error = addError(msg, line: line, link: error);
    }
    return result;
  }
}

const int FRAMES_MAX = 64;
const int STACK_MAX = FRAMES_MAX * UINT8_COUNT;
const int BATCH_COUNT = 1000000; // Must be fast enough

class CallFrame {
  late ObjClosure closure;
  late int ip;
  late Chunk chunk; // Additionnal reference
  late int slots_idx; // Index in stack of the frame slot

  CallFrame();
}

class InterpreterResult {
  final List<LangError> errors;
  final int last_line;
  final int step_count;
  final Object? return_value;

  InterpreterResult(
    final List<LangError> errors,
    this.last_line,
    this.step_count,
    this.return_value,
  ) : errors = List<LangError>.from(errors);

  bool get done {
    return errors.isNotEmpty || return_value != null;
  }
}

class FunctionParams {
  final String? function;
  final List<Object>? args;
  final Map<String?, Object?>? globals;

  const FunctionParams({
    final this.function,
    final this.args,
    final this.globals,
  });
}
// endregion
