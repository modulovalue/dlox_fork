import 'dart:collection';
import 'dart:math';

import 'package:sprintf/sprintf.dart';

import 'model.dart';

// region compiler
// TODO: Optimisation - bump
const UINT8_COUNT = 256;
const UINT8_MAX = UINT8_COUNT - 1;
const UINT16_MAX = 65535;

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
  PRIMARY
}

typedef ParseFn = void Function(bool canAssign);

class ParseRule {
  final ParseFn? prefix;
  final ParseFn? infix;
  final Precedence precedence;

  const ParseRule(this.prefix, this.infix, this.precedence);
}

class Local {
  final SyntheticToken? name;
  int depth;
  bool isCaptured = false;

  Local(this.name, {this.depth = -1, this.isCaptured = false});

  bool get initialized {
    return depth >= 0;
  }
}

class Upvalue {
  final SyntheticToken? name;
  final int index;
  final bool isLocal;

  const Upvalue(this.name, this.index, this.isLocal);
}

enum FunctionType { FUNCTION, INITIALIZER, METHOD, SCRIPT }

class ClassCompiler {
  final ClassCompiler? enclosing;
  final NaturalToken? name;
  bool hasSuperclass;

  ClassCompiler(this.enclosing, this.name, this.hasSuperclass);
}

class CompilerResult {
  final ObjFunction? function;
  final List<CompilerError> errors;
  final Debug? debug;

  const CompilerResult(this.function, this.errors, this.debug);
}

class Compiler {
  final Compiler? enclosing;

  // TODO I can't move the parsing routines into the parser
  // TODO  because compilation occurs during parsing?
  Parser? parser;
  ClassCompiler? currentClass;
  ObjFunction? function;
  FunctionType type;
  final List<Local> locals = [];
  final List<Upvalue> upvalues = [];
  int scopeDepth = 0;

  // Degug tracer
  bool traceBytecode;

  Compiler._(
    this.type, {
    this.parser,
    this.enclosing,
    this.traceBytecode = false,
  }) {
    function = ObjFunction();
    if (enclosing != null) {
      assert(parser == null, "");
      parser = enclosing!.parser;
      currentClass = enclosing!.currentClass;
      scopeDepth = enclosing!.scopeDepth + 1;
      traceBytecode = enclosing!.traceBytecode;
    } else {
      assert(parser != null, "");
    }
    if (type != FunctionType.SCRIPT) {
      function!.name = parser!.previous!.str;
    }
    final str = type != FunctionType.FUNCTION ? 'this' : '';
    final name = SyntheticTokenImpl(type: TokenType.FUN, str: str);
    locals.add(Local(name, depth: 0));
  }

  static CompilerResult compile(
    final List<NaturalToken> tokens, {
    final bool silent = false,
    final bool traceBytecode = false,
  }) {
    // Compile script
    final parser = Parser(tokens, silent: silent);
    final compiler = Compiler._(
      FunctionType.SCRIPT,
      parser: parser,
      traceBytecode: traceBytecode,
    );
    parser.advance();
    while (!compiler.match(TokenType.EOF)) {
      compiler.declaration();
    }
    final function = compiler.endCompiler();
    return CompilerResult(
      function,
      parser.errors,
      parser.debug,
    );
  }

  ObjFunction? endCompiler() {
    emitReturn();
    if (parser!.errors.isEmpty && traceBytecode) {
      parser!.debug!.disassembleChunk(currentChunk, function!.name ?? '<script>');
    }
    return function;
  }

  Chunk get currentChunk {
    return function!.chunk;
  }

  void consume(final TokenType type, final String message) {
    parser!.consume(type, message);
  }

  bool match(final TokenType type) {
    final res = parser!.match(type);
    return res;
  }

  bool matchPair(final TokenType first, final TokenType second) {
    final res = parser!.matchPair(first, second);
    return res;
  }

  void emitOp(final OpCode op) {
    emitByte(op.index);
  }

  void emitByte(final int byte) {
    currentChunk.write(byte, parser!.previous!);
  }

  void emitBytes(final int byte1, final int byte2) {
    emitByte(byte1);
    emitByte(byte2);
  }

  void emitLoop(final int loopStart) {
    emitOp(OpCode.LOOP);
    final offset = currentChunk.count - loopStart + 2;
    if (offset > UINT16_MAX) parser!.error('Loop body too large');
    emitByte((offset >> 8) & 0xff);
    emitByte(offset & 0xff);
  }

  int emitJump(final OpCode instruction) {
    emitOp(instruction);
    emitByte(0xff);
    emitByte(0xff);
    return currentChunk.count - 2;
  }

  void emitReturn() {
    if (type == FunctionType.INITIALIZER) {
      emitBytes(OpCode.GET_LOCAL.index, 0);
    } else {
      emitOp(OpCode.NIL);
    }

    emitOp(OpCode.RETURN);
  }

  int makeConstant(final Object? value) {
    final constant = currentChunk.addConstant(value);
    if (constant > UINT8_MAX) {
      parser!.error('Too many constants in one chunk');
      return 0;
    }
    return constant;
  }

  void emitConstant(final Object? value) {
    emitBytes(OpCode.CONSTANT.index, makeConstant(value));
  }

  void patchJump(final int offset) {
    // -2 to adjust for the bytecode for the jump offset itself.
    final jump = currentChunk.count - offset - 2;
    if (jump > UINT16_MAX) {
      parser!.error('Too much code to jump over');
    }
    currentChunk.code[offset] = (jump >> 8) & 0xff;
    currentChunk.code[offset + 1] = jump & 0xff;
  }

  void beginScope() {
    scopeDepth++;
  }

  void endScope() {
    scopeDepth--;
    while (locals.isNotEmpty && locals.last.depth > scopeDepth) {
      if (locals.last.isCaptured) {
        emitOp(OpCode.CLOSE_UPVALUE);
      } else {
        emitOp(OpCode.POP);
      }
      locals.removeLast();
    }
  }

  int identifierConstant(final SyntheticToken name) {
    return makeConstant(name.str);
  }

  bool identifiersEqual(final SyntheticToken a, final SyntheticToken b) {
    return a.str == b.str;
  }

  int resolveLocal(final SyntheticToken? name) {
    for (var i = locals.length - 1; i >= 0; i--) {
      final local = locals[i];
      if (identifiersEqual(name!, local.name!)) {
        if (!local.initialized) {
          parser!.error('Can\'t read local variable in its own initializer');
        }
        return i;
      }
    }
    return -1;
  }

  int addUpvalue(final SyntheticToken? name, final int index, final bool isLocal) {
    assert(upvalues.length == function!.upvalueCount, "");
    for (var i = 0; i < upvalues.length; i++) {
      final upvalue = upvalues[i];
      if (upvalue.index == index && upvalue.isLocal == isLocal) {
        return i;
      }
    }
    if (upvalues.length == UINT8_COUNT) {
      parser!.error('Too many closure variables in function');
      return 0;
    }
    upvalues.add(Upvalue(name, index, isLocal));
    return function!.upvalueCount++;
  }

  int resolveUpvalue(final SyntheticToken? name) {
    if (enclosing == null) return -1;
    final localIdx = enclosing!.resolveLocal(name);
    if (localIdx != -1) {
      final local = enclosing!.locals[localIdx];
      local.isCaptured = true;
      return addUpvalue(local.name, localIdx, true);
    }
    final upvalueIdx = enclosing!.resolveUpvalue(name);
    if (upvalueIdx != -1) {
      final upvalue = enclosing!.upvalues[upvalueIdx];
      return addUpvalue(upvalue.name, upvalueIdx, false);
    }
    return -1;
  }

  void addLocal(final SyntheticToken? name) {
    if (locals.length >= UINT8_COUNT) {
      parser!.error('Too many local variables in function');
      return;
    }
    locals.add(Local(name));
  }

  void delareLocalVariable() {
    // Global variables are implicitly declared.
    if (scopeDepth == 0) return;
    final name = parser!.previous;
    for (var i = locals.length - 1; i >= 0; i--) {
      final local = locals[i];
      if (local.depth != -1 && local.depth < scopeDepth) {
        break; // [negative]
      }
      if (identifiersEqual(name!, local.name!)) {
        parser!.error('Already variable with this name in this scope');
      }
    }
    addLocal(name);
  }

  int parseVariable(final String errorMessage) {
    consume(TokenType.IDENTIFIER, errorMessage);
    if (scopeDepth > 0) {
      delareLocalVariable();
      return 0;
    } else {
      return identifierConstant(parser!.previous!);
    }
  }

  void markLocalVariableInitialized() {
    if (scopeDepth == 0) return;
    locals.last.depth = scopeDepth;
  }

  void defineVariable(final int global, {final NaturalToken? token, final int peekDist = 0}) {
    final isLocal = scopeDepth > 0;
    if (isLocal) {
      markLocalVariableInitialized();
    } else {
      emitBytes(OpCode.DEFINE_GLOBAL.index, global);
    }
  }

  int argumentList() {
    var argCount = 0;
    if (!parser!.check(TokenType.RIGHT_PAREN)) {
      do {
        expression();
        if (argCount == 255) {
          parser!.error("Can't have more than 255 arguments");
        }
        argCount++;
      } while (match(TokenType.COMMA));
    }
    consume(TokenType.RIGHT_PAREN, "Expect ')' after arguments");
    return argCount;
  }

  void _and(final bool canAssign) {
    final endJump = emitJump(OpCode.JUMP_IF_FALSE);
    emitOp(OpCode.POP);
    parsePrecedence(Precedence.AND);
    patchJump(endJump);
  }

  void binary(final bool canAssign) {
    final operatorType = parser!.previous!.type;
    final rule = getRule(operatorType)!;
    parsePrecedence(Precedence.values[rule.precedence.index + 1]);

    // Emit the operator instruction.
    switch (operatorType) {
      case TokenType.BANG_EQUAL:
        emitBytes(OpCode.EQUAL.index, OpCode.NOT.index);
        break;
      case TokenType.EQUAL_EQUAL:
        emitOp(OpCode.EQUAL);
        break;
      case TokenType.GREATER:
        emitOp(OpCode.GREATER);
        break;
      case TokenType.GREATER_EQUAL:
        emitBytes(OpCode.LESS.index, OpCode.NOT.index);
        break;
      case TokenType.LESS:
        emitOp(OpCode.LESS);
        break;
      case TokenType.LESS_EQUAL:
        emitBytes(OpCode.GREATER.index, OpCode.NOT.index);
        break;
      case TokenType.PLUS:
        emitOp(OpCode.ADD);
        break;
      case TokenType.MINUS:
        emitOp(OpCode.SUBTRACT);
        break;
      case TokenType.STAR:
        emitOp(OpCode.MULTIPLY);
        break;
      case TokenType.SLASH:
        emitOp(OpCode.DIVIDE);
        break;
      case TokenType.CARET:
        emitOp(OpCode.POW);
        break;
      case TokenType.PERCENT:
        emitOp(OpCode.MOD);
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

  void call(final bool canAssign) {
    final argCount = argumentList();
    emitBytes(OpCode.CALL.index, argCount);
  }

  void listIndex(final bool canAssign) {
    var getRange = match(TokenType.COLON);
    // Left hand side operand
    if (getRange) {
      emitConstant(Nil);
    } else {
      expression();
      getRange = match(TokenType.COLON);
    }
    // Right hand side operand
    if (match(TokenType.RIGHT_BRACK)) {
      if (getRange) emitConstant(Nil);
    } else {
      if (getRange) expression();
      consume(TokenType.RIGHT_BRACK, "Expect ']' after list indexing");
    }
    // Emit operation
    if (getRange) {
      emitOp(OpCode.CONTAINER_GET_RANGE);
    } else if (canAssign && match(TokenType.EQUAL)) {
      expression();
      emitOp(OpCode.CONTAINER_SET);
    } else {
      emitOp(OpCode.CONTAINER_GET);
    }
  }

  void dot(final bool canAssign) {
    consume(TokenType.IDENTIFIER, "Expect property name after '.'");
    final name = identifierConstant(parser!.previous!);
    if (canAssign && match(TokenType.EQUAL)) {
      expression();
      emitBytes(OpCode.SET_PROPERTY.index, name);
    } else if (match(TokenType.LEFT_PAREN)) {
      final argCount = argumentList();
      emitBytes(OpCode.INVOKE.index, name);
      emitByte(argCount);
    } else {
      emitBytes(OpCode.GET_PROPERTY.index, name);
    }
  }

  void literal(final bool canAssign) {
    switch (parser!.previous!.type) {
      case TokenType.NIL:
        emitOp(OpCode.NIL);
        break;
      case TokenType.FALSE:
        emitOp(OpCode.FALSE);
        break;
      case TokenType.TRUE:
        emitOp(OpCode.TRUE);
        break;
      // ignore: no_default_cases
      default:
        throw Exception("Unreachable");
    }
  }

  void grouping(final bool canAssign) {
    expression();
    consume(TokenType.RIGHT_PAREN, "Expect ')' after expression");
  }

  void listInit(final bool canAssign) {
    var valCount = 0;
    if (!parser!.check(TokenType.RIGHT_BRACK)) {
      expression();
      valCount += 1;
      if (parser!.match(TokenType.COLON)) {
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
      emitBytes(OpCode.LIST_INIT.index, valCount);
    } else {
      emitByte(OpCode.LIST_INIT_RANGE.index);
    }
  }

  void mapInit(final bool canAssign) {
    var valCount = 0;
    if (!parser!.check(TokenType.RIGHT_BRACE)) {
      do {
        expression();
        consume(TokenType.COLON, "Expect ':' between map key-value pairs");
        expression();
        valCount++;
      } while (match(TokenType.COMMA));
    }
    consume(TokenType.RIGHT_BRACE, "Expect '}' after map initializer");
    emitBytes(OpCode.MAP_INIT.index, valCount);
  }

  void number(final bool canAssign) {
    final value = double.tryParse(parser!.previous!.str!);
    if (value == null) {
      parser!.error('Invalid number');
    } else {
      emitConstant(value);
    }
  }

  void object(final bool canAssign) {
    emitConstant(null);
  }

  void _or(final bool canAssign) {
    final elseJump = emitJump(OpCode.JUMP_IF_FALSE);
    final endJump = emitJump(OpCode.JUMP);
    patchJump(elseJump);
    emitOp(OpCode.POP);
    parsePrecedence(Precedence.OR);
    patchJump(endJump);
  }

  void string(final bool canAssign) {
    final str = parser!.previous!.str;
    emitConstant(str);
  }

  void getOrSetVariable(final SyntheticToken? name, final bool canAssign) {
    OpCode getOp, setOp;
    var arg = resolveLocal(name);
    if (arg != -1) {
      getOp = OpCode.GET_LOCAL;
      setOp = OpCode.SET_LOCAL;
    } else if ((arg = resolveUpvalue(name)) != -1) {
      getOp = OpCode.GET_UPVALUE;
      setOp = OpCode.SET_UPVALUE;
    } else {
      arg = identifierConstant(name!);
      getOp = OpCode.GET_GLOBAL;
      setOp = OpCode.SET_GLOBAL;
    }

    // Special mathematical assignment
    OpCode? assignOp;
    if (canAssign) {
      if (matchPair(TokenType.PLUS, TokenType.EQUAL)) {
        assignOp = OpCode.ADD;
      } else if (matchPair(TokenType.MINUS, TokenType.EQUAL)) {
        assignOp = OpCode.SUBTRACT;
      } else if (matchPair(TokenType.STAR, TokenType.EQUAL)) {
        assignOp = OpCode.MULTIPLY;
      } else if (matchPair(TokenType.SLASH, TokenType.EQUAL)) {
        assignOp = OpCode.DIVIDE;
      } else if (matchPair(TokenType.PERCENT, TokenType.EQUAL)) {
        assignOp = OpCode.MOD;
      } else if (matchPair(TokenType.CARET, TokenType.EQUAL)) {
        assignOp = OpCode.POW;
      }
    }

    if (canAssign && (assignOp != null || match(TokenType.EQUAL))) {
      if (assignOp != null) emitBytes(getOp.index, arg);
      expression();
      if (assignOp != null) emitOp(assignOp);
      emitBytes(setOp.index, arg);
    } else {
      emitBytes(getOp.index, arg);
    }
  }

  void variable(final bool canAssign) {
    getOrSetVariable(parser!.previous, canAssign);
  }

  SyntheticTokenImpl syntheticToken(final String str) {
    return SyntheticTokenImpl(type: TokenType.IDENTIFIER, str: str);
  }

  void _super(final bool canAssign) {
    if (currentClass == null) {
      parser!.error("Can't use 'super' outside of a class");
    } else if (!currentClass!.hasSuperclass) {
      parser!.error("Can't use 'super' in a class with no superclass");
    }

    consume(TokenType.DOT, "Expect '.' after 'super'");
    consume(TokenType.IDENTIFIER, 'Expect superclass method name');
    final name = identifierConstant(parser!.previous!);

    getOrSetVariable(syntheticToken('this'), false);
    if (match(TokenType.LEFT_PAREN)) {
      final argCount = argumentList();
      getOrSetVariable(syntheticToken('super'), false);
      emitBytes(OpCode.SUPER_INVOKE.index, name);
      emitByte(argCount);
    } else {
      getOrSetVariable(syntheticToken('super'), false);
      emitBytes(OpCode.GET_SUPER.index, name);
    }
  }

  void _this(final bool canAssign) {
    if (currentClass == null) {
      parser!.error("Can't use 'this' outside of a class");
      return;
    }
    variable(false);
  }

  void unary(final bool canAssign) {
    final operatorType = parser!.previous!.type;
    parsePrecedence(Precedence.UNARY);
    switch (operatorType) {
      case TokenType.BANG:
        emitOp(OpCode.NOT);
        break;
      case TokenType.MINUS:
        emitOp(OpCode.NEGATE);
        break;
      // ignore: no_default_cases
      default:
        throw Exception("Unreachable");
    }
  }

  Map<TokenType, ParseRule> get rules => {
        TokenType.LEFT_PAREN: ParseRule(grouping, call, Precedence.CALL),
        TokenType.RIGHT_PAREN: const ParseRule(null, null, Precedence.NONE),
        TokenType.LEFT_BRACE: ParseRule(mapInit, null, Precedence.NONE),
        TokenType.RIGHT_BRACE: const ParseRule(null, null, Precedence.NONE),
        TokenType.LEFT_BRACK: ParseRule(listInit, listIndex, Precedence.CALL),
        TokenType.RIGHT_BRACK: const ParseRule(null, null, Precedence.NONE),
        TokenType.COMMA: const ParseRule(null, null, Precedence.NONE),
        TokenType.DOT: ParseRule(null, dot, Precedence.CALL),
        TokenType.MINUS: ParseRule(unary, binary, Precedence.TERM),
        TokenType.PLUS: ParseRule(null, binary, Precedence.TERM),
        TokenType.SEMICOLON: const ParseRule(null, null, Precedence.NONE),
        TokenType.SLASH: ParseRule(null, binary, Precedence.FACTOR),
        TokenType.STAR: ParseRule(null, binary, Precedence.FACTOR),
        TokenType.CARET: ParseRule(null, binary, Precedence.POWER),
        TokenType.PERCENT: ParseRule(null, binary, Precedence.FACTOR),
        TokenType.COLON: const ParseRule(null, null, Precedence.NONE),
        TokenType.BANG: ParseRule(unary, null, Precedence.NONE),
        TokenType.BANG_EQUAL: ParseRule(null, binary, Precedence.EQUALITY),
        TokenType.EQUAL: const ParseRule(null, null, Precedence.NONE),
        TokenType.EQUAL_EQUAL: ParseRule(null, binary, Precedence.EQUALITY),
        TokenType.GREATER: ParseRule(null, binary, Precedence.COMPARISON),
        TokenType.GREATER_EQUAL: ParseRule(null, binary, Precedence.COMPARISON),
        TokenType.LESS: ParseRule(null, binary, Precedence.COMPARISON),
        TokenType.LESS_EQUAL: ParseRule(null, binary, Precedence.COMPARISON),
        TokenType.IDENTIFIER: ParseRule(variable, null, Precedence.NONE),
        TokenType.STRING: ParseRule(string, null, Precedence.NONE),
        TokenType.NUMBER: ParseRule(number, null, Precedence.NONE),
        TokenType.OBJECT: ParseRule(object, null, Precedence.NONE),
        TokenType.AND: ParseRule(null, _and, Precedence.AND),
        TokenType.CLASS: const ParseRule(null, null, Precedence.NONE),
        TokenType.ELSE: const ParseRule(null, null, Precedence.NONE),
        TokenType.FALSE: ParseRule(literal, null, Precedence.NONE),
        TokenType.FOR: const ParseRule(null, null, Precedence.NONE),
        TokenType.FUN: const ParseRule(null, null, Precedence.NONE),
        TokenType.IF: const ParseRule(null, null, Precedence.NONE),
        TokenType.NIL: ParseRule(literal, null, Precedence.NONE),
        TokenType.OR: ParseRule(null, _or, Precedence.OR),
        TokenType.PRINT: const ParseRule(null, null, Precedence.NONE),
        TokenType.RETURN: const ParseRule(null, null, Precedence.NONE),
        TokenType.SUPER: ParseRule(_super, null, Precedence.NONE),
        TokenType.THIS: ParseRule(_this, null, Precedence.NONE),
        TokenType.TRUE: ParseRule(literal, null, Precedence.NONE),
        TokenType.VAR: const ParseRule(null, null, Precedence.NONE),
        TokenType.WHILE: const ParseRule(null, null, Precedence.NONE),
        TokenType.BREAK: const ParseRule(null, null, Precedence.NONE),
        TokenType.CONTINUE: const ParseRule(null, null, Precedence.NONE),
        TokenType.ERROR: const ParseRule(null, null, Precedence.NONE),
        TokenType.EOF: const ParseRule(null, null, Precedence.NONE),
      };

  void parsePrecedence(final Precedence precedence) {
    parser!.advance();
    final prefixRule = getRule(parser!.previous!.type)!.prefix;
    if (prefixRule == null) {
      parser!.error('Expect expression');
      return;
    }
    final canAssign = precedence.index <= Precedence.ASSIGNMENT.index;
    prefixRule(canAssign);

    while (precedence.index <= getRule(parser!.current!.type)!.precedence.index) {
      parser!.advance();
      final infixRule = getRule(parser!.previous!.type)!.infix!;
      infixRule(canAssign);
    }

    if (canAssign && match(TokenType.EQUAL)) {
      parser!.error('Invalid assignment target');
    }
  }

  ParseRule? getRule(final TokenType type) {
    return rules[type];
  }

  void expression() {
    parsePrecedence(Precedence.ASSIGNMENT);
  }

  void block() {
    while (!parser!.check(TokenType.RIGHT_BRACE) && !parser!.check(TokenType.EOF)) {
      declaration();
    }
    consume(TokenType.RIGHT_BRACE, 'Unterminated block');
  }

  ObjFunction? functionInner() {
    // beginScope(); // [no-end-scope]
    // not needeed because of wrapped compiler scope propagation

    // Compile the parameter list.
    // final functionToken = parser.previous;
    consume(TokenType.LEFT_PAREN, "Expect '(' after function name");
    final args = <NaturalToken?>[];
    if (!parser!.check(TokenType.RIGHT_PAREN)) {
      do {
        function!.arity++;
        if (function!.arity > 255) {
          parser!.errorAtCurrent("Can't have more than 255 parameters");
        }
        parseVariable('Expect parameter name');
        markLocalVariableInitialized();
        args.add(parser!.previous);
      } while (match(TokenType.COMMA));
    }
    for (var k = 0; k < args.length; k++) {
      defineVariable(0, token: args[k], peekDist: args.length - 1 - k);
    }
    consume(TokenType.RIGHT_PAREN, "Expect ')' after parameters");

    // The body.
    consume(TokenType.LEFT_BRACE, 'Expect function body');
    block();

    // Create the function object.
    return endCompiler();
  }

  ObjFunction? functionBlock(final FunctionType type) {
    final compiler = Compiler._(type, enclosing: this);
    final function = compiler.functionInner();
    emitBytes(OpCode.CLOSURE.index, makeConstant(function));
    for (var i = 0; i < compiler.upvalues.length; i++) {
      emitByte(compiler.upvalues[i].isLocal ? 1 : 0);
      emitByte(compiler.upvalues[i].index);
    }
    return function;
  }

  void method() {
    // Methods don't require
    // consume(TokenType.FUN, 'Expect function identifier');
    consume(TokenType.IDENTIFIER, 'Expect method name');
    final identifier = parser!.previous!;
    final constant = identifierConstant(identifier);
    var type = FunctionType.METHOD;
    if (identifier.str == 'init') {
      type = FunctionType.INITIALIZER;
    }
    functionBlock(type);
    emitBytes(OpCode.METHOD.index, constant);
  }

  void classDeclaration() {
    consume(TokenType.IDENTIFIER, 'Expect class name');
    final className = parser!.previous;
    final nameConstant = identifierConstant(parser!.previous!);
    delareLocalVariable();

    emitBytes(OpCode.CLASS.index, nameConstant);
    defineVariable(nameConstant);

    final classCompiler = ClassCompiler(currentClass, parser!.previous, false);
    currentClass = classCompiler;

    if (match(TokenType.LESS)) {
      consume(TokenType.IDENTIFIER, 'Expect superclass name');
      variable(false);

      if (identifiersEqual(className!, parser!.previous!)) {
        parser!.error("A class can't inherit from itself");
      }

      beginScope();
      addLocal(syntheticToken('super'));
      defineVariable(0);

      getOrSetVariable(className, false);
      emitOp(OpCode.INHERIT);
      classCompiler.hasSuperclass = true;
    }

    getOrSetVariable(className, false);
    consume(TokenType.LEFT_BRACE, 'Expect class body');
    while (!parser!.check(TokenType.RIGHT_BRACE) && !parser!.check(TokenType.EOF)) {
      method();
    }
    consume(TokenType.RIGHT_BRACE, 'Unterminated class body');
    emitOp(OpCode.POP);

    if (classCompiler.hasSuperclass) {
      endScope();
    }

    currentClass = currentClass!.enclosing;
  }

  void funDeclaration() {
    final global = parseVariable('Expect function name');
    final token = parser!.previous;
    markLocalVariableInitialized();
    functionBlock(FunctionType.FUNCTION);

    defineVariable(global, token: token);
  }

  void varDeclaration() {
    do {
      final global = parseVariable('Expect variable name');
      final token = parser!.previous;
      if (match(TokenType.EQUAL)) {
        expression();
      } else {
        emitOp(OpCode.NIL);
      }
      defineVariable(global, token: token);
    } while (match(TokenType.COMMA));
    consume(TokenType.SEMICOLON, 'Expect a newline after variable declaration');
  }

  void expressionStatement() {
    expression();
    consume(TokenType.SEMICOLON, 'Expect a newline after expression');
    emitOp(OpCode.POP);
  }

  void forStatementCheck() {
    if (match(TokenType.LEFT_PAREN)) {
      legacyForStatement();
    } else {
      forStatement();
    }
  }

  void legacyForStatement() {
    // Deprecated
    beginScope();
    // consume(TokenType.LEFT_PAREN, "Expect '(' after 'for'");
    if (match(TokenType.SEMICOLON)) {
      // No initializer.
    } else if (match(TokenType.VAR)) {
      varDeclaration();
    } else {
      expressionStatement();
    }

    var loopStart = currentChunk.count;
    var exitJump = -1;
    if (!match(TokenType.SEMICOLON)) {
      expression();
      consume(TokenType.SEMICOLON, "Expect ';' after loop condition");
      exitJump = emitJump(OpCode.JUMP_IF_FALSE);
      emitOp(OpCode.POP); // Condition.
    }

    if (!match(TokenType.RIGHT_PAREN)) {
      final bodyJump = emitJump(OpCode.JUMP);
      final incrementStart = currentChunk.count;
      expression();
      emitOp(OpCode.POP);
      consume(TokenType.RIGHT_PAREN, "Expect ')' after for clauses");
      emitLoop(loopStart);
      loopStart = incrementStart;
      patchJump(bodyJump);
    }

    statement();
    emitLoop(loopStart);
    if (exitJump != -1) {
      patchJump(exitJump);
      emitOp(OpCode.POP); // Condition.
    }
    endScope();
  }

  void forStatement() {
    beginScope();
    // Key variable
    parseVariable('Expect variable name'); // Streamline those operations
    emitOp(OpCode.NIL);
    defineVariable(0, token: parser!.previous); // Remove 0
    final stackIdx = locals.length - 1;
    if (match(TokenType.COMMA)) {
      // Value variable
      parseVariable('Expect variable name');
      emitOp(OpCode.NIL);
      defineVariable(0, token: parser!.previous);
    } else {
      // Create dummy value slot
      addLocal(syntheticToken('_for_val_'));
      emitConstant(0); // Emit a zero to permute val & key
      markLocalVariableInitialized();
    }
    // Now add two dummy local variables. Idx & entries
    addLocal(syntheticToken('_for_idx_'));
    emitOp(OpCode.NIL);
    markLocalVariableInitialized();
    addLocal(syntheticToken('_for_iterable_'));
    emitOp(OpCode.NIL);
    markLocalVariableInitialized();
    // Rest of the loop
    consume(TokenType.IN, "Expect 'in' after loop variables");
    expression(); // Iterable
    // Iterator
    final loopStart = currentChunk.count;
    emitBytes(OpCode.CONTAINER_ITERATE.index, stackIdx);
    final exitJump = emitJump(OpCode.JUMP_IF_FALSE);
    emitOp(OpCode.POP); // Condition
    // Body
    statement();
    emitLoop(loopStart);
    // Exit
    patchJump(exitJump);
    emitOp(OpCode.POP); // Condition
    endScope();
  }

  void ifStatement() {
    // consume(TokenType.LEFT_PAREN, "Expect '(' after 'if'");
    expression();
    // consume(TokenType.RIGHT_PAREN, "Expect ')' after condition"); // [paren]
    final thenJump = emitJump(OpCode.JUMP_IF_FALSE);
    emitOp(OpCode.POP);
    statement();
    final elseJump = emitJump(OpCode.JUMP);
    patchJump(thenJump);
    emitOp(OpCode.POP);
    if (match(TokenType.ELSE)) statement();
    patchJump(elseJump);
  }

  void printStatement() {
    expression();
    consume(TokenType.SEMICOLON, 'Expect a newline after value');
    emitOp(OpCode.PRINT);
  }

  void returnStatement() {
    // if (type == FunctionType.SCRIPT) {
    //   parser.error("Can't return from top-level code");
    // }
    if (match(TokenType.SEMICOLON)) {
      emitReturn();
    } else {
      if (type == FunctionType.INITIALIZER) {
        parser!.error("Can't return a value from an initializer");
      }
      expression();
      consume(TokenType.SEMICOLON, 'Expect a newline after return value');
      emitOp(OpCode.RETURN);
    }
  }

  void whileStatement() {
    final loopStart = currentChunk.count;

    // consume(TokenType.LEFT_PAREN, "Expect '(' after 'while'");
    expression();
    // consume(TokenType.RIGHT_PAREN, "Expect ')' after condition");

    final exitJump = emitJump(OpCode.JUMP_IF_FALSE);

    emitOp(OpCode.POP);
    statement();

    emitLoop(loopStart);

    patchJump(exitJump);
    emitOp(OpCode.POP);
  }

  void synchronize() {
    parser!.panicMode = false;

    while (parser!.current!.type != TokenType.EOF) {
      if (parser!.previous!.type == TokenType.SEMICOLON) return;

      switch (parser!.current!.type) {
        case TokenType.CLASS:
        case TokenType.FUN:
        case TokenType.VAR:
        case TokenType.FOR:
        case TokenType.IF:
        case TokenType.WHILE:
        case TokenType.PRINT:
        case TokenType.RETURN:
          return;
        // ignore: no_default_cases
        default:
        // Do nothing.
      }

      parser!.advance();
    }
  }

  void declaration() {
    if (match(TokenType.CLASS)) {
      classDeclaration();
    } else if (match(TokenType.FUN)) {
      funDeclaration();
    } else if (match(TokenType.VAR)) {
      varDeclaration();
    } else {
      statement();
    }
    if (parser!.panicMode) synchronize();
  }

  void statement() {
    if (match(TokenType.PRINT)) {
      printStatement();
    } else if (match(TokenType.FOR)) {
      forStatementCheck();
    } else if (match(TokenType.IF)) {
      ifStatement();
    } else if (match(TokenType.RETURN)) {
      returnStatement();
    } else if (match(TokenType.WHILE)) {
      whileStatement();
    } else if (match(TokenType.LEFT_BRACE)) {
      beginScope();
      block();
      endScope();
    } else {
      expressionStatement();
    }
  }
}
// endregion

// region table
class Table {
  // Optimisation: replace with MAP
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

// region parser
class Parser {
  final List<NaturalToken> tokens;
  final List<CompilerError> errors = [];
  NaturalToken? current;
  NaturalToken? previous;
  NaturalToken? secondPrevious;
  int currentIdx = 0;
  bool panicMode = false;
  Debug? debug;

  Parser(
    this.tokens, {
    final bool silent = false,
  }) {
    debug = Debug(silent);
  }

  void errorAt(
    final NaturalToken? token,
    final String? message,
  ) {
    if (panicMode) return;
    panicMode = true;
    final error = CompilerError(token!, message);
    errors.add(error);
    error.dump(debug!);
  }

  void error(final String message) {
    errorAt(previous, message);
  }

  void errorAtCurrent(final String? message) {
    errorAt(current, message);
  }

  void advance() {
    secondPrevious = previous; // TODO: is it needed?
    previous = current;
    while (currentIdx < tokens.length) {
      current = tokens[currentIdx++];
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
      return;
    }
    errorAtCurrent(message);
  }

  bool check(final TokenType type) {
    return current!.type == type;
  }

  bool matchPair(final TokenType first, final TokenType second) {
    if (!check(first) || currentIdx >= tokens.length || tokens[currentIdx].type != second) return false;
    advance();
    advance();
    return true;
  }

  bool match(final TokenType type) {
    if (!check(type)) return false;
    advance();
    return true;
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
      buf.write('[${token!.loc.line + 1}:${token!.loc.line_token_counter}] $type error');
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
    stdwrite(sprintf('== %s ==\n', [name]));

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
