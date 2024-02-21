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
  return _DloxCompilerRootImpl(
    function: DloxFunction(
      name: null,
      arity: 0,
      chunk: DloxChunk(),
    ),
    debug: debug,
  )._ast_to_objfunction(
    debug: debug,
    compilation_unit: compilation_unit.decls,
    trace_bytecode: trace_bytecode,
    last_line: last_line,
  );
}

// region private
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
  void emit_loop(
    final Token<TokenAug> previous,
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
    final Token<TokenAug> token,
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

  void patch_jump(
    final Token<TokenAug> token,
    final int offset,
  ) {
    final jump = function.chunk.code.length - offset - 2;
    if (jump > DLOX_UINT16_MAX) {
      debug.error_at(token, 'Too much code to jump over');
    }
    function.chunk.code[offset] = MapEntry((jump >> 8) & 0xff, function.chunk.code[offset].value);
    function.chunk.code[offset + 1] = MapEntry(jump & 0xff, function.chunk.code[offset + 1].value);
  }

  void add_local(
    final Token<TokenAug> name,
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
    final Token<TokenAug> name,
  ) {
    for (int i = locals.length - 1; i >= 0; i--) {
      final local = locals[i];
      if (name.aug.lexeme == local.name.aug.lexeme) {
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
    final Token<TokenAug> name,
    final int index,
    final bool is_local,
  ) {
    assert(
      upvalues.length == function.chunk.upvalue_count,
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
      return function.chunk.upvalue_count++;
    }
  }

  @override
  int? resolve_upvalue(
    final Token<TokenAug> name,
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
      function.chunk.emit_global(global, line);
    }
  }

  void declare_local_variable(
    final Token<TokenAug> name,
  ) {
    // Global variables are implicitly declared.
    if (scope_depth != 0) {
      for (int i = locals.length - 1; i >= 0; i--) {
        final local = locals[i];
        if (local.depth != -1 && local.depth < scope_depth) {
          break; // [negative]
        }
        if (name.aug.lexeme == local.name.aug.lexeme) {
          debug.error_at(name, 'Already variable with this name in this scope');
        }
      }
      add_local(name);
    }
  }

  int make_variable(
    final Token<TokenAug> name,
  ) {
    if (scope_depth > 0) {
      declare_local_variable(name);
      return 0;
    } else {
      return make_constant(name, name.aug.lexeme);
    }
  }

  DloxFunction _ast_to_objfunction({
    required final Debug debug,
    required final List<Declaration> compilation_unit,
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
        final function = DloxFunction(
          name: block.name,
          arity: () {
            int i = 0;
            for (final name in block.args) {
              i++;
              if (i > 255) {
                debug.error_at(name, "Can't have more than 255 parameters");
              }
            }
            return i;
          }(),
          chunk: DloxChunk(),
        );
        final new_compiler = _DloxCompilerWrappedImpl(
          function: function,
          is_initializer: is_initializer,
          local: _init_local(is_function),
          enclosing: this,
        );
        for (final name in block.args) {
          new_compiler.make_variable(name);
          new_compiler.mark_local_variable_initialized();
        }
        for (int k = 0; k < block.args.length; k++) {
          new_compiler.define_variable(0, peek_dist: block.args.length - 1 - k, line: line);
        }
        new_compiler._ast_to_objfunction(
          trace_bytecode: trace_bytecode,
          debug: debug,
          compilation_unit: block.decls,
          last_line: line,
        );
      }

      MapEntry<void Function(int line), void Function(int line)> get_or_set(
        final Token<TokenAug> name,
      ) {
        final local_arg = this.resolve_local(name);
        if (local_arg == null) {
          final upvalue_arg = this.resolve_upvalue(name);
          if (upvalue_arg == null) {
            final constant_arg = this.make_constant(name, name.aug.lexeme);
            return MapEntry(
              (final line) => this.function.chunk.emit_get_global(constant_arg, line),
              (final line) => this.function.chunk.emit_set_global(constant_arg, line),
            );
          } else {
            return MapEntry(
              (final line) => this.function.chunk.emit_get_upvalue(upvalue_arg, line),
              (final line) => this.function.chunk.emit_set_upvalue(upvalue_arg, line),
            );
          }
        } else {
          return MapEntry(
            (final line) => this.function.chunk.emit_get_local(local_arg, line),
            (final line) => this.function.chunk.emit_set_local(local_arg, line),
          );
        }
      }

      void compile_expr(
        final Expr expr,
      ) {
        final self = compile_expr;
        match_expr<void, int>(
          expr: expr,
          string: (final a) {
            this.function.chunk.emit_constant(this.make_constant(a.token, a.token.aug.lexeme), a.aug,);
          },
          number: (final a) {
            final value = double.tryParse(a.value.aug.lexeme);
            if (value == null) {
              debug.error_at(a.value, 'Invalid number');
            } else {
              this.function.chunk.emit_constant(this.make_constant(a.value, value), a.aug);
            }
          },
          object: (final a) {
            this.function.chunk.emit_constant(this.make_constant(a.token, null), a.aug);
          },
          self: (final a) {
            if (this.current_class == null) {
              debug.error_at(a.previous, "Can't use 'this' outside of a class");
            } else {
              get_or_set(a.previous).key(a.aug);
            }
          },
          nil: (final a) => this.function.chunk.emit_nil(a.aug),
          falsity: (final a) => this.function.chunk.emit_false(a.aug),
          truth: (final a) => this.function.chunk.emit_true(a.aug),
          get: (final a) => this.function.chunk.emit_get_property(
                this.make_constant(a.name, a.name.aug.lexeme),
                a.aug,
              ),
          set2: (final a) {
            self(a.arg);
            get_or_set(a.name).value(a.aug);
          },
          negated: (final a) {
            self(a.child);
            this.function.chunk.emit_negate(a.aug);
          },
          not: (final a) {
            self(a.child);
            this.function.chunk.emit_not(a.aug);
          },
          call: (final a) {
            for (final x in a.args) {
              self(x);
            }
            this.function.chunk.emit_call(a.args.length, a.aug);
          },
          set: (final a) {
            self(a.arg);
            this.function.chunk.emit_set_property(this.make_constant(a.name, a.name.aug.lexeme), a.aug);
          },
          invoke: (final a) {
            for (final x in a.args) {
              self(x);
            }
            this.function.chunk.emit_invoke(
                  this.make_constant(a.name, a.name.aug.lexeme),
                  a.args.length,
                  a.aug,
                );
          },
          map: (final a) {
            for (final x in a.entries) {
              self(x.key);
              self(x.value);
            }
            this.function.chunk.emit_map_init(a.entries.length, a.aug);
          },
          list: (final a) {
            for (final x in a.values) {
              self(x);
            }
            if (a.val_count >= 0) {
              this.function.chunk.emit_list_init(a.val_count, a.aug);
            } else {
              this.function.chunk.emit_list_init_range(a.aug);
            }
          },
          minus: (final a) {
            self(a.child);
            this.function.chunk.emit_subtract(a.aug);
          },
          plus: (final a) {
            self(a.child);
            this.function.chunk.emit_add(a.aug);
          },
          slash: (final a) {
            self(a.child);
            this.function.chunk.emit_divide(a.aug);
          },
          star: (final a) {
            self(a.child);
            this.function.chunk.emit_multiply(a.aug);
          },
          g: (final a) {
            self(a.child);
            this.function.chunk.emit_greater(a.aug);
          },
          geq: (final a) {
            self(a.child);
            final line = a.aug;
            this.function.chunk.emit_not_less(line);
          },
          l: (final a) {
            self(a.child);
            this.function.chunk.emit_less(a.aug);
          },
          leq: (final a) {
            self(a.child);
            final line = a.aug;
            this.function.chunk.emit_not_greater(line);
          },
          pow: (final a) {
            self(a.child);
            this.function.chunk.emit_pow(a.aug);
          },
          modulo: (final a) {
            self(a.child);
            this.function.chunk.emit_mod(a.aug);
          },
          neq: (final a) {
            self(a.child);
            this.function.chunk.emit_notequal(a.aug);
          },
          eq: (final a) {
            self(a.child);
            this.function.chunk.emit_equal(a.aug);
          },
          expected: (final a) {},
          getset2: (final a) {
            final setter_child = a.child;
            final line = a.aug;
            final data = get_or_set(a.name);
            data.key(line);
            if (setter_child != null) {
              switch (setter_child.type) {
                case GetsetType.pluseq:
                  self(setter_child.child);
                  this.function.chunk.emit_add(a.aug);
                  data.value(line);
                  break;
                case GetsetType.minuseq:
                  self(setter_child.child);
                  this.function.chunk.emit_subtract(a.aug);
                  data.value(line);
                  break;
                case GetsetType.stareq:
                  self(setter_child.child);
                  this.function.chunk.emit_multiply(a.aug);
                  data.value(line);
                  break;
                case GetsetType.slasheq:
                  self(setter_child.child);
                  this.function.chunk.emit_divide(a.aug);
                  data.value(line);
                  break;
                case GetsetType.poweq:
                  self(setter_child.child);
                  this.function.chunk.emit_pow(a.aug);
                  data.value(line);
                  break;
                case GetsetType.modeq:
                  self(setter_child.child);
                  this.function.chunk.emit_mod(a.aug);
                  data.value(line);
                  break;
              }
            }
          },
          and: (final a) {
            final line = a.aug;
            final end_jump = this.function.chunk.emit_jump_if_false(
                  line,
                );
            this.function.chunk.emit_pop(a.aug);
            self(a.child);
            this.patch_jump(a.token, end_jump);
          },
          or: (final a) {
            final else_jump = this.function.chunk.emit_jump_if_false(a.aug);
            final end_jump = this.function.chunk.emit_jump(a.aug);
            this.patch_jump(a.token, else_jump);
            this.function.chunk.emit_pop(a.aug);
            self(a.child);
            this.patch_jump(a.token, end_jump);
          },
          listgetter: (final a) {
            if (a.first != null) {
              self(a.first!);
            } else {
              this.function.chunk.emit_constant(this.make_constant(a.first_token, DloxNil), a.aug);
            }
            if (a.second != null) {
              self(a.second!);
            } else {
              this.function.chunk.emit_constant(this.make_constant(a.second_token, DloxNil), a.aug);
            }
            this.function.chunk.emit_container_get_range(a.aug);
          },
          listsetter: (final a) {
            if (a.first != null) {
              self(a.first!);
            } else {
              this.function.chunk.emit_constant(this.make_constant(a.token, DloxNil), a.aug);
            }
            if (a.second != null) {
              self(a.second!);
              this.function.chunk.emit_container_set(a.aug);
            } else {
              this.function.chunk.emit_container_get(a.aug);
            }
          },
          superaccess: (final a) {
            if (this.current_class == null) {
              debug.error_at(a.kw, "Can't use 'super' outside of a class");
            } else if (!this.current_class!.has_superclass) {
              debug.error_at(a.kw, "Can't use 'super' in a class with no superclass");
            }
            final name = this.make_constant(a.kw, a.kw.aug.lexeme);
            get_or_set(const TokenImpl(type: TokenType.IDENTIFIER, aug: TokenAug(lexeme: 'this', line: -1)))
                .key(a.aug);
            final _args = a.args;
            if (_args != null) {
              for (final x in _args) {
                self(x);
              }
            }
            get_or_set(const TokenImpl(type: TokenType.IDENTIFIER, aug: TokenAug(lexeme: 'super', line: -1)))
                .key(a.aug);
            if (_args != null) {
              this.function.chunk.emit_super_invoke(name, _args.length, a.aug);
            } else {
              this.function.chunk.emit_get_super(name, a.aug);
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
          final global = this.make_variable(x.key);
          compile_expr(x.value);
          this.define_variable(global, line: a.aug);
        }
      }

      T wrap_in_scope<T>({
        required final T Function() fn,
        required final int line,
      }) {
        this.scope_depth++;
        final val = fn();
        this.scope_depth--;
        while (this.locals.isNotEmpty && this.locals.last.depth > this.scope_depth) {
          if (this.locals.last.is_captured) {
            this.function.chunk.emit_close_upvalue(line);
          } else {
            this.function.chunk.emit_pop(line);
          }
          this.locals.removeLast();
        }
        return val;
      }

      void compile_stmt(
        final Stmt stmt,
      ) {
        stmt.match(
          output: (final a) {
            compile_expr(a.expr);
            this.function.chunk.emit_print(a.aug);
          },
          ret: (final a) {
            final expr = a.expr;
            if (expr == null) {
              final line = a.aug;
              if (this.is_initializer) {
                this.function.chunk.emit_return_local(line);
              } else {
                this.function.chunk.emit_return_nil(line);
              }
            } else {
              if (this.is_initializer) {
                debug.error_at(a.kw, "Can't return a value from an initializer");
              }
              compile_expr(expr);
              this.function.chunk.emit_return(a.aug);
            }
          },
          expr: (final a) {
            compile_expr(a.expr);
            this.function.chunk.emit_pop(a.aug);
          },
          loop: (final a) => wrap_in_scope(
            fn: () {
              final left = a.left;
              final line = a.aug;
              if (left != null) {
                left.match(
                  vari: (final a) {
                    compile_vari(
                      a.decl,
                    );
                  },
                  expr: (final a) {
                    compile_expr(a.expr);
                    this.function.chunk.emit_pop(line);
                  },
                );
              }
              int loop_start = this.function.chunk.code.length;
              int exit_jump = -1;
              final center = a.center;
              if (center != null) {
                compile_expr(center);
                exit_jump = this.function.chunk.emit_jump_if_false(
                      line,
                    );
                this.function.chunk.emit_pop(line);
              }
              final _right = a.right;
              if (_right != null) {
                final body_jump = this.function.chunk.emit_jump(
                      line,
                    );
                final increment_start = this.function.chunk.code.length;
                final _expr = _right;
                compile_expr(_expr);
                this.function.chunk.emit_pop(line);
                this.emit_loop(a.right_kw, loop_start, line);
                loop_start = increment_start;
                this.patch_jump(a.right_kw, body_jump);
              }
              final _stmt = a.body;
              compile_stmt(_stmt);
              this.emit_loop(a.end_kw, loop_start, line);
              if (exit_jump != -1) {
                this.patch_jump(a.end_kw, exit_jump);
                this.function.chunk.emit_pop(line);
              }
            },
            line: a.aug,
          ),
          loop2: (final a) => wrap_in_scope(
            fn: () {
              this.make_variable(a.key_name);
              final line = a.aug;
              this.function.chunk.emit_nil(line);
              this.define_variable(0, line: line); // Remove 0
              final stack_idx = this.locals.length - 1;
              final value_name = a.value_name;
              if (value_name != null) {
                this.make_variable(value_name);
                this.function.chunk.emit_nil(line);
                this.define_variable(0, line: line);
              } else {
                this.add_local(
                  const TokenImpl<TokenAug>(type: TokenType.IDENTIFIER, aug: TokenAug(lexeme: '_for_val_', line: -1)),
                );
                // Emit a zero to permute val & key
                this.function.chunk.emit_constant(
                      this.make_constant(
                        const TokenImpl<TokenAug>(type: TokenType.IDENTIFIER, aug: TokenAug(lexeme: "INVALID", line: -1)),
                        0,
                      ),
                      line,
                    );
                this.mark_local_variable_initialized();
              }
              // Now add two dummy local variables. Idx & entries
              this.add_local(
                const TokenImpl(type: TokenType.IDENTIFIER, aug: TokenAug(lexeme: '_for_idx_', line: -1)),
              );
              this.function.chunk.emit_nil(line);
              this.mark_local_variable_initialized();
              this.add_local(
                const TokenImpl(type: TokenType.IDENTIFIER, aug: TokenAug(lexeme: '_for_iterable_', line: -1)),
              );
              this.function.chunk.emit_nil(line);
              this.mark_local_variable_initialized();
              compile_expr(a.center);
              final loop_start = this.function.chunk.code.length;
              this.function.chunk.emit_container_iterate(stack_idx, line);
              final exit_jump = this.function.chunk.emit_jump_if_false(line);
              this.function.chunk.emit_pop(line);
              final body = a.body;
              compile_stmt(body);
              this.emit_loop(a.exit_token, loop_start, line);
              this.patch_jump(a.exit_token, exit_jump);
              this.function.chunk.emit_pop(line);
            },
            line: a.aug,
          ),
          block: (final a) => wrap_in_scope(
            fn: () {
              for (final x in a.block) {
                debug.restore();
                compile_declaration(x);
              }
            },
            line: a.aug,
          ),
          whil: (final a) {
            final loop_start = this.function.chunk.code.length;
            compile_expr(a.expr);
            final line = a.aug;
            final exit_jump = this.function.chunk.emit_jump_if_false(
                  line,
                );
            this.function.chunk.emit_pop(line);
            final stmt = a.stmt;
            compile_stmt(stmt);
            this.emit_loop(a.exit_kw, loop_start, line);
            this.patch_jump(a.exit_kw, exit_jump);
            this.function.chunk.emit_pop(line);
          },
          conditional: (final a) {
            compile_expr(a.expr);
            final then_jump = this.function.chunk.emit_jump_if_false(a.aug);
            this.function.chunk.emit_pop(a.aug);
            compile_stmt(a.stmt);
            final else_jump = this.function.chunk.emit_jump(
                  a.aug,
                );
            this.patch_jump(a.if_kw, then_jump);
            this.function.chunk.emit_pop(a.aug);
            final other = a.other;
            if (other != null) {
              compile_stmt(other);
            }
            this.patch_jump(a.else_kw, else_jump);
          },
        );
      }

      decl.match(
        clazz: (final a) {
          final name_constant = this.make_constant(
            a.name,
            a.name.aug.lexeme,
          );
          this.current_class = _ClassCompiler(
            enclosing: this.current_class,
            name: a.name,
            has_superclass: a.superclass_name != null,
          );
          this.declare_local_variable(a.name);
          this.function.chunk.emit_class(name_constant, a.aug);
          this.define_variable(name_constant, line: a.aug);
          wrap_in_scope(
            fn: () {
              final superclass_name = a.superclass_name;
              if (superclass_name != null) {
                final class_name = this.current_class!.name!;
                get_or_set(superclass_name).key(a.aug);
                if (class_name.aug.lexeme == superclass_name.aug.lexeme) {
                  debug.error_at(superclass_name, "A class can't inherit from itself");
                }
                this.add_local(
                  const TokenImpl(type: TokenType.IDENTIFIER, aug: TokenAug(lexeme: 'super', line: -1)),
                );
                this.define_variable(0, line: a.aug);
                get_or_set(class_name).key(a.aug);
                this.function.chunk.emit_inherit(a.aug);
              }
              get_or_set(a.name).key(a.aug);
              final functions = a.functions;
              for (final a in functions) {
                visit_fn(a.name.aug.lexeme == 'init', false, a.block, a.aug);
                final line = a.aug;
                this.function.chunk.emit_method(this.make_constant(a.name, a.name.aug.lexeme), line);
              }
              this.function.chunk.emit_pop(a.aug);
              this.current_class = this.current_class!.enclosing;
              return functions;
            },
            line: a.aug,
          );
        },
        fun: (final a) {
          final global = this.make_variable(a.name);
          this.mark_local_variable_initialized();
          visit_fn(false, true, a.block, a.aug);
          this.define_variable(global, line: a.aug);
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
    if (this.is_initializer) {
      this.function.chunk.emit_return_local(last_line);
    } else {
      this.function.chunk.emit_return_nil(last_line);
    }
    if (debug.errors.isEmpty && trace_bytecode) {
      debug.disassemble_chunk(
        this.function.chunk,
        this.function.name ?? '<script>',
      );
    }
    if (this.enclosing != null) {
      final _enclosing = this.enclosing!;
      _enclosing.function.chunk.emit_closure(
        _enclosing.make_constant(
          const TokenImpl(type: TokenType.IDENTIFIER, aug: TokenAug(lexeme: "INVALID", line: -1)),
          this.function,
        ),
        last_line,
      );
      for (final x in this.upvalues) {
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
      return this.function;
    } else {
      return this.function;
    }
    // endregion
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

  int make_constant(
    final Token<TokenAug> token,
    final Object? value,
  );

  int? resolve_local(
    final Token<TokenAug> name,
  );

  int? resolve_upvalue(
    final Token<TokenAug> name,
  );
}

class _ClassCompiler {
  final _ClassCompiler? enclosing;
  final Token<TokenAug>? name;
  final bool has_superclass;

  const _ClassCompiler({
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
      aug: TokenAug(lexeme: () {
        if (is_function) {
          return '';
        } else {
          return 'this';
        }
      }(),
      line: -1,)
    ),
    depth: 0,
    is_captured: false,
  );
}

class _Local {
  final Token<TokenAug> name;
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
  final Token<TokenAug> name;
  final int index;
  final bool is_local;

  const _Upvalue({
    required final this.name,
    required final this.index,
    required final this.is_local,
  });
}
// endregion
