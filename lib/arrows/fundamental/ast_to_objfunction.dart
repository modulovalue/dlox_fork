import '../../domains/ast.dart';
import '../../domains/objfunction.dart';
import '../../domains/tokens.dart';
import 'tokens_to_ast.dart';

DloxFunction ast_to_objfunction({
  required final DloxErrorDelegate error_delegate,
  required final CompilationUnit compilation_unit,
  required final int last_line,
  required final bool trace_bytecode,
}) {
  return _ast_to_objfunction(
    error_delegate: error_delegate,
    compilation_unit: compilation_unit.decls,
    compiler: _DloxCompilerRootImpl(
      function: DloxFunction(
        name: null,
      ),
      error_delegate: error_delegate,
      debug_trace_bytecode: trace_bytecode,
    ),
    last_line: last_line,
  );
}

DloxFunction _ast_to_objfunction({
  required final DloxErrorDelegate error_delegate,
  required final List<Declaration> compilation_unit,
  required final _Compiler compiler,
  required final int last_line,
}) {
  // region run
  void compile_declaration(
    final Declaration decl,
  ) {
    void visit_fn(
      final _FunctionType type,
      final Functiony block,
      final int line,
    ) {
      final new_compiler = _DloxCompilerWrappedImpl(
        function: DloxFunction(
          name: block.name,
        ),
        is_initializer: type == _FunctionType.INITIALIZER,
        local: _init_local(type != _FunctionType.FUNCTION),
        enclosing: compiler,
      );
      for (final name in block.args) {
        new_compiler.function.arity++;
        if (new_compiler.function.arity > 255) {
          error_delegate.error_at(name, "Can't have more than 255 parameters");
        }
        new_compiler.make_variable(name);
        new_compiler.mark_local_variable_initialized();
      }
      for (int k = 0; k < block.args.length; k++) {
        new_compiler.define_variable(0, peek_dist: block.args.length - 1 - k, line: line);
      }
      _ast_to_objfunction(
        error_delegate: error_delegate,
        compiler: new_compiler,
        compilation_unit: block.decls,
        last_line: line,
      );
    }

    void visit_method(
      final Method a,
    ) {
      visit_fn(
        () {
          if (a.name.lexeme == 'init') {
            return _FunctionType.INITIALIZER;
          } else {
            return _FunctionType.METHOD;
          }
        }(),
        a.block,
        a.line,
      );
      final line = a.line;
      compiler.emit_byte(DloxOpCode.METHOD.index, line);
      compiler.emit_byte(compiler.make_constant(a.name, a.name.lexeme), line);
    }

    MapEntry<int, MapEntry<DloxOpCode, DloxOpCode>> get_or_set(
      final Token name,
    ) {
      int? arg = compiler.resolve_local(name);
      DloxOpCode get_op;
      DloxOpCode set_op;
      if (arg == null) {
        final resolved_arg = compiler.resolve_upvalue(name);
        if (resolved_arg == null) {
          arg = compiler.make_constant(name, name.lexeme);
          get_op = DloxOpCode.GET_GLOBAL;
          set_op = DloxOpCode.SET_GLOBAL;
        } else {
          arg = resolved_arg;
          get_op = DloxOpCode.GET_UPVALUE;
          set_op = DloxOpCode.SET_UPVALUE;
        }
      } else {
        get_op = DloxOpCode.GET_LOCAL;
        set_op = DloxOpCode.SET_LOCAL;
      }
      return MapEntry(
        arg,
        MapEntry(
          get_op,
          set_op,
        ),
      );
    }

    MapEntry<int, DloxOpCode> visit_getter(
      final Token name,
      final int line,
    ) {
      final data = get_or_set(name);
      compiler.emit_byte(data.value.key.index, line);
      compiler.emit_byte(data.key, line);
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
          compiler.function.chunk.emit_constant(compiler.make_constant(a.token, a.token.lexeme), line);
        },
        number: (final a) {
          final value = double.tryParse(a.value.lexeme);
          if (value == null) {
            error_delegate.error_at(a.value, 'Invalid number');
          } else {
            final line = a.line;
            compiler.function.chunk.emit_constant(compiler.make_constant(a.value, value), line);
          }
        },
        object: (final a) {
          final line = a.line;
          compiler.function.chunk.emit_constant(compiler.make_constant(a.token, null), line);
        },
        self: (final a) {
          if (compiler.current_class == null) {
            error_delegate.error_at(a.previous, "Can't use 'this' outside of a class");
          } else {
            visit_getter(a.previous, a.line);
          }
        },
        nil: (final a) {
          compiler.emit_byte(DloxOpCode.NIL.index, a.line);
        },
        falsity: (final a) {
          compiler.emit_byte(DloxOpCode.FALSE.index, a.line);
        },
        truth: (final a) {
          compiler.emit_byte(DloxOpCode.TRUE.index, a.line);
        },
        get: (final a) {
          final name = compiler.make_constant(a.name, a.name.lexeme);
          final line = a.line;
          compiler.emit_byte(DloxOpCode.GET_PROPERTY.index, line);
          compiler.emit_byte(name, line);
        },
        set2: (final a) {
          self(a.arg);
          final data = get_or_set(a.name);
          final line = a.line;
          compiler.emit_byte(data.value.value.index, line);
          compiler.emit_byte(data.key, line);
        },
        negated: (final a) {
          self(a.child);
          compiler.emit_byte(DloxOpCode.NEGATE.index, a.line);
        },
        not: (final a) {
          self(a.child);
          compiler.emit_byte(DloxOpCode.NOT.index, a.line);
        },
        call: (final a) {
          for (final x in a.args) {
            self(x);
          }
          final line = a.line;
          compiler.emit_byte(DloxOpCode.CALL.index, line);
          compiler.emit_byte(a.args.length, line);
        },
        set: (final a) {
          self(a.arg);
          final line = a.line;
          compiler.emit_byte(DloxOpCode.SET_PROPERTY.index, line);
          compiler.emit_byte(compiler.make_constant(a.name, a.name.lexeme), line);
        },
        invoke: (final a) {
          for (final x in a.args) {
            self(x);
          }
          final line = a.line;
          compiler.emit_byte(DloxOpCode.INVOKE.index, line);
          compiler.emit_byte(compiler.make_constant(a.name, a.name.lexeme), line);
          compiler.emit_byte(a.args.length, line);
        },
        map: (final a) {
          for (final x in a.entries) {
            self(x.key);
            self(x.value);
          }
          final line = a.line;
          compiler.emit_byte(DloxOpCode.MAP_INIT.index, line);
          compiler.emit_byte(a.entries.length, line);
        },
        list: (final a) {
          for (final x in a.values) {
            self(x);
          }
          final line = a.line;
          if (a.val_count >= 0) {
            compiler.emit_byte(DloxOpCode.LIST_INIT.index, line);
            compiler.emit_byte(a.val_count, line);
          } else {
            compiler.emit_byte(DloxOpCode.LIST_INIT_RANGE.index, line);
          }
        },
        minus: (final a) {
          self(a.child);
          compiler.emit_byte(DloxOpCode.SUBTRACT.index, a.line);
        },
        plus: (final a) {
          self(a.child);
          compiler.emit_byte(DloxOpCode.ADD.index, a.line);
        },
        slash: (final a) {
          self(a.child);
          compiler.emit_byte(DloxOpCode.DIVIDE.index, a.line);
        },
        star: (final a) {
          self(a.child);
          compiler.emit_byte(DloxOpCode.MULTIPLY.index, a.line);
        },
        g: (final a) {
          self(a.child);
          compiler.emit_byte(DloxOpCode.GREATER.index, a.line);
        },
        geq: (final a) {
          self(a.child);
          final line = a.line;
          compiler.emit_byte(DloxOpCode.LESS.index, line);
          compiler.emit_byte(DloxOpCode.NOT.index, line);
        },
        l: (final a) {
          self(a.child);
          compiler.emit_byte(DloxOpCode.LESS.index, a.line);
        },
        leq: (final a) {
          self(a.child);
          final line = a.line;
          compiler.emit_byte(DloxOpCode.GREATER.index, line);
          compiler.emit_byte(DloxOpCode.NOT.index, line);
        },
        pow: (final a) {
          self(a.child);
          compiler.emit_byte(DloxOpCode.POW.index, a.line);
        },
        modulo: (final a) {
          self(a.child);
          compiler.emit_byte(DloxOpCode.MOD.index, a.line);
        },
        neq: (final a) {
          self(a.child);
          final line = a.line;
          compiler.emit_byte(DloxOpCode.EQUAL.index, line);
          compiler.emit_byte(DloxOpCode.NOT.index, line);
        },
        eq: (final a) {
          self(a.child);
          compiler.emit_byte(DloxOpCode.EQUAL.index, a.line);
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
                compiler.emit_byte(DloxOpCode.ADD.index, line);
                compiler.emit_byte(data.value.index, line);
                compiler.emit_byte(data.key, line);
                break;
              case GetsetType.minuseq:
                self(arg.child);
                compiler.emit_byte(DloxOpCode.SUBTRACT.index, line);
                compiler.emit_byte(data.value.index, line);
                compiler.emit_byte(data.key, line);
                break;
              case GetsetType.stareq:
                self(arg.child);
                compiler.emit_byte(DloxOpCode.MULTIPLY.index, line);
                compiler.emit_byte(data.value.index, line);
                compiler.emit_byte(data.key, line);
                break;
              case GetsetType.slasheq:
                self(arg.child);
                compiler.emit_byte(DloxOpCode.DIVIDE.index, line);
                compiler.emit_byte(data.value.index, line);
                compiler.emit_byte(data.key, line);
                break;
              case GetsetType.poweq:
                self(arg.child);
                compiler.emit_byte(DloxOpCode.POW.index, line);
                compiler.emit_byte(data.value.index, line);
                compiler.emit_byte(data.key, line);
                break;
              case GetsetType.modeq:
                self(arg.child);
                compiler.emit_byte(DloxOpCode.MOD.index, line);
                compiler.emit_byte(data.value.index, line);
                compiler.emit_byte(data.key, line);
                break;
            }
          }
        },
        and: (final a) {
          final line = a.line;
          final end_jump = compiler.function.chunk.emit_jump_if_false(
            line,
          );
          compiler.emit_byte(DloxOpCode.POP.index, line);
          self(a.child);
          compiler.patch_jump(a.token, end_jump);
        },
        or: (final a) {
          final line = a.line;
          final else_jump = compiler.function.chunk.emit_jump_if_false(
            line,
          );
          final end_jump = compiler.function.chunk.emit_jump(
            line,
          );
          compiler.patch_jump(a.token, else_jump);
          compiler.emit_byte(DloxOpCode.POP.index, line);
          self(a.child);
          compiler.patch_jump(a.token, end_jump);
        },
        listgetter: (final a) {
          final line = a.line;
          if (a.first != null) {
            self(a.first!);
          } else {
            compiler.function.chunk.emit_constant(compiler.make_constant(a.first_token, DloxNil), line);
          }
          if (a.second != null) {
            self(a.second!);
          } else {
            compiler.function.chunk.emit_constant(compiler.make_constant(a.second_token, DloxNil), line);
          }
          compiler.emit_byte(DloxOpCode.CONTAINER_GET_RANGE.index, line);
        },
        listsetter: (final a) {
          final line = a.line;
          if (a.first != null) {
            self(a.first!);
          } else {
            compiler.function.chunk.emit_constant(compiler.make_constant(a.token, DloxNil), line);
          }
          if (a.second != null) {
            self(a.second!);
            compiler.emit_byte(DloxOpCode.CONTAINER_SET.index, line);
          } else {
            compiler.emit_byte(DloxOpCode.CONTAINER_GET.index, line);
          }
        },
        superaccess: (final a) {
          if (compiler.current_class == null) {
            error_delegate.error_at(a.kw, "Can't use 'super' outside of a class");
          } else if (!compiler.current_class!.has_superclass) {
            error_delegate.error_at(a.kw, "Can't use 'super' in a class with no superclass");
          }
          final name = compiler.make_constant(a.kw, a.kw.lexeme);
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
            compiler.emit_byte(DloxOpCode.SUPER_INVOKE.index, line);
            compiler.emit_byte(name, line);
            compiler.emit_byte(_args.length, line);
          } else {
            compiler.emit_byte(DloxOpCode.GET_SUPER.index, line);
            compiler.emit_byte(name, line);
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
        final global = compiler.make_variable(x.key);
        compile_expr(x.value);
        compiler.define_variable(global, line: a.line);
      }
    }

    T wrap_in_scope<T>({
      required final T Function() fn,
      required final int line,
    }) {
      compiler.scope_depth++;
      final val = fn();
      compiler.scope_depth--;
      while (compiler.locals.isNotEmpty && compiler.locals.last.depth > compiler.scope_depth) {
        if (compiler.locals.last.is_captured) {
          compiler.emit_byte(DloxOpCode.CLOSE_UPVALUE.index, line);
        } else {
          compiler.emit_byte(DloxOpCode.POP.index, line);
        }
        compiler.locals.removeLast();
      }
      return val;
    }

    void compile_stmt(
      final Stmt stmt,
    ) {
      stmt.match(
        output: (final a) {
          compile_expr(a.expr);
          compiler.emit_byte(DloxOpCode.PRINT.index, a.line);
        },
        ret: (final a) {
          final expr = a.expr;
          if (expr == null) {
            final line = a.line;
            if (compiler.is_initializer) {
              compiler.function.chunk.emit_return_local(line);
            } else {
              compiler.function.chunk.emit_return_nil(line);
            }
          } else {
            if (compiler.is_initializer) {
              error_delegate.error_at(a.kw, "Can't return a value from an initializer");
            }
            compile_expr(expr);
            compiler.emit_byte(DloxOpCode.RETURN.index, a.line);
          }
        },
        expr: (final a) {
          compile_expr(a.expr);
          compiler.emit_byte(DloxOpCode.POP.index, a.line);
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
                  compiler.emit_byte(DloxOpCode.POP.index, line);
                },
              );
            }
            int loop_start = compiler.function.chunk.count;
            int exit_jump = -1;
            final center = a.center;
            if (center != null) {
              compile_expr(center);
              exit_jump = compiler.function.chunk.emit_jump_if_false(
                line,
              );
              compiler.emit_byte(DloxOpCode.POP.index, line); // Condition.
            }
            final _right = a.right;
            if (_right != null) {
              final body_jump = compiler.function.chunk.emit_jump(
                line,
              );
              final increment_start = compiler.function.chunk.count;
              final _expr = _right;
              compile_expr(_expr);
              compiler.emit_byte(DloxOpCode.POP.index, line);
              compiler.emit_loop(a.right_kw, loop_start, line);
              loop_start = increment_start;
              compiler.patch_jump(a.right_kw, body_jump);
            }
            final _stmt = a.body;
            compile_stmt(_stmt);
            compiler.emit_loop(a.end_kw, loop_start, line);
            if (exit_jump != -1) {
              compiler.patch_jump(a.end_kw, exit_jump);
              compiler.emit_byte(DloxOpCode.POP.index, line); // Condition.
            }
          },
          line: a.line,
        ),
        loop2: (final a) => wrap_in_scope(
          fn: () {
            compiler.make_variable(a.key_name);
            final line = a.line;
            compiler.emit_byte(DloxOpCode.NIL.index, line);
            compiler.define_variable(0, line: line); // Remove 0
            final stack_idx = compiler.locals.length - 1;
            final value_name = a.value_name;
            if (value_name != null) {
              compiler.make_variable(value_name);
              compiler.emit_byte(DloxOpCode.NIL.index, line);
              compiler.define_variable(0, line: line);
            } else {
              compiler.add_local(
                  const TokenImpl(type: TokenType.IDENTIFIER, lexeme: '_for_val_', loc: LocImpl(-1)));
              // Emit a zero to permute val & key
              compiler.function.chunk.emit_constant(
                compiler.make_constant(
                    const TokenImpl(type: TokenType.IDENTIFIER, lexeme: "INVALID", loc: LocImpl(-1)), 0),
                line,
              );
              compiler.mark_local_variable_initialized();
            }
            // Now add two dummy local variables. Idx & entries
            compiler.add_local(
                const TokenImpl(type: TokenType.IDENTIFIER, lexeme: '_for_idx_', loc: LocImpl(-1)));
            compiler.emit_byte(DloxOpCode.NIL.index, line);
            compiler.mark_local_variable_initialized();
            compiler.add_local(
                const TokenImpl(type: TokenType.IDENTIFIER, lexeme: '_for_iterable_', loc: LocImpl(-1)));
            compiler.emit_byte(DloxOpCode.NIL.index, line);
            compiler.mark_local_variable_initialized();
            compile_expr(a.center);
            final loop_start = compiler.function.chunk.count;
            compiler.emit_byte(DloxOpCode.CONTAINER_ITERATE.index, line);
            compiler.emit_byte(stack_idx, line);
            final exit_jump = compiler.function.chunk.emit_jump_if_false(
              line,
            );
            compiler.emit_byte(DloxOpCode.POP.index, line); // Condition
            final body = a.body;
            compile_stmt(body);
            compiler.emit_loop(a.exit_token, loop_start, line);
            compiler.patch_jump(a.exit_token, exit_jump);
            compiler.emit_byte(DloxOpCode.POP.index, line); // Condition
          },
          line: a.line,
        ),
        block: (final a) => wrap_in_scope(
          fn: () {
            for (final x in a.block) {
              error_delegate.restore();
              compile_declaration(x);
            }
          },
          line: a.line,
        ),
        whil: (final a) {
          final loop_start = compiler.function.chunk.count;
          compile_expr(a.expr);
          final line = a.line;
          final exit_jump = compiler.function.chunk.emit_jump_if_false(
            line,
          );
          compiler.emit_byte(DloxOpCode.POP.index, line);
          final stmt = a.stmt;
          compile_stmt(stmt);
          compiler.emit_loop(a.exit_kw, loop_start, line);
          compiler.patch_jump(a.exit_kw, exit_jump);
          compiler.emit_byte(DloxOpCode.POP.index, line);
        },
        conditional: (final a) {
          compile_expr(a.expr);
          final then_jump = compiler.function.chunk.emit_jump_if_false(a.line);
          compiler.emit_byte(DloxOpCode.POP.index, a.line);
          compile_stmt(a.stmt);
          final else_jump = compiler.function.chunk.emit_jump(
            a.line,
          );
          compiler.patch_jump(a.if_kw, then_jump);
          compiler.emit_byte(DloxOpCode.POP.index, a.line);
          final other = a.other;
          if (other != null) {
            compile_stmt(other);
          }
          compiler.patch_jump(a.else_kw, else_jump);
        },
      );
    }

    decl.match(
      clazz: (final a) {
        final name_constant = compiler.make_constant(
          a.name,
          a.name.lexeme,
        );
        compiler.declare_local_variable(a.name);
        compiler.emit_byte(DloxOpCode.CLASS.index, a.line);
        compiler.emit_byte(name_constant, a.line);
        compiler.define_variable(name_constant, line: a.line);
        compiler.current_class = _ClassCompiler(
          enclosing: compiler.current_class,
          name: a.name,
          has_superclass: a.superclass_name != null,
        );
        wrap_in_scope(
          fn: () {
            final superclass_name = a.superclass_name;
            if (superclass_name != null) {
              final class_name = compiler.current_class!.name!;
              visit_getter(superclass_name, a.line);
              if (class_name.lexeme == superclass_name.lexeme) {
                error_delegate.error_at(superclass_name, "A class can't inherit from itself");
              }
              compiler.add_local(
                const TokenImpl(type: TokenType.IDENTIFIER, lexeme: 'super', loc: LocImpl(-1)),
              );
              compiler.define_variable(0, line: a.line);
              visit_getter(class_name, a.line);
              compiler.emit_byte(DloxOpCode.INHERIT.index, a.line);
            }
            visit_getter(a.name, a.line);
            final functions = a.functions;
            for (final x in functions) {
              visit_method(x);
            }
            compiler.emit_byte(DloxOpCode.POP.index, a.line);
            compiler.current_class = compiler.current_class!.enclosing;
            return functions;
          },
          line: a.line,
        );
      },
      fun: (final a) {
        final global = compiler.make_variable(a.name);
        compiler.mark_local_variable_initialized();
        visit_fn(
          _FunctionType.FUNCTION,
          a.block,
          a.line,
        );
        compiler.define_variable(global, line: a.line);
      },
      vari: (final a) => compile_vari(
        a,
      ),
      stmt: (final a) => compile_stmt(
        a.stmt,
      ),
    );
  }

  for (final x in compilation_unit) {
    error_delegate.restore();
    compile_declaration(x);
  }
  // endregion
  // region finish
  if (compiler.is_initializer) {
    compiler.function.chunk.emit_return_local(last_line);
  } else {
    compiler.function.chunk.emit_return_nil(last_line);
  }
  if (error_delegate.debug.errors.isEmpty && compiler.debug_trace_bytecode) {
    error_delegate.debug.disassemble_chunk(
      compiler.function.chunk,
      compiler.function.name ?? '<script>',
    );
  }
  if (compiler.enclosing != null) {
    final _enclosing = compiler.enclosing!;
    _enclosing.emit_byte(DloxOpCode.CLOSURE.index, last_line);
    _enclosing.emit_byte(
      _enclosing.make_constant(
        const TokenImpl(type: TokenType.IDENTIFIER, lexeme: "INVALID", loc: LocImpl(-1)),
        compiler.function,
      ),
      last_line,
    );
    for (final x in compiler.upvalues) {
      _enclosing.emit_byte(
        () {
          if (x.is_local) {
            return 1;
          } else {
            return 0;
          }
        }(),
        last_line,
      );
      _enclosing.emit_byte(x.index, last_line);
    }
    return compiler.function;
  } else {
    return compiler.function;
  }
  // endregion
}

class _DloxCompilerRootImpl with _DloxCompilerMixin {
  @override
  final DloxErrorDelegate error_delegate;
  @override
  final List<_Local> locals;
  @override
  final List<_Upvalue> upvalues;
  @override
  final bool is_initializer;
  @override
  int scope_depth;
  @override
  bool debug_trace_bytecode;
  @override
  _ClassCompiler? current_class;
  @override
  DloxFunction function;

  _DloxCompilerRootImpl({
    required final this.error_delegate,
    required final this.debug_trace_bytecode,
    required final this.function,
  })  : is_initializer = false,
        scope_depth = 0,
        locals = [
          _init_local(true),
        ],
        upvalues = [];

  @override
  Null get enclosing => null;
}

class _DloxCompilerWrappedImpl with _DloxCompilerMixin {
  @override
  final List<_Local> locals;
  @override
  final List<_Upvalue> upvalues;
  @override
  final bool is_initializer;
  @override
  final _Compiler enclosing;
  @override
  int scope_depth;
  @override
  _ClassCompiler? current_class;
  @override
  DloxFunction function;

  _DloxCompilerWrappedImpl({
    required final this.is_initializer,
    required final this.enclosing,
    required final this.function,
    required final _Local local,
  })  : current_class = enclosing.current_class,
        scope_depth = enclosing.scope_depth + 1,
        locals = [
          local,
        ],
        upvalues = [];

  @override
  bool get debug_trace_bytecode => enclosing.debug_trace_bytecode;

  @override
  DloxErrorDelegate get error_delegate => enclosing.error_delegate;
}

mixin _DloxCompilerMixin implements _Compiler {
  @override
  void emit_byte(
    final int byte,
    final int line_number,
  ) {
    function.chunk.write(byte, line_number);
  }

  @override
  void emit_loop(
    final Token previous,
    final int loop_start,
    final int line,
  ) {
    final offset = function.chunk.count - loop_start + 3;
    if (offset > DLOX_UINT16_MAX) {
      error_delegate.error_at(previous, 'Loop body too large');
    }
    function.chunk.emit_loop(offset, line);
  }

  @override
  int make_constant(
    final Token token,
    final Object? value,
  ) {
    final constant = function.chunk.add_constant(value);
    if (constant > DLOX_UINT8_MAX) {
      error_delegate.error_at(token, 'Too many constants in one chunk');
      return 0;
    } else {
      return constant;
    }
  }

  @override
  void patch_jump(
    final Token token,
    final int offset,
  ) {
    final jump = function.chunk.count - offset - 2;
    if (jump > DLOX_UINT16_MAX) {
      error_delegate.error_at(token, 'Too much code to jump over');
    }
    function.chunk.code[offset] = (jump >> 8) & 0xff;
    function.chunk.code[offset + 1] = jump & 0xff;
  }

  @override
  void add_local(
    final Token name,
  ) {
    if (locals.length >= DLOX_UINT8_COUNT) {
      error_delegate.error_at(name, 'Too many local variables in function');
    } else {
      locals.add(
        _Local(
          name: name,
          depth: -1,
          is_captured: false,
        ),
      );
    }
  }

  @override
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

  @override
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
    if (upvalues.length == DLOX_UINT8_COUNT) {
      error_delegate.error_at(name, 'Too many closure variables in function');
      return 0;
    } else {
      upvalues.add(
        _Upvalue(
          name: name,
          index: index,
          is_local: is_local,
        ),
      );
      return function.upvalue_count++;
    }
  }

  @override
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

  @override
  void mark_local_variable_initialized() {
    if (scope_depth != 0) {
      locals.last.depth = scope_depth;
    }
  }

  @override
  void define_variable(
    final int global, {
    required final int line,
    final int peek_dist = 0,
  }) {
    final is_local = scope_depth > 0;
    if (is_local) {
      mark_local_variable_initialized();
    } else {
      emit_byte(DloxOpCode.DEFINE_GLOBAL.index, line);
      emit_byte(global, line);
    }
  }

  @override
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

  @override
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
}

abstract class _Compiler {
  abstract _ClassCompiler? current_class;

  abstract int scope_depth;

  DloxFunction get function;

  _Compiler? get enclosing;

  bool get debug_trace_bytecode;

  List<_Local> get locals;

  List<_Upvalue> get upvalues;

  DloxErrorDelegate get error_delegate;

  bool get is_initializer;

  // TODO remove once chunk emitters are complete.
  void emit_byte(
    final int byte,
    final int line_number,
  );

  // TODO remove once chunk emitters are complete.
  void emit_loop(
    final Token previous,
    final int loop_start,
    final int line,
  );

  int make_constant(
    final Token token,
    final Object? value,
  );

  void patch_jump(
    final Token token,
    final int offset,
  );

  void add_local(
    final Token name,
  );

  int? resolve_local(
    final Token name,
  );

  int add_upvalue(
    final Token name,
    final int index,
    final bool is_local,
  );

  int? resolve_upvalue(
    final Token name,
  );

  void mark_local_variable_initialized();

  void define_variable(
    final int global, {
    required final int line,
    final int peek_dist = 0,
  });

  void declare_local_variable(
    final Token name,
  );

  int make_variable(
    final Token name,
  );
}

_Local _init_local(
  final bool is_not_function,
) {
  return _Local(
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

class _Local {
  final Token name;
  int depth;
  bool is_captured;

  _Local({
    required final this.name,
    required final this.depth,
    required final this.is_captured,
  });

  bool get initialized {
    return depth >= 0;
  }
}

class _Upvalue {
  final Token name;
  final int index;
  final bool is_local;

  const _Upvalue({
    required final this.name,
    required final this.index,
    required final this.is_local,
  });
}

enum _FunctionType {
  FUNCTION,
  INITIALIZER,
  METHOD,
}

class _ClassCompiler {
  final _ClassCompiler? enclosing;
  final Token? name;
  bool has_superclass;

  _ClassCompiler({
    required final this.enclosing,
    required final this.name,
    required final this.has_superclass,
  });
}
