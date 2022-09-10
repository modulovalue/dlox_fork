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
    FunctionType.SCRIPT,
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

// TODO move parsing logic into the parser
// TODO convert ast to bytecode as a separate step
class Compiler with CompilerMixin {
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
  ObjFunction? function;

  @override
  Compiler? get enclosing => null;

  Compiler(
    final this.type, {
    required final this.parser,
    final this.debug_trace_bytecode = false,
  }) : scope_depth = 0, function = ObjFunction() {
    switch(type) {
      case FunctionType.FUNCTION:
        function!.name = this.parser.previous!.str;
        locals.add(Local(const SyntheticTokenImpl(type: TokenType.FUN, str: ''), depth: 0));
        break;
      case FunctionType.INITIALIZER:
        function!.name = this.parser.previous!.str;
        locals.add(Local(const SyntheticTokenImpl(type: TokenType.FUN, str: 'this'), depth: 0));
        break;
      case FunctionType.METHOD:
        function!.name = this.parser.previous!.str;
        locals.add(Local(const SyntheticTokenImpl(type: TokenType.FUN, str: 'this'), depth: 0));
        break;
      case FunctionType.SCRIPT:
        locals.add(Local(const SyntheticTokenImpl(type: TokenType.FUN, str: 'this'), depth: 0));
        break;
    }
  }
}

class CompilerWrapped with CompilerMixin {
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
  ObjFunction? function;

  CompilerWrapped(
    final this.type, {
    required final this.enclosing,
  })  : function = ObjFunction(),
        parser = enclosing.parser,
        current_class = enclosing.current_class,
        scope_depth = enclosing.scope_depth + 1,
        debug_trace_bytecode = enclosing.debug_trace_bytecode {
    if (type != FunctionType.SCRIPT) {
      function!.name = this.parser.previous!.str;
    }
    locals.add(
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
    );
  }
}

mixin CompilerMixin {
  final List<Local> locals = [];
  final List<Upvalue> upvalues = [];
  abstract int scope_depth;
  abstract ClassCompiler? current_class;
  abstract ObjFunction? function;

  // TODO I can't move the parsing routines into the parser
  // TODO  because compilation happens during parsing.
  Parser get parser;

  FunctionType get type;

  CompilerMixin? get enclosing;

  bool get debug_trace_bytecode;

  ObjFunction? end_compiler() {
    emit_return();
    if (parser.errors.isEmpty && debug_trace_bytecode) {
      parser.debug.disassembleChunk(current_chunk, function!.name ?? '<script>');
    }
    return function;
  }

  Chunk get current_chunk {
    return function!.chunk;
  }

  void consume(
    final TokenType type,
    final String message,
  ) {
    parser.consume(type, message);
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
    final constant = current_chunk.addConstant(value);
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
    assert(upvalues.length == function!.upvalueCount, "");
    for (var i = 0; i < upvalues.length; i++) {
      final upvalue = upvalues[i];
      if (upvalue.index == index && upvalue.isLocal == is_local) {
        return i;
      }
    }
    if (upvalues.length == UINT8_COUNT) {
      parser.error('Too many closure variables in function');
      return 0;
    }
    upvalues.add(Upvalue(name, index, is_local));
    return function!.upvalueCount++;
  }

  int resolve_upvalue(
    final SyntheticToken? name,
  ) {
    if (enclosing == null) {
      return -1;
    } else {
      final localIdx = enclosing!.resolve_local(name);
      if (localIdx != -1) {
        final local = enclosing!.locals[localIdx];
        local.isCaptured = true;
        return add_upvalue(local.name, localIdx, true);
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
      return;
    }
    locals.add(Local(name));
  }

  void delare_local_variable() {
    // Global variables are implicitly declared.
    if (scope_depth == 0) {
      return;
    } else {
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
    consume(TokenType.IDENTIFIER, error_message);
    if (scope_depth > 0) {
      delare_local_variable();
      return 0;
    } else {
      return identifier_constant(parser.previous!);
    }
  }

  void mark_local_variable_initialized() {
    if (scope_depth == 0) return;
    locals.last.depth = scope_depth;
  }

  void define_variable(
    final int global, {
    final NaturalToken? token,
    final int peekDist = 0,
  }) {
    final isLocal = scope_depth > 0;
    if (isLocal) {
      mark_local_variable_initialized();
    } else {
      emit_bytes(OpCode.DEFINE_GLOBAL.index, global);
    }
  }

  int argument_list() {
    var argCount = 0;
    if (!parser.check(TokenType.RIGHT_PAREN)) {
      do {
        expression();
        if (argCount == 255) {
          parser.error("Can't have more than 255 arguments");
        }
        argCount++;
      } while (match(TokenType.COMMA));
    }
    consume(TokenType.RIGHT_PAREN, "Expect ')' after arguments");
    return argCount;
  }

  void call(
    final bool canAssign,
  ) {
    final arg_count = argument_list();
    emit_bytes(OpCode.CALL.index, arg_count);
  }

  void get_or_set_variable(
    final SyntheticToken? name,
    final bool canAssign,
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
      if (canAssign) {
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
    if (canAssign && (assign_op != null || match(TokenType.EQUAL))) {
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

  void parse_precedence(
    final Precedence precedence,
  ) {
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

    void Function(bool can_assign)? get_prefix_rule(
      final TokenType type,
    ) {
      switch (type) {
        case TokenType.LEFT_PAREN:
          return (final bool canAssign) {
            expression();
            consume(TokenType.RIGHT_PAREN, "Expect ')' after expression");
          };
        case TokenType.RIGHT_PAREN:
          return null;
        case TokenType.LEFT_BRACE:
          return (final bool canAssign) {
            var valCount = 0;
            if (!parser.check(TokenType.RIGHT_BRACE)) {
              do {
                expression();
                consume(TokenType.COLON, "Expect ':' between map key-value pairs");
                expression();
                valCount++;
              } while (match(TokenType.COMMA));
            }
            consume(TokenType.RIGHT_BRACE, "Expect '}' after map initializer");
            emit_bytes(OpCode.MAP_INIT.index, valCount);
          };
        case TokenType.RIGHT_BRACE:
          return null;
        case TokenType.LEFT_BRACK:
          return (final bool canAssign) {
            var valCount = 0;
            if (!parser.check(TokenType.RIGHT_BRACK)) {
              expression();
              valCount += 1;
              if (parser.match(TokenType.COLON)) {
                expression();
                valCount = -1;
              } else {
                while (match(TokenType.COMMA)) {
                  expression();
                  valCount++;
                }
              }
            }
            consume(TokenType.RIGHT_BRACK, "Expect ']' after list initializer");
            if (valCount >= 0) {
              emit_bytes(OpCode.LIST_INIT.index, valCount);
            } else {
              emit_byte(OpCode.LIST_INIT_RANGE.index);
            }
          };
        case TokenType.RIGHT_BRACK:
          return null;
        case TokenType.COMMA:
          return null;
        case TokenType.DOT:
          return null;
        case TokenType.MINUS:
          return (final a) {
            parse_precedence(Precedence.UNARY);
            emit_op(OpCode.NEGATE);
          };
        case TokenType.PLUS:
          return null;
        case TokenType.SEMICOLON:
          return null;
        case TokenType.SLASH:
          return null;
        case TokenType.STAR:
          return null;
        case TokenType.CARET:
          return null;
        case TokenType.PERCENT:
          return null;
        case TokenType.COLON:
          return null;
        case TokenType.BANG:
          return (final a) {
            parse_precedence(Precedence.UNARY);
            emit_op(OpCode.NOT);
          };
        case TokenType.BANG_EQUAL:
          return null;
        case TokenType.EQUAL:
          return null;
        case TokenType.EQUAL_EQUAL:
          return null;
        case TokenType.GREATER:
          return null;
        case TokenType.GREATER_EQUAL:
          return null;
        case TokenType.LESS:
          return null;
        case TokenType.LESS_EQUAL:
          return null;
        case TokenType.IDENTIFIER:
          return (final bool canAssign) => get_or_set_variable(parser.previous, canAssign);
        case TokenType.STRING:
          // string
          return (final bool canAssign) {
            final str = parser.previous!.str;
            emit_constant(str);
          };
        case TokenType.NUMBER:
          // number
          return (final bool canAssign) {
            final value = double.tryParse(parser.previous!.str!);
            if (value == null) {
              parser.error('Invalid number');
            } else {
              emit_constant(value);
            }
          };
        case TokenType.OBJECT:
          // object
          return (final bool canAssign) {
            emit_constant(null);
          };
        case TokenType.AND:
          // and
          return null;
        case TokenType.CLASS:
          return null;
        case TokenType.ELSE:
          return null;
        case TokenType.FALSE:
          return (final a) => emit_op(OpCode.FALSE);
        case TokenType.FOR:
          return null;
        case TokenType.FUN:
          return null;
        case TokenType.IF:
          return null;
        case TokenType.NIL:
          return (final a) => emit_op(OpCode.NIL);
        case TokenType.OR:
          // or
          return null;
        case TokenType.PRINT:
          return null;
        case TokenType.RETURN:
          return null;
        case TokenType.SUPER:
          // super
          return (final bool canAssign) {
            if (current_class == null) {
              parser.error("Can't use 'super' outside of a class");
            } else if (!current_class!.hasSuperclass) {
              parser.error("Can't use 'super' in a class with no superclass");
            }
            consume(TokenType.DOT, "Expect '.' after 'super'");
            consume(TokenType.IDENTIFIER, 'Expect superclass method name');
            final name = identifier_constant(parser.previous!);
            get_or_set_variable(synthetic_token('this'), false);
            if (match(TokenType.LEFT_PAREN)) {
              final argCount = argument_list();
              get_or_set_variable(synthetic_token('super'), false);
              emit_bytes(OpCode.SUPER_INVOKE.index, name);
              emit_byte(argCount);
            } else {
              get_or_set_variable(synthetic_token('super'), false);
              emit_bytes(OpCode.GET_SUPER.index, name);
            }
          };
        case TokenType.THIS:
          // this
          return (final bool canAssign) {
            if (current_class == null) {
              parser.error("Can't use 'this' outside of a class");
              return;
            }
            get_or_set_variable(parser.previous, false);
          };
        case TokenType.TRUE:
          return (final a) => emit_op(OpCode.TRUE);
        case TokenType.VAR:
          return null;
        case TokenType.WHILE:
          return null;
        case TokenType.BREAK:
          return null;
        case TokenType.CONTINUE:
          return null;
        case TokenType.ERROR:
          return null;
        case TokenType.EOF:
          return null;
        // ignore: no_default_cases
        default:
          return null;
      }
    }

    void Function(bool can_assign)? get_infix_rule(
      final TokenType type,
    ) {
      void parse_binary(
        final bool can_assign,
      ) {
        final operatorType = parser.previous!.type;
        final rule = get_precedence(operatorType);
        parse_precedence(Precedence.values[rule.index + 1]);
        // Emit the operator instruction.
        switch (operatorType) {
          case TokenType.BANG_EQUAL:
            emit_bytes(OpCode.EQUAL.index, OpCode.NOT.index);
            break;
          case TokenType.EQUAL_EQUAL:
            emit_op(OpCode.EQUAL);
            break;
          case TokenType.GREATER:
            emit_op(OpCode.GREATER);
            break;
          case TokenType.GREATER_EQUAL:
            emit_bytes(OpCode.LESS.index, OpCode.NOT.index);
            break;
          case TokenType.LESS:
            emit_op(OpCode.LESS);
            break;
          case TokenType.LESS_EQUAL:
            emit_bytes(OpCode.GREATER.index, OpCode.NOT.index);
            break;
          case TokenType.PLUS:
            emit_op(OpCode.ADD);
            break;
          case TokenType.MINUS:
            emit_op(OpCode.SUBTRACT);
            break;
          case TokenType.STAR:
            emit_op(OpCode.MULTIPLY);
            break;
          case TokenType.SLASH:
            emit_op(OpCode.DIVIDE);
            break;
          case TokenType.CARET:
            emit_op(OpCode.POW);
            break;
          case TokenType.PERCENT:
            emit_op(OpCode.MOD);
            break;
          case TokenType.LEFT_PAREN:
            throw Exception("Unreachable");
          case TokenType.RIGHT_PAREN:
            throw Exception("Unreachable");
          case TokenType.LEFT_BRACE:
            throw Exception("Unreachable");
          case TokenType.RIGHT_BRACE:
            throw Exception("Unreachable");
          case TokenType.LEFT_BRACK:
            throw Exception("Unreachable");
          case TokenType.RIGHT_BRACK:
            throw Exception("Unreachable");
          case TokenType.COMMA:
            throw Exception("Unreachable");
          case TokenType.DOT:
            throw Exception("Unreachable");
          case TokenType.SEMICOLON:
            throw Exception("Unreachable");
          case TokenType.COLON:
            throw Exception("Unreachable");
          case TokenType.BANG:
            throw Exception("Unreachable");
          case TokenType.EQUAL:
            throw Exception("Unreachable");
          case TokenType.IDENTIFIER:
            throw Exception("Unreachable");
          case TokenType.STRING:
            throw Exception("Unreachable");
          case TokenType.NUMBER:
            throw Exception("Unreachable");
          case TokenType.OBJECT:
            throw Exception("Unreachable");
          case TokenType.AND:
            throw Exception("Unreachable");
          case TokenType.CLASS:
            throw Exception("Unreachable");
          case TokenType.ELSE:
            throw Exception("Unreachable");
          case TokenType.FALSE:
            throw Exception("Unreachable");
          case TokenType.FOR:
            throw Exception("Unreachable");
          case TokenType.FUN:
            throw Exception("Unreachable");
          case TokenType.IF:
            throw Exception("Unreachable");
          case TokenType.NIL:
            throw Exception("Unreachable");
          case TokenType.OR:
            throw Exception("Unreachable");
          case TokenType.PRINT:
            throw Exception("Unreachable");
          case TokenType.RETURN:
            throw Exception("Unreachable");
          case TokenType.SUPER:
            throw Exception("Unreachable");
          case TokenType.THIS:
            throw Exception("Unreachable");
          case TokenType.TRUE:
            throw Exception("Unreachable");
          case TokenType.VAR:
            throw Exception("Unreachable");
          case TokenType.WHILE:
            throw Exception("Unreachable");
          case TokenType.IN:
            throw Exception("Unreachable");
          case TokenType.BREAK:
            throw Exception("Unreachable");
          case TokenType.CONTINUE:
            throw Exception("Unreachable");
          case TokenType.ERROR:
            throw Exception("Unreachable");
          case TokenType.COMMENT:
            throw Exception("Unreachable");
          case TokenType.EOF:
            throw Exception("Unreachable");
        }
      }

      switch (type) {
        case TokenType.LEFT_PAREN:
          // grouping
          return call;
        case TokenType.RIGHT_PAREN:
          return null;
        case TokenType.LEFT_BRACE:
          // map init
          return null;
        case TokenType.RIGHT_BRACE:
          return null;
        case TokenType.LEFT_BRACK:
          // list index
          return (final bool canAssign) {
            var getRange = match(TokenType.COLON);
            // Left hand side operand
            if (getRange) {
              emit_constant(Nil);
            } else {
              expression();
              getRange = match(TokenType.COLON);
            }
            // Right hand side operand
            if (match(TokenType.RIGHT_BRACK)) {
              if (getRange) emit_constant(Nil);
            } else {
              if (getRange) expression();
              consume(TokenType.RIGHT_BRACK, "Expect ']' after list indexing");
            }
            // Emit operation
            if (getRange) {
              emit_op(OpCode.CONTAINER_GET_RANGE);
            } else if (canAssign && match(TokenType.EQUAL)) {
              expression();
              emit_op(OpCode.CONTAINER_SET);
            } else {
              emit_op(OpCode.CONTAINER_GET);
            }
          };
        case TokenType.RIGHT_BRACK:
          return null;
        case TokenType.COMMA:
          return null;
        case TokenType.DOT:
          // dot
          return (final bool canAssign) {
            consume(TokenType.IDENTIFIER, "Expect property name after '.'");
            final name = identifier_constant(parser.previous!);
            if (canAssign && match(TokenType.EQUAL)) {
              expression();
              emit_bytes(OpCode.SET_PROPERTY.index, name);
            } else if (match(TokenType.LEFT_PAREN)) {
              final argCount = argument_list();
              emit_bytes(OpCode.INVOKE.index, name);
              emit_byte(argCount);
            } else {
              emit_bytes(OpCode.GET_PROPERTY.index, name);
            }
          };
        case TokenType.MINUS:
          return parse_binary;
        case TokenType.PLUS:
          return parse_binary;
        case TokenType.SEMICOLON:
          return null;
        case TokenType.SLASH:
          return parse_binary;
        case TokenType.STAR:
          return parse_binary;
        case TokenType.CARET:
          return parse_binary;
        case TokenType.PERCENT:
          return parse_binary;
        case TokenType.COLON:
          return null;
        case TokenType.BANG:
          return null;
        case TokenType.BANG_EQUAL:
          return parse_binary;
        case TokenType.EQUAL:
          return null;
        case TokenType.EQUAL_EQUAL:
          return parse_binary;
        case TokenType.GREATER:
          return parse_binary;
        case TokenType.GREATER_EQUAL:
          return parse_binary;
        case TokenType.LESS:
          return parse_binary;
        case TokenType.LESS_EQUAL:
          return parse_binary;
        case TokenType.IDENTIFIER:
          return null;
        case TokenType.STRING:
          return null;
        case TokenType.NUMBER:
          return null;
        case TokenType.OBJECT:
          return null;
        case TokenType.AND:
          return (final bool canAssign) {
            final endJump = emit_jump(OpCode.JUMP_IF_FALSE);
            emit_op(OpCode.POP);
            parse_precedence(Precedence.AND);
            patch_jump(endJump);
          };
        case TokenType.CLASS:
          return null;
        case TokenType.ELSE:
          return null;
        case TokenType.FALSE:
          return null;
        case TokenType.FOR:
          return null;
        case TokenType.FUN:
          return null;
        case TokenType.IF:
          return null;
        case TokenType.NIL:
          return null;
        case TokenType.OR:
          return (final bool canAssign) {
            final elseJump = emit_jump(OpCode.JUMP_IF_FALSE);
            final endJump = emit_jump(OpCode.JUMP);
            patch_jump(elseJump);
            emit_op(OpCode.POP);
            parse_precedence(Precedence.OR);
            patch_jump(endJump);
          };
        case TokenType.PRINT:
          return null;
        case TokenType.RETURN:
          return null;
        case TokenType.SUPER:
          return null;
        case TokenType.THIS:
          return null;
        case TokenType.TRUE:
          return null;
        case TokenType.VAR:
          return null;
        case TokenType.WHILE:
          return null;
        case TokenType.BREAK:
          return null;
        case TokenType.CONTINUE:
          return null;
        case TokenType.ERROR:
          return null;
        case TokenType.EOF:
          return null;
        // ignore: no_default_cases
        default:
          return null;
      }
    }

    parser.advance();
    final prefix_rule = get_prefix_rule(parser.previous!.type);
    if (prefix_rule == null) {
      parser.error('Expect expression');
    } else {
      final can_assign = precedence.index <= Precedence.ASSIGNMENT.index;
      prefix_rule(can_assign);
      while (precedence.index <= get_precedence(parser.current!.type).index) {
        parser.advance();
        final infix_rule = get_infix_rule(parser.previous!.type);
        if (infix_rule != null) {
          infix_rule(can_assign);
        } else {
          throw Exception("Invalid State");
        }
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

  Block block() {
    final decls = <Declaration>[];
    while (!parser.check(TokenType.RIGHT_BRACE) && !parser.check(TokenType.EOF)) {
      decls.add(declaration());
    }
    consume(TokenType.RIGHT_BRACE, 'Unterminated block');
    return Block(
      decls: decls,
    );
  }

  Declaration declaration() {
    void begin_scope() {
      scope_depth++;
    }

    void end_scope() {
      scope_depth--;
      while (locals.isNotEmpty && locals.last.depth > scope_depth) {
        if (locals.last.isCaptured) {
          emit_op(OpCode.CLOSE_UPVALUE);
        } else {
          emit_op(OpCode.POP);
        }
        locals.removeLast();
      }
    }

    DeclarationVari var_declaration() {
      do {
        final global = parse_variable('Expect variable name');
        final token = parser.previous;
        if (match(TokenType.EQUAL)) {
          expression();
        } else {
          emit_op(OpCode.NIL);
        }
        define_variable(global, token: token);
      } while (match(TokenType.COMMA));
      consume(TokenType.SEMICOLON, 'Expect a newline after variable declaration');
      return const DeclarationVari();
    }

    Stmt statement() {
      Expr expressionStatement() {
        final expr = expression();
        consume(TokenType.SEMICOLON, 'Expect a newline after expression');
        emit_op(OpCode.POP);
        return expr;
      }

      if (match(TokenType.PRINT)) {
        // print statement
        expression();
        consume(TokenType.SEMICOLON, 'Expect a newline after value');
        emit_op(OpCode.PRINT);
        return const StmtOutput();
      } else if (match(TokenType.FOR)) {
        // for statement check
        if (match(TokenType.LEFT_PAREN)) {
          // legacy for statement
          // Deprecated
          begin_scope();
          // consume(TokenType.LEFT_PAREN, "Expect '(' after 'for'");
          if (match(TokenType.SEMICOLON)) {
            // No initializer.
          } else if (match(TokenType.VAR)) {
            var_declaration();
          } else {
            expressionStatement();
          }
          var loopStart = current_chunk.count;
          var exitJump = -1;
          if (!match(TokenType.SEMICOLON)) {
            expression();
            consume(TokenType.SEMICOLON, "Expect ';' after loop condition");
            exitJump = emit_jump(OpCode.JUMP_IF_FALSE);
            emit_op(OpCode.POP); // Condition.
          }
          if (!match(TokenType.RIGHT_PAREN)) {
            final bodyJump = emit_jump(OpCode.JUMP);
            final incrementStart = current_chunk.count;
            expression();
            emit_op(OpCode.POP);
            consume(TokenType.RIGHT_PAREN, "Expect ')' after for clauses");
            emit_loop(loopStart);
            loopStart = incrementStart;
            patch_jump(bodyJump);
          }
          statement();
          emit_loop(loopStart);
          if (exitJump != -1) {
            patch_jump(exitJump);
            emit_op(OpCode.POP); // Condition.
          }
          end_scope();
        } else {
          // for statement
          begin_scope();
          // Key variable
          parse_variable('Expect variable name'); // Streamline those operations
          emit_op(OpCode.NIL);
          define_variable(0, token: parser.previous); // Remove 0
          final stackIdx = locals.length - 1;
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
          consume(TokenType.IN, "Expect 'in' after loop variables");
          expression(); // Iterable
          // Iterator
          final loopStart = current_chunk.count;
          emit_bytes(OpCode.CONTAINER_ITERATE.index, stackIdx);
          final exitJump = emit_jump(OpCode.JUMP_IF_FALSE);
          emit_op(OpCode.POP); // Condition
          // Body
          statement();
          emit_loop(loopStart);
          // Exit
          patch_jump(exitJump);
          emit_op(OpCode.POP); // Condition
          end_scope();
        }
        return const StmtLoop();
      } else if (match(TokenType.IF)) {
        // if statement
        // consume(TokenType.LEFT_PAREN, "Expect '(' after 'if'");
        expression();
        // consume(TokenType.RIGHT_PAREN, "Expect ')' after condition"); // [paren]
        final thenJump = emit_jump(OpCode.JUMP_IF_FALSE);
        emit_op(OpCode.POP);
        statement();
        final elseJump = emit_jump(OpCode.JUMP);
        patch_jump(thenJump);
        emit_op(OpCode.POP);
        if (match(TokenType.ELSE)) statement();
        patch_jump(elseJump);
        return const StmtConditional();
      } else if (match(TokenType.RETURN)) {
        // return statement
        // if (type == FunctionType.SCRIPT) {
        //   parser.error("Can't return from top-level code");
        // }
        if (match(TokenType.SEMICOLON)) {
          emit_return();
        } else {
          if (type == FunctionType.INITIALIZER) {
            parser.error("Can't return a value from an initializer");
          }
          expression();
          consume(TokenType.SEMICOLON, 'Expect a newline after return value');
          emit_op(OpCode.RETURN);
        }
        return const StmtRet();
      } else if (match(TokenType.WHILE)) {
        final loopStart = current_chunk.count;
        // consume(TokenType.LEFT_PAREN, "Expect '(' after 'while'");
        expression();
        // consume(TokenType.RIGHT_PAREN, "Expect ')' after condition");
        final exitJump = emit_jump(OpCode.JUMP_IF_FALSE);
        emit_op(OpCode.POP);
        statement();
        emit_loop(loopStart);
        patch_jump(exitJump);
        emit_op(OpCode.POP);
        return const StmtWhil();
      } else if (match(TokenType.LEFT_BRACE)) {
        begin_scope();
        block();
        end_scope();
        return const StmtBlock();
      } else {
        return StmtExpr(
          expr: expressionStatement(),
        );
      }
    }

    Block function_block(
      final FunctionType type,
    ) {
      final compiler = CompilerWrapped(type, enclosing: this);
      // beginScope(); // [no-end-scope]
      // not needed because of wrapped compiler scope propagation

      // Compile the parameter list.
      // final functionToken = parser.previous;
      compiler.consume(TokenType.LEFT_PAREN, "Expect '(' after function name");
      final args = <NaturalToken?>[];
      if (!compiler.parser.check(TokenType.RIGHT_PAREN)) {
        do {
          compiler.function!.arity++;
          if (compiler.function!.arity > 255) {
            compiler.parser.errorAtCurrent("Can't have more than 255 parameters");
          }
          compiler.parse_variable('Expect parameter name');
          compiler.mark_local_variable_initialized();
          args.add(compiler.parser.previous);
        } while (compiler.match(TokenType.COMMA));
      }
      for (var k = 0; k < args.length; k++) {
        compiler.define_variable(0, token: args[k], peekDist: args.length - 1 - k);
      }
      compiler.consume(TokenType.RIGHT_PAREN, "Expect ')' after parameters");
      // The body.
      compiler.consume(TokenType.LEFT_BRACE, 'Expect function body');
      final block = compiler.block();
      // Create the function object.
      final function = compiler.end_compiler();
      emit_bytes(OpCode.CLOSURE.index, make_constant(function));
      for (var i = 0; i < compiler.upvalues.length; i++) {
        emit_byte(compiler.upvalues[i].isLocal ? 1 : 0);
        emit_byte(compiler.upvalues[i].index);
      }
      return block;
    }

    final Declaration decl = () {
      if (match(TokenType.CLASS)) {
        // class declaration
        consume(TokenType.IDENTIFIER, 'Expect class name');
        final className = parser.previous;
        final nameConstant = identifier_constant(parser.previous!);
        delare_local_variable();
        emit_bytes(OpCode.CLASS.index, nameConstant);
        define_variable(nameConstant);
        final classCompiler = ClassCompiler(current_class, parser.previous, false);
        current_class = classCompiler;
        if (match(TokenType.LESS)) {
          consume(TokenType.IDENTIFIER, 'Expect superclass name');
          get_or_set_variable(parser.previous, false);
          if (identifiers_equal(className!, parser.previous!)) {
            parser.error("A class can't inherit from itself");
          }
          begin_scope();
          add_local(synthetic_token('super'));
          define_variable(0);
          get_or_set_variable(className, false);
          emit_op(OpCode.INHERIT);
          classCompiler.hasSuperclass = true;
        }
        get_or_set_variable(className, false);
        consume(TokenType.LEFT_BRACE, 'Expect class body');
        while (!parser.check(TokenType.RIGHT_BRACE) && !parser.check(TokenType.EOF)) {
          // parse method
          consume(TokenType.IDENTIFIER, 'Expect method name');
          final identifier = parser.previous!;
          final constant = identifier_constant(identifier);
          var type = FunctionType.METHOD;
          if (identifier.str == 'init') {
            type = FunctionType.INITIALIZER;
          }
          function_block(type);
          emit_bytes(OpCode.METHOD.index, constant);
        }
        consume(TokenType.RIGHT_BRACE, 'Unterminated class body');
        emit_op(OpCode.POP);
        if (classCompiler.hasSuperclass) {
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
  bool isCaptured = false;

  Local(
      final this.name, {
        final this.depth = -1,
        final this.isCaptured = false,
      });

  bool get initialized {
    return depth >= 0;
  }
}

class Upvalue {
  final SyntheticToken? name;
  final int index;
  final bool isLocal;

  const Upvalue(
      final this.name,
      final this.index,
      final this.isLocal,
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
  bool hasSuperclass;

  ClassCompiler(
      final this.enclosing,
      final this.name,
      final this.hasSuperclass,
      );
}

class CompilerResult {
  final ObjFunction? function;
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
  })  : debug = Debug(silent),
        errors = [],
        current_idx = 0,
        panic_mode = false;

  void errorAt(
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

  void error(final String message) {
    errorAt(previous, message);
  }

  void errorAtCurrent(final String? message) {
    errorAt(current, message);
  }

  void advance() {
    second_previous = previous; // TODO: is it needed?
    previous = current;
    while (current_idx < tokens.length) {
      current = tokens[current_idx++];
      // Skip invalid tokens
      if (current!.type == TokenType.ERROR) {
        errorAtCurrent(current!.str);
      } else if (current!.type != TokenType.COMMENT) {
        break;
      }
    }
  }

  void consume(final TokenType type, final String message) {
    if (current!.type == type) {
      advance();
    } else {
      errorAtCurrent(message);
    }
  }

  bool check(final TokenType type) {
    return current!.type == type;
  }

  bool matchPair(final TokenType first, final TokenType second) {
    if (!check(first) || current_idx >= tokens.length || tokens[current_idx].type != second) {
      return false;
    } else {
      advance();
      advance();
      return true;
    }
  }

  bool match(final TokenType type) {
    if (!check(type)) {
      return false;
    } else {
      advance();
      return true;
    }
  }
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
      str.write(val == null ? '⮐' : valueToString(val, maxChars: maxChars - str.length));
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

int hashString(final String key) {
  var hash = 2166136261;
  for (var i = 0; i < key.length; i++) {
    hash ^= key.codeUnitAt(i);
    hash *= 16777619;
  }
  return hash;
}

String functionToString(final ObjFunction function) {
  if (function.name == null) {
    return '<script>';
  }
  return '<fn ${function.name}>';
}

void printObject(final Object value) {
  print(objectToString(value));
}

String? objectToString(final Object? value, {final int maxChars = 100}) {
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

  LangError(this.type, this.msg, {this.line, this.token});

  void dump(final Debug debug) {
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
  CompilerError(final NaturalToken token, final String? msg)
      : super('Compile', msg, token: token, line: token.loc.line);
}

class RuntimeError extends LangError {
  final RuntimeError? link;

  RuntimeError(final int line, final String? msg, {this.link}) : super('Runtime', msg, line: line);
}
// endregion

// region debug
class Debug {
  final bool silent;
  final buf = StringBuffer();

  Debug(this.silent);

  String clear() {
    final str = buf.toString();
    buf.clear();
    return str;
  }

  void stdwrite(final String? string) {
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

  void stdwriteln([final String? string]) {
    return stdwrite((string ?? '') + '\n');
  }

  void printValue(final Object? value) {
    stdwrite(valueToString(value));
  }

  void disassembleChunk(final Chunk chunk, final String name) {
    stdwrite("==" + name + "==\n");
    int? prevLine = -1;
    for (var offset = 0; offset < chunk.code.length;) {
      offset = disassembleInstruction(prevLine, chunk, offset);
      prevLine = offset > 0 ? chunk.lines[offset - 1] : null;
    }
  }

  int constantInstruction(final String name, final Chunk chunk, final int offset) {
    final constant = chunk.code[offset + 1];
    stdwrite(sprintf('%-16s %4d \'', [name, constant]));
    printValue(chunk.constants[constant]);
    stdwrite('\'\n');
    return offset + 2;
  }

  int initializerListInstruction(final String name, final Chunk chunk, final int offset) {
    final nArgs = chunk.code[offset + 1];
    stdwriteln(sprintf('%-16s %4d', [name, nArgs]));
    return offset + 2;
  }

  int invokeInstruction(final String name, final Chunk chunk, final int offset) {
    final constant = chunk.code[offset + 1];
    final argCount = chunk.code[offset + 2];
    stdwrite(sprintf('%-16s (%d args) %4d \'', [name, argCount, constant]));
    printValue(chunk.constants[constant]);
    stdwrite('\'\n');
    return offset + 3;
  }

  int simpleInstruction(final String name, final int offset) {
    stdwrite(sprintf('%s\n', [name]));
    return offset + 1;
  }

  int byteInstruction(final String name, final Chunk chunk, final int offset) {
    final slot = chunk.code[offset + 1];
    stdwrite(sprintf('%-16s %4d\n', [name, slot]));
    return offset + 2; // [debug]
  }

  int jumpInstruction(final String name, final int sign, final Chunk chunk, final int offset) {
    var jump = chunk.code[offset + 1] << 8;
    jump |= chunk.code[offset + 2];
    stdwrite(sprintf('%-16s %4d -> %d\n', [name, offset, offset + 3 + sign * jump]));
    return offset + 3;
  }

  int disassembleInstruction(final int? prevLine, final Chunk chunk, int offset) {
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
        return constantInstruction('OP_CONSTANT', chunk, offset);
      case OpCode.NIL:
        return simpleInstruction('OP_NIL', offset);
      case OpCode.TRUE:
        return simpleInstruction('OP_TRUE', offset);
      case OpCode.FALSE:
        return simpleInstruction('OP_FALSE', offset);
      case OpCode.POP:
        return simpleInstruction('OP_POP', offset);
      case OpCode.GET_LOCAL:
        return byteInstruction('OP_GET_LOCAL', chunk, offset);
      case OpCode.SET_LOCAL:
        return byteInstruction('OP_SET_LOCAL', chunk, offset);
      case OpCode.GET_GLOBAL:
        return constantInstruction('OP_GET_GLOBAL', chunk, offset);
      case OpCode.DEFINE_GLOBAL:
        return constantInstruction('OP_DEFINE_GLOBAL', chunk, offset);
      case OpCode.SET_GLOBAL:
        return constantInstruction('OP_SET_GLOBAL', chunk, offset);
      case OpCode.GET_UPVALUE:
        return byteInstruction('OP_GET_UPVALUE', chunk, offset);
      case OpCode.SET_UPVALUE:
        return byteInstruction('OP_SET_UPVALUE', chunk, offset);
      case OpCode.GET_PROPERTY:
        return constantInstruction('OP_GET_PROPERTY', chunk, offset);
      case OpCode.SET_PROPERTY:
        return constantInstruction('OP_SET_PROPERTY', chunk, offset);
      case OpCode.GET_SUPER:
        return constantInstruction('OP_GET_SUPER', chunk, offset);
      case OpCode.EQUAL:
        return simpleInstruction('OP_EQUAL', offset);
      case OpCode.GREATER:
        return simpleInstruction('OP_GREATER', offset);
      case OpCode.LESS:
        return simpleInstruction('OP_LESS', offset);
      case OpCode.ADD:
        return simpleInstruction('OP_ADD', offset);
      case OpCode.SUBTRACT:
        return simpleInstruction('OP_SUBTRACT', offset);
      case OpCode.MULTIPLY:
        return simpleInstruction('OP_MULTIPLY', offset);
      case OpCode.DIVIDE:
        return simpleInstruction('OP_DIVIDE', offset);
      case OpCode.POW:
        return simpleInstruction('OP_POW', offset);
      case OpCode.NOT:
        return simpleInstruction('OP_NOT', offset);
      case OpCode.NEGATE:
        return simpleInstruction('OP_NEGATE', offset);
      case OpCode.PRINT:
        return simpleInstruction('OP_PRINT', offset);
      case OpCode.JUMP:
        return jumpInstruction('OP_JUMP', 1, chunk, offset);
      case OpCode.JUMP_IF_FALSE:
        return jumpInstruction('OP_JUMP_IF_FALSE', 1, chunk, offset);
      case OpCode.LOOP:
        return jumpInstruction('OP_LOOP', -1, chunk, offset);
      case OpCode.CALL:
        return byteInstruction('OP_CALL', chunk, offset);
      case OpCode.INVOKE:
        return invokeInstruction('OP_INVOKE', chunk, offset);
      case OpCode.SUPER_INVOKE:
        return invokeInstruction('OP_SUPER_INVOKE', chunk, offset);
      case OpCode.CLOSURE:
        {
          // ignore: parameter_assignments
          offset++;
          // ignore: parameter_assignments
          final constant = chunk.code[offset++];
          stdwrite(sprintf('%-16s %4d ', ['OP_CLOSURE', constant]));
          printValue(chunk.constants[constant]);
          stdwrite('\n');
          final function = (chunk.constants[constant] as ObjFunction?)!;
          for (var j = 0; j < function.upvalueCount; j++) {
            // ignore: parameter_assignments
            final isLocal = chunk.code[offset++] == 1;
            // ignore: parameter_assignments
            final index = chunk.code[offset++];
            stdwrite(sprintf('%04d      |                     %s %d\n',
                [offset - 2, isLocal ? 'local' : 'upvalue', index]));
          }
          return offset;
        }
      case OpCode.CLOSE_UPVALUE:
        return simpleInstruction('OP_CLOSE_UPVALUE', offset);
      case OpCode.RETURN:
        return simpleInstruction('OP_RETURN', offset);
      case OpCode.CLASS:
        return constantInstruction('OP_CLASS', chunk, offset);
      case OpCode.INHERIT:
        return simpleInstruction('OP_INHERIT', offset);
      case OpCode.METHOD:
        return constantInstruction('OP_METHOD', chunk, offset);
      case OpCode.LIST_INIT:
        return initializerListInstruction('OP_LIST_INIT', chunk, offset);
      case OpCode.LIST_INIT_RANGE:
        return simpleInstruction('LIST_INIT_RANGE', offset);
      case OpCode.MAP_INIT:
        return initializerListInstruction('OP_MAP_INIT', chunk, offset);
      case OpCode.CONTAINER_GET:
        return simpleInstruction('OP_CONTAINER_GET', offset);
      case OpCode.CONTAINER_SET:
        return simpleInstruction('OP_CONTAINER_SET', offset);
      case OpCode.CONTAINER_GET_RANGE:
        return simpleInstruction('CONTAINER_GET_RANGE', offset);
      case OpCode.CONTAINER_ITERATE:
        return simpleInstruction('CONTAINER_ITERATE', offset);
      // ignore: no_default_cases
      default:
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
  final _constantMap = <Object?, int>{};

  // Trace information
  final List<int> lines = [];

  Chunk();

  int get count => code.length;

  void write(final int byte, final NaturalToken token) {
    code.add(byte);
    lines.add(token.loc.line);
  }

  int addConstant(final Object? value) {
    final idx = _constantMap[value];
    if (idx != null) return idx;
    // Add entry
    constants.add(value);
    _constantMap[value] = constants.length - 1;
    return constants.length - 1;
  }
}
// endregion

// region value
class Nil {}

Object valueCloneDeep(final Object value) {
  if (value is Map) {
    return Map.fromEntries(value.entries.map((final e) => valueCloneDeep(e) as MapEntry<Object, Object>));
  } else if (value is List<Object>) {
    return value.map((final e) => valueCloneDeep(e)).toList();
  } else {
    // TODO: clone object instances
    return value;
  }
}

String listToString(final List<dynamic> list, {final int maxChars = 100}) {
  final buf = StringBuffer('[');
  for (var k = 0; k < list.length; k++) {
    if (k > 0) buf.write(',');
    buf.write(valueToString(list[k], maxChars: maxChars - buf.length));
    if (buf.length > maxChars) {
      buf.write('...');
      break;
    }
  }
  buf.write(']');
  return buf.toString();
}

String mapToString(final Map<dynamic, dynamic> map, {final int maxChars = 100}) {
  final buf = StringBuffer('{');
  final entries = map.entries.toList();
  for (var k = 0; k < entries.length; k++) {
    if (k > 0) buf.write(',');
    buf.write(valueToString(entries[k].key, maxChars: maxChars - buf.length));
    buf.write(':');
    buf.write(valueToString(
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

String? valueToString(
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
    return listToString(value, maxChars: maxChars);
  } else if (value is Map) {
    return mapToString(value, maxChars: maxChars);
  } else {
    return objectToString(value, maxChars: maxChars);
  }
}

// Copied from foundation.dart
bool listEquals<T>(final List<T>? a, final List<T>? b) {
  if (a == null) return b == null;
  if (b == null || a.length != b.length) return false;
  if (identical(a, b)) return true;
  for (var index = 0; index < a.length; index += 1) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

bool mapEquals<T, U>(final Map<T, U>? a, final Map<T, U>? b) {
  if (a == null) return b == null;
  if (b == null || a.length != b.length) return false;
  if (identical(a, b)) return true;
  for (final key in a.keys) {
    if (!b.containsKey(key) || b[key] != a[key]) return false;
  }
  return true;
}

bool valuesEqual(final Object? a, final Object? b) {
  // TODO: confirm behavior (especially for deep equality)
  // Equality relied on this function, but not hashmap indexing
  // It might trigger strange cases where two equal lists don't have the same hashcode
  if (a is List<dynamic> && b is List<dynamic>) {
    return listEquals<dynamic>(a, b);
  } else if (a is Map<dynamic, dynamic> && b is Map<dynamic, dynamic>) {
    return mapEquals<dynamic, dynamic>(a, b);
  } else {
    return a == b;
  }
}
// endregion

// region vm
const int FRAMES_MAX = 64;
const int STACK_MAX = FRAMES_MAX * UINT8_COUNT;
const BATCH_COUNT = 1000000; // Must be fast enough

class CallFrame {
  late ObjClosure closure;
  late int ip;
  late Chunk chunk; // Additionnal reference
  late int slotsIdx; // Index in stack of the frame slot
}

class InterpreterResult {
  final List<LangError> errors;
  final int lastLine;
  final int stepCount;
  final Object? returnValue;

  bool get done {
    return errors.isNotEmpty || returnValue != null;
  }

  InterpreterResult(
    final List<LangError> errors,
    this.lastLine,
    this.stepCount,
    this.returnValue,
  ) : errors = List<LangError>.from(errors);
}

class FunctionParams {
  final String? function;
  final List<Object>? args;
  final Map<String?, Object?>? globals;

  FunctionParams({this.function, this.args, this.globals});
}

class VM {
  static const INIT_STRING = 'init';
  final List<CallFrame?> frames = List<CallFrame?>.filled(FRAMES_MAX, null);
  final List<Object?> stack = List<Object?>.filled(STACK_MAX, null);

  // VM state
  final List<RuntimeError> errors = [];
  final Table globals = Table();
  final Table strings = Table();
  CompilerResult? compilerResult;
  int frameCount = 0;
  int stackTop = 0;
  ObjUpvalue? openUpvalues;

  // Debug variables
  int stepCount = 0;
  int line = -1;

  // int skipLine = -1;
  bool hasOp = false;

  // Debug API
  bool traceExecution = false;
  bool stepCode = false;
  late Debug err_debug;
  late Debug trace_debug;
  late Debug stdout;

  VM({
    required final bool silent,
  }) {
    err_debug = Debug(silent);
    trace_debug = Debug(silent);
    stdout = Debug(silent);
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
      stepCount,
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
    stackTop = 0;
    frameCount = 0;
    openUpvalues = null;
    // Reset debug values
    stepCount = 0;
    line = -1;
    hasOp = false;
    stdout.clear();
    err_debug.clear();
    trace_debug.clear();
    // Reset flags
    stepCode = false;
    // Define natives
    defineNatives();
  }

  void setFunction(
    final CompilerResult compilerResult,
    final FunctionParams params,
  ) {
    _reset();
    // Set compiler result
    if (compilerResult.errors.isNotEmpty) {
      throw Exception('Compiler result had errors');
    }
    this.compilerResult = compilerResult;
    // Set function
    var fun = compilerResult.function;
    if (params.function != null) {
      fun = compilerResult.function!.chunk.constants.firstWhere((final obj) {
        return obj is ObjFunction && obj.name == params.function;
      }) as ObjFunction?;
      if (fun == null) throw Exception('Function not found ${params.function}');
    }
    // Set globals
    if (params.globals != null) globals.data.addAll(params.globals!);
    // Init VM
    final closure = ObjClosure(fun!);
    push(closure);
    if (params.args != null) params.args!.forEach((final arg) => push(arg));
    callValue(closure, params.args?.length ?? 0);
  }

  void defineNatives() {
    NATIVE_FUNCTIONS.forEach((final function) {
      globals.setVal(function.name, function);
    });
    NATIVE_VALUES.forEach((final key, final value) {
      globals.setVal(key, value);
    });
    NATIVE_CLASSES.forEach((final key, final value) {
      globals.setVal(key, value);
    });
  }

  void push(final Object? value) {
    stack[stackTop++] = value;
  }

  Object? pop() {
    return stack[--stackTop];
  }

  Object? peek(
    final int distance,
  ) {
    return stack[stackTop - distance - 1];
  }

  bool call(
    final ObjClosure closure,
    final int argCount,
  ) {
    if (argCount != closure.function.arity) {
      runtimeError('Expected %d arguments but got %d', [closure.function.arity, argCount]);
      return false;
    }

    if (frameCount == FRAMES_MAX) {
      runtimeError('Stack overflow');
      return false;
    }

    final frame = frames[frameCount++]!;
    frame.closure = closure;
    frame.chunk = closure.function.chunk;
    frame.ip = 0;

    frame.slotsIdx = stackTop - argCount - 1;
    return true;
  }

  bool callValue(
    final Object? callee,
    final int argCount,
  ) {
    if (callee is ObjBoundMethod) {
      stack[stackTop - argCount - 1] = callee.receiver;
      return call(callee.method, argCount);
    } else if (callee is ObjClass) {
      stack[stackTop - argCount - 1] = ObjInstance(klass: callee);
      final initializer = callee.methods.getVal(INIT_STRING);
      if (initializer != null) {
        return call(initializer as ObjClosure, argCount);
      } else if (argCount != 0) {
        runtimeError('Expected 0 arguments but got %d', [argCount]);
        return false;
      }
      return true;
    } else if (callee is ObjClosure) {
      return call(callee, argCount);
    } else if (callee is ObjNative) {
      final res = callee.fn(stack, stackTop - argCount, argCount);
      stackTop -= argCount + 1;
      push(res);
      return true;
    } else if (callee is NativeClassCreator) {
      try {
        final res = callee(stack, stackTop - argCount, argCount);
        stackTop -= argCount + 1;
        push(res);
      } on NativeError catch (e) {
        runtimeError(e.format, e.args);
        return false;
      }
      return true;
    } else {
      runtimeError('Can only call functions and classes');
      return false;
    }
  }

  bool invokeFromClass(
    final ObjClass klass,
    final String? name,
    final int argCount,
  ) {
    final method = klass.methods.getVal(name);
    if (method == null) {
      runtimeError("Undefined property '%s'", [name]);
      return false;
    }
    return call(method as ObjClosure, argCount);
  }

  bool invokeMap(
    final Map<dynamic, dynamic> map,
    final String? name,
    final int argCount,
  ) {
    if (!MAP_NATIVE_FUNCTIONS.containsKey(name)) {
      runtimeError('Unknown method for map');
      return false;
    }
    final function = MAP_NATIVE_FUNCTIONS[name!]!;
    try {
      final rtn = function(map, stack, stackTop - argCount, argCount);
      stackTop -= argCount + 1;
      push(rtn);
      return true;
    } on NativeError catch (e) {
      runtimeError(e.format, e.args);
      return false;
    }
  }

  bool invokeList(
    final List<dynamic> list,
    final String? name,
    final int argCount,
  ) {
    if (!LIST_NATIVE_FUNCTIONS.containsKey(name)) {
      runtimeError('Unknown method for list');
      return false;
    }
    final function = LIST_NATIVE_FUNCTIONS[name!]!;
    try {
      final rtn = function(list, stack, stackTop - argCount, argCount);
      stackTop -= argCount + 1;
      push(rtn);
      return true;
    } on NativeError catch (e) {
      runtimeError(e.format, e.args);
      return false;
    }
  }

  bool invokeString(
    final String str,
    final String? name,
    final int argCount,
  ) {
    if (!STRING_NATIVE_FUNCTIONS.containsKey(name)) {
      runtimeError('Unknown method for string');
      return false;
    }
    final function = STRING_NATIVE_FUNCTIONS[name!]!;
    try {
      final rtn = function(str, stack, stackTop - argCount, argCount);
      stackTop -= argCount + 1;
      push(rtn);
      return true;
    } on NativeError catch (e) {
      runtimeError(e.format, e.args);
      return false;
    }
  }

  bool invokeNativeClass(
    final ObjNativeClass klass,
    final String? name,
    final int argCount,
  ) {
    try {
      final rtn = klass.call(name, stack, stackTop - argCount, argCount);
      stackTop -= argCount + 1;
      push(rtn);
      return true;
    } on NativeError catch (e) {
      runtimeError(e.format, e.args);
      return false;
    }
  }

  bool invoke(
    final String? name,
    final int argCount,
  ) {
    final receiver = peek(argCount);
    if (receiver is List) return invokeList(receiver, name, argCount);
    if (receiver is Map) return invokeMap(receiver, name, argCount);
    if (receiver is String) return invokeString(receiver, name, argCount);
    if (receiver is ObjNativeClass) {
      return invokeNativeClass(receiver, name, argCount);
    }
    if (!(receiver is ObjInstance)) {
      runtimeError('Only instances have methods');
      return false;
    }
    final instance = receiver;
    final value = instance.fields.getVal(name);
    if (value != null) {
      stack[stackTop - argCount - 1] = value;
      return callValue(value, argCount);
    }
    if (instance.klass == null) {
      final klass = globals.getVal(instance.klassName);
      if (!(klass is ObjClass)) {
        runtimeError('Class ${instance.klassName} not found');
        return false;
      }
      instance.klass = klass;
    }
    return invokeFromClass(instance.klass!, name, argCount);
  }

  bool bindMethod(
    final ObjClass klass,
    final String? name,
  ) {
    final method = klass.methods.getVal(name);
    if (method == null) {
      runtimeError("Undefined property '%s'", [name]);
      return false;
    }
    final bound = ObjBoundMethod(peek(0), method as ObjClosure);
    pop();
    push(bound);
    return true;
  }

  ObjUpvalue captureUpvalue(
    final int localIdx,
  ) {
    ObjUpvalue? prevUpvalue;
    var upvalue = openUpvalues;

    while (upvalue != null && upvalue.location! > localIdx) {
      prevUpvalue = upvalue;
      upvalue = upvalue.next;
    }

    if (upvalue != null && upvalue.location == localIdx) {
      return upvalue;
    }

    final createdUpvalue = ObjUpvalue(localIdx);
    createdUpvalue.next = upvalue;

    if (prevUpvalue == null) {
      openUpvalues = createdUpvalue;
    } else {
      prevUpvalue.next = createdUpvalue;
    }

    return createdUpvalue;
  }

  void closeUpvalues(
    final int? lastIdx,
  ) {
    while (openUpvalues != null && openUpvalues!.location! >= lastIdx!) {
      final upvalue = openUpvalues!;
      upvalue.closed = stack[upvalue.location!];
      upvalue.location = null;
      openUpvalues = upvalue.next;
    }
  }

  void defineMethod(
    final String? name,
  ) {
    final method = peek(0);
    final ObjClass klass = (peek(1) as ObjClass?)!;
    klass.methods.setVal(name, method);
    pop();
  }

  bool isFalsey(
    final Object? value,
  ) {
    return value == Nil || (value is bool && !value);
  }

  // Repace macros (slower -> try inlining)
  int readByte(
    final CallFrame frame,
  ) {
    return frame.chunk.code[frame.ip++];
  }

  int readShort(
    final CallFrame frame,
  ) {
    // TODO: Optimisation - remove
    frame.ip += 2;
    return frame.chunk.code[frame.ip - 2] << 8 | frame.chunk.code[frame.ip - 1];
  }

  Object? readConstant(
    final CallFrame frame,
  ) {
    return frame.closure.function.chunk.constants[readByte(frame)];
  }

  String? readString(
    final CallFrame frame,
  ) {
    return readConstant(frame) as String?;
  }

  bool assertNumber(
    final dynamic a,
    final dynamic b,
  ) {
    if (!(a is double) || !(b is double)) {
      runtimeError('Operands must be numbers');
      return false;
    }
    return true;
  }

  int? checkIndex(
    final int length,
    Object? idxObj, {
    final bool fromStart = true,
  }) {
    // ignore: parameter_assignments
    if (idxObj == Nil) idxObj = fromStart ? 0.0 : length.toDouble();
    if (!(idxObj is double)) {
      runtimeError('Index must be a number');
      return null;
    }
    var idx = idxObj.toInt();
    if (idx < 0) idx = length + idx;
    final max = fromStart ? length - 1 : length;
    if (idx < 0 || idx > max) {
      runtimeError('Index $idx out of bounds [0, $max]');
      return null;
    }
    return idx;
  }

  bool get done {
    return frameCount == 0;
  }

  InterpreterResult run() {
    InterpreterResult? res;
    do {
      res = stepBatch();
    } while (res == null);
    return res;
  }

  InterpreterResult? stepBatch({
    final int batchCount = BATCH_COUNT,
  }) {
    // Setup
    if (frameCount == 0) return withError('No call frame');
    var frame = frames[frameCount - 1];
    final stepCountLimit = stepCount + batchCount;
    // Main loop
    while (stepCount++ < stepCountLimit) {
      // Setup current line
      final frameLine = frame!.chunk.lines[frame.ip];
      // Step code helper
      if (stepCode) {
        final instruction = frame.chunk.code[frame.ip];
        final op = OpCode.values[instruction];
        // Pause execution on demand
        if (frameLine != line && hasOp) {
          // Newline detected, return
          // No need to set line to frameLine thanks to hasOp
          hasOp = false;
          return getResult(line);
        }
        // A line is worth stopping on if it has one of those opts
        hasOp |= op != OpCode.POP && op != OpCode.LOOP && op != OpCode.JUMP;
      }

      // Update line
      final prevLine = line;
      line = frameLine;

      // Trace execution if needed
      if (traceExecution) {
        trace_debug.stdwrite('          ');
        for (var k = 0; k < stackTop; k++) {
          trace_debug.stdwrite('[ ');
          trace_debug.printValue(stack[k]);
          trace_debug.stdwrite(' ]');
        }
        trace_debug.stdwrite('\n');
        trace_debug.disassembleInstruction(prevLine, frame.closure.function.chunk, frame.ip);
      }

      final instruction = readByte(frame);
      switch (OpCode.values[instruction]) {
        case OpCode.CONSTANT:
          {
            final constant = readConstant(frame);
            push(constant);
            break;
          }

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
          {
            final slot = readByte(frame);
            push(stack[frame.slotsIdx + slot]);
            break;
          }

        case OpCode.SET_LOCAL:
          {
            final slot = readByte(frame);
            stack[frame.slotsIdx + slot] = peek(0);
            break;
          }

        case OpCode.GET_GLOBAL:
          {
            final name = readString(frame);
            final value = globals.getVal(name);
            if (value == null) {
              return runtimeError("Undefined variable '%s'", [name]);
            }
            push(value);
            break;
          }

        case OpCode.DEFINE_GLOBAL:
          {
            final name = readString(frame);
            globals.setVal(name, peek(0));
            pop();
            break;
          }

        case OpCode.SET_GLOBAL:
          {
            final name = readString(frame);
            if (globals.setVal(name, peek(0))) {
              globals.delete(name); // [delete]
              return runtimeError("Undefined variable '%s'", [name]);
            }
            break;
          }

        case OpCode.GET_UPVALUE:
          {
            final slot = readByte(frame);
            final upvalue = frame.closure.upvalues[slot]!;
            push(upvalue.location != null ? stack[upvalue.location!] : upvalue.closed);
            break;
          }

        case OpCode.SET_UPVALUE:
          {
            final slot = readByte(frame);
            final upvalue = frame.closure.upvalues[slot]!;
            if (upvalue.location != null) {
              stack[upvalue.location!] = peek(0);
            } else {
              upvalue.closed = peek(0);
            }
            break;
          }

        case OpCode.GET_PROPERTY:
          {
            Object? value;
            if (peek(0) is ObjInstance) {
              final ObjInstance instance = (peek(0) as ObjInstance?)!;
              final name = readString(frame);
              value = instance.fields.getVal(name);
              if (value == null && !bindMethod(instance.klass!, name)) {
                return result;
              }
            } else if (peek(0) is ObjNativeClass) {
              final ObjNativeClass instance = (peek(0) as ObjNativeClass?)!;
              final name = readString(frame);
              try {
                value = instance.getVal(name);
              } on NativeError catch (e) {
                return runtimeError(e.format, e.args);
              }
            } else {
              return runtimeError('Only instances have properties');
            }
            if (value != null) {
              pop(); // Instance.
              push(value);
            }
            break;
          }

        case OpCode.SET_PROPERTY:
          {
            if (peek(1) is ObjInstance) {
              final ObjInstance instance = (peek(1) as ObjInstance?)!;
              instance.fields.setVal(readString(frame), peek(0));
            } else if (peek(1) is ObjNativeClass) {
              final ObjNativeClass instance = (peek(1) as ObjNativeClass?)!;
              instance.setVal(readString(frame), peek(0));
            } else {
              return runtimeError('Only instances have fields');
            }
            final value = pop();
            pop();
            push(value);
            break;
          }

        case OpCode.GET_SUPER:
          {
            final name = readString(frame);
            final ObjClass superclass = (pop() as ObjClass?)!;
            if (!bindMethod(superclass, name)) {
              return result;
            }
            break;
          }

        case OpCode.EQUAL:
          {
            final b = pop();
            final a = pop();
            push(valuesEqual(a, b));
            break;
          }

        // Optimisation create greater_or_equal
        case OpCode.GREATER:
          {
            final b = pop();
            final a = pop();
            if (a is String && b is String) {
              push(a.compareTo(b));
            } else if (a is double && b is double) {
              push(a > b);
            } else {
              return runtimeError('Operands must be numbers or strings');
            }
            break;
          }

        // Optimisation create less_or_equal
        case OpCode.LESS:
          {
            final b = pop();
            final a = pop();
            if (a is String && b is String) {
              push(b.compareTo(a));
            } else if (a is double && b is double) {
              push(a < b);
            } else {
              return runtimeError('Operands must be numbers or strings');
            }
            break;
          }

        case OpCode.ADD:
          {
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
              push(valueToString(a, quoteEmpty: false)! + valueToString(b, quoteEmpty: false)!);
            } else {
              return runtimeError('Operands must numbers, strings, lists or maps');
            }
            break;
          }

        case OpCode.SUBTRACT:
          {
            final b = pop();
            final a = pop();
            if (!assertNumber(a, b)) return result;
            push((a as double?)! - (b as double?)!);
            break;
          }

        case OpCode.MULTIPLY:
          {
            final b = pop();
            final a = pop();
            if (!assertNumber(a, b)) return result;
            push((a as double?)! * (b as double?)!);
            break;
          }

        case OpCode.DIVIDE:
          {
            final b = pop();
            final a = pop();
            if (!assertNumber(a, b)) return result;
            push((a as double?)! / (b as double?)!);
            break;
          }

        case OpCode.POW:
          {
            final b = pop();
            final a = pop();
            if (!assertNumber(a, b)) return result;
            push(pow((a as double?)!, (b as double?)!));
            break;
          }

        case OpCode.MOD:
          {
            final b = pop();
            final a = pop();
            if (!assertNumber(a, b)) return result;
            push((a as double?)! % (b as double?)!);
            break;
          }

        case OpCode.NOT:
          push(isFalsey(pop()));
          break;

        case OpCode.NEGATE:
          if (!(peek(0) is double)) {
            return runtimeError('Operand must be a number');
          }
          push(-(pop() as double?)!);
          break;

        case OpCode.PRINT:
          {
            final val = valueToString(pop());
            stdout.stdwriteln(val);
            break;
          }

        case OpCode.JUMP:
          {
            final offset = readShort(frame);
            frame.ip += offset;
            break;
          }

        case OpCode.JUMP_IF_FALSE:
          {
            final offset = readShort(frame);
            if (isFalsey(peek(0))) frame.ip += offset;
            break;
          }

        case OpCode.LOOP:
          {
            final offset = readShort(frame);
            frame.ip -= offset;
            break;
          }

        case OpCode.CALL:
          {
            final argCount = readByte(frame);
            if (!callValue(peek(argCount), argCount)) {
              return result;
            }
            frame = frames[frameCount - 1];
            break;
          }

        case OpCode.INVOKE:
          {
            final method = readString(frame);
            final argCount = readByte(frame);
            if (!invoke(method, argCount)) {
              return result;
            }
            frame = frames[frameCount - 1];
            break;
          }

        case OpCode.SUPER_INVOKE:
          {
            final method = readString(frame);
            final argCount = readByte(frame);
            final ObjClass superclass = (pop() as ObjClass?)!;
            if (!invokeFromClass(superclass, method, argCount)) {
              return result;
            }
            frame = frames[frameCount - 1];
            break;
          }

        case OpCode.CLOSURE:
          {
            final ObjFunction function = (readConstant(frame) as ObjFunction?)!;
            final closure = ObjClosure(function);
            push(closure);
            for (var i = 0; i < closure.upvalueCount; i++) {
              final isLocal = readByte(frame);
              final index = readByte(frame);
              if (isLocal == 1) {
                closure.upvalues[i] = captureUpvalue(frame.slotsIdx + index);
              } else {
                closure.upvalues[i] = frame.closure.upvalues[index];
              }
            }
            break;
          }

        case OpCode.CLOSE_UPVALUE:
          closeUpvalues(stackTop - 1);
          pop();
          break;

        case OpCode.RETURN:
          {
            final res = pop();
            closeUpvalues(frame.slotsIdx);
            frameCount--;
            // ignore: invariant_booleans
            if (frameCount == 0) {
              pop();
              return getResult(line, returnValue: res);
            }
            stackTop = frame.slotsIdx;
            push(res);
            frame = frames[frameCount - 1];
            break;
          }

        case OpCode.CLASS:
          push(ObjClass(readString(frame)));
          break;

        case OpCode.INHERIT:
          {
            final sup = peek(1);
            if (!(sup is ObjClass)) {
              return runtimeError('Superclass must be a class');
            }
            final ObjClass superclass = sup;
            final ObjClass subclass = (peek(0) as ObjClass?)!;
            subclass.methods.addAll(superclass.methods);
            pop(); // Subclass.
            break;
          }

        case OpCode.METHOD:
          defineMethod(readString(frame));
          break;

        case OpCode.LIST_INIT:
          final valCount = readByte(frame);
          final arr = <dynamic>[];
          for (var k = 0; k < valCount; k++) {
            arr.add(peek(valCount - k - 1));
          }
          stackTop -= valCount;
          push(arr);
          break;

        case OpCode.LIST_INIT_RANGE:
          if (!(peek(0) is double) || !(peek(1) is double)) {
            return runtimeError('List initializer bounds must be number');
          }
          final start = (peek(1) as double?)!;
          final end = (peek(0) as double?)!;
          if (end - start == double.infinity) {
            return runtimeError('Invalid list initializer');
          }
          final arr = <dynamic>[];
          for (var k = start; k < end; k++) {
            arr.add(k);
          }
          stackTop -= 2;
          push(arr);
          break;

        case OpCode.MAP_INIT:
          final valCount = readByte(frame);
          final map = <dynamic, dynamic>{};
          for (var k = 0; k < valCount; k++) {
            map[peek((valCount - k - 1) * 2 + 1)] = peek((valCount - k - 1) * 2);
          }
          stackTop -= 2 * valCount;
          push(map);
          break;

        case OpCode.CONTAINER_GET:
          {
            final idxObj = pop();
            final container = pop();
            if (container is List) {
              final idx = checkIndex(container.length, idxObj);
              if (idx == null) return result;
              push(container[idx]);
            } else if (container is Map) {
              push(container[idxObj]);
            } else if (container is String) {
              final idx = checkIndex(container.length, idxObj);
              if (idx == null) return result;
              push(container[idx]);
            } else {
              return runtimeError(
                'Indexing targets must be Strings, Lists or Maps',
              );
            }
            break;
          }

        case OpCode.CONTAINER_SET:
          {
            final val = pop();
            final idxObj = pop();
            final container = pop();
            if (container is List) {
              final idx = checkIndex(container.length, idxObj);
              if (idx == null) return result;
              container[idx] = val;
            } else if (container is Map) {
              container[idxObj] = val;
            } else {
              return runtimeError('Indexing targets must be Lists or Maps');
            }
            push(val);
            break;
          }

        case OpCode.CONTAINER_GET_RANGE:
          {
            var bIdx = pop();
            var aIdx = pop();
            final container = pop();
            var length = 0;
            if (container is List) {
              length = container.length;
            } else if (container is String) {
              length = container.length;
            } else {
              return runtimeError('Range indexing targets must be Lists or Strings');
            }
            aIdx = checkIndex(length, aIdx);
            bIdx = checkIndex(length, bIdx, fromStart: false);
            if (aIdx == null || bIdx == null) return result;
            if (container is List) {
              push(container.sublist(aIdx as int, bIdx as int?));
            } else if (container is String) {
              push(container.substring(aIdx as int, bIdx as int?));
            }
            break;
          }

        case OpCode.CONTAINER_ITERATE:
          {
            // Init stack indexes
            final valIdx = readByte(frame);
            final keyIdx = valIdx + 1;
            final idxIdx = valIdx + 2;
            final iterableIdx = valIdx + 3;
            final containerIdx = valIdx + 4;
            // Retreive data
            var idxObj = stack[frame.slotsIdx + idxIdx];
            // Initialize
            if (idxObj == Nil) {
              final container = stack[frame.slotsIdx + containerIdx];
              idxObj = 0.0;
              if (container is String) {
                stack[frame.slotsIdx + iterableIdx] = container.split('');
              } else if (container is List) {
                stack[frame.slotsIdx + iterableIdx] = container;
              } else if (container is Map) {
                stack[frame.slotsIdx + iterableIdx] = container.entries.toList();
              } else {
                return runtimeError('Iterable must be Strings, Lists or Maps');
              }
              // Pop container from stack
              pop();
            }
            // Iterate
            final double idx = (idxObj as double?)!;
            final iterable = (stack[frame.slotsIdx + iterableIdx] as List?)!;
            if (idx >= iterable.length) {
              // Return early
              push(false);
              break;
            }
            // Populate key & value
            final dynamic item = iterable[idx.toInt()];
            if (item is MapEntry) {
              stack[frame.slotsIdx + keyIdx] = item.key;
              stack[frame.slotsIdx + valIdx] = item.value;
            } else {
              stack[frame.slotsIdx + keyIdx] = idx;
              stack[frame.slotsIdx + valIdx] = item;
            }
            // Increment index
            stack[frame.slotsIdx + idxIdx] = idx + 1;
            push(true);
            break;
          }
      }
    }
    return null;
  }

  InterpreterResult runtimeError(
    final String format, [
    final List<Object?>? args,
  ]) {
    var error = addError(sprintf(format, args ?? []));
    for (var i = frameCount - 2; i >= 0; i--) {
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
// endregion
