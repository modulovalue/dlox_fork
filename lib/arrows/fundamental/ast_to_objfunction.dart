import '../../domains/ast.dart';
import '../../domains/errors.dart';
import '../../domains/objfunction.dart';
import '../../domains/tokens.dart';

DloxFunction ast_to_objfunction({
  required final Debug debug,
  required final CompilationUnit compilation_unit,
  required final int last_line,
  required final bool trace_bytecode,
}) {
  return _ast_to_objfunction(
    debug: debug,
    compilation_unit: compilation_unit.decls,
    compiler: _DloxCompilerRootImpl(
      function: DloxFunction(
        name: null,
      ),
      debug: debug,
    ),
    trace_bytecode: trace_bytecode,
    last_line: last_line,
  );
}

// region private
DloxFunction _ast_to_objfunction({
  required final Debug debug,
  required final List<Declaration> compilation_unit,
  required final _Compiler compiler,
  required final int last_line,
  required final bool trace_bytecode,
}) {
  // region run
  void compile_declaration(
    final Declaration decl,
  ) {
    void visit_fn(
      final bool is_initializer,
      final bool is_function,
      final Functiony block,
      final int line,
    ) {
      final new_compiler = _DloxCompilerWrappedImpl(
        function: DloxFunction(
          name: block.name,
        ),
        is_initializer: is_initializer,
        local: _init_local(is_function),
        enclosing: compiler,
      );
      for (final name in block.args) {
        new_compiler.function.arity++;
        if (new_compiler.function.arity > 255) {
          debug.error_at(name, "Can't have more than 255 parameters");
        }
        new_compiler.make_variable(name);
        new_compiler.mark_local_variable_initialized();
      }
      for (int k = 0; k < block.args.length; k++) {
        new_compiler.define_variable(0, peek_dist: block.args.length - 1 - k, line: line);
      }
      _ast_to_objfunction(
        trace_bytecode: trace_bytecode,
        debug: debug,
        compiler: new_compiler,
        compilation_unit: block.decls,
        last_line: line,
      );
    }

    MapEntry<void Function(int line), void Function(int line)> get_or_set(
      final Token name,
    ) {
      final local_arg = compiler.resolve_local(name);
      if (local_arg == null) {
        final upvalue_arg = compiler.resolve_upvalue(name);
        if (upvalue_arg == null) {
          final constant_arg = compiler.make_constant(name, name.lexeme);
          return MapEntry(
            (final line) => compiler.function.chunk.emit_get_global(constant_arg, line),
            (final line) => compiler.function.chunk.emit_set_global(constant_arg, line),
          );
        } else {
          return MapEntry(
            (final line) => compiler.function.chunk.emit_get_upvalue(upvalue_arg, line),
            (final line) => compiler.function.chunk.emit_set_upvalue(upvalue_arg, line),
          );
        }
      } else {
        return MapEntry(
          (final line) => compiler.function.chunk.emit_get_local(local_arg, line),
          (final line) => compiler.function.chunk.emit_set_local(local_arg, line),
        );
      }
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
            debug.error_at(a.value, 'Invalid number');
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
            debug.error_at(a.previous, "Can't use 'this' outside of a class");
          } else {
            get_or_set(a.previous).key(a.line);
          }
        },
        nil: (final a) => compiler.function.chunk.emit_nil(a.line),
        falsity: (final a) => compiler.function.chunk.emit_false(a.line),
        truth: (final a) => compiler.function.chunk.emit_true(a.line),
        get: (final a) => compiler.function.chunk.emit_get_property(
          compiler.make_constant(a.name, a.name.lexeme),
          a.line,
        ),
        set2: (final a) {
          self(a.arg);
          get_or_set(a.name).value(a.line);
        },
        negated: (final a) {
          self(a.child);
          compiler.function.chunk.emit_negate(a.line);
        },
        not: (final a) {
          self(a.child);
          compiler.function.chunk.emit_not(a.line);
        },
        call: (final a) {
          for (final x in a.args) {
            self(x);
          }
          compiler.function.chunk.emit_call(a.args.length, a.line);
        },
        set: (final a) {
          self(a.arg);
          compiler.function.chunk.emit_set_property(compiler.make_constant(a.name, a.name.lexeme), a.line);
        },
        invoke: (final a) {
          for (final x in a.args) {
            self(x);
          }
          compiler.function.chunk.emit_invoke(
            compiler.make_constant(a.name, a.name.lexeme),
            a.args.length,
            a.line,
          );
        },
        map: (final a) {
          for (final x in a.entries) {
            self(x.key);
            self(x.value);
          }
          compiler.function.chunk.emit_map_init(a.entries.length, a.line);
        },
        list: (final a) {
          for (final x in a.values) {
            self(x);
          }
          if (a.val_count >= 0) {
            compiler.function.chunk.emit_list_init(a.val_count, a.line);
          } else {
            compiler.function.chunk.emit_list_init_range(a.line);
          }
        },
        minus: (final a) {
          self(a.child);
          compiler.function.chunk.emit_subtract(a.line);
        },
        plus: (final a) {
          self(a.child);
          compiler.function.chunk.emit_add(a.line);
        },
        slash: (final a) {
          self(a.child);
          compiler.function.chunk.emit_divide(a.line);
        },
        star: (final a) {
          self(a.child);
          compiler.function.chunk.emit_multiply(a.line);
        },
        g: (final a) {
          self(a.child);
          compiler.function.chunk.emit_greater(a.line);
        },
        geq: (final a) {
          self(a.child);
          final line = a.line;
          compiler.function.chunk.emit_not_less(line);
        },
        l: (final a) {
          self(a.child);
          compiler.function.chunk.emit_less(a.line);
        },
        leq: (final a) {
          self(a.child);
          final line = a.line;
          compiler.function.chunk.emit_not_greater(line);
        },
        pow: (final a) {
          self(a.child);
          compiler.function.chunk.emit_pow(a.line);
        },
        modulo: (final a) {
          self(a.child);
          compiler.function.chunk.emit_mod(a.line);
        },
        neq: (final a) {
          self(a.child);
          compiler.function.chunk.emit_notequal(a.line);
        },
        eq: (final a) {
          self(a.child);
          compiler.function.chunk.emit_equal(a.line);
        },
        expected: (final a) {},
        getset2: (final a) {
          final setter_child = a.child;
          final line = a.line;
          final data = get_or_set(a.name);
          data.key(line);
          if (setter_child != null) {
            switch (setter_child.type) {
              case GetsetType.pluseq:
                self(setter_child.child);
                compiler.function.chunk.emit_add(a.line);
                data.value(line);
                break;
              case GetsetType.minuseq:
                self(setter_child.child);
                compiler.function.chunk.emit_subtract(a.line);
                data.value(line);
                break;
              case GetsetType.stareq:
                self(setter_child.child);
                compiler.function.chunk.emit_multiply(a.line);
                data.value(line);
                break;
              case GetsetType.slasheq:
                self(setter_child.child);
                compiler.function.chunk.emit_divide(a.line);
                data.value(line);
                break;
              case GetsetType.poweq:
                self(setter_child.child);
                compiler.function.chunk.emit_pow(a.line);
                data.value(line);
                break;
              case GetsetType.modeq:
                self(setter_child.child);
                compiler.function.chunk.emit_mod(a.line);
                data.value(line);
                break;
            }
          }
        },
        and: (final a) {
          final line = a.line;
          final end_jump = compiler.function.chunk.emit_jump_if_false(
            line,
          );
          compiler.function.chunk.emit_pop(a.line);
          self(a.child);
          compiler.patch_jump(a.token, end_jump);
        },
        or: (final a) {
          final else_jump = compiler.function.chunk.emit_jump_if_false(a.line);
          final end_jump = compiler.function.chunk.emit_jump(a.line);
          compiler.patch_jump(a.token, else_jump);
          compiler.function.chunk.emit_pop(a.line);
          self(a.child);
          compiler.patch_jump(a.token, end_jump);
        },
        listgetter: (final a) {
          if (a.first != null) {
            self(a.first!);
          } else {
            compiler.function.chunk.emit_constant(compiler.make_constant(a.first_token, DloxNil), a.line);
          }
          if (a.second != null) {
            self(a.second!);
          } else {
            compiler.function.chunk.emit_constant(compiler.make_constant(a.second_token, DloxNil), a.line);
          }
          compiler.function.chunk.emit_container_get_range(a.line);
        },
        listsetter: (final a) {
          if (a.first != null) {
            self(a.first!);
          } else {
            compiler.function.chunk.emit_constant(compiler.make_constant(a.token, DloxNil), a.line);
          }
          if (a.second != null) {
            self(a.second!);
            compiler.function.chunk.emit_container_set(a.line);
          } else {
            compiler.function.chunk.emit_container_get(a.line);
          }
        },
        superaccess: (final a) {
          if (compiler.current_class == null) {
            debug.error_at(a.kw, "Can't use 'super' outside of a class");
          } else if (!compiler.current_class!.has_superclass) {
            debug.error_at(a.kw, "Can't use 'super' in a class with no superclass");
          }
          final name = compiler.make_constant(a.kw, a.kw.lexeme);
          get_or_set(const TokenImpl(type: TokenType.IDENTIFIER, lexeme: 'this', loc: LocImpl(-1))).key(a.line);
          final _args = a.args;
          if (_args != null) {
            for (final x in _args) {
              self(x);
            }
          }
          get_or_set(const TokenImpl(type: TokenType.IDENTIFIER, lexeme: 'super', loc: LocImpl(-1))).key(a.line);
          if (_args != null) {
            compiler.function.chunk.emit_super_invoke(name, _args.length, a.line);
          } else {
            compiler.function.chunk.emit_get_super(name, a.line);
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
          compiler.function.chunk.emit_close_upvalue(line);
        } else {
          compiler.function.chunk.emit_pop(line);
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
          compiler.function.chunk.emit_print(a.line);
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
              debug.error_at(a.kw, "Can't return a value from an initializer");
            }
            compile_expr(expr);
            compiler.function.chunk.emit_return(a.line);
          }
        },
        expr: (final a) {
          compile_expr(a.expr);
          compiler.function.chunk.emit_pop(a.line);
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
                  compiler.function.chunk.emit_pop(line);
                },
              );
            }
            int loop_start = compiler.function.chunk.code.length;
            int exit_jump = -1;
            final center = a.center;
            if (center != null) {
              compile_expr(center);
              exit_jump = compiler.function.chunk.emit_jump_if_false(
                line,
              );
              compiler.function.chunk.emit_pop(line);
            }
            final _right = a.right;
            if (_right != null) {
              final body_jump = compiler.function.chunk.emit_jump(
                line,
              );
              final increment_start = compiler.function.chunk.code.length;
              final _expr = _right;
              compile_expr(_expr);
              compiler.function.chunk.emit_pop(line);
              compiler.emit_loop(a.right_kw, loop_start, line);
              loop_start = increment_start;
              compiler.patch_jump(a.right_kw, body_jump);
            }
            final _stmt = a.body;
            compile_stmt(_stmt);
            compiler.emit_loop(a.end_kw, loop_start, line);
            if (exit_jump != -1) {
              compiler.patch_jump(a.end_kw, exit_jump);
              compiler.function.chunk.emit_pop(line);
            }
          },
          line: a.line,
        ),
        loop2: (final a) => wrap_in_scope(
          fn: () {
            compiler.make_variable(a.key_name);
            final line = a.line;
            compiler.function.chunk.emit_nil(line);
            compiler.define_variable(0, line: line); // Remove 0
            final stack_idx = compiler.locals.length - 1;
            final value_name = a.value_name;
            if (value_name != null) {
              compiler.make_variable(value_name);
              compiler.function.chunk.emit_nil(line);
              compiler.define_variable(0, line: line);
            } else {
              compiler.add_local(
                const TokenImpl(type: TokenType.IDENTIFIER, lexeme: '_for_val_', loc: LocImpl(-1)),
              );
              // Emit a zero to permute val & key
              compiler.function.chunk.emit_constant(
                compiler.make_constant(
                  const TokenImpl(type: TokenType.IDENTIFIER, lexeme: "INVALID", loc: LocImpl(-1)),
                  0,
                ),
                line,
              );
              compiler.mark_local_variable_initialized();
            }
            // Now add two dummy local variables. Idx & entries
            compiler.add_local(
              const TokenImpl(type: TokenType.IDENTIFIER, lexeme: '_for_idx_', loc: LocImpl(-1)),
            );
            compiler.function.chunk.emit_nil(line);
            compiler.mark_local_variable_initialized();
            compiler.add_local(
              const TokenImpl(type: TokenType.IDENTIFIER, lexeme: '_for_iterable_', loc: LocImpl(-1)),
            );
            compiler.function.chunk.emit_nil(line);
            compiler.mark_local_variable_initialized();
            compile_expr(a.center);
            final loop_start = compiler.function.chunk.code.length;
            compiler.function.chunk.emit_container_iterate(stack_idx, line);
            final exit_jump = compiler.function.chunk.emit_jump_if_false(line);
            compiler.function.chunk.emit_pop(line);
            final body = a.body;
            compile_stmt(body);
            compiler.emit_loop(a.exit_token, loop_start, line);
            compiler.patch_jump(a.exit_token, exit_jump);
            compiler.function.chunk.emit_pop(line);
          },
          line: a.line,
        ),
        block: (final a) => wrap_in_scope(
          fn: () {
            for (final x in a.block) {
              debug.restore();
              compile_declaration(x);
            }
          },
          line: a.line,
        ),
        whil: (final a) {
          final loop_start = compiler.function.chunk.code.length;
          compile_expr(a.expr);
          final line = a.line;
          final exit_jump = compiler.function.chunk.emit_jump_if_false(
            line,
          );
          compiler.function.chunk.emit_pop(line);
          final stmt = a.stmt;
          compile_stmt(stmt);
          compiler.emit_loop(a.exit_kw, loop_start, line);
          compiler.patch_jump(a.exit_kw, exit_jump);
          compiler.function.chunk.emit_pop(line);
        },
        conditional: (final a) {
          compile_expr(a.expr);
          final then_jump = compiler.function.chunk.emit_jump_if_false(a.line);
          compiler.function.chunk.emit_pop(a.line);
          compile_stmt(a.stmt);
          final else_jump = compiler.function.chunk.emit_jump(
            a.line,
          );
          compiler.patch_jump(a.if_kw, then_jump);
          compiler.function.chunk.emit_pop(a.line);
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
        compiler.current_class = _ClassCompiler(
          enclosing: compiler.current_class,
          name: a.name,
          has_superclass: a.superclass_name != null,
        );
        compiler.declare_local_variable(a.name);
        compiler.function.chunk.emit_class(name_constant, a.line);
        compiler.define_variable(name_constant, line: a.line);
        wrap_in_scope(
          fn: () {
            final superclass_name = a.superclass_name;
            if (superclass_name != null) {
              final class_name = compiler.current_class!.name!;
              get_or_set(superclass_name).key(a.line);
              if (class_name.lexeme == superclass_name.lexeme) {
                debug.error_at(superclass_name, "A class can't inherit from itself");
              }
              compiler.add_local(
                const TokenImpl(type: TokenType.IDENTIFIER, lexeme: 'super', loc: LocImpl(-1)),
              );
              compiler.define_variable(0, line: a.line);
              get_or_set(class_name).key(a.line);
              compiler.function.chunk.emit_inherit(a.line);
            }
            get_or_set(a.name).key(a.line);
            final functions = a.functions;
            for (final x in functions) {
              visit_fn(x.name.lexeme == 'init', false, x.block, x.line);
              final line = x.line;
              compiler.function.chunk.emit_method(compiler.make_constant(x.name, x.name.lexeme), line);
            }
            compiler.function.chunk.emit_pop(a.line);
            compiler.current_class = compiler.current_class!.enclosing;
            return functions;
          },
          line: a.line,
        );
      },
      fun: (final a) {
        final global = compiler.make_variable(a.name);
        compiler.mark_local_variable_initialized();
        visit_fn(false, true, a.block, a.line);
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
    debug.restore();
    compile_declaration(x);
  }
  // endregion
  // region finish
  if (compiler.is_initializer) {
    compiler.function.chunk.emit_return_local(last_line);
  } else {
    compiler.function.chunk.emit_return_nil(last_line);
  }
  if (debug.errors.isEmpty && trace_bytecode) {
    debug.disassemble_chunk(
      compiler.function.chunk,
      compiler.function.name ?? '<script>',
    );
  }
  if (compiler.enclosing != null) {
    final _enclosing = compiler.enclosing!;
    _enclosing.function.chunk.emit_closure(
      _enclosing.make_constant(
        const TokenImpl(type: TokenType.IDENTIFIER, lexeme: "INVALID", loc: LocImpl(-1)),
        compiler.function,
      ),
      last_line,
    );
    for (final x in compiler.upvalues) {
      _enclosing.function.chunk.emit_upvalue(
        () {
          if (x.is_local) {
            return 1;
          } else {
            return 0;
          }
        }(),
        x.index,
        last_line,
      );
    }
    return compiler.function;
  } else {
    return compiler.function;
  }
  // endregion
}

class _DloxCompilerRootImpl with _DloxCompilerMixin {
  @override
  final Debug debug;
  @override
  final List<_Local> locals;
  @override
  final List<_Upvalue> upvalues;
  @override
  final bool is_initializer;
  @override
  int scope_depth;
  @override
  _ClassCompiler? current_class;
  @override
  DloxFunction function;

  _DloxCompilerRootImpl({
    required final this.debug,
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
  Debug get debug => enclosing.debug;
}

mixin _DloxCompilerMixin implements _Compiler {
  @override
  void emit_loop(
    final Token previous,
    final int loop_start,
    final int line,
  ) {
    final offset = function.chunk.code.length - loop_start + 3;
    if (offset > DLOX_UINT16_MAX) {
      debug.error_at(previous, 'Loop body too large');
    }
    function.chunk.emit_loop(offset, line);
  }

  @override
  int make_constant(
    final Token token,
    final Object? value,
  ) {
    final constant = function.chunk.heap.add_constant(value);
    if (constant > DLOX_UINT8_MAX) {
      debug.error_at(token, 'Too many constants in one chunk');
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
    final jump = function.chunk.code.length - offset - 2;
    if (jump > DLOX_UINT16_MAX) {
      debug.error_at(token, 'Too much code to jump over');
    }
    function.chunk.code[offset] = MapEntry((jump >> 8) & 0xff, function.chunk.code[offset].value);
    function.chunk.code[offset + 1] = MapEntry(jump & 0xff, function.chunk.code[offset + 1].value);
  }

  @override
  void add_local(
    final Token name,
  ) {
    if (locals.length >= DLOX_UINT8_COUNT) {
      debug.error_at(name, 'Too many local variables in function');
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
          debug.error_at(name, 'Can\'t read local variable in its own initializer');
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
    if (upvalues.length == DLOX_UINT8_COUNT) {
      debug.error_at(name, 'Too many closure variables in function');
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
      function.chunk.emit_global(global, line);
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
          debug.error_at(name, 'Already variable with this name in this scope');
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

  List<_Local> get locals;

  List<_Upvalue> get upvalues;

  Debug get debug;

  bool get is_initializer;

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

_Local _init_local(
  final bool is_function,
) {
  return _Local(
    name: TokenImpl(
      type: TokenType.IDENTIFIER,
      lexeme: () {
        if (is_function) {
          return '';
        } else {
          return 'this';
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
// endregion
