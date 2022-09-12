import 'dart:collection';
import 'dart:math';

import 'models/ast.dart';
import 'models/errors.dart';
import 'models/model.dart';
import 'parser.dart';

// region compiler
CompilationResult run_dlox_compiler({
  required final List<NaturalToken> tokens,
  required final Debug debug,
  required final bool trace_bytecode,
}) {
  final parser = make_parser(
    tokens: tokens,
    debug: debug,
  );
  final fn = compile_dlox(
    parser: parser.key,
    error_delegate: parser.value,
    trace_bytecode: trace_bytecode,
  );
  return CompilationResult(
    function: fn.value,
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

MapEntry<CompilationUnit, ObjFunction> compile_dlox({
  required final Parser parser,
  required final ErrorDelegate error_delegate,
  required final bool trace_bytecode,
}) {
  final compiler = CompilerRootImpl(
    function: ObjFunction(
      name: null,
    ),
    line_provider: () => parser.previous_line,
    error_delegate: error_delegate,
    debug_trace_bytecode: trace_bytecode,
  );
  final decls = <Declaration>[];
  for (;;) {
    if (parser.is_eof()) {
      break;
    } else {
      decls.add(
        parser.parse_declaration(
          compiler: compiler,
        ),
      );
    }
  }
  return MapEntry(
    CompilationUnit(
      decls: decls,
    ),
    compiler.end_compiler(),
  );
}

class CompilerRootImpl with CompilerMixin {
  @override
  final ErrorDelegate error_delegate;
  @override
  final List<Local> locals;
  @override
  final List<Upvalue> upvalues;
  @override
  final bool is_initializer;
  @override
  int scope_depth;
  @override
  bool debug_trace_bytecode;
  @override
  ClassCompiler? current_class;
  @override
  ObjFunction function;
  @override
  final int Function() line_provider;

  CompilerRootImpl({
    required final this.error_delegate,
    required final this.debug_trace_bytecode,
    required final this.line_provider,
    required final this.function,
  })  : is_initializer = false,
        scope_depth = 0,
        locals = [
          init_local(true),
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
  final bool is_initializer;
  @override
  final CompilerMixin enclosing;
  @override
  int scope_depth;
  @override
  ClassCompiler? current_class;
  @override
  ObjFunction function;
  @override
  final int Function() line_provider;

  CompilerWrappedImpl({
    required final this.is_initializer,
    required final this.enclosing,
    required final this.line_provider,
    required final this.function,
    required final bool is_not_function,
  })  : current_class = enclosing.current_class,
        scope_depth = enclosing.scope_depth + 1,
        locals = [
          init_local(is_not_function),
        ],
        upvalues = [];

  @override
  bool get debug_trace_bytecode => enclosing.debug_trace_bytecode;

  @override
  ErrorDelegate get error_delegate => enclosing.error_delegate;
}

mixin CompilerMixin implements Compiler {
  abstract ClassCompiler? current_class;

  ObjFunction get function;

  CompilerMixin? get enclosing;

  bool get debug_trace_bytecode;

  abstract int scope_depth;

  List<Local> get locals;

  List<Upvalue> get upvalues;

  int Function() get line_provider;

  ErrorDelegate get error_delegate;

  bool get is_initializer;

  ObjFunction end_compiler() {
    emit_return();
    if (error_delegate.errors.isEmpty && debug_trace_bytecode) {
      error_delegate.debug.disassemble_chunk(current_chunk, function.name ?? '<script>');
    }
    if (enclosing != null) {
      final _enclosing = enclosing!;
      _enclosing.emit_byte(OpCode.CLOSURE.index);
      _enclosing.emit_byte(_enclosing.make_constant(function));
      for (final x in this.upvalues) {
        _enclosing.emit_byte(
          () {
            if (x.is_local) {
              return 1;
            } else {
              return 0;
            }
          }(),
        );
        _enclosing.emit_byte(x.index);
      }
      return function;
    } else {
      return function;
    }
  }

  Chunk get current_chunk {
    return function.chunk;
  }

  void emit_op(
    final OpCode op,
  ) {
    emit_byte(op.index);
  }

  void emit_byte(
    final int byte,
  ) {
    current_chunk.write(byte, line_provider());
  }

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

  int emit_jump(
    final OpCode instruction,
  ) {
    emit_op(instruction);
    emit_byte(0xff);
    emit_byte(0xff);
    return current_chunk.count - 2;
  }

  void emit_return() {
    if (is_initializer) {
      emit_byte(OpCode.GET_LOCAL.index);
      emit_byte(0);
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
      error_delegate.error_at_previous('Too many constants in one chunk');
      return 0;
    } else {
      return constant;
    }
  }

  void emit_constant(
    final Object? value,
  ) {
    emit_byte(OpCode.CONSTANT.index);
    emit_byte(make_constant(value));
  }

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

  void add_local(
    final SyntheticToken? name,
  ) {
    if (locals.length >= UINT8_COUNT) {
      error_delegate.error_at_previous('Too many local variables in function');
    } else {
      locals.add(
        Local(
          name: name,
          depth: -1,
          is_captured: false,
        ),
      );
    }
  }

  int identifier_constant(
    final SyntheticToken name,
  ) {
    return make_constant(name.lexeme);
  }

  int? resolve_local(
    final SyntheticToken? name,
  ) {
    for (int i = locals.length - 1; i >= 0; i--) {
      final local = locals[i];
      if (name!.lexeme == local.name!.lexeme) {
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
    assert(
      upvalues.length == function.upvalue_count,
      "",
    );
    for (int i = 0; i < upvalues.length; i++) {
      final upvalue = upvalues[i];
      if (upvalue.index == index && upvalue.is_local == is_local) {
        return i;
      } else {
        // continue.
      }
    }
    if (upvalues.length == UINT8_COUNT) {
      error_delegate.error_at_previous('Too many closure variables in function');
      return 0;
    } else {
      upvalues.add(
        Upvalue(
          name: name,
          index: index,
          is_local: is_local,
        ),
      );
      return function.upvalue_count++;
    }
  }

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
      emit_byte(OpCode.DEFINE_GLOBAL.index);
      emit_byte(global);
    }
  }

  void declare_local_variable(
    final NaturalToken name,
  ) {
    // Global variables are implicitly declared.
    if (scope_depth != 0) {
      for (int i = locals.length - 1; i >= 0; i--) {
        final local = locals[i];
        if (local.depth != -1 && local.depth < scope_depth) {
          break; // [negative]
        }
        if (name.lexeme == local.name!.lexeme) {
          error_delegate.error_at_previous('Already variable with this name in this scope');
        }
      }
      add_local(name);
    }
  }

  T get_or_set<T>(
    final SyntheticToken name,
    final T Function(
      int,
      OpCode get_op,
      OpCode set_op,
    )
        fn,
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

  T wrap_in_scope<T>({
    required final T Function() fn,
  }) {
    scope_depth++;
    final val = fn();
    scope_depth--;
    while (locals.isNotEmpty && locals.last.depth > scope_depth) {
      if (locals.last.is_captured) {
        emit_op(OpCode.CLOSE_UPVALUE);
      } else {
        emit_op(OpCode.POP);
      }
      locals.removeLast();
    }
    return val;
  }

  int make_variable(
    final NaturalToken name,
  ) {
    if (scope_depth > 0) {
      declare_local_variable(name);
      return 0;
    } else {
      return identifier_constant(name);
    }
  }

  @override
  void visit_print_post() {
    emit_op(OpCode.PRINT);
  }

  @override
  void visit_set_post(
    final SyntheticToken name,
  ) {
    get_or_set<void>(
      name,
      (final arg, final get_op, final set_op) {
        emit_byte(set_op.index);
        emit_byte(arg);
      },
    );
  }

  T visit_getter<T>(
    final SyntheticToken name,
    final T Function(void Function(OpCode type) p1) setter,
  ) {
    return get_or_set<T>(
      name,
      (final arg, final get_op, final set_op) {
        emit_byte(get_op.index);
        emit_byte(arg);
        return setter(
          (final op) {
            emit_op(op);
            emit_byte(set_op.index);
            emit_byte(arg);
          },
        );
      },
    );
  }

  @override
  void visit_get_post(
    final SyntheticToken name,
  ) {
    visit_getter(name, (final _) {});
  }

  @override
  R visit_while<E, S, R>(
    final E Function() expression,
    final S Function() statement,
    final R Function(E expr, S stmt) make,
  ) {
    final loop_start = current_chunk.count;
    final expr = expression();
    final exit_jump = emit_jump(OpCode.JUMP_IF_FALSE);
    emit_op(OpCode.POP);
    final stmt = statement();
    emit_loop(loop_start);
    patch_jump(exit_jump);
    emit_op(OpCode.POP);
    return make(expr, stmt);
  }

  @override
  void visit_expr_stmt_post() {
    emit_op(OpCode.POP);
  }

  @override
  void visit_return_empty_post() {
    emit_return();
  }

  @override
  T visit_return_expr<T>(
    final T Function() expression,
  ) {
    if (is_initializer) {
      error_delegate.error_at_previous("Can't return a value from an initializer");
    }
    final expr = expression();
    emit_op(OpCode.RETURN);
    return expr;
  }

  @override
  R visit_if<E, S, R>(
    final E Function() condition,
    final S Function() body,
    final S? Function() other,
    final R Function(E, S, S?) make,
  ) {
    final expr = condition();
    final then_jump = emit_jump(OpCode.JUMP_IF_FALSE);
    emit_op(OpCode.POP);
    final stmt = body();
    final else_jump = emit_jump(OpCode.JUMP);
    patch_jump(then_jump);
    emit_op(OpCode.POP);
    final elsee = other();
    patch_jump(else_jump);
    return make(expr, stmt, elsee);
  }

  @override
  R visit_iter_for<E, S, R>({
    required final NaturalToken key_name,
    required final NaturalToken? value_name,
    required final E Function() iterable,
    required final S Function() body,
    required final R Function(E iterable, S body) make,
  }) {
    return wrap_in_scope(
      fn: () {
        make_variable(key_name);
        emit_op(OpCode.NIL);
        define_variable(0, token: key_name); // Remove 0
        final stack_idx = locals.length - 1;
        if (value_name != null) {
          make_variable(value_name);
          emit_op(OpCode.NIL);
          define_variable(0, token: value_name);
        } else {
          add_local(
            const SyntheticTokenImpl(
              type: TokenType.IDENTIFIER,
              lexeme: '_for_val_',
            ),
          );
          emit_constant(0); // Emit a zero to permute val & key
          mark_local_variable_initialized();
        }
        // Now add two dummy local variables. Idx & entries
        add_local(
          const SyntheticTokenImpl(
            type: TokenType.IDENTIFIER,
            lexeme: '_for_idx_',
          ),
        );
        emit_op(OpCode.NIL);
        mark_local_variable_initialized();
        add_local(
          const SyntheticTokenImpl(
            type: TokenType.IDENTIFIER,
            lexeme: '_for_iterable_',
          ),
        );
        emit_op(OpCode.NIL);
        mark_local_variable_initialized();
        final _iterable = iterable();
        final loop_start = current_chunk.count;
        emit_byte(OpCode.CONTAINER_ITERATE.index);
        emit_byte(stack_idx);
        final exit_jump = emit_jump(OpCode.JUMP_IF_FALSE);
        emit_op(OpCode.POP); // Condition
        final _body = body();
        emit_loop(loop_start);
        patch_jump(exit_jump);
        emit_op(OpCode.POP); // Condition
        return make(
          _iterable,
          _body,
        );
      },
    );
  }

  @override
  List<T> visit_var_decl<T>(
    final Iterable<MapEntry<NaturalToken, T Function()>> Function() fn,
  ) {
    final exprs = <T>[];
    for (final x in fn()) {
      final global = make_variable(x.key);
      final made = x.value();
      exprs.add(made);
      define_variable(global, token: x.key);
    }
    return exprs;
  }

  @override
  R visit_classic_for<L, E, S, R>(
    final L? Function() left,
    final E? Function() center,
    final E Function()? Function() expr,
    final S Function() stmt,
    final R Function(L?, E?, E?, S) make,
  ) {
    return wrap_in_scope(
      fn: () {
        final _left = left();
        int loop_start = current_chunk.count;
        int exit_jump = -1;
        final _center = () {
          final _center = center();
          if (_center != null) {
            exit_jump = emit_jump(OpCode.JUMP_IF_FALSE);
            emit_op(OpCode.POP); // Condition.
          }
          return _center;
        }();
        final _right = () {
          final _right = expr();
          if (_right == null) {
            return null;
          } else {
            final body_jump = emit_jump(OpCode.JUMP);
            final increment_start = current_chunk.count;
            final _expr = _right();
            emit_op(OpCode.POP);
            emit_loop(loop_start);
            loop_start = increment_start;
            patch_jump(body_jump);
            return _expr;
          }
        }();
        final _stmt = stmt();
        emit_loop(loop_start);
        if (exit_jump != -1) {
          patch_jump(exit_jump);
          emit_op(OpCode.POP); // Condition.
        }
        return make(
          _left,
          _center,
          _right,
          _stmt,
        );
      },
    );
  }

  @override
  T visit_fun<T>(
    final NaturalToken name,
    final T Function() block,
  ) {
    final global = make_variable(name);
    mark_local_variable_initialized();
    final _block = block();
    define_variable(global, token: name);
    return _block;
  }

  @override
  void visit_nil_post() {
    emit_op(OpCode.NIL);
  }

  @override
  void visit_set_prop_post(
    final NaturalToken name,
  ) {
    final _name = identifier_constant(name);
    emit_byte(OpCode.SET_PROPERTY.index);
    emit_byte(_name);
  }

  @override
  void visit_invoke_post(
    final NaturalToken name_token,
    final int length,
  ) {
    final name = identifier_constant(name_token);
    emit_byte(OpCode.INVOKE.index);
    emit_byte(name);
    emit_byte(length);
  }

  @override
  List<T>? visit_super<T>(
    final NaturalToken name_token,
    final List<T>? Function() arg_count,
  ) {
    if (current_class == null) {
      error_delegate.error_at_previous("Can't use 'super' outside of a class");
    } else if (!current_class!.has_superclass) {
      error_delegate.error_at_previous("Can't use 'super' in a class with no superclass");
    }
    final name = identifier_constant(name_token);
    visit_getter(
      const SyntheticTokenImpl(
        type: TokenType.IDENTIFIER,
        lexeme: 'this',
      ),
      (final _) {},
    );
    final _args = arg_count();
    // endregion
    if (_args != null) {
      // region emitter
      visit_getter(
        const SyntheticTokenImpl(
          type: TokenType.IDENTIFIER,
          lexeme: 'super',
        ),
        (final _) {},
      );
      emit_byte(OpCode.SUPER_INVOKE.index);
      emit_byte(name);
      emit_byte(_args.length);
      // endregion
    } else {
      visit_getter(
        const SyntheticTokenImpl(
          type: TokenType.IDENTIFIER,
          lexeme: 'super',
        ),
        (final _) {},
      );
      emit_byte(OpCode.GET_SUPER.index);
      emit_byte(name);
    }
    return _args;
  }

  @override
  void visit_truth_post() {
    emit_op(OpCode.TRUE);
  }

  @override
  void visit_falsity_post() {
    emit_op(OpCode.FALSE);
  }

  @override
  B visit_fn<D, B>(
    final String Function() name,
    final FunctionType type,
    final List<NaturalToken> Function() args,
    final B Function(D Function() declaration) block,
    final D Function(Compiler compiler) declaration,
  ) {
    final new_compiler = CompilerWrappedImpl(
      function: ObjFunction(
        name: name(),
      ),
      is_initializer: type == FunctionType.INITIALIZER,
      is_not_function: type != FunctionType.FUNCTION,
      enclosing: this,
      line_provider: line_provider,
    );
    final _args = args();
    for (final name in _args) {
      new_compiler.function.arity++;
      if (new_compiler.function.arity > 255) {
        new_compiler.error_delegate.error_at_current("Can't have more than 255 parameters");
      }
      new_compiler.make_variable(name);
      new_compiler.mark_local_variable_initialized();
    }
    for (int k = 0; k < _args.length; k++) {
      new_compiler.define_variable(0, token: _args[k], peek_dist: _args.length - 1 - k);
    }
    final _block = block(() => declaration(new_compiler));
    new_compiler.end_compiler();
    return _block;
  }

  @override
  List<T> visit_class<T, B>(
    final NaturalToken class_name,
    final NaturalToken Function() before_class_name,
    final NaturalToken? Function() superclass,
    final List<T> Function(
      T Function(
        NaturalToken,
        B Function(
          bool true_init_false_method,
        ),
      )
          fn,
    )
        methods,
    final T Function(
      NaturalToken name,
      B block,
    ) make_method,
  ) {
    final name_constant = identifier_constant(class_name);
    declare_local_variable(class_name);
    emit_byte(OpCode.CLASS.index);
    emit_byte(name_constant);
    define_variable(name_constant);
    final class_compiler = ClassCompiler(
      enclosing: current_class,
      name: before_class_name(),
      has_superclass: false,
    );
    current_class = class_compiler;
    return wrap_in_scope(
      fn: () {
        final superclass_name = superclass();
        if (superclass_name != null) {
          final class_name = current_class!.name!;
          visit_getter(superclass_name, (final _) {});
          if (class_name.lexeme == superclass_name.lexeme) {
            error_delegate.error_at_previous("A class can't inherit from itself");
          }
          add_local(
            const SyntheticTokenImpl(
              type: TokenType.IDENTIFIER,
              lexeme: 'super',
            ),
          );
          define_variable(0);
          visit_getter(class_name, (final _) {});
          emit_op(OpCode.INHERIT);
          current_class!.has_superclass = true;
        }
        visit_getter(class_name, (final _) {});
        final functions = methods(
          (final name, final make_block) {
            final constant = identifier_constant(name);
            final block = make_block(
              () {
                if (name.lexeme == 'init') {
                  return true;
                } else {
                  return false;
                }
              }(),
            );
            emit_byte(OpCode.METHOD.index);
            emit_byte(constant);
            return make_method(
              name,
              block,
            );
          },
        );
        emit_op(OpCode.POP);
        current_class = current_class!.enclosing;
        return functions;
      },
    );
  }

  @override
  void visit_self_post(
    final NaturalToken name,
  ) {
    if (current_class == null) {
      error_delegate.error_at_previous("Can't use 'this' outside of a class");
    } else {
      visit_getter(name, (final _) {});
    }
  }

  @override
  List<T> visit_block<T>(
    final Iterable<T> Function() fn,
  ) {
    final decls = <T>[];
    wrap_in_scope(
      fn: () {
        for (final x in fn()) {
          decls.add(x);
        }
      },
    );
    return decls;
  }

  @override
  T visit_and<T>(
    final T Function() fn,
  ) {
    final end_jump = emit_jump(OpCode.JUMP_IF_FALSE);
    emit_op(OpCode.POP);
    final res = fn();
    patch_jump(end_jump);
    return res;
  }

  @override
  T visit_or<T>(
    final T Function() fn,
  ) {
    final else_jump = emit_jump(OpCode.JUMP_IF_FALSE);
    final end_jump = emit_jump(OpCode.JUMP);
    patch_jump(else_jump);
    emit_op(OpCode.POP);
    final res = fn();
    patch_jump(end_jump);
    return res;
  }

  @override
  E? visit_getset<E>(
    final NaturalToken name,
    final E Function() expression,
    final bool Function(
      TokenType first,
      TokenType second,
    )
        match_pair,
  ) {
    return visit_getter(
      name,
      (final setter) {
        if (match_pair(TokenType.PLUS, TokenType.EQUAL)) {
          // ignore: unused_local_variable
          final expr = expression();
          setter(OpCode.ADD);
          return expr;
        } else if (match_pair(TokenType.MINUS, TokenType.EQUAL)) {
          // ignore: unused_local_variable
          final expr = expression();
          setter(OpCode.SUBTRACT);
          return expr;
        } else if (match_pair(TokenType.STAR, TokenType.EQUAL)) {
          // ignore: unused_local_variable
          final expr = expression();
          setter(OpCode.MULTIPLY);
          return expr;
        } else if (match_pair(TokenType.SLASH, TokenType.EQUAL)) {
          // ignore: unused_local_variable
          final expr = expression();
          setter(OpCode.DIVIDE);
          return expr;
        } else if (match_pair(TokenType.PERCENT, TokenType.EQUAL)) {
          // ignore: unused_local_variable
          final expr = expression();
          setter(OpCode.MOD);
          return expr;
        } else if (match_pair(TokenType.CARET, TokenType.EQUAL)) {
          // ignore: unused_local_variable
          final expr = expression();
          setter(OpCode.POW);
        } else {
          // Ignore.
          return null;
        }
      },
    );
  }

  @override
  E? visit_bracket<E extends Object>(
    final bool Function() match_colon,
    final E? Function() getter_ish_second,
    final E? Function() setter_ish_second,
    final E Function() expression,
    final E Function(E? first, E? second) getter,
    final E Function(E? first, E? second) setter,
  ) {
    final E? first = () {
      if (match_colon()) {
        emit_constant(Nil);
        return null;
      } else {
        return expression();
      }
    }();
    final getter_ish = () {
      if (first == null) {
        return true;
      } else {
        return match_colon();
      }
    }();
    if (getter_ish) {
      final second = () {
        final _second = getter_ish_second();
        if (_second == null) {
          emit_constant(Nil);
          return null;
        } else {
          return _second;
        }
      }();
      emit_op(OpCode.CONTAINER_GET_RANGE);
      return getter(
        first,
        second,
      );
    } else {
      final _second = () {
        final _second = setter_ish_second();
        if (_second != null) {
          emit_op(OpCode.CONTAINER_SET);
          return _second;
        } else {
          emit_op(OpCode.CONTAINER_GET);
          return null;
        }
      }();
      return setter(
        first,
        _second,
      );
    }
  }

  @override
  void visit_dot_get_post(
    final NaturalToken name_token,
  ) {
    final name = identifier_constant(name_token);
    emit_byte(OpCode.GET_PROPERTY.index);
    emit_byte(name);
  }

  @override
  void visit_string_post(
    final String value,
  ) {
    emit_constant(value);
  }

  @override
  void visit_number_post(
    final String val,
  ) {
    final value = double.tryParse(val);
    if (value == null) {
      error_delegate.error_at_previous('Invalid number');
    } else {
      emit_constant(value);
    }
  }

  @override
  void visit_call_post(
    final int length,
  ) {
    emit_byte(OpCode.CALL.index);
    emit_byte(length);
  }

  @override
  void visit_object_post() {
    emit_constant(null);
  }

  @override
  void visit_not_post() {
    emit_op(OpCode.NOT);
  }

  @override
  void visit_negate_post() {
    emit_op(OpCode.NEGATE);
  }

  @override
  void visit_map_post(
    final int length,
  ) {
    emit_byte(OpCode.MAP_INIT.index);
    emit_byte(length);
  }

  @override
  void visit_subtract_post() {
    emit_op(OpCode.SUBTRACT);
  }

  @override
  void visit_add_post() {
    emit_op(OpCode.ADD);
  }

  @override
  void visit_divide_post() {
    emit_op(OpCode.DIVIDE);
  }

  @override
  void visit_multiply_post() {
    emit_op(OpCode.MULTIPLY);
  }

  @override
  void visit_power_post() {
    emit_op(OpCode.POW);
  }

  @override
  void visit_modulo_post() {
    emit_op(OpCode.MOD);
  }

  @override
  void visit_neq_post() {
    emit_byte(OpCode.EQUAL.index);
    emit_byte(OpCode.NOT.index);
  }

  @override
  void visit_eq_post() {
    emit_op(OpCode.EQUAL);
  }

  @override
  void visit_geq_post() {
    emit_byte(OpCode.LESS.index);
    emit_byte(OpCode.NOT.index);
  }

  @override
  void visit_greater_post() {
    emit_op(OpCode.GREATER);
  }

  @override
  void visit_less_post() {
    emit_op(OpCode.LESS);
  }

  @override
  void visit_leq_post() {
    emit_byte(OpCode.GREATER.index);
    emit_byte(OpCode.NOT.index);
  }

  @override
  void visit_list_init_post(
    final int val_count,
  ) {
    if (val_count >= 0) {
      emit_byte(OpCode.LIST_INIT.index);
      emit_byte(val_count);
    } else {
      emit_byte(OpCode.LIST_INIT_RANGE.index);
    }
  }

  @override
  void pop() {
    emit_op(OpCode.POP);
  }
}

abstract class Compiler {
  // TODO preorder postorder or keep generic fns?
  // region fix
  B visit_fn<D, B>(
    final String Function() name,
    final FunctionType type,
    final List<NaturalToken> Function() args,
    final B Function(D Function() declaration) block,
    final D Function(Compiler compiler) declaration,
  );

  List<T> visit_class<T, B>(
    final NaturalToken class_name,
    final NaturalToken Function() before_class_name,
    final NaturalToken? Function() superclass,
    final List<T> Function(
      T Function(
        NaturalToken,
        B Function(
          bool true_init_false_method,
        ),
      ) fn,
    ) methods,
    final T Function(
      NaturalToken name,
      B block,
    ) make,
  );

  R visit_classic_for<L, E, S, R>(
    final L? Function() left,
    final E? Function() center,
    final E Function()? Function() expr,
    final S Function() stmt,
    final R Function(L?, E?, E?, S) make,
  );

  List<T> visit_block<T>(
    final Iterable<T> Function() fn,
  );

  List<T> visit_var_decl<T>(
    final Iterable<MapEntry<NaturalToken, T Function()>> Function() fn,
  );

  T visit_fun<T>(
    final NaturalToken name,
    final T Function() param1,
  );

  T visit_return_expr<T>(
    final T Function() expression,
  );

  List<T>? visit_super<T>(
    final NaturalToken name_token,
    final List<T>? Function() arg_count,
  );

  E? visit_getset<E>(
    final NaturalToken name,
    final E Function() expression,
    final bool Function(
      TokenType first,
      TokenType second,
    ) match_pair,
  );

  E? visit_bracket<E extends Object>(
    final bool Function() match_colon,
    final E? Function() getter_ish_second,
    final E? Function() setter_ish_second,
    final E Function() expression,
    final E Function(E? first, E? second) getter,
    final E Function(E? first, E? second) setter,
  );

  R visit_while<E, S, R>(
    final E Function() expression,
    final S Function() statement,
    final R Function(E expr, S stmt) make,
  );

  R visit_if<E, S, R>(
    final E Function() condition,
    final S Function() body,
    final S? Function() other,
    final R Function(E, S, S?) make,
  );

  R visit_iter_for<E, S, R>({
    required final NaturalToken key_name,
    required final NaturalToken? value_name,
    required final E Function() iterable,
    required final S Function() body,
    required final R Function(E iterable, S body) make,
  });

  T visit_and<T>(
    final T Function() fn,
  );

  T visit_or<T>(
    final T Function() fn,
  );
  // endregion

  // region all post
  void visit_self_post(
    final NaturalToken name,
  );

  void visit_print_post();

  void visit_set_post(
    final SyntheticToken name,
  );

  void visit_get_post(
    final SyntheticToken name,
  );

  void visit_expr_stmt_post();

  void visit_return_empty_post();

  void visit_nil_post();

  void visit_set_prop_post(
    final NaturalToken name,
  );

  void visit_invoke_post(
    final NaturalToken name_token,
    final int length,
  );

  void visit_truth_post();

  void visit_falsity_post();

  void visit_dot_get_post(
    final NaturalToken name_token,
  );

  void visit_string_post(
    final String value,
  );

  void visit_number_post(
    final String value,
  );

  void visit_call_post(
    final int length,
  );

  void visit_object_post();

  void visit_not_post();

  void visit_negate_post();

  void visit_map_post(
    final int length,
  );

  void visit_subtract_post();

  void visit_add_post();

  void visit_divide_post();

  void visit_multiply_post();

  void visit_power_post();

  void visit_modulo_post();

  void visit_neq_post();

  void visit_eq_post();

  void visit_geq_post();

  void visit_greater_post();

  void visit_less_post();

  void visit_leq_post();

  void visit_list_init_post(
    final int val_count,
  );
  // endregion

  void pop();
}

const UINT8_COUNT = 256;
const UINT8_MAX = UINT8_COUNT - 1;
const UINT16_MAX = 65535;

Local init_local(
  final bool is_function,
) {
  return Local(
    name: SyntheticTokenImpl(
      type: TokenType.FUN,
      lexeme: () {
        if (is_function) {
          return 'this';
        } else {
          return '';
        }
      }(),
    ),
    depth: 0,
    is_captured: false,
  );
}

class Local {
  final SyntheticToken? name;
  int depth;
  bool is_captured;

  Local({
    required final this.name,
    required final this.depth,
    required final this.is_captured,
  });

  bool get initialized {
    return depth >= 0;
  }
}

class Upvalue {
  final SyntheticToken? name;
  final int index;
  final bool is_local;

  const Upvalue({
    required final this.name,
    required final this.index,
    required final this.is_local,
  });
}

enum FunctionType {
  FUNCTION,
  INITIALIZER,
  METHOD,
}

class ClassCompiler {
  final ClassCompiler? enclosing;
  final NaturalToken? name;
  bool has_superclass;

  ClassCompiler({
    required final this.enclosing,
    required final this.name,
    required final this.has_superclass,
  });
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
  final Map<String?, Object?> properties;
  final Map<String, Type>? properties_types;
  final List<String> init_arg_keys;

  ObjNativeClass({
    required this.init_arg_keys,
    this.name,
    this.properties_types,
    final List<Object?>? stack,
    final int? arg_idx,
    final int? arg_count,
  }) : properties = {} {
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
  final Map<dynamic, dynamic> map,
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  if (arg_count != 0) {
    arg_count_error(0, arg_count);
  }
  return map.length.toDouble();
}

List<dynamic> map_keys(
  final Map<dynamic, dynamic> map,
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  if (arg_count != 0) {
    arg_count_error(0, arg_count);
  }
  return map.keys.toList();
}

List<dynamic> map_values(
  final Map<dynamic, dynamic> map,
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  if (arg_count != 0) arg_count_error(0, arg_count);
  return map.values.toList();
}

bool map_has(
  final Map<dynamic, dynamic> map,
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  if (arg_count != 1) {
    arg_count_error(1, arg_count);
  }
  return map.containsKey(stack[arg_idx]);
}

typedef MapNativeFunction = Object Function(
  Map<dynamic, dynamic> list,
  List<Object?> stack,
  int arg_idx,
  int arg_count,
);

const MAP_NATIVE_FUNCTIONS = <String, MapNativeFunction>{
  'length': map_length,
  'keys': map_keys,
  'values': map_values,
  'has': map_has,
};

// String native functions
double str_length(
  final String str,
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  if (arg_count != 0) {
    arg_count_error(0, arg_count);
  }
  return str.length.toDouble();
}

typedef StringNativeFunction = Object Function(
  String list,
  List<Object?> stack,
  int arg_idx,
  int arg_count,
);

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
  final String? name;
  final Chunk chunk;
  int arity;
  int upvalue_count;

  ObjFunction({
    required final this.name,
  })  : upvalue_count = 0,
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
    final this.klass,
    final this.klass_name,
  }) : fields = Table();
}

class ObjBoundMethod {
  Object? receiver;
  ObjClosure method;

  ObjBoundMethod({
    required final this.receiver,
    required final this.method,
  });
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
// endregion
