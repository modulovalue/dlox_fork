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
  final _parser = ParserAtCompiler(
    parser: parser.key,
    error_delegate: parser.value,
  );
  final compiler = CompilerRootImpl(
    type: FunctionType.SCRIPT,
    parser: parser.key,
    error_delegate: parser.value,
    debug_trace_bytecode: trace_bytecode,
  );
  while (!parser.key.match(TokenType.EOF)) {
    _parser.declaration(compiler);
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
              function.name = parser.previous!.lexeme;
              break;
            case FunctionType.INITIALIZER:
              function.name = parser.previous!.lexeme;
              break;
            case FunctionType.METHOD:
              function.name = parser.previous!.lexeme;
              break;
            case FunctionType.SCRIPT:
              break;
          }
          return function;
        }()),
        locals = [
          Local(
            name: SyntheticTokenImpl(
              type: TokenType.FUN,
              lexeme: () {
                if (type != FunctionType.FUNCTION) {
                  return 'this';
                } else {
                  return '';
                }
              }(),
            ),
            depth: 0,
            is_captured: false,
          ),
        ],
        upvalues = [];

  @override
  Null get enclosing => null;

  @override
  int line_provider() {
    return parser.previous!.loc.line;
  }
}

class CompilerWrappedImpl with CompilerMixin {
  @override
  final List<Local> locals;
  @override
  final List<Upvalue> upvalues;
  @override
  final FunctionType type;
  @override
  final CompilerMixin enclosing;
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
              function.name = parser.previous!.lexeme;
              break;
            case FunctionType.INITIALIZER:
              function.name = parser.previous!.lexeme;
              break;
            case FunctionType.METHOD:
              function.name = parser.previous!.lexeme;
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
            name: SyntheticTokenImpl(
              type: TokenType.FUN,
              lexeme: () {
                if (type != FunctionType.FUNCTION) {
                  return 'this';
                } else {
                  return '';
                }
              }(),
            ),
            depth: 0,
            is_captured: false,
          ),
        ],
        upvalues = [];

  @override
  ErrorDelegate get error_delegate => enclosing.error_delegate;

  @override
  int line_provider() {
    return parser.previous!.loc.line;
  }
}

mixin CompilerMixin implements Compiler {
  ObjFunction get function;

  Parser get parser;

  CompilerMixin? get enclosing;

  bool get debug_trace_bytecode;

  abstract int scope_depth;

  List<Local> get locals;

  @override
  List<Upvalue> get upvalues;

  static bool identifiers_equal2(
    final SyntheticToken a,
    final SyntheticToken b,
  ) {
    return a.lexeme == b.lexeme;
  }

  int line_provider();

  ErrorDelegate get error_delegate;

  FunctionType get type;

  @override
  Compiler wrap(
    final FunctionType type,
  ) {
    return CompilerWrappedImpl(
      type: type,
      enclosing: this,
      parser: parser,
    );
  }

  @override
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
    }
    return function;
  }

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

  @override
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

  @override
  void emit_constant(
    final Object? value,
  ) {
    emit_byte(OpCode.CONSTANT.index);
    emit_byte(make_constant(value));
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

  void add_local(
    final SyntheticToken? name,
  ) {
    if (locals.length >= UINT8_COUNT) {
      error_delegate.error_at_previous('Too many local variables in function');
    } else {
      locals.add(Local(name: name,depth: -1,
        is_captured: false,),);
    }
  }

  @override
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
        if (CompilerMixin.identifiers_equal2(name, local.name!)) {
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

  @override
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
  void visit_print() {
    emit_op(OpCode.PRINT);
  }

  @override
  void visit_setter(
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

  @override
  void visit_getter(
    final SyntheticToken name,
    final void Function(void Function(OpCode type) p1) setter,
  ) {
    get_or_set<void>(
      name,
      (final arg, final get_op, final set_op) {
        emit_byte(get_op.index);
        emit_byte(arg);
        setter(
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
  void visit_class_name(
    final NaturalToken class_name,
    final NaturalToken? previous,
  ) {
    final name_constant = identifier_constant(class_name);
    declare_local_variable(class_name);
    emit_byte(OpCode.CLASS.index);
    emit_byte(name_constant);
    define_variable(name_constant);
    final class_compiler = ClassCompiler(
      enclosing: current_class,
      name: previous,
      has_superclass: false,
    );
    current_class = class_compiler;
  }

  @override
  void visit_superclass(
    final SyntheticToken superclass_name,
  ) {
    final class_name = current_class!.name!;
    visit_getter(superclass_name, (final _) {});
    if (CompilerMixin.identifiers_equal2(class_name, superclass_name)) {
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

  @override
  void visit_fn_args(
    final List<NaturalToken> args,
  ) {
    for (final name in args) {
      function.arity++;
      if (function.arity > 255) {
        error_delegate.error_at_current("Can't have more than 255 parameters");
      }
      make_variable(name);
      mark_local_variable_initialized();
    }
    for (int k = 0; k < args.length; k++) {
      define_variable(0, token: args[k], peek_dist: args.length - 1 - k);
    }
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
  void visit_expr_stmt() {
    emit_op(OpCode.POP);
  }

  @override
  void visit_return_empty() {
    emit_return();
  }

  @override
  Expr visit_return_expr(
    final Expr Function() expression,
  ) {
    if (type == FunctionType.INITIALIZER) {
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
    required final Expr Function() iterable,
    required final Stmt Function() body,
    required final R Function(Expr iterable, Stmt body) make,
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
  List<Expr> visit_var_decl(
    final Iterable<MapEntry<NaturalToken, Expr Function()>> Function() fn,
  ) {
    final exprs = <Expr>[];
    for(final x in fn()) {
      final global = make_variable(x.key);
      final made = x.value();
      exprs.add(made);
      define_variable(global, token: x.key);
    }
    return exprs;
  }

  @override
  StmtLoop visit_classic_for(
    final LoopLeft? Function() left,
    final Expr? Function() center,
    final Expr Function()? Function() expr,
    final Stmt Function() stmt,
  ) {
    return wrap_in_scope(
      fn: () {
        final _left = () {
          final _left = left();
          if (_left is LoopLeftExpr) {
            emit_op(OpCode.POP);
          }
          return _left;
        }();
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
        return StmtLoop(
          left: _left,
          center: _center,
          right: _right,
          body: _stmt,
        );
      },
    );
  }

  @override
  Block visit_fun(
    final NaturalToken name,
    final Block Function() block,
  ) {
    final global = make_variable(name);
    mark_local_variable_initialized();
    final _block = block();
    define_variable(global, token: name);
    return _block;
  }

  @override
  ExprNil visit_nil() {
    emit_op(OpCode.NIL);
    return const ExprNil();
  }

  @override
  void visit_set_prop(
    final NaturalToken name,
  ) {
    final _name = identifier_constant(name);
    emit_byte(OpCode.SET_PROPERTY.index);
    emit_byte(_name);
  }

  @override
  void visit_invoke(
    final NaturalToken name_token,
    final int length,
  ) {
    final name = identifier_constant(name_token);
    emit_byte(OpCode.INVOKE.index);
    emit_byte(name);
    emit_byte(length);
  }

  @override
  void visit_super(
    final NaturalToken Function() name_token,
    final int? Function() arg_count,
  ) {
    if (current_class == null) {
      error_delegate.error_at_previous("Can't use 'super' outside of a class");
    } else if (!current_class!.has_superclass) {
      error_delegate.error_at_previous("Can't use 'super' in a class with no superclass");
    }
    final name = identifier_constant(name_token());
    visit_getter(
      const SyntheticTokenImpl(
        type: TokenType.IDENTIFIER,
        lexeme: 'this',
      ),
      (final _) {},
    );
    final _arg_count = arg_count();
    // endregion
    if (_arg_count != null) {
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
      emit_byte(_arg_count);
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
  }

  @override
  Expr visit_truth() {
    emit_op(OpCode.TRUE);
    return ExprTruth();
  }

  @override
  Expr visit_falsity() {
    emit_op(OpCode.FALSE);
    return ExprFalsity();
  }
}

// TODO hide many by removing completely or moving to the mixin.
abstract class Compiler {
  // TODO hide
  abstract ClassCompiler? current_class;

  Iterable<Upvalue> get upvalues;

  // TODO hide
  T wrap_in_scope<T>({
    required final T Function() fn,
  });

  Compiler wrap(
    final FunctionType type,
  );

  // TODO hide?
  ObjFunction end_compiler();

  void emit_op(
    final OpCode op,
  );

  // TODO hide
  void emit_byte(
    final int byte,
  );

  // TODO hide
  int emit_jump(
    final OpCode instruction,
  );

  // TODO hide
  void emit_constant(
    final Object? value,
  );

  // TODO hide
  void patch_jump(
    final int offset,
  );

  // TODO hide
  int identifier_constant(
    final SyntheticToken name,
  );

  void visit_print();

  void visit_setter(
    final SyntheticToken name,
  );

  void visit_getter(
    final SyntheticToken name,
    final void Function(void Function(OpCode type)) setter,
  );

  void visit_superclass(
    final SyntheticToken superclass_name,
  );

  void visit_class_name(
    final NaturalToken class_name,
    final NaturalToken? previous,
  );

  void visit_fn_args(
    final List<NaturalToken> args,
  );

  R visit_while<E, S, R>(
    final E Function() expression,
    final S Function() statement,
    final R Function(E expr, S stmt) make,
  );

  void visit_expr_stmt();

  void visit_return_empty();

  Expr visit_return_expr(
    final Expr Function() expression,
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
    required final Expr Function() iterable,
    required final Stmt Function() body,
    required final R Function(Expr iterable, Stmt body) make,
  });

  List<Expr> visit_var_decl(
    final Iterable<MapEntry<NaturalToken, Expr Function()>> Function() fn,
  );

  StmtLoop visit_classic_for(
    final LoopLeft? Function() left,
    final Expr? Function() center,
    final Expr Function()? Function() expr,
    final Stmt Function() stmt,
  );

  Block visit_fun(
    final NaturalToken name,
    final Block Function() param1,
  );

  ExprNil visit_nil();

  void visit_set_prop(
    final NaturalToken name,
  );

  void visit_invoke(
    final NaturalToken name_token,
    final int length,
  );

  void visit_super(
    final NaturalToken Function() name_token,
    final int? Function() arg_count,
  );

  Expr visit_truth();

  Expr visit_falsity();
}

const UINT8_COUNT = 256;
const UINT8_MAX = UINT8_COUNT - 1;
const UINT16_MAX = 65535;

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
  SCRIPT,
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

// region parser
// TODO * finish parsing into an ast
// TODO * interpret ast
class ParserAtCompiler {
  final Parser parser;
  final ErrorDelegate error_delegate;

  const ParserAtCompiler({
    required final this.parser,
    required final this.error_delegate,
  });

  Declaration declaration(
    final Compiler compiler,
  ) {
    Expr expression() {
      Expr? parse_precedence(
        final Precedence precedence,
      ) {
        final can_assign = precedence.index <= Precedence.ASSIGNMENT.index;
        parser.advance();
        final Expr? Function()? prefix_rule = () {
          switch (parser.previous!.type) {
            case TokenType.LEFT_PAREN:
              return () {
                // TODO visit and expr
                final expr = expression();
                parser.consume(TokenType.RIGHT_PAREN, "Expect ')' after expression");
                return expr;
              };
            case TokenType.LEFT_BRACE:
              return () {
                // TODO visit
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
                  } while (parser.match(TokenType.COMMA));
                }
                parser.consume(TokenType.RIGHT_BRACE, "Expect '}' after map initializer");
                // region emitter
                compiler.emit_byte(OpCode.MAP_INIT.index);
                compiler.emit_byte(entries.length);
                // endregion
                return ExprMap(
                  entries: entries,
                );
              };
            case TokenType.LEFT_BRACK:
              return () {
                // TODO visit
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
                  compiler.emit_byte(OpCode.LIST_INIT.index);
                  compiler.emit_byte(val_count);
                } else {
                  compiler.emit_byte(OpCode.LIST_INIT_RANGE.index);
                }
                // endregion
                return ExprList(
                  values: values,
                  val_count: val_count,
                );
              };
            case TokenType.MINUS:
              return () {
                // TODO visit and expr
                final expr = parse_precedence(Precedence.UNARY);
                // region emitter
                compiler.emit_op(OpCode.NEGATE);
                // endregion
                return expr;
              };
            case TokenType.BANG:
              return () {
                // TODO visit and expr
                final expr = parse_precedence(Precedence.UNARY);
                // region emitter
                compiler.emit_op(OpCode.NOT);
                // endregion
                return expr;
              };
            case TokenType.IDENTIFIER:
              return () {
                // TODO visit and expr
                if (can_assign) {
                  final name = parser.previous!;
                  if (parser.match(TokenType.EQUAL)) {
                    // ignore: unused_local_variable
                    final expr = expression();
                    compiler.visit_setter(name);
                  } else {
                    compiler.visit_getter(
                      name,
                      (final setter) {
                        if (parser.match_pair(TokenType.PLUS, TokenType.EQUAL)) {
                          // ignore: unused_local_variable
                          final expr = expression();
                          setter(OpCode.ADD);
                        } else if (parser.match_pair(TokenType.MINUS, TokenType.EQUAL)) {
                          // ignore: unused_local_variable
                          final expr = expression();
                          setter(OpCode.SUBTRACT);
                        } else if (parser.match_pair(TokenType.STAR, TokenType.EQUAL)) {
                          // ignore: unused_local_variable
                          final expr = expression();
                          setter(OpCode.MULTIPLY);
                        } else if (parser.match_pair(TokenType.SLASH, TokenType.EQUAL)) {
                          // ignore: unused_local_variable
                          final expr = expression();
                          setter(OpCode.DIVIDE);
                        } else if (parser.match_pair(TokenType.PERCENT, TokenType.EQUAL)) {
                          // ignore: unused_local_variable
                          final expr = expression();
                          setter(OpCode.MOD);
                        } else if (parser.match_pair(TokenType.CARET, TokenType.EQUAL)) {
                          // ignore: unused_local_variable
                          final expr = expression();
                          setter(OpCode.POW);
                        } else {
                          // Ignore.
                        }
                      },
                    );
                  }
                } else {
                  compiler.visit_getter(parser.previous!, (final _) {});
                }
              };
            case TokenType.STRING:
              return () {
                // TODO visit and expr
                // region emitter
                compiler.emit_constant(parser.previous!.lexeme);
                // endregion
              };
            case TokenType.NUMBER:
              return () {
                // TODO visit and expr
                final value = double.tryParse(parser.previous!.lexeme!);
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
                // TODO visit and expr
                // region emitter
                compiler.emit_constant(null);
                // endregion
              };
            case TokenType.SUPER:
              return () {
                // TODO expr
                compiler.visit_super(
                  () {
                    parser.consume(TokenType.DOT, "Expect '.' after 'super'");
                    parser.consume(TokenType.IDENTIFIER, 'Expect superclass method name');
                    return parser.previous!;
                  },
                  () {
                    if (parser.match(TokenType.LEFT_PAREN)) {
                      return parser.parse_argument_list(expression).args.length;
                    } else {
                      return null;
                    }
                  },
                );
              };
            case TokenType.THIS:
              return () {
                // TODO visit and expr
                if (compiler.current_class == null) {
                  error_delegate.error_at_previous("Can't use 'this' outside of a class");
                } else {
                  compiler.visit_getter(parser.previous!, (final _) {});
                }
              };
            case TokenType.FALSE:
              return () => compiler.visit_falsity();
            case TokenType.NIL:
              return () => compiler.visit_nil();
            case TokenType.TRUE:
              return () => compiler.visit_truth();
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
                  final args = parser.parse_argument_list(expression);
                  // region emitter
                  compiler.emit_byte(OpCode.CALL.index);
                  compiler.emit_byte(args.args.length);
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
                    compiler.visit_set_prop(name_token);
                    return ExprSet(arg: expr, name: name_token);
                  } else if (parser.match(TokenType.LEFT_PAREN)) {
                    final args = parser.parse_argument_list(expression);
                    compiler.visit_invoke(name_token, args.args.length);
                    return ExprInvoke(args: args, name: name_token);
                  } else {
                    // region emitter
                    final name = compiler.identifier_constant(name_token);
                    compiler.emit_byte(OpCode.GET_PROPERTY.index);
                    compiler.emit_byte(name);
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
                  compiler.emit_byte(OpCode.EQUAL.index);
                  compiler.emit_byte(OpCode.NOT.index);
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
                  compiler.emit_byte(OpCode.LESS.index);
                  compiler.emit_byte(OpCode.NOT.index);
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
                  compiler.emit_byte(OpCode.GREATER.index);
                  compiler.emit_byte(OpCode.NOT.index);
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

    DeclarationVari var_declaration() {
      return DeclarationVari(
        exprs: () {
          final exprs = compiler.visit_var_decl(
            () sync* {
              for(;;) {
                parser.consume(TokenType.IDENTIFIER, 'Expect variable name');
                yield MapEntry(
                  parser.previous!,
                  () {
                    if (parser.match(TokenType.EQUAL)) {
                      return expression();
                    } else {
                      return compiler.visit_nil();
                    }
                  },
                );
                if (parser.match(TokenType.COMMA)) {
                  continue;
                } else {
                  break;
                }
              }
            },
          );
          parser.consume(TokenType.SEMICOLON, 'Expect a newline after variable declaration');
          return exprs;
        }(),
      );
    }

    Stmt statement() {
      if (parser.match(TokenType.PRINT)) {
        final expr = expression();
        parser.consume(TokenType.SEMICOLON, 'Expect a newline after value');
        compiler.visit_print();
        return StmtOutput(
          expr: expr,
        );
      } else if (parser.match(TokenType.FOR)) {
        if (parser.match(TokenType.LEFT_PAREN)) {
          return compiler.visit_classic_for(
            () {
              if (parser.match(TokenType.SEMICOLON)) {
                return null;
              } else if (parser.match(TokenType.VAR)) {
                return LoopLeftVari(
                  decl: var_declaration(),
                );
              } else {
                final expr = expression();
                parser.consume(TokenType.SEMICOLON, 'Expect a newline after expression');
                return LoopLeftExpr(
                  expr: expr,
                );
              }
            },
            () {
              if (parser.match(TokenType.SEMICOLON)) {
                return null;
              } else {
                final expr = expression();
                parser.consume(TokenType.SEMICOLON, "Expect ';' after loop condition");
                return expr;
              }
            },
            () {
              if (parser.match(TokenType.RIGHT_PAREN)) {
                return null;
              } else {
                return () {
                  final expr = expression();
                  parser.consume(TokenType.RIGHT_PAREN, "Expect ')' after for clauses");
                  return expr;
                };
              }
            },
            statement,
          );
        } else {
          final key_name = () {
            parser.consume(TokenType.IDENTIFIER, 'Expect variable name');
            return parser.previous!;
          }();
          final value_name = () {
            if (parser.match(TokenType.COMMA)) {
              parser.consume(TokenType.IDENTIFIER, 'Expect variable name');
              return parser.previous!;
            } else {
              return null;
            }
          }();
          parser.consume(TokenType.IN, "Expect 'in' after loop variables");
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
      } else if (parser.match(TokenType.IF)) {
        return compiler.visit_if<Expr, Stmt, StmtConditional>(
          expression,
          statement,
          () {
            if (parser.match(TokenType.ELSE)) {
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
      } else if (parser.match(TokenType.RETURN)) {
        if (parser.match(TokenType.SEMICOLON)) {
          compiler.visit_return_empty();
          return const StmtRet(
            expr: null,
          );
        } else {
          return StmtRet(
            expr: compiler.visit_return_expr(
              () {
                final expr = expression();
                parser.consume(TokenType.SEMICOLON, 'Expect a newline after return value');
                return expr;
              },
            ),
          );
        }
      } else if (parser.match(TokenType.WHILE)) {
        return compiler.visit_while<Expr, Stmt, Stmt>(
          expression,
          statement,
          (final expr, final stmt) => StmtWhil(
            expr: expr,
            stmt: stmt,
          ),
        );
      } else if (parser.match(TokenType.LEFT_BRACE)) {
        return StmtBlock(
          block: Block(
            decls: compiler.wrap_in_scope(
              fn: () {
                final decls = <Declaration>[];
                while (!parser.check(TokenType.RIGHT_BRACE) && !parser.check(TokenType.EOF)) {
                  decls.add(declaration(compiler));
                }
                parser.consume(TokenType.RIGHT_BRACE, 'Unterminated block');
                return decls;
              },
            ),
          ),
        );
      } else {
        final expr = expression();
        parser.consume(TokenType.SEMICOLON, 'Expect a newline after expression');
        // region emitter
        compiler.visit_expr_stmt();
        // endregion
        return StmtExpr(
          expr: expr,
        );
      }
    }

    Block function_block(
      final FunctionType type,
    ) {
      // TODO visit fn hide wrap, visit_fn_args and end_compiler from here.
      final new_compiler = compiler.wrap(type);
      parser.consume(TokenType.LEFT_PAREN, "Expect '(' after function name");
      final args = <NaturalToken>[];
      if (!parser.check(TokenType.RIGHT_PAREN)) {
        argloop: for(;;) {
          parser.consume(TokenType.IDENTIFIER, 'Expect parameter name');
          args.add(parser.previous!);
          if (parser.match(TokenType.COMMA)) {
            continue argloop;
          } else {
            break argloop;
          }
        }
      }
      new_compiler.visit_fn_args(args);
      parser.consume(TokenType.RIGHT_PAREN, "Expect ')' after parameters");
      parser.consume(TokenType.LEFT_BRACE, 'Expect function body');
      final block = Block(
        decls: () {
          final decls = <Declaration>[];
          while (!parser.check(TokenType.RIGHT_BRACE) && !parser.check(TokenType.EOF)) {
            final decl = declaration(new_compiler);
            decls.add(decl);
          }
          parser.consume(TokenType.RIGHT_BRACE, 'Unterminated block');
          return decls;
        }(),
      );
      new_compiler.end_compiler();
      return block;
    }

    Declaration parse_decl() {
      if (parser.match(TokenType.CLASS)) {
        parser.consume(TokenType.IDENTIFIER, 'Expect class name');
        final class_name = parser.previous!;
        // region emitter
        compiler.visit_class_name(class_name, parser.previous);
        // endregion
        return compiler.wrap_in_scope(
          fn: () {
            if (parser.match(TokenType.LESS)) {
              parser.consume(TokenType.IDENTIFIER, 'Expect superclass name');
              // region emitter
              compiler.visit_superclass(parser.previous!);
              // endregion
            }
            // region emitter
            compiler.visit_getter(class_name, (final _) {});
            // endregion
            parser.consume(TokenType.LEFT_BRACE, 'Expect class body');
            final functions = <Method>[];
            while (!parser.check(TokenType.RIGHT_BRACE) && !parser.check(TokenType.EOF)) {
              parser.consume(TokenType.IDENTIFIER, 'Expect method name');
              // region emitter
              final method_name = parser.previous!;
              final constant = compiler.identifier_constant(method_name);
              // endregion
              functions.add(
                Method(
                  block: function_block(
                    () {
                      if (method_name.lexeme == 'init') {
                        return FunctionType.INITIALIZER;
                      } else {
                        return FunctionType.METHOD;
                      }
                    }(),
                  ),
                  name: method_name,
                ),
              );
              // region emitter
              compiler.emit_byte(OpCode.METHOD.index);
              compiler.emit_byte(constant);
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
        parser.consume(TokenType.IDENTIFIER, 'Expect function name');
        final name = parser.previous!;
        final block = compiler.visit_fun(
          name,
          () => function_block(FunctionType.FUNCTION),
        );
        return DeclarationFun(
          block: block,
          name: name,
        );
      } else if (parser.match(TokenType.VAR)) {
        return var_declaration();
      } else {
        return DeclarationStmt(
          stmt: statement(),
        );
      }
    }

    final decl = parse_decl();
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
        buf.write(' at \'${token!.lexeme}\'');
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

  const CompilerError({
    required final this.token,
    required final this.msg,
  });

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
    // TODO: clone object instances.
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
  // TODO: confirm behavior (especially for deep equality).
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
