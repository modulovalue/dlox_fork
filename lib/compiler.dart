import 'models/ast.dart';
import 'models/errors.dart';
import 'models/objfunction.dart';
import 'models/op_code.dart';
import 'parser.dart';

ObjFunction run_dlox_compiler({
  required final List<Token> tokens,
  required final Debug debug,
  required final bool trace_bytecode,
}) {
  final parser = make_parser(
    tokens: tokens,
    debug: debug,
  );
  // TODO parser should return a compilation unit
  final fn = compile_dlox(
    parser: parser.key,
    error_delegate: parser.value,
    trace_bytecode: trace_bytecode,
  );
  // final compilation_unit = fn.key;
  // TODO transform compilation unit to ObjFunction.
  return fn.value;
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
    error_delegate: error_delegate,
    debug_trace_bytecode: trace_bytecode,
  );
  final compilation_unit = parser.parse_compilation_unit(
    compiler: compiler,
  );
  return MapEntry(
    compilation_unit,
    compiler.compile(parser.previous_line),
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

  CompilerRootImpl({
    required final this.error_delegate,
    required final this.debug_trace_bytecode,
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

  CompilerWrappedImpl({
    required final this.is_initializer,
    required final this.enclosing,
    required final this.function,
    required final Local local,
  })  : current_class = enclosing.current_class,
        scope_depth = enclosing.scope_depth + 1,
        locals = [
          local,
        ],
        upvalues = [];

  @override
  bool get debug_trace_bytecode => enclosing.debug_trace_bytecode;

  @override
  ErrorDelegate get error_delegate => enclosing.error_delegate;
}

mixin CompilerMixin implements Compiler {
  abstract ClassCompiler? current_class;

  abstract int scope_depth;

  ObjFunction get function;

  CompilerMixin? get enclosing;

  bool get debug_trace_bytecode;

  List<Local> get locals;

  List<Upvalue> get upvalues;

  ErrorDelegate get error_delegate;

  bool get is_initializer;

  // region infrastructure
  // TODO remove once chunk emitters are complete.
  void emit_byte(
    final int byte,
    final int line_number,
  ) {
    function.chunk.write(byte, line_number);
  }

  void emit_loop(
    final Token previous,
    final int loop_start,
    final int line,
  ) {
    final offset = function.chunk.count - loop_start + 3;
    if (offset > UINT16_MAX) {
      error_delegate.error_at(previous, 'Loop body too large');
    }
    function.chunk.emit_loop(offset, line);
  }

  int make_constant(
    final Token token,
    final Object? value,
  ) {
    final constant = function.chunk.add_constant(value);
    if (constant > UINT8_MAX) {
      error_delegate.error_at(token, 'Too many constants in one chunk');
      return 0;
    } else {
      return constant;
    }
  }

  void patch_jump(
    final Token token,
    final int offset,
  ) {
    final jump = function.chunk.count - offset - 2;
    if (jump > UINT16_MAX) {
      error_delegate.error_at(token, 'Too much code to jump over');
    }
    function.chunk.code[offset] = (jump >> 8) & 0xff;
    function.chunk.code[offset + 1] = jump & 0xff;
  }

  void add_local(
    final Token name,
  ) {
    if (locals.length >= UINT8_COUNT) {
      error_delegate.error_at(name, 'Too many local variables in function');
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

  int? resolve_local(
    final Token name,
  ) {
    for (int i = locals.length - 1; i >= 0; i--) {
      final local = locals[i];
      if (name.lexeme == local.name.lexeme) {
        if (!local.initialized) {
          error_delegate.error_at(name, 'Can\'t read local variable in its own initializer');
        }
        return i;
      } else {
        continue;
      }
    }
    return null;
  }

  int add_upvalue(
    final Token name,
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
      error_delegate.error_at(name, 'Too many closure variables in function');
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
    final Token name,
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
    required final int line,
    final int peek_dist = 0,
  }) {
    final is_local = scope_depth > 0;
    if (is_local) {
      mark_local_variable_initialized();
    } else {
      emit_byte(OpCode.DEFINE_GLOBAL.index, line);
      emit_byte(global, line);
    }
  }

  void declare_local_variable(
    final Token name,
  ) {
    // Global variables are implicitly declared.
    if (scope_depth != 0) {
      for (int i = locals.length - 1; i >= 0; i--) {
        final local = locals[i];
        if (local.depth != -1 && local.depth < scope_depth) {
          break; // [negative]
        }
        if (name.lexeme == local.name.lexeme) {
          error_delegate.error_at(name, 'Already variable with this name in this scope');
        }
      }
      add_local(name);
    }
  }

  int make_variable(
    final Token name,
  ) {
    if (scope_depth > 0) {
      declare_local_variable(name);
      return 0;
    } else {
      return make_constant(name, name.lexeme);
    }
  }
  // endregion

  ObjFunction end_compiler(
    final int line,
  ) {
    if (is_initializer) {
      function.chunk.emit_return_local(line);
    } else {
      function.chunk.emit_return_nil(line);
    }
    if (error_delegate.debug.errors.isEmpty && debug_trace_bytecode) {
      error_delegate.debug.disassemble_chunk(function.chunk, function.name ?? '<script>');
    }
    if (enclosing != null) {
      final _enclosing = enclosing!;
      _enclosing.emit_byte(OpCode.CLOSURE.index, line);
      _enclosing.emit_byte(
        _enclosing.make_constant(
          const TokenImpl(type: TokenType.IDENTIFIER, lexeme: "INVALID", loc: LocImpl(-1)),
          function,
        ),
        line,
      );
      for (final x in this.upvalues) {
        _enclosing.emit_byte(
              () {
            if (x.is_local) {
              return 1;
            } else {
              return 0;
            }
          }(),
          line,
        );
        _enclosing.emit_byte(x.index, line);
      }
      return function;
    } else {
      return function;
    }
  }

  @override
  void visit_fn(
    final FunctionType type,
    final Functiony block,
    final int line,
  ) {
    final new_compiler = CompilerWrappedImpl(
      function: ObjFunction(
        name: block.name,
      ),
      is_initializer: type == FunctionType.INITIALIZER,
      local: init_local(type != FunctionType.FUNCTION),
      enclosing: this,
    );
    for (final name in block.args) {
      new_compiler.function.arity++;
      if (new_compiler.function.arity > 255) {
        new_compiler.error_delegate.error_at(name, "Can't have more than 255 parameters");
      }
      new_compiler.make_variable(name);
      new_compiler.mark_local_variable_initialized();
    }
    for (int k = 0; k < block.args.length; k++) {
      new_compiler.define_variable(0, peek_dist: block.args.length - 1 - k, line: line);
    }
    block.decls = block.make_decls(new_compiler);
    new_compiler.end_compiler(line);
  }

  @override
  void visit_method(
    final Method a,
  ) {
    visit_fn(
      () {
        if (a.name.lexeme == 'init') {
          return FunctionType.INITIALIZER;
        } else {
          return FunctionType.METHOD;
        }
      }(),
      a.block,
      a.line,
    );
    final line = a.line;
    emit_byte(OpCode.METHOD.index, line);
    emit_byte(make_constant(a.name, a.name.lexeme), line);
  }

  @override
  void compile_declaration(
    final Declaration decl,
  ) {
    MapEntry<int, MapEntry<OpCode, OpCode>> get_or_set(
      final Token name,
    ) {
      int? arg = resolve_local(name);
      OpCode get_op;
      OpCode set_op;
      if (arg == null) {
        final resolved_arg = resolve_upvalue(name);
        if (resolved_arg == null) {
          arg = make_constant(name, name.lexeme);
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
      return MapEntry(
        arg,
        MapEntry(
          get_op,
          set_op,
        ),
      );
    }

    MapEntry<int, OpCode> visit_getter(
      final Token name,
      final int line,
    ) {
      final data = get_or_set(name);
      emit_byte(data.value.key.index, line);
      emit_byte(data.key, line);
      return MapEntry(data.key, data.value.value);
    }

    void compile_expr(
      final Expr expr,
    ) {
      final self = compile_expr;
      match_expr<void>(
        expr: expr,
        string: (final a) {
          final line = a.line;
          function.chunk.emit_constant(make_constant(a.token, a.token.lexeme), line);
        },
        number: (final a) {
          final value = double.tryParse(a.value.lexeme);
          if (value == null) {
            error_delegate.error_at(a.value, 'Invalid number');
          } else {
            final line = a.line;
            function.chunk.emit_constant(make_constant(a.value, value), line);
          }
        },
        object: (final a) {
          final line = a.line;
          function.chunk.emit_constant(make_constant(a.token, null), line);
        },
        self: (final a) {
          if (current_class == null) {
            error_delegate.error_at(a.previous, "Can't use 'this' outside of a class");
          } else {
            visit_getter(a.previous, a.line);
          }
        },
        nil: (final a) {
          emit_byte(OpCode.NIL.index, a.line);
        },
        falsity: (final a) {
          emit_byte(OpCode.FALSE.index, a.line);
        },
        truth: (final a) {
          emit_byte(OpCode.TRUE.index, a.line);
        },
        get: (final a) {
          final name = make_constant(a.name, a.name.lexeme);
          final line = a.line;
          emit_byte(OpCode.GET_PROPERTY.index, line);
          emit_byte(name, line);
        },
        set2: (final a) {
          self(a.arg);
          final data = get_or_set(a.name);
          final line = a.line;
          emit_byte(data.value.value.index, line);
          emit_byte(data.key, line);
        },
        negated: (final a) {
          self(a.child);
          emit_byte(OpCode.NEGATE.index, a.line);
        },
        not: (final a) {
          self(a.child);
          emit_byte(OpCode.NOT.index, a.line);
        },
        call: (final a) {
          for (final x in a.args) {
            self(x);
          }
          final line = a.line;
          emit_byte(OpCode.CALL.index, line);
          emit_byte(a.args.length, line);
        },
        set: (final a) {
          self(a.arg);
          final line = a.line;
          emit_byte(OpCode.SET_PROPERTY.index, line);
          emit_byte(make_constant(a.name, a.name.lexeme), line);
        },
        invoke: (final a) {
          for (final x in a.args) {
            self(x);
          }
          final line = a.line;
          emit_byte(OpCode.INVOKE.index, line);
          emit_byte(make_constant(a.name, a.name.lexeme), line);
          emit_byte(a.args.length, line);
        },
        map: (final a) {
          for (final x in a.entries) {
            self(x.key);
            self(x.value);
          }
          final line = a.line;
          emit_byte(OpCode.MAP_INIT.index, line);
          emit_byte(a.entries.length, line);
        },
        list: (final a) {
          for (final x in a.values) {
            self(x);
          }
          final line = a.line;
          if (a.val_count >= 0) {
            emit_byte(OpCode.LIST_INIT.index, line);
            emit_byte(a.val_count, line);
          } else {
            emit_byte(OpCode.LIST_INIT_RANGE.index, line);
          }
        },
        minus: (final a) {
          self(a.child);
          emit_byte(OpCode.SUBTRACT.index, a.line);
        },
        plus: (final a) {
          self(a.child);
          emit_byte(OpCode.ADD.index, a.line);
        },
        slash: (final a) {
          self(a.child);
          emit_byte(OpCode.DIVIDE.index, a.line);
        },
        star: (final a) {
          self(a.child);
          emit_byte(OpCode.MULTIPLY.index, a.line);
        },
        g: (final a) {
          self(a.child);
          emit_byte(OpCode.GREATER.index, a.line);
        },
        geq: (final a) {
          self(a.child);
          final line = a.line;
          emit_byte(OpCode.LESS.index, line);
          emit_byte(OpCode.NOT.index, line);
        },
        l: (final a) {
          self(a.child);
          emit_byte(OpCode.LESS.index, a.line);
        },
        leq: (final a) {
          self(a.child);
          final line = a.line;
          emit_byte(OpCode.GREATER.index, line);
          emit_byte(OpCode.NOT.index, line);
        },
        pow: (final a) {
          self(a.child);
          emit_byte(OpCode.POW.index, a.line);
        },
        modulo: (final a) {
          self(a.child);
          emit_byte(OpCode.MOD.index, a.line);
        },
        neq: (final a) {
          self(a.child);
          final line = a.line;
          emit_byte(OpCode.EQUAL.index, line);
          emit_byte(OpCode.NOT.index, line);
        },
        eq: (final a) {
          self(a.child);
          emit_byte(OpCode.EQUAL.index, a.line);
        },
        expected: (final a) {},
        getset2: (final a) {
          final arg = a.child;
          final line = a.line;
          final data = visit_getter(a.name, line);
          if (arg != null) {
            switch (arg.type) {
              case GetsetType.pluseq:
                self(arg.child);
                emit_byte(OpCode.ADD.index, line);
                emit_byte(data.value.index, line);
                emit_byte(data.key, line);
                break;
              case GetsetType.minuseq:
                self(arg.child);
                emit_byte(OpCode.SUBTRACT.index, line);
                emit_byte(data.value.index, line);
                emit_byte(data.key, line);
                break;
              case GetsetType.stareq:
                self(arg.child);
                emit_byte(OpCode.MULTIPLY.index, line);
                emit_byte(data.value.index, line);
                emit_byte(data.key, line);
                break;
              case GetsetType.slasheq:
                self(arg.child);
                emit_byte(OpCode.DIVIDE.index, line);
                emit_byte(data.value.index, line);
                emit_byte(data.key, line);
                break;
              case GetsetType.poweq:
                self(arg.child);
                emit_byte(OpCode.POW.index, line);
                emit_byte(data.value.index, line);
                emit_byte(data.key, line);
                break;
              case GetsetType.modeq:
                self(arg.child);
                emit_byte(OpCode.MOD.index, line);
                emit_byte(data.value.index, line);
                emit_byte(data.key, line);
                break;
            }
          }
        },
        and: (final a) {
          final line = a.line;
          final end_jump = function.chunk.emit_jump_if_false(
            line,
          );
          emit_byte(OpCode.POP.index, line);
          self(a.child);
          patch_jump(a.token, end_jump);
        },
        or: (final a) {
          final line = a.line;
          final else_jump = function.chunk.emit_jump_if_false(
            line,
          );
          final end_jump = function.chunk.emit_jump(
            line,
          );
          patch_jump(a.token, else_jump);
          emit_byte(OpCode.POP.index, line);
          self(a.child);
          patch_jump(a.token, end_jump);
        },
        listgetter: (final a) {
          final line = a.line;
          if (a.first != null) {
            self(a.first!);
          } else {
            function.chunk.emit_constant(make_constant(a.first_token, Nil), line);
          }
          if (a.second != null) {
            self(a.second!);
          } else {
            function.chunk.emit_constant(make_constant(a.second_token, Nil), line);
          }
          emit_byte(OpCode.CONTAINER_GET_RANGE.index, line);
        },
        listsetter: (final a) {
          final line = a.line;
          if (a.first != null) {
            self(a.first!);
          } else {
            function.chunk.emit_constant(make_constant(a.token, Nil), line);
          }
          if (a.second != null) {
            self(a.second!);
            emit_byte(OpCode.CONTAINER_SET.index, line);
          } else {
            emit_byte(OpCode.CONTAINER_GET.index, line);
          }
        },
        superaccess: (final a) {
          if (current_class == null) {
            error_delegate.error_at(a.kw, "Can't use 'super' outside of a class");
          } else if (!current_class!.has_superclass) {
            error_delegate.error_at(a.kw, "Can't use 'super' in a class with no superclass");
          }
          final name = make_constant(a.kw, a.kw.lexeme);
          final line = a.line;
          visit_getter(const TokenImpl(type: TokenType.IDENTIFIER, lexeme: 'this', loc: LocImpl(-1)), line);
          final _args = a.args;
          if (_args != null) {
            for (final x in _args) {
              self(x);
            }
          }
          visit_getter(const TokenImpl(type: TokenType.IDENTIFIER, lexeme: 'super', loc: LocImpl(-1)), line);
          if (_args != null) {
            emit_byte(OpCode.SUPER_INVOKE.index, line);
            emit_byte(name, line);
            emit_byte(_args.length, line);
          } else {
            emit_byte(OpCode.GET_SUPER.index, line);
            emit_byte(name, line);
          }
        },
        composite: (final a) {
          for (final x in a.exprs) {
            self(x);
          }
        },
      );
    }

    void compile_vari(
      final DeclarationVari a,
    ) {
      for (final x in a.exprs) {
        final global = make_variable(x.key);
        compile_expr(x.value);
        define_variable(global, line: a.line);
      }
    }

    T wrap_in_scope<T>({
      required final T Function() fn,
      required final int line,
    }) {
      scope_depth++;
      final val = fn();
      scope_depth--;
      while (locals.isNotEmpty && locals.last.depth > scope_depth) {
        if (locals.last.is_captured) {
          emit_byte(OpCode.CLOSE_UPVALUE.index, line);
        } else {
          emit_byte(OpCode.POP.index, line);
        }
        locals.removeLast();
      }
      return val;
    }

    void compile_stmt(
      final Stmt stmt,
    ) {
      stmt.match(
        output: (final a) {
          compile_expr(a.expr);
          emit_byte(OpCode.PRINT.index, a.line);
        },
        ret: (final a) {
          final expr = a.expr;
          if (expr == null) {
            final line = a.line;
            if (is_initializer) {
              function.chunk.emit_return_local(line);
            } else {
              function.chunk.emit_return_nil(line);
            }
          } else {
            if (is_initializer) {
              error_delegate.error_at(a.kw, "Can't return a value from an initializer");
            }
            compile_expr(expr);
            emit_byte(OpCode.RETURN.index, a.line);
          }
        },
        expr: (final a) {
          compile_expr(a.expr);
          emit_byte(OpCode.POP.index, a.line);
        },
        loop: (final a) => wrap_in_scope(
          fn: () {
            final left = a.left;
            final line = a.line;
            if (left != null) {
              left.match(
                vari: (final a) {
                  compile_vari(
                    a.decl,
                  );
                },
                expr: (final a) {
                  compile_expr(a.expr);
                  emit_byte(OpCode.POP.index, line);
                },
              );
            }
            int loop_start = function.chunk.count;
            int exit_jump = -1;
            final center = a.center;
            if (center != null) {
              compile_expr(center);
              exit_jump = function.chunk.emit_jump_if_false(
                line,
              );
              emit_byte(OpCode.POP.index, line); // Condition.
            }
            final _right = a.right;
            if (_right != null) {
              final body_jump = function.chunk.emit_jump(
                line,
              );
              final increment_start = function.chunk.count;
              final _expr = _right;
              compile_expr(_expr);
              emit_byte(OpCode.POP.index, line);
              emit_loop(a.right_kw, loop_start, line);
              loop_start = increment_start;
              patch_jump(a.right_kw, body_jump);
            }
            final _stmt = a.body;
            compile_stmt(_stmt);
            emit_loop(a.end_kw, loop_start, line);
            if (exit_jump != -1) {
              patch_jump(a.end_kw, exit_jump);
              emit_byte(OpCode.POP.index, line); // Condition.
            }
          },
          line: a.line,
        ),
        loop2: (final a) => wrap_in_scope(
          fn: () {
            make_variable(a.key_name);
            final line = a.line;
            emit_byte(OpCode.NIL.index, line);
            define_variable(0, line: line); // Remove 0
            final stack_idx = locals.length - 1;
            final value_name = a.value_name;
            if (value_name != null) {
              make_variable(value_name);
              emit_byte(OpCode.NIL.index, line);
              define_variable(0, line: line);
            } else {
              add_local(const TokenImpl(type: TokenType.IDENTIFIER, lexeme: '_for_val_', loc: LocImpl(-1)));
              // Emit a zero to permute val & key
              function.chunk.emit_constant(
                make_constant(const TokenImpl(type: TokenType.IDENTIFIER, lexeme: "INVALID", loc: LocImpl(-1)), 0),
                line,
              );
              mark_local_variable_initialized();
            }
            // Now add two dummy local variables. Idx & entries
            add_local(const TokenImpl(type: TokenType.IDENTIFIER, lexeme: '_for_idx_', loc: LocImpl(-1)));
            emit_byte(OpCode.NIL.index, line);
            mark_local_variable_initialized();
            add_local(const TokenImpl(type: TokenType.IDENTIFIER, lexeme: '_for_iterable_', loc: LocImpl(-1)));
            emit_byte(OpCode.NIL.index, line);
            mark_local_variable_initialized();
            compile_expr(a.center);
            final loop_start = function.chunk.count;
            emit_byte(OpCode.CONTAINER_ITERATE.index, line);
            emit_byte(stack_idx, line);
            final exit_jump = function.chunk.emit_jump_if_false(
              line,
            );
            emit_byte(OpCode.POP.index, line); // Condition
            final body = a.body;
            compile_stmt(body);
            emit_loop(a.exit_token, loop_start, line);
            patch_jump(a.exit_token, exit_jump);
            emit_byte(OpCode.POP.index, line); // Condition
          },
          line: a.line,
        ),
        block: (final a) {
          final decls = <Declaration>[];
          wrap_in_scope(
            fn: () {
              for (final x in a.block_maker(this)) {
                decls.add(x);
              }
            },
            line: a.line,
          );
          a.block = decls;
        },
        whil: (final a) {
          final loop_start = function.chunk.count;
          compile_expr(a.expr);
          final line = a.line;
          final exit_jump = function.chunk.emit_jump_if_false(
            line,
          );
          emit_byte(OpCode.POP.index, line);
          final stmt = a.stmt;
          compile_stmt(stmt);
          emit_loop(a.exit_kw, loop_start, line);
          patch_jump(a.exit_kw, exit_jump);
          emit_byte(OpCode.POP.index, line);
        },
        conditional: (final a) {
          compile_expr(a.expr);
          final then_jump = function.chunk.emit_jump_if_false(a.line);
          emit_byte(OpCode.POP.index, a.line);
          compile_stmt(a.stmt);
          final else_jump = function.chunk.emit_jump(
            a.line,
          );
          patch_jump(a.if_kw, then_jump);
          emit_byte(OpCode.POP.index, a.line);
          final other = a.other_maker();
          if (other != null) {
            final made = other;
            compile_stmt(made);
            a.other = made;
          } else {
            a.other = null;
          }
          patch_jump(a.else_kw, else_jump);
        },
      );
    }

    decl.match(
      clazz: (final a) {
        final name_constant = make_constant(
          a.name,
          a.name.lexeme,
        );
        declare_local_variable(a.name);
        final line = a.line;
        emit_byte(OpCode.CLASS.index, line);
        emit_byte(name_constant, line);
        define_variable(name_constant, line: line);
        current_class = ClassCompiler(
          enclosing: current_class,
          name: a.name,
          has_superclass: a.superclass_name != null,
        );
        a.functions = wrap_in_scope(
          fn: () {
            final superclass_name = a.superclass_name;
            if (superclass_name != null) {
              final class_name = current_class!.name!;
              visit_getter(superclass_name, line);
              if (class_name.lexeme == superclass_name.lexeme) {
                error_delegate.error_at(superclass_name, "A class can't inherit from itself");
              }
              add_local(const TokenImpl(type: TokenType.IDENTIFIER, lexeme: 'super', loc: LocImpl(-1)));
              define_variable(0, line: line);
              visit_getter(class_name, line);
              emit_byte(OpCode.INHERIT.index, line);
            }
            visit_getter(a.name, line);
            final functions = a.make_functions(this);
            emit_byte(OpCode.POP.index, line);
            current_class = current_class!.enclosing;
            return functions;
          },
          line: a.line,
        );
      },
      fun: (final a) {
        final global = make_variable(a.name);
        mark_local_variable_initialized();
        final _block = a.make_block(this);
        define_variable(global, line: a.line);
        a.block = _block;
      },
      vari: (final a) => compile_vari(
        a,
      ),
      stmt: (final a) => compile_stmt(
        a.stmt,
      ),
    );
  }

  @override
  ObjFunction compile(
    final int last_line,
  ) {
    return end_compiler(last_line);
  }
}

// TODO remove interface, have just one top level compile function.
abstract class Compiler {
  // TODO preorder postorder or keep generic fns?
  void visit_fn(
    final FunctionType type,
    final Functiony block,
    final int line,
  );

  void visit_method(
    final Method method,
  );

  void compile_declaration(
    final Declaration decl,
  );

  ObjFunction compile(
    final int last_line,
  );
}

Local init_local(
  final bool is_not_function,
) {
  return Local(
    name: TokenImpl(
      type: TokenType.IDENTIFIER,
      lexeme: () {
        if (is_not_function) {
          return 'this';
        } else {
          return '';
        }
      }(),
      loc: const LocImpl(-1),
    ),
    depth: 0,
    is_captured: false,
  );
}

class Local {
  final Token name;
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
  final Token name;
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
  final Token? name;
  bool has_superclass;

  ClassCompiler({
    required final this.enclosing,
    required final this.name,
    required final this.has_superclass,
  });
}
