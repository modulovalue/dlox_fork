import 'dart:collection';
import 'dart:math';

import 'package:sprintf/sprintf.dart';

import 'ast.dart';
import 'model.dart';
import 'parser.dart';

// region compiler
CompilationResult run_compiler({
  required final List<NaturalToken> tokens,
  required final Debug debug,
  required final bool trace_bytecode,
}) {
  final parser = make_parser(
    tokens: tokens,
    debug: debug,
  );
  final compiler = CompilerRootImpl(
    type: FunctionType.SCRIPT,
    parser: parser.key,
    error_delegate: parser.value,
    debug_trace_bytecode: trace_bytecode,
  );
  parser.key.advance();
  final _parser = ParserAtCompiler(
    parser: parser.key,
    error_delegate: parser.value,
    compiler: compiler,
  );
  while (!parser.key.match(TokenType.EOF)) {
    _parser.declaration();
  }
  final function = compiler.end_compiler();
  return CompilationResult(
    function: function,
    errors: parser.value.errors,
  );
}

class CompilationResult {
  final ObjFunction function;
  final List<CompilerError> errors;

  const CompilationResult({
    required final this.function,
    required final this.errors,
  });
}

class CompilerRootImpl with CompilerMixin {
  @override
  final ErrorDelegate error_delegate;
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

  CompilerRootImpl({
    required final this.type,
    required final this.parser,
    required final this.error_delegate,
    required final this.debug_trace_bytecode,
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

  @override
  Null get enclosing => null;
}

class CompilerWrappedImpl with CompilerMixin {
  @override
  final List<Local> locals;
  @override
  final List<Upvalue> upvalues;
  @override
  final FunctionType type;
  @override
  final Compiler enclosing;
  @override
  final Parser parser;
  @override
  int scope_depth;
  @override
  bool debug_trace_bytecode;
  @override
  ClassCompiler? current_class;
  @override
  ObjFunction function;

  CompilerWrappedImpl({
    required final this.type,
    required final this.enclosing,
    required final this.parser,
  })  : function = (() {
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

  @override
  ErrorDelegate get error_delegate => enclosing.error_delegate;
}

mixin CompilerMixin implements Compiler {
  static bool identifiers_equal2(
    final SyntheticToken a,
    final SyntheticToken b,
  ) {
    return a.str == b.str;
  }

  Parser get parser;

  @override
  ErrorDelegate get error_delegate;

  @override
  ObjFunction end_compiler() {
    emit_return();
    if (error_delegate.errors.isEmpty && debug_trace_bytecode) {
      error_delegate.debug.disassemble_chunk(current_chunk, function.name ?? '<script>');
    }
    return function;
  }

  @override
  Chunk get current_chunk {
    return function.chunk;
  }

  @override
  void emit_op(
    final OpCode op,
  ) {
    emit_byte(op.index);
  }

  @override
  void emit_byte(
    final int byte,
  ) {
    current_chunk.write(byte, parser.previous!.loc.line);
  }

  @override
  void emit_bytes(
    final int byte1,
    final int byte2,
  ) {
    emit_byte(byte1);
    emit_byte(byte2);
  }

  @override
  void emit_loop(
    final int loopStart,
  ) {
    emit_op(OpCode.LOOP);
    final offset = current_chunk.count - loopStart + 2;
    if (offset > UINT16_MAX) {
      error_delegate.error_at_previous('Loop body too large');
    }
    emit_byte((offset >> 8) & 0xff);
    emit_byte(offset & 0xff);
  }

  @override
  int emit_jump(
    final OpCode instruction,
  ) {
    emit_op(instruction);
    emit_byte(0xff);
    emit_byte(0xff);
    return current_chunk.count - 2;
  }

  @override
  void emit_return() {
    if (type == FunctionType.INITIALIZER) {
      emit_bytes(OpCode.GET_LOCAL.index, 0);
    } else {
      emit_op(OpCode.NIL);
    }
    emit_op(OpCode.RETURN);
  }

  @override
  int make_constant(
    final Object? value,
  ) {
    final constant = current_chunk.add_constant(value);
    if (constant > UINT8_MAX) {
      error_delegate.error_at_previous('Too many constants in one chunk');
      return 0;
    } else {
      return constant;
    }
  }

  @override
  void emit_constant(
    final Object? value,
  ) {
    emit_bytes(OpCode.CONSTANT.index, make_constant(value));
  }

  @override
  void patch_jump(
    final int offset,
  ) {
    // -2 to adjust for the bytecode for the jump offset itself.
    final jump = current_chunk.count - offset - 2;
    if (jump > UINT16_MAX) {
      error_delegate.error_at_previous('Too much code to jump over');
    }
    current_chunk.code[offset] = (jump >> 8) & 0xff;
    current_chunk.code[offset + 1] = jump & 0xff;
  }

  @override
  void add_local(
    final SyntheticToken? name,
  ) {
    if (locals.length >= UINT8_COUNT) {
      error_delegate.error_at_previous('Too many local variables in function');
    } else {
      locals.add(Local(name));
    }
  }

  @override
  int identifier_constant(
    final SyntheticToken name,
  ) {
    return make_constant(name.str);
  }

  @override
  int? resolve_local(
    final SyntheticToken? name,
  ) {
    for (int i = locals.length - 1; i >= 0; i--) {
      final local = locals[i];
      if (CompilerMixin.identifiers_equal2(name!, local.name!)) {
        if (!local.initialized) {
          error_delegate.error_at_previous('Can\'t read local variable in its own initializer');
        }
        return i;
      } else {
        continue;
      }
    }
    return null;
  }

  int add_upvalue(
    final SyntheticToken? name,
    final int index,
    final bool is_local,
  ) {
    assert(upvalues.length == function.upvalue_count, "");
    for (var i = 0; i < upvalues.length; i++) {
      final upvalue = upvalues[i];
      if (upvalue.index == index && upvalue.is_local == is_local) {
        return i;
      }
    }
    if (upvalues.length == UINT8_COUNT) {
      error_delegate.error_at_previous('Too many closure variables in function');
      return 0;
    } else {
      upvalues.add(Upvalue(name, index, is_local));
      return function.upvalue_count++;
    }
  }

  @override
  int? resolve_upvalue(
    final SyntheticToken name,
  ) {
    if (enclosing == null) {
      return null;
    } else {
      final local_idx = enclosing!.resolve_local(name);
      if (local_idx != null) {
        final local = enclosing!.locals[local_idx];
        local.is_captured = true;
        return add_upvalue(local.name, local_idx, true);
      } else {
        final upvalue_idx = enclosing!.resolve_upvalue(name);
        if (upvalue_idx != null) {
          final upvalue = enclosing!.upvalues[upvalue_idx];
          return add_upvalue(upvalue.name, upvalue_idx, false);
        } else {
          return null;
        }
      }
    }
  }

  @override
  void mark_local_variable_initialized() {
    if (scope_depth != 0) {
      locals.last.depth = scope_depth;
    }
  }

  @override
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

  @override
  void declare_local_variable() {
    // Global variables are implicitly declared.
    if (scope_depth != 0) {
      final name = parser.previous;
      for (int i = locals.length - 1; i >= 0; i--) {
        final local = locals[i];
        if (local.depth != -1 && local.depth < scope_depth) {
          break; // [negative]
        }
        if (CompilerMixin.identifiers_equal2(name!, local.name!)) {
          error_delegate.error_at_previous('Already variable with this name in this scope');
        }
      }
      add_local(name);
    }
  }

  @override
  T get_or_set<T>(
    final SyntheticToken name,
    final T Function(
      int,
      OpCode get_op,
      OpCode set_op,
    ) fn,
  ) {
    int? arg = resolve_local(name);
    OpCode get_op;
    OpCode set_op;
    if (arg == null) {
      final resolved_arg = resolve_upvalue(name);
      if (resolved_arg == null) {
        arg = identifier_constant(name);
        get_op = OpCode.GET_GLOBAL;
        set_op = OpCode.SET_GLOBAL;
      } else {
        arg = resolved_arg;
        get_op = OpCode.GET_UPVALUE;
        set_op = OpCode.SET_UPVALUE;
      }
    } else {
      get_op = OpCode.GET_LOCAL;
      set_op = OpCode.SET_LOCAL;
    }
    return fn(arg, get_op, set_op);
  }
}

abstract class Compiler {
  abstract int scope_depth;
  abstract ClassCompiler? current_class;

  ObjFunction get function;

  List<Local> get locals;

  List<Upvalue> get upvalues;

  ErrorDelegate get error_delegate;

  FunctionType get type;

  Compiler? get enclosing;

  bool get debug_trace_bytecode;

  ObjFunction end_compiler();

  Chunk get current_chunk;

  void emit_op(
    final OpCode op,
  );

  void emit_byte(
    final int byte,
  );

  void emit_bytes(
    final int byte1,
    final int byte2,
  );

  void emit_loop(
    final int loopStart,
  );

  int emit_jump(
    final OpCode instruction,
  );

  void emit_return();

  int make_constant(
    final Object? value,
  );

  void emit_constant(
    final Object? value,
  );

  void patch_jump(
    final int offset,
  );

  void add_local(
    final SyntheticToken? name,
  );

  int identifier_constant(
    final SyntheticToken name,
  );

  int? resolve_local(
    final SyntheticToken name,
  );

  int? resolve_upvalue(
    final SyntheticToken name,
  );

  void mark_local_variable_initialized();

  void define_variable(
    final int global, {
    final NaturalToken? token,
    final int peek_dist = 0,
  });

  void declare_local_variable();

  T get_or_set<T>(
    final SyntheticToken name,
    final T Function(
      int,
      OpCode get_op,
      OpCode set_op,
    ) fn,
  );
}

const UINT8_COUNT = 256;
const UINT8_MAX = UINT8_COUNT - 1;
const UINT16_MAX = 65535;

class Local {
  final SyntheticToken? name;
  int depth;
  bool is_captured;

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
// endregion

// region parser
// TODO * finish parsing into an ast
// TODO * interpret ast
class ParserAtCompiler {
  final Parser parser;
  final ErrorDelegate error_delegate;
  final Compiler compiler;

  const ParserAtCompiler({
    required final this.parser,
    required final this.error_delegate,
    required final this.compiler,
  });

  Declaration declaration() {
    Expr expression() {
      Expr expression() {
        void get_or_set_can_assign(
          final SyntheticToken name,
        ) {
          compiler.get_or_set<void>(
            name,
                (final arg, final get_op, final set_op) {
              if (parser.match(TokenType.EQUAL)) {
                // ignore: unused_local_variable
                final expr = expression();
                // region emitter
                compiler.emit_bytes(set_op.index, arg);
                // endregion
              } else {
                // region emitter
                compiler.emit_bytes(get_op.index, arg);
                // endregion
                if (parser.match_pair(TokenType.PLUS, TokenType.EQUAL)) {
                  // ignore: unused_local_variable
                  final expr = expression();
                  // region emitter
                  compiler.emit_op(OpCode.ADD);
                  compiler.emit_bytes(set_op.index, arg);
                  // endregion
                } else if (parser.match_pair(TokenType.MINUS, TokenType.EQUAL)) {
                  // ignore: unused_local_variable
                  final expr = expression();
                  // region emitter
                  compiler.emit_op(OpCode.SUBTRACT);
                  compiler.emit_bytes(set_op.index, arg);
                  // endregion
                } else if (parser.match_pair(TokenType.STAR, TokenType.EQUAL)) {
                  // ignore: unused_local_variable
                  final expr = expression();
                  // region emitter
                  compiler.emit_op(OpCode.MULTIPLY);
                  compiler.emit_bytes(set_op.index, arg);
                  // endregion
                } else if (parser.match_pair(TokenType.SLASH, TokenType.EQUAL)) {
                  // ignore: unused_local_variable
                  final expr = expression();
                  // region emitter
                  compiler.emit_op(OpCode.DIVIDE);
                  compiler.emit_bytes(set_op.index, arg);
                  // endregion
                } else if (parser.match_pair(TokenType.PERCENT, TokenType.EQUAL)) {
                  // ignore: unused_local_variable
                  final expr = expression();
                  // region emitter
                  compiler.emit_op(OpCode.MOD);
                  compiler.emit_bytes(set_op.index, arg);
                  // endregion
                } else if (parser.match_pair(TokenType.CARET, TokenType.EQUAL)) {
                  // ignore: unused_local_variable
                  final expr = expression();
                  // region emitter
                  compiler.emit_op(OpCode.POW);
                  compiler.emit_bytes(set_op.index, arg);
                  // endregion
                } else {
                  // Ignore.
                }
              }
            },
          );
        }

        List<Expr> argument_list() {
          final args = <Expr>[];
          if (!parser.check(TokenType.RIGHT_PAREN)) {
            do {
              args.add(expression());
              if (args.length == 256) {
                error_delegate.error_at_previous("Can't have more than 255 arguments");
              }
            } while (parser.match(TokenType.COMMA));
          }
          parser.consume(TokenType.RIGHT_PAREN, "Expect ')' after arguments");
          return args;
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
                    } while (parser.match(TokenType.COMMA));
                  }
                  parser.consume(TokenType.RIGHT_BRACE, "Expect '}' after map initializer");
                  // region emitter
                  compiler.emit_bytes(OpCode.MAP_INIT.index, val_count);
                  // endregion
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
                      while (parser.match(TokenType.COMMA)) {
                        values.add(expression());
                        val_count++;
                      }
                    }
                  }
                  parser.consume(TokenType.RIGHT_BRACK, "Expect ']' after list initializer");
                  // region emitter
                  if (val_count >= 0) {
                    compiler.emit_bytes(OpCode.LIST_INIT.index, val_count);
                  } else {
                    compiler.emit_byte(OpCode.LIST_INIT_RANGE.index);
                  }
                  // endregion
                  return ExprList(
                    values: values,
                  );
                };
              case TokenType.MINUS:
                return () {
                  final expr = parse_precedence(Precedence.UNARY);
                  // region emitter
                  compiler.emit_op(OpCode.NEGATE);
                  // endregion
                  return expr;
                };
              case TokenType.BANG:
                return () {
                  final expr = parse_precedence(Precedence.UNARY);
                  // region emitter
                  compiler.emit_op(OpCode.NOT);
                  // endregion
                  return expr;
                };
              case TokenType.IDENTIFIER:
                return () {
                  if (can_assign) {
                    get_or_set_can_assign(parser.previous!);
                  } else {
                    // region emitter
                    compiler.get_or_set<void>(
                      parser.previous!,
                          (final arg, final get_op, final set_op) {
                        compiler.emit_bytes(get_op.index, arg);
                      },
                    );
                    // endregion
                  }
                };
              case TokenType.STRING:
                return () {
                  // region emitter
                  compiler.emit_constant(parser.previous!.str);
                  // endregion
                };
              case TokenType.NUMBER:
                return () {
                  final value = double.tryParse(parser.previous!.str!);
                  if (value == null) {
                    error_delegate.error_at_previous('Invalid number');
                  } else {
                    // region emitter
                    compiler.emit_constant(value);
                    // endregion
                  }
                };
              case TokenType.OBJECT:
                return () {
                  // region emitter
                  compiler.emit_constant(null);
                  // endregion
                };
              case TokenType.FALSE:
                return () {
                  // region emitter
                  compiler.emit_op(OpCode.FALSE);
                  // endregion
                };
              case TokenType.NIL:
                return () {
                  // region emitter
                  compiler.emit_op(OpCode.NIL);
                  // endregion
                };
              case TokenType.SUPER:
                return () {
                  if (compiler.current_class == null) {
                    error_delegate.error_at_previous("Can't use 'super' outside of a class");
                  } else if (!compiler.current_class!.has_superclass) {
                    error_delegate.error_at_previous("Can't use 'super' in a class with no superclass");
                  }
                  parser.consume(TokenType.DOT, "Expect '.' after 'super'");
                  parser.consume(TokenType.IDENTIFIER, 'Expect superclass method name');
                  // region emitter
                  final name = compiler.identifier_constant(parser.previous!);
                  compiler.get_or_set<void>(
                    const SyntheticTokenImpl(
                      type: TokenType.IDENTIFIER,
                      str: 'this',
                    ),
                        (final arg, final get_op, final set_op) {
                      compiler.emit_bytes(get_op.index, arg);
                    },
                  );
                  // endregion
                  if (parser.match(TokenType.LEFT_PAREN)) {
                    final arg_count = argument_list();
                    // region emitter
                    compiler.get_or_set<void>(
                      const SyntheticTokenImpl(
                        type: TokenType.IDENTIFIER,
                        str: 'super',
                      ),
                          (final arg, final get_op, final set_op) {
                        compiler.emit_bytes(get_op.index, arg);
                      },
                    );
                    compiler.emit_bytes(OpCode.SUPER_INVOKE.index, name);
                    compiler.emit_byte(arg_count.length);
                    // endregion
                  } else {
                    // region emitter
                    compiler.get_or_set<void>(
                      const SyntheticTokenImpl(
                        type: TokenType.IDENTIFIER,
                        str: 'super',
                      ),
                          (final arg, final get_op, final set_op) {
                        compiler.emit_bytes(get_op.index, arg);
                      },
                    );
                    compiler.emit_bytes(OpCode.GET_SUPER.index, name);
                    // endregion
                  }
                };
              case TokenType.THIS:
                return () {
                  if (compiler.current_class == null) {
                    error_delegate.error_at_previous("Can't use 'this' outside of a class");
                  } else {
                    // region emitter
                    compiler.get_or_set<void>(
                      parser.previous!,
                          (final arg, final get_op, final set_op) {
                        compiler.emit_bytes(get_op.index, arg);
                      },
                    );
                    // endregion
                  }
                };
              case TokenType.TRUE:
                return () {
                  // region emitter
                  compiler.emit_op(OpCode.TRUE);
                  // endregion
                };
            // ignore: no_default_cases
              default:
                return null;
            }
          }();
          if (prefix_rule == null) {
            error_delegate.error_at_previous('Expect expression');
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
                    // region emitter
                    compiler.emit_bytes(OpCode.CALL.index, args.length);
                    // endregion
                    return ExprCall(
                      args: args,
                    );
                  case TokenType.LEFT_BRACK:
                    bool get_range = parser.match(TokenType.COLON);
                    // Left hand side operand
                    if (get_range) {
                      // region emitter
                      compiler.emit_constant(Nil);
                      // endregion
                    } else {
                      expression();
                      get_range = parser.match(TokenType.COLON);
                    }
                    // Right hand side operand
                    if (parser.match(TokenType.RIGHT_BRACK)) {
                      // region emitter
                      if (get_range) {
                        compiler.emit_constant(Nil);
                      }
                      // endregion
                    } else {
                      if (get_range) {
                        expression();
                      }
                      parser.consume(TokenType.RIGHT_BRACK, "Expect ']' after list indexing");
                    }
                    // Emit operation
                    if (get_range) {
                      // region emitter
                      compiler.emit_op(OpCode.CONTAINER_GET_RANGE);
                      // endregion
                    } else if (can_assign && parser.match(TokenType.EQUAL)) {
                      expression();
                      // region emitter
                      compiler.emit_op(OpCode.CONTAINER_SET);
                      // endregion
                    } else {
                      // region emitter
                      compiler.emit_op(OpCode.CONTAINER_GET);
                      // endregion
                    }
                    break;
                  case TokenType.DOT:
                    parser.consume(TokenType.IDENTIFIER, "Expect property name after '.'");
                    final name_token = parser.previous!;
                    if (can_assign && parser.match(TokenType.EQUAL)) {
                      final expr = expression();
                      // region emitter
                      final name = compiler.identifier_constant(name_token);
                      compiler.emit_bytes(OpCode.SET_PROPERTY.index, name);
                      // endregion
                      return ExprSet(arg: expr, name: name_token);
                    } else if (parser.match(TokenType.LEFT_PAREN)) {
                      final args = argument_list();
                      // region emitter
                      final name = compiler.identifier_constant(name_token);
                      compiler.emit_bytes(OpCode.INVOKE.index, name);
                      compiler.emit_byte(args.length);
                      // endregion
                      return ExprInvoke(args: args, name: name_token);
                    } else {
                      // region emitter
                      final name = compiler.identifier_constant(name_token);
                      compiler.emit_bytes(OpCode.GET_PROPERTY.index, name);
                      // endregion
                      return ExprGet(name: name_token);
                    }
                  case TokenType.MINUS:
                    parse_precedence(get_next_precedence(TokenType.MINUS));
                    // region emitter
                    compiler.emit_op(OpCode.SUBTRACT);
                    // endregion
                    break;
                  case TokenType.PLUS:
                    parse_precedence(get_next_precedence(TokenType.PLUS));
                    // region emitter
                    compiler.emit_op(OpCode.ADD);
                    // endregion
                    break;
                  case TokenType.SLASH:
                    parse_precedence(get_next_precedence(TokenType.SLASH));
                    // region emitter
                    compiler.emit_op(OpCode.DIVIDE);
                    // endregion
                    break;
                  case TokenType.STAR:
                    parse_precedence(get_next_precedence(TokenType.STAR));
                    // region emitter
                    compiler.emit_op(OpCode.MULTIPLY);
                    // endregion
                    break;
                  case TokenType.CARET:
                    parse_precedence(get_next_precedence(TokenType.CARET));
                    // region emitter
                    compiler.emit_op(OpCode.POW);
                    // endregion
                    break;
                  case TokenType.PERCENT:
                    parse_precedence(get_next_precedence(TokenType.PERCENT));
                    // region emitter
                    compiler.emit_op(OpCode.MOD);
                    // endregion
                    break;
                  case TokenType.BANG_EQUAL:
                    parse_precedence(get_next_precedence(TokenType.BANG_EQUAL));
                    // region emitter
                    compiler.emit_bytes(OpCode.EQUAL.index, OpCode.NOT.index);
                    // endregion
                    break;
                  case TokenType.EQUAL_EQUAL:
                    parse_precedence(get_next_precedence(TokenType.EQUAL_EQUAL));
                    // region emitter
                    compiler.emit_op(OpCode.EQUAL);
                    // endregion
                    break;
                  case TokenType.GREATER:
                    parse_precedence(get_next_precedence(TokenType.GREATER));
                    // region emitter
                    compiler.emit_op(OpCode.GREATER);
                    // endregion
                    break;
                  case TokenType.GREATER_EQUAL:
                    parse_precedence(get_next_precedence(TokenType.GREATER_EQUAL));
                    // region emitter
                    compiler.emit_bytes(OpCode.LESS.index, OpCode.NOT.index);
                    // endregion
                    break;
                  case TokenType.LESS:
                    parse_precedence(get_next_precedence(TokenType.LESS));
                    // region emitter
                    compiler.emit_op(OpCode.LESS);
                    // endregion
                    break;
                  case TokenType.LESS_EQUAL:
                    parse_precedence(get_next_precedence(TokenType.LESS_EQUAL));
                    // region emitter
                    compiler.emit_bytes(OpCode.GREATER.index, OpCode.NOT.index);
                    // endregion
                    break;
                  case TokenType.AND:
                  // region emitter
                    final end_jump = compiler.emit_jump(OpCode.JUMP_IF_FALSE);
                    compiler.emit_op(OpCode.POP);
                    // endregion
                    parse_precedence(get_precedence(TokenType.AND));
                    // region emitter
                    compiler.patch_jump(end_jump);
                    // endregion
                    break;
                  case TokenType.OR:
                  // region emitter
                    final else_jump = compiler.emit_jump(OpCode.JUMP_IF_FALSE);
                    final end_jump = compiler.emit_jump(OpCode.JUMP);
                    compiler.patch_jump(else_jump);
                    compiler.emit_op(OpCode.POP);
                    // endregion
                    parse_precedence(get_precedence(TokenType.OR));
                    // region emitter
                    compiler.patch_jump(end_jump);
                    // endregion
                    break;
                // ignore: no_default_cases
                  default:
                    throw Exception("Invalid State");
                }
              }();
            }
            if (can_assign) {
              if (parser.match(TokenType.EQUAL)) {
                error_delegate.error_at_previous('Invalid assignment target');
              }
            }
          }
        }

        return parse_precedence(Precedence.ASSIGNMENT) ?? Expr();
      }

      return expression();
    }

    T wrap_in_scope<T>({
      required final T Function() fn,
    }) {
      compiler.scope_depth++;
      final val = fn();
      compiler.scope_depth--;
      while (compiler.locals.isNotEmpty && compiler.locals.last.depth > compiler.scope_depth) {
        if (compiler.locals.last.is_captured) {
          compiler.emit_op(OpCode.CLOSE_UPVALUE);
        } else {
          compiler.emit_op(OpCode.POP);
        }
        compiler.locals.removeLast();
      }
      return val;
    }

    int parse_variable(
      final String error_message,
      final Compiler compiler,
    ) {
      parser.consume(TokenType.IDENTIFIER, error_message);
      if (compiler.scope_depth > 0) {
        compiler.declare_local_variable();
        return 0;
      } else {
        return compiler.identifier_constant(parser.previous!);
      }
    }

    DeclarationVari var_declaration() {
      final exprs = <Expr>[];
      do {
        final global = parse_variable('Expect variable name', compiler);
        final token = parser.previous;
        if (parser.match(TokenType.EQUAL)) {
          exprs.add(expression());
        } else {
          exprs.add(const ExprNil());
          // region emitter
          compiler.emit_op(OpCode.NIL);
          // endregion
        }
        // region emitter
        compiler.define_variable(global, token: token);
        // endregion
      } while (parser.match(TokenType.COMMA));
      parser.consume(TokenType.SEMICOLON, 'Expect a newline after variable declaration');
      return DeclarationVari(
        exprs: exprs,
      );
    }

    Stmt statement() {
      if (parser.match(TokenType.PRINT)) {
        final expr = expression();
        // region emitter
        parser.consume(TokenType.SEMICOLON, 'Expect a newline after value');
        compiler.emit_op(OpCode.PRINT);
        // endregion
        return StmtOutput(
          expr: expr,
        );
      } else if (parser.match(TokenType.FOR)) {
        if (parser.match(TokenType.LEFT_PAREN)) {
          return wrap_in_scope(
            fn: () {
              final left = () {
                if (parser.match(TokenType.SEMICOLON)) {
                  return null;
                } else if (parser.match(TokenType.VAR)) {
                  return LoopLeftVari(
                    decl: var_declaration(),
                  );
                } else {
                  final expr = expression();
                  // region emitter
                  parser.consume(TokenType.SEMICOLON, 'Expect a newline after expression');
                  compiler.emit_op(OpCode.POP);
                  // endregion
                  return LoopLeftExpr(
                    expr: expr,
                  );
                }
              }();
              // region emitter
              int loop_start = compiler.current_chunk.count;
              int exit_jump = -1;
              // endregion
              final center = () {
                if (!parser.match(TokenType.SEMICOLON)) {
                  final expr = expression();
                  // region emitter
                  parser.consume(TokenType.SEMICOLON, "Expect ';' after loop condition");
                  exit_jump = compiler.emit_jump(OpCode.JUMP_IF_FALSE);
                  compiler.emit_op(OpCode.POP); // Condition.
                  // endregion
                  return expr;
                } else {
                  return null;
                }
              }();
              final right = () {
                if (!parser.match(TokenType.RIGHT_PAREN)) {
                  // region emitter
                  final body_jump = compiler.emit_jump(OpCode.JUMP);
                  final increment_start = compiler.current_chunk.count;
                  // endregion
                  final expr = expression();
                  // region emitter
                  compiler.emit_op(OpCode.POP);
                  parser.consume(TokenType.RIGHT_PAREN, "Expect ')' after for clauses");
                  compiler.emit_loop(loop_start);
                  loop_start = increment_start;
                  compiler.patch_jump(body_jump);
                  // endregion
                  return expr;
                } else {
                  return null;
                }
              }();
              final stmt = statement();
              // region emitter
              compiler.emit_loop(loop_start);
              if (exit_jump != -1) {
                compiler.patch_jump(exit_jump);
                compiler.emit_op(OpCode.POP); // Condition.
              }
              // endregion
              return StmtLoop(
                left: left,
                center: center,
                right: right,
                body: stmt,
              );
            },
          );
        } else {
          return wrap_in_scope(
            fn: () {
              parse_variable('Expect variable name', compiler);
              // region emitter
              compiler.emit_op(OpCode.NIL);
              compiler.define_variable(0, token: parser.previous); // Remove 0
              final stack_idx = compiler.locals.length - 1;
              // endregion
              if (parser.match(TokenType.COMMA)) {
                parse_variable('Expect variable name', compiler);
                // region emitter
                compiler.emit_op(OpCode.NIL);
                compiler.define_variable(0, token: parser.previous);
                // endregion
              } else {
                // region emitter
                // Create dummy value slot
                compiler.add_local(
                  const SyntheticTokenImpl(
                    type: TokenType.IDENTIFIER,
                    str: '_for_val_',
                  ),
                );
                compiler.emit_constant(0); // Emit a zero to permute val & key
                compiler.mark_local_variable_initialized();
                // endregion
              }
              // region emitter
              // Now add two dummy local variables. Idx & entries
              compiler.add_local(
                const SyntheticTokenImpl(
                  type: TokenType.IDENTIFIER,
                  str: '_for_idx_',
                ),
              );
              compiler.emit_op(OpCode.NIL);
              compiler.mark_local_variable_initialized();
              compiler.add_local(
                const SyntheticTokenImpl(
                  type: TokenType.IDENTIFIER,
                  str: '_for_iterable_',
                ),
              );
              compiler.emit_op(OpCode.NIL);
              compiler.mark_local_variable_initialized();
              // Rest of the loop
              parser.consume(TokenType.IN, "Expect 'in' after loop variables");
              // endregion
              final iterable = expression();
              // region emitter
              // Iterator
              final loop_start = compiler.current_chunk.count;
              compiler.emit_bytes(OpCode.CONTAINER_ITERATE.index, stack_idx);
              final exit_jump = compiler.emit_jump(OpCode.JUMP_IF_FALSE);
              compiler.emit_op(OpCode.POP); // Condition
              // endregion
              final body = statement();
              // region emitter
              compiler.emit_loop(loop_start);
              // Exit
              compiler.patch_jump(exit_jump);
              compiler.emit_op(OpCode.POP); // Condition
              // endregion
              return StmtLoop2(
                center: iterable,
                body: body,
              );
            },
          );
        }
      } else if (parser.match(TokenType.IF)) {
        final expr = expression();
        // region emitter
        final then_jump = compiler.emit_jump(OpCode.JUMP_IF_FALSE);
        compiler.emit_op(OpCode.POP);
        // endregion
        final stmt = statement();
        // region emitter
        final else_jump = compiler.emit_jump(OpCode.JUMP);
        compiler.patch_jump(then_jump);
        compiler.emit_op(OpCode.POP);
        // endregion
        if (parser.match(TokenType.ELSE)) {
          statement();
        }
        // region emitter
        compiler.patch_jump(else_jump);
        // endregion
        return StmtConditional(
          expr: expr,
          stmt: stmt,
        );
      } else if (parser.match(TokenType.RETURN)) {
        if (parser.match(TokenType.SEMICOLON)) {
          // region emitter
          compiler.emit_return();
          // endregion
          return const StmtRet(
            expr: null,
          );
        } else {
          // region emitter
          if (compiler.type == FunctionType.INITIALIZER) {
            error_delegate.error_at_previous("Can't return a value from an initializer");
          }
          // endregion
          final expr = expression();
          // region emitter
          parser.consume(TokenType.SEMICOLON, 'Expect a newline after return value');
          compiler.emit_op(OpCode.RETURN);
          // endregion
          return StmtRet(
            expr: expr,
          );
        }
      } else if (parser.match(TokenType.WHILE)) {
        // region emitter
        final loop_start = compiler.current_chunk.count;
        // endregion
        final expr = expression();
        // region emitter
        final exit_jump = compiler.emit_jump(OpCode.JUMP_IF_FALSE);
        compiler.emit_op(OpCode.POP);
        // endregion
        final stmt = statement();
        // region emitter
        compiler.emit_loop(loop_start);
        compiler.patch_jump(exit_jump);
        compiler.emit_op(OpCode.POP);
        // endregion
        return StmtWhil(
          expr: expr,
          stmt: stmt,
        );
      } else if (parser.match(TokenType.LEFT_BRACE)) {
        return wrap_in_scope(
          fn: () {
            final decls = <Declaration>[];
            while (!parser.check(TokenType.RIGHT_BRACE) && !parser.check(TokenType.EOF)) {
              decls.add(declaration());
            }
            parser.consume(TokenType.RIGHT_BRACE, 'Unterminated block');
            return StmtBlock(
              block: Block(
                decls: decls,
              ),
            );
          },
        );
      } else {
        final expr = expression();
        // region emitter
        parser.consume(TokenType.SEMICOLON, 'Expect a newline after expression');
        compiler.emit_op(OpCode.POP);
        // endregion
        return StmtExpr(
          expr: expr,
        );
      }
    }

    Block function_block(
      final FunctionType type,
    ) {
      final new_compiler = CompilerWrappedImpl(
        type: type,
        enclosing: compiler,
        parser: parser,
      );
      parser.consume(TokenType.LEFT_PAREN, "Expect '(' after function name");
      final args = <NaturalToken?>[];
      if (!parser.check(TokenType.RIGHT_PAREN)) {
        do {
          // region emitter
          new_compiler.function.arity++;
          if (new_compiler.function.arity > 255) {
            new_compiler.error_delegate.error_at_current("Can't have more than 255 parameters");
          }
          // endregion
          parse_variable('Expect parameter name', new_compiler);
          // region emitter
          new_compiler.mark_local_variable_initialized();
          // endregion
          args.add(parser.previous);
        } while (parser.match(TokenType.COMMA));
      }
      // region emitter
      for (int k = 0; k < args.length; k++) {
        new_compiler.define_variable(0, token: args[k], peek_dist: args.length - 1 - k);
      }
      // endregion
      parser.consume(TokenType.RIGHT_PAREN, "Expect ')' after parameters");
      parser.consume(TokenType.LEFT_BRACE, 'Expect function body');
      final _parser = ParserAtCompiler(
        parser: parser,
        error_delegate: error_delegate,
        compiler: new_compiler,
      );
      final decls = <Declaration>[];
      while (!parser.check(TokenType.RIGHT_BRACE) && !parser.check(TokenType.EOF)) {
        decls.add(
          _parser.declaration(),
        );
      }
      parser.consume(TokenType.RIGHT_BRACE, 'Unterminated block');
      final block = Block(
        decls: decls,
      );
      // region emitter
      final function = new_compiler.end_compiler();
      compiler.emit_bytes(OpCode.CLOSURE.index, compiler.make_constant(function));
      for (var i = 0; i < new_compiler.upvalues.length; i++) {
        compiler.emit_byte(new_compiler.upvalues[i].is_local ? 1 : 0);
        compiler.emit_byte(new_compiler.upvalues[i].index);
      }
      // endregion
      return block;
    }

    final decl = () {
      if (parser.match(TokenType.CLASS)) {
        // class declaration
        parser.consume(TokenType.IDENTIFIER, 'Expect class name');
        final class_name = parser.previous;
        // region emitter
        final name_constant = compiler.identifier_constant(class_name!);
        compiler.declare_local_variable();
        compiler.emit_bytes(OpCode.CLASS.index, name_constant);
        compiler.define_variable(name_constant);
        final class_compiler = ClassCompiler(
          compiler.current_class,
          parser.previous,
          false,
        );
        compiler.current_class = class_compiler;
        // endregion
        return wrap_in_scope(
          fn: () {
            if (parser.match(TokenType.LESS)) {
              parser.consume(TokenType.IDENTIFIER, 'Expect superclass name');
              // region emitter
              compiler.get_or_set<void>(
                parser.previous!,
                (final arg, final get_op, final set_op) {
                  compiler.emit_bytes(get_op.index, arg);
                },
              );
              if (CompilerMixin.identifiers_equal2(class_name, parser.previous!)) {
                error_delegate.error_at_previous("A class can't inherit from itself");
              }
              compiler.add_local(
                const SyntheticTokenImpl(
                  type: TokenType.IDENTIFIER,
                  str: 'super',
                ),
              );
              compiler.define_variable(0);
              compiler.get_or_set<void>(
                class_name,
                (final arg, final get_op, final set_op) {
                  compiler.emit_bytes(get_op.index, arg);
                },
              );
              compiler.emit_op(OpCode.INHERIT);
              class_compiler.has_superclass = true;
              // endregion
            }
            // region emitter
            compiler.get_or_set<void>(
              class_name,
              (final arg, final get_op, final set_op) {
                compiler.emit_bytes(get_op.index, arg);
              },
            );
            // endregion
            parser.consume(TokenType.LEFT_BRACE, 'Expect class body');
            final functions = <Block>[];
            while (!parser.check(TokenType.RIGHT_BRACE) && !parser.check(TokenType.EOF)) {
              // parse method
              parser.consume(TokenType.IDENTIFIER, 'Expect method name');
              // region emitter
              final identifier = parser.previous!;
              final constant = compiler.identifier_constant(identifier);
              FunctionType type = FunctionType.METHOD;
              if (identifier.str == 'init') {
                type = FunctionType.INITIALIZER;
              }
              // endregion
              functions.add(function_block(type));
              // region emitter
              compiler.emit_bytes(OpCode.METHOD.index, constant);
              // endregion
            }
            parser.consume(TokenType.RIGHT_BRACE, 'Unterminated class body');
            // region emitter
            compiler.emit_op(OpCode.POP);
            compiler.current_class = compiler.current_class!.enclosing;
            // endregion
            return DeclarationClazz(
              functions: functions,
            );
          },
        );
      } else if (parser.match(TokenType.FUN)) {
        // fun declaration
        final global = parse_variable('Expect function name', compiler);
        // region emitter
        final token = parser.previous!;
        compiler.mark_local_variable_initialized();
        // endregion
        final block = function_block(FunctionType.FUNCTION);
        // region emitter
        compiler.define_variable(global, token: token);
        // endregion
        return DeclarationFun(
          block: block,
          name: token,
        );
      } else if (parser.match(TokenType.VAR)) {
        return var_declaration();
      } else {
        return DeclarationStmt(
          stmt: statement(),
        );
      }
    }();
    if (parser.panic_mode) {
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
              parser.advance();
              continue outer;
          }
        }
      }
    }
    return decl;
  }
}
// endregion

// region table
class Table {
  final Map<String?, Object?> data;

  Table() : data = {};

  Object? get_val(
    final String? key,
  ) {
    return data[key];
  }

  bool set_val(
    final String? key,
    final Object? val,
  ) {
    final had_key = data.containsKey(key);
    data[key] = val;
    return !had_key;
  }

  void delete(
    final String? key,
  ) {
    data.remove(key);
  }

  void add_all(
    final Table other,
  ) {
    data.addAll(other.data);
  }

  Object? find_string(
    final String str,
  ) {
    // Optimisation: key on hashKeys
    return data[str];
  }
}
// endregion

// region native classes
abstract class ObjNativeClass {
  final String? name;
  final Map<String?, Object?> properties = {};
  final Map<String, Type>? properties_types;
  final List<String> init_arg_keys;

  ObjNativeClass({
    required this.init_arg_keys,
    this.name,
    this.properties_types,
    final List<Object?>? stack,
    final int? arg_idx,
    final int? arg_count,
  }) {
    if (arg_count != init_arg_keys.length) {
      arg_count_error(init_arg_keys.length, arg_count);
    }
    for (int k = 0; k < init_arg_keys.length; k++) {
      final expected = properties_types![init_arg_keys[k]];
      if (expected != Object && stack![arg_idx! + k].runtimeType != expected) {
        arg_type_error(0, expected, stack[arg_idx + k].runtimeType);
      }
      properties[init_arg_keys[k]] = stack![arg_idx! + k];
    }
  }

  Object call(
    final String? key,
    final List<Object?> stack,
    final int arg_idx,
    final int arg_count,
  ) {
    throw NativeError('Undefined function $key');
  }

  void set_val(
    final String? key,
    final Object? value,
  ) {
    if (!properties_types!.containsKey(key)) {
      throw NativeError('Undefined property $key');
    } else if (value.runtimeType != properties_types![key!]) {
      throw NativeError(
        'Invalid object type, expected <%s>, but received <%s>',
        [type_to_string(properties_types![key]), type_to_string(value.runtimeType)],
      );
    } else {
      properties[key] = value;
    }
  }

  Object get_val(
    final String? key,
  ) {
    if (!properties.containsKey(key)) {
      throw NativeError('Undefined property $key');
    } else {
      return properties[key] ?? Nil;
    }
  }

  String string_expr({
    final int max_chars,
  });
}

class ListNode extends ObjNativeClass {
  ListNode(
    final List<Object?> stack,
    final int arg_idx,
    final int arg_count,
  ) : super(
          name: 'ListNode',
          properties_types: {
            'val': Object,
            'next': ListNode,
          },
          init_arg_keys: [
            'val',
          ],
          stack: stack,
          arg_idx: arg_idx,
          arg_count: arg_count,
        );

  Object? get val {
    return properties['val'];
  }

  ListNode? get next {
    return properties['next'] as ListNode?;
  }

  List<ListNode?> link_to_list({
    final int max_length = 100,
  }) {
    // ignore: prefer_collection_literals
    final visited = LinkedHashSet<ListNode?>();
    ListNode? node = this;
    while (node != null && !visited.contains(node) && visited.length <= max_length) {
      visited.add(node);
      node = node.next;
    }
    // Mark list as infinite
    if (node == this) {
      visited.add(null);
    }
    return visited.toList();
  }

  @override
  String string_expr({
    final int max_chars = 100,
  }) {
    final str = StringBuffer('[');
    final list = link_to_list(
      max_length: max_chars ~/ 2,
    );
    for (int k = 0; k < list.length; k++) {
      final val = list[k]!.val;
      if (k > 0) {
        str.write(' → ');
      }
      str.write(
        () {
          if (val == null) {
            return '⮐';
          } else {
            return value_to_string(
              val,
              max_chars: max_chars - str.length,
            );
          }
        }(),
      );
      if (str.length > max_chars) {
        str.write('...');
        break;
      }
    }
    str.write(']');
    return str.toString();
  }
}

typedef NativeClassCreator = ObjNativeClass Function(
  List<Object?> stack,
  int arg_idx,
  int arg_count,
);

ListNode list_node(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  return ListNode(
    stack,
    arg_idx,
    arg_count,
  );
}

const Map<String, ObjNativeClass Function(List<Object>, int, int)> NATIVE_CLASSES =
    <String, NativeClassCreator>{
  'ListNode': list_node,
};
// endregion

// region native
class NativeError implements Exception {
  String format;
  List<Object?>? args;

  NativeError(
    final this.format, [
    final this.args,
  ]);
}

String type_to_string(
  final Type? type,
) {
  if (type == double) {
    return 'Number';
  } else {
    return type.toString();
  }
}

void arg_count_error(
  final int expected,
  final int? received,
) {
  throw NativeError(
    'Expected %d arguments, but got %d',
    [expected, received],
  );
}

void arg_type_error(
  final int index,
  final Type? expected,
  final Type? received,
) {
  throw NativeError(
    'Invalid argument %d type, expected <%s>, but received <%s>',
    [
      index + 1,
      type_to_string(expected),
      type_to_string(received),
    ],
  );
}

void assert_types(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
  final List<Type> types,
) {
  if (arg_count != types.length) {
    arg_count_error(
      types.length,
      arg_count,
    );
  }
  for (int k = 0; k < types.length; k++) {
    if (types[k] != Object && stack[arg_idx + k].runtimeType != types[k]) {
      arg_type_error(
        0,
        double,
        stack[arg_idx + k] as Type?,
      );
    }
  }
}

double assert1double(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  assert_types(
    stack,
    arg_idx,
    arg_count,
    <Type>[double],
  );
  return (stack[arg_idx] as double?)!;
}

void assert2doubles(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  assert_types(
    stack,
    arg_idx,
    arg_count,
    <Type>[double, double],
  );
}

// Native functions
typedef NativeFunction = Object? Function(List<Object?> stack, int arg_idx, int arg_count);

double clock_native(final List<Object?> stack, final int arg_idx, final int arg_count) {
  if (arg_count != 0) {
    arg_count_error(0, arg_count);
  }
  return DateTime.now().millisecondsSinceEpoch.toDouble();
}

double min_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  assert2doubles(stack, arg_idx, arg_count);
  return min((stack[arg_idx] as double?)!, (stack[arg_idx + 1] as double?)!);
}

double max_native(final List<Object?> stack, final int arg_idx, final int arg_count) {
  assert2doubles(stack, arg_idx, arg_count);
  return max(
    (stack[arg_idx] as double?)!,
    (stack[arg_idx + 1] as double?)!,
  );
}

double floor_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  final arg_0 = assert1double(stack, arg_idx, arg_count);
  return arg_0.floorToDouble();
}

double ceil_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  final arg_0 = assert1double(stack, arg_idx, arg_count);
  return arg_0.ceilToDouble();
}

double abs_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  final arg_0 = assert1double(stack, arg_idx, arg_count);
  return arg_0.abs();
}

double round_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  final arg_0 = assert1double(stack, arg_idx, arg_count);
  return arg_0.roundToDouble();
}

double sqrt_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  final arg_0 = assert1double(stack, arg_idx, arg_count);
  return sqrt(arg_0);
}

double sign_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  return assert1double(stack, arg_idx, arg_count).sign;
}

double exp_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  return exp(assert1double(stack, arg_idx, arg_count));
}

double log_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  return log(assert1double(stack, arg_idx, arg_count));
}

double sin_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  return sin(assert1double(stack, arg_idx, arg_count));
}

double asin_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  return asin(assert1double(stack, arg_idx, arg_count));
}

double cos_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  return cos(assert1double(stack, arg_idx, arg_count));
}

double acos_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  return acos(assert1double(stack, arg_idx, arg_count));
}

double tan_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  return tan(assert1double(stack, arg_idx, arg_count));
}

double atan_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  return atan(assert1double(stack, arg_idx, arg_count));
}

// ignore: non_constant_identifier_names
final NATIVE_FUNCTIONS = <ObjNative>[
  ObjNative('clock', 0, clock_native),
  ObjNative('min', 2, min_native),
  ObjNative('max', 2, max_native),
  ObjNative('floor', 1, floor_native),
  ObjNative('ceil', 1, ceil_native),
  ObjNative('abs', 1, abs_native),
  ObjNative('round', 1, round_native),
  ObjNative('sqrt', 1, sqrt_native),
  ObjNative('sign', 1, sign_native),
  ObjNative('exp', 1, exp_native),
  ObjNative('log', 1, log_native),
  ObjNative('sin', 1, sin_native),
  ObjNative('asin', 1, asin_native),
  ObjNative('cos', 1, cos_native),
  ObjNative('acos', 1, acos_native),
  ObjNative('tan', 1, tan_native),
  ObjNative('atan', 1, atan_native),
];

const NATIVE_VALUES = <String, Object>{
  'π': pi,
  '𝘦': e,
  '∞': double.infinity,
};

// List native functions
double list_length(
  final List<dynamic> list,
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  if (arg_count != 0) {
    arg_count_error(0, arg_count);
  }
  return list.length.toDouble();
}

void list_add(
  final List<dynamic> list,
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  if (arg_count != 1) {
    arg_count_error(1, arg_count);
  }
  list.add(stack[arg_idx]);
}

void list_insert(
  final List<dynamic> list,
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  assert_types(stack, arg_idx, arg_count, [double, Object]);
  final idx = (stack[arg_idx] as double?)!.toInt();
  if (idx < 0 || idx > list.length) {
    throw NativeError('Index %d out of bounds [0, %d]', [idx, list.length]);
  } else {
    list.insert(idx, stack[arg_idx + 1]);
  }
}

Object? list_remove(
  final List<dynamic> list,
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  assert_types(stack, arg_idx, arg_count, [double]);
  final idx = (stack[arg_idx] as double?)!.toInt();
  if (idx < 0 || idx > list.length) {
    throw NativeError('Index %d out of bounds [0, %d]', [idx, list.length]);
  } else {
    return list.removeAt(idx);
  }
}

Object? list_pop(
  final List<dynamic> list,
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  if (arg_count != 0) {
    arg_count_error(0, arg_count);
  }
  return list.removeLast();
}

void list_clear(final List<dynamic> list, final List<Object?> stack, final int arg_idx, final int arg_count) {
  if (arg_count != 0) {
    arg_count_error(0, arg_count);
  }
  list.clear();
}

typedef ListNativeFunction = Object? Function(
  List<dynamic> list,
  List<Object?> stack,
  int arg_idx,
  int arg_count,
);

const LIST_NATIVE_FUNCTIONS = <String, ListNativeFunction>{
  'length': list_length,
  'add': list_add,
  'insert': list_insert,
  'remove': list_remove,
  'pop': list_pop,
  'clear': list_clear,
};

// Map native functions
double map_length(
    final Map<dynamic, dynamic> map, final List<Object?> stack, final int arg_idx, final int arg_count,) {
  if (arg_count != 0) {
    arg_count_error(0, arg_count);
  }
  return map.length.toDouble();
}

List<dynamic> map_keys(
    final Map<dynamic, dynamic> map, final List<Object?> stack, final int arg_idx, final int arg_count,) {
  if (arg_count != 0) {
    arg_count_error(0, arg_count);
  }
  return map.keys.toList();
}

List<dynamic> map_values(
    final Map<dynamic, dynamic> map, final List<Object?> stack, final int arg_idx, final int arg_count,) {
  if (arg_count != 0) arg_count_error(0, arg_count);
  return map.values.toList();
}

bool map_has(
    final Map<dynamic, dynamic> map, final List<Object?> stack, final int arg_idx, final int arg_count,) {
  if (arg_count != 1) {
    arg_count_error(1, arg_count);
  }
  return map.containsKey(stack[arg_idx]);
}

typedef MapNativeFunction = Object Function(
    Map<dynamic, dynamic> list, List<Object?> stack, int arg_idx, int arg_count,);

const MAP_NATIVE_FUNCTIONS = <String, MapNativeFunction>{
  'length': map_length,
  'keys': map_keys,
  'values': map_values,
  'has': map_has,
};

// String native functions
double str_length(final String str, final List<Object?> stack, final int arg_idx, final int arg_count,) {
  if (arg_count != 0) {
    arg_count_error(0, arg_count);
  }
  return str.length.toDouble();
}

typedef StringNativeFunction = Object Function(String list, List<Object?> stack, int arg_idx, int arg_count,);

const STRING_NATIVE_FUNCTIONS = <String, StringNativeFunction>{
  'length': str_length,
};
// endregion

// region object
class ObjNative {
  String name;
  int arity;
  NativeFunction fn;

  ObjNative(
    this.name,
    this.arity,
    this.fn,
  );
}

class ObjFunction {
  final Chunk chunk;
  int arity;
  int upvalue_count;
  String? name;

  ObjFunction()
      : upvalue_count = 0,
        arity = 0,
        chunk = Chunk();
}

class ObjUpvalue {
  int? location;
  Object? closed;
  ObjUpvalue? next;

  ObjUpvalue(
    final this.location,
  ) : closed = Nil;
}

class ObjClosure {
  ObjFunction function;
  late List<ObjUpvalue?> upvalues;
  late int upvalue_count;

  ObjClosure(
    final this.function,
  ) {
    upvalues = List<ObjUpvalue?>.generate(
      function.upvalue_count,
      (final index) => null,
    );
    upvalue_count = function.upvalue_count;
  }
}

class ObjClass {
  String? name;
  Table methods;

  ObjClass(
    final this.name,
  ) : methods = Table();
}

class ObjInstance {
  String? klass_name; // For dynamic class lookup
  ObjClass? klass;
  Table fields;

  ObjInstance({
    this.klass,
    this.klass_name,
  }) : fields = Table();
}

class ObjBoundMethod {
  Object? receiver;
  ObjClosure method;

  ObjBoundMethod(
    final this.receiver,
    final this.method,
  );
}

int hash_string(
  final String key,
) {
  int hash = 2166136261;
  for (int i = 0; i < key.length; i++) {
    hash ^= key.codeUnitAt(i);
    hash *= 16777619;
  }
  return hash;
}

String function_to_string(
  final ObjFunction function,
) {
  if (function.name == null) {
    return '<script>';
  } else {
    return '<fn ${function.name}>';
  }
}

void print_object(
  final Object value,
) {
  print(object_to_string(value));
}

String? object_to_string(
  final Object? value, {
  final int maxChars = 100,
}) {
  if (value is ObjClass) {
    return value.name;
  } else if (value is ObjBoundMethod) {
    return function_to_string(value.method.function);
  } else if (value is ObjClosure) {
    return function_to_string(value.function);
  } else if (value is ObjFunction) {
    return function_to_string(value);
  } else if (value is ObjInstance) {
    return '${value.klass!.name} instance';
    // return instanceToString(value, maxChars: maxChars);
  } else if (value is ObjNative) {
    return '<native fn>';
  } else if (value is ObjUpvalue) {
    return 'upvalue';
  } else if (value is ObjNativeClass) {
    return value.string_expr(max_chars: maxChars);
  } else if (value is NativeClassCreator) {
    return '<native class>';
  }
  return value.toString();
}
// endregion

// region error
mixin LangError {
  String get type;
  NaturalToken? get token;
  int? get line;
  String? get msg;

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

class CompilerError with LangError {
  @override
  final NaturalToken token;
  @override
  final String? msg;

  const CompilerError(
    final this.token,
    final this.msg,
  );

  @override
  String get type => "Compile";

  @override
  int? get line => token.loc.line;
}
// endregion

// region debug
class Debug {
  final bool silent;
  final StringBuffer buf;

  Debug(
    final this.silent,
  ) : buf = StringBuffer();

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
    final arg_count = chunk.code[offset + 2];
    stdwrite(sprintf('%-16s (%d args) %4d \'', [name, arg_count, constant]));
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
        for (var j = 0; j < function.upvalue_count; j++) {
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
  final List<int> code;
  final List<Object?> constants;
  final Map<Object?, int> _constant_map;
  final List<int> lines;

  Chunk()
      : lines = [],
        constants = [],
        code = [],
        _constant_map = {};

  int get count => code.length;

  void write(
    final int byte,
    final int line,
  ) {
    code.add(byte);
    lines.add(line);
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
    buf.write(value_to_string(list[k], max_chars: maxChars - buf.length));
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
    buf.write(value_to_string(entries[k].key, max_chars: maxChars - buf.length));
    buf.write(':');
    buf.write(value_to_string(
      entries[k].value,
      max_chars: maxChars - buf.length,
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
  final int max_chars = 100,
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
    return list_to_string(value, maxChars: max_chars);
  } else if (value is Map) {
    return map_to_string(value, maxChars: max_chars);
  } else {
    return object_to_string(value, maxChars: max_chars);
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
