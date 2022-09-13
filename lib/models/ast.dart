import '../compiler.dart';

// region compilation unit
class CompilationUnit {
  final List<Declaration> decls;

  const CompilationUnit({
    required this.decls,
  });
}
// endregion

// region decl
abstract class Declaration {
  Z match<Z>({
    required final Z Function(DeclarationClazz) clazz,
    required final Z Function(DeclarationFun) fun,
    required final Z Function(DeclarationVari) vari,
    required final Z Function(DeclarationStmt) stmt,
  });
}

class DeclarationClazz implements Declaration {
  final Token name;
  final Token? superclass_name;
  final List<Method> Function(Compiler) make_functions;
  late final List<Method> functions;
  final int line;

  DeclarationClazz({
    required final this.name,
    required final this.superclass_name,
    required final this.make_functions,
    required final this.line,
  });

  @override
  Z match<Z>({
    required final Z Function(DeclarationClazz) clazz,
    required final Z Function(DeclarationFun) fun,
    required final Z Function(DeclarationVari) vari,
    required final Z Function(DeclarationStmt) stmt,
  }) =>
      clazz(this);
}

class DeclarationFun implements Declaration {
  final Block Function(Compiler) make_block;
  late final Block block;
  final Token name;
  final int line;

  DeclarationFun({
    required this.make_block,
    required this.name,
    required this.line,
  });

  @override
  Z match<Z>({
    required final Z Function(DeclarationClazz) clazz,
    required final Z Function(DeclarationFun) fun,
    required final Z Function(DeclarationVari) vari,
    required final Z Function(DeclarationStmt) stmt,
  }) =>
      fun(this);
}

class DeclarationVari implements Declaration {
  final List<MapEntry<Token, Expr>> exprs;
  final int line;

  const DeclarationVari({
    required final this.exprs,
    required final this.line,
  });

  @override
  Z match<Z>({
    required final Z Function(DeclarationClazz) clazz,
    required final Z Function(DeclarationFun) fun,
    required final Z Function(DeclarationVari) vari,
    required final Z Function(DeclarationStmt) stmt,
  }) =>
      vari(this);
}

class DeclarationStmt implements Declaration {
  final Stmt stmt;

  const DeclarationStmt({
    required this.stmt,
  });

  @override
  Z match<Z>({
    required final Z Function(DeclarationClazz) clazz,
    required final Z Function(DeclarationFun) fun,
    required final Z Function(DeclarationVari) vari,
    required final Z Function(DeclarationStmt) stmt,
  }) =>
      stmt(this);
}
// endregion

// region method
class Method {
  final Token name;
  final Functiony block;
  final int line;

  const Method({
    required final this.name,
    required final this.block,
    required final this.line,
  });
}
// endregion

// region block
class Functiony {
  final String name;
  final List<Token> args;
  final List<Declaration> Function(Compiler) make_decls;
  late final List<Declaration> decls;

  Functiony({
    required final this.name,
    required final this.args,
    required final this.make_decls,
  });
}

class Block {
  final List<Declaration> decls;

  const Block({
    required final this.decls,
  });
}
// endregion

// region stmt
abstract class Stmt {
  Z match<Z>({
    required final Z Function(StmtOutput) output,
    required final Z Function(StmtLoop) loop,
    required final Z Function(StmtLoop2) loop2,
    required final Z Function(StmtConditional) conditional,
    required final Z Function(StmtRet) ret,
    required final Z Function(StmtWhil) whil,
    required final Z Function(StmtBlock) block,
    required final Z Function(StmtExpr) expr,
  });
}

class StmtOutput implements Stmt {
  final Expr expr;
  final int line;

  const StmtOutput({
    required final this.expr,
    required final this.line,
  });

  @override
  Z match<Z>({
    required final Z Function(StmtOutput) output,
    required final Z Function(StmtLoop) loop,
    required final Z Function(StmtLoop2) loop2,
    required final Z Function(StmtConditional) conditional,
    required final Z Function(StmtRet) ret,
    required final Z Function(StmtWhil) whil,
    required final Z Function(StmtBlock) block,
    required final Z Function(StmtExpr) expr,
  }) => output(this);
}

class StmtLoop implements Stmt {
  final LoopLeft? left;
  final Expr? center;
  final Expr? right;
  final Stmt body;
  final Token right_kw;
  final Token end_kw;
  final int line;

  StmtLoop({
    required final this.left,
    required final this.center,
    required final this.right,
    required final this.right_kw,
    required final this.body,
    required final this.end_kw,
    required final this.line,
  });

  @override
  Z match<Z>({
    required final Z Function(StmtOutput) output,
    required final Z Function(StmtLoop) loop,
    required final Z Function(StmtLoop2) loop2,
    required final Z Function(StmtConditional) conditional,
    required final Z Function(StmtRet) ret,
    required final Z Function(StmtWhil) whil,
    required final Z Function(StmtBlock) block,
    required final Z Function(StmtExpr) expr,
  }) => loop(this);
}

class StmtLoop2 implements Stmt {
  final Token key_name;
  final Token? value_name;
  final Expr center;
  final Stmt body;
  final Token exit_token;
  final int line;

  StmtLoop2({
    required final this.center,
    required final this.key_name,
    required final this.value_name,
    required final this.body,
    required final this.exit_token,
    required final this.line,
  });

  @override
  Z match<Z>({
    required final Z Function(StmtOutput) output,
    required final Z Function(StmtLoop) loop,
    required final Z Function(StmtLoop2) loop2,
    required final Z Function(StmtConditional) conditional,
    required final Z Function(StmtRet) ret,
    required final Z Function(StmtWhil) whil,
    required final Z Function(StmtBlock) block,
    required final Z Function(StmtExpr) expr,
  }) => loop2(this);
}

class StmtConditional implements Stmt {
  final Expr expr;
  final Stmt stmt;
  final Stmt? Function() other_maker;
  late final Stmt? other;
  final Token if_kw;
  final Token else_kw;
  final int line;

  StmtConditional({
    required final this.expr,
    required final this.stmt,
    required final this.other_maker,
    required final this.if_kw,
    required final this.else_kw,
    required final this.line,
  });

  @override
  Z match<Z>({
    required final Z Function(StmtOutput) output,
    required final Z Function(StmtLoop) loop,
    required final Z Function(StmtLoop2) loop2,
    required final Z Function(StmtConditional) conditional,
    required final Z Function(StmtRet) ret,
    required final Z Function(StmtWhil) whil,
    required final Z Function(StmtBlock) block,
    required final Z Function(StmtExpr) expr,
  }) => conditional(this);
}

class StmtRet implements Stmt {
  final Token kw;
  final Expr? expr;
  final int line;

  const StmtRet({
    required final this.kw,
    required final this.expr,
    required final this.line,
  });

  @override
  Z match<Z>({
    required final Z Function(StmtOutput) output,
    required final Z Function(StmtLoop) loop,
    required final Z Function(StmtLoop2) loop2,
    required final Z Function(StmtConditional) conditional,
    required final Z Function(StmtRet) ret,
    required final Z Function(StmtWhil) whil,
    required final Z Function(StmtBlock) block,
    required final Z Function(StmtExpr) expr,
  }) => ret(this);
}

class StmtWhil implements Stmt {
  final Expr expr;
  final Stmt stmt;
  final Token exit_kw;
  final int line;

  const StmtWhil({
    required final this.expr,
    required final this.stmt,
    required final this.exit_kw,
    required final this.line,
  });

  @override
  Z match<Z>({
    required final Z Function(StmtOutput) output,
    required final Z Function(StmtLoop) loop,
    required final Z Function(StmtLoop2) loop2,
    required final Z Function(StmtConditional) conditional,
    required final Z Function(StmtRet) ret,
    required final Z Function(StmtWhil) whil,
    required final Z Function(StmtBlock) block,
    required final Z Function(StmtExpr) expr,
  }) => whil(this);
}

class StmtBlock implements Stmt {
  final Iterable<Declaration> Function(Compiler) block_maker;
  late final List<Declaration> block;
  final int line;

  StmtBlock({
    required final this.block_maker,
    required final this.line,
  });

  @override
  Z match<Z>({
    required final Z Function(StmtOutput) output,
    required final Z Function(StmtLoop) loop,
    required final Z Function(StmtLoop2) loop2,
    required final Z Function(StmtConditional) conditional,
    required final Z Function(StmtRet) ret,
    required final Z Function(StmtWhil) whil,
    required final Z Function(StmtBlock) block,
    required final Z Function(StmtExpr) expr,
  }) => block(this);
}

class StmtExpr implements Stmt {
  final Expr expr;
  final int line;

  const StmtExpr({
    required this.expr,
    required this.line,
  });

  @override
  Z match<Z>({
    required final Z Function(StmtOutput) output,
    required final Z Function(StmtLoop) loop,
    required final Z Function(StmtLoop2) loop2,
    required final Z Function(StmtConditional) conditional,
    required final Z Function(StmtRet) ret,
    required final Z Function(StmtWhil) whil,
    required final Z Function(StmtBlock) block,
    required final Z Function(StmtExpr) expr,
  }) => expr(this);
}
// endregion

// region loop left
abstract class LoopLeft {
  R match<R>({
    required final R Function(LoopLeftVari) vari,
    required final R Function(LoopLeftExpr) expr,
  });
}

class LoopLeftVari implements LoopLeft {
  final DeclarationVari decl;

  const LoopLeftVari({
    required final this.decl,
  });

  @override
  R match<R>({
    required final R Function(LoopLeftVari) vari,
    required final R Function(LoopLeftExpr) expr,
  }) => vari(this);
}

class LoopLeftExpr implements LoopLeft {
  final Expr expr;

  const LoopLeftExpr({
    required final this.expr,
  });

  @override
  R match<R>({
    required final R Function(LoopLeftVari) vari,
    required final R Function(LoopLeftExpr) expr,
  }) => expr(this);
}
// endregion

// region expr
abstract class Expr {}

class ExprMap implements Expr {
  final List<MapEntry<Expr, Expr>> entries;
  final int line;

  const ExprMap({
    required final this.entries,
    required final this.line,
  });
}

class ExprCall implements Expr {
  final List<Expr> args;
  final int line;

  const ExprCall({
    required final this.args,
    required final this.line,
  });
}

class ExprInvoke implements Expr {
  final List<Expr> args;
  final Token name;
  final int line;

  const ExprInvoke({
    required final this.args,
    required final this.name,
    required final this.line,
  });
}

class ExprGet implements Expr {
  final Token name;
  final int line;

  const ExprGet({
    required final this.name,
    required final this.line,
  });
}

class ExprSet implements Expr {
  final Expr arg;
  final Token name;
  final int line;

  const ExprSet({
    required final this.arg,
    required final this.name,
    required final this.line,
  });
}

class ExprSet2 implements Expr {
  final Expr arg;
  final Token name;
  final int line;

  const ExprSet2({
    required final this.arg,
    required final this.name,
    required final this.line,
  });
}

class ExprGetSet2 implements Expr {
  final Token name;
  final Getset? child;
  final int line;

  const ExprGetSet2({
    required final this.child,
    required final this.name,
    required final this.line,
  });
}

class Getset {
  final Expr child;
  final GetsetType type;

  const Getset({
    required final this.child,
    required final this.type,
  });
}

enum GetsetType {
  pluseq,
  minuseq,
  stareq,
  slasheq,
  poweq,
  modeq,
}

class ExprList implements Expr {
  final List<Expr> values;
  final int val_count;
  final int line;

  const ExprList({
    required final this.values,
    required final this.val_count,
    required final this.line,
  });
}

class ExprNil implements Expr {
  final int line;

  const ExprNil({
    required final this.line,
  });
}

class ExprString implements Expr {
  final Token token;
  final int line;

  const ExprString({
    required final this.token,
    required final this.line,
  });
}

class ExprNumber implements Expr {
  final Token value;
  final int line;

  const ExprNumber({
    required final this.value,
    required final this.line,
  });
}

class ExprObject implements Expr {
  final Token token;
  final int line;

  const ExprObject({
    required final this.token,
    required final this.line,
  });
}

class ExprListGetter implements Expr {
  final Expr? first;
  final Expr? second;
  final Token first_token;
  final Token second_token;
  final int line;

  const ExprListGetter({
    required final this.first,
    required final this.first_token,
    required final this.second,
    required final this.second_token,
    required final this.line,
  });
}

class ExprListSetter implements Expr {
  final Expr? first;
  final Expr? second;
  final Token token;
  final int line;

  const ExprListSetter({
    required final this.first,
    required final this.second,
    required final this.token,
    required final this.line,
  });
}

class ExprSuperaccess implements Expr {
  final Token kw;
  final List<Expr>? args;
  final int line;

  const ExprSuperaccess({
    required final this.kw,
    required final this.args,
    required final this.line,
  });
}

class ExprTruth implements Expr {
  final int line;

  const ExprTruth({
    required final this.line,
  });
}

class ExprFalsity implements Expr {
  final int line;

  const ExprFalsity({
    required final this.line,
  });
}

class ExprSelf implements Expr {
  final Token previous;
final   int line;

  const ExprSelf({
    required final this.previous,
    required final this.line,
  });
}

class ExprComposite implements Expr {
  final List<Expr> exprs;

  const ExprComposite({
    required final this.exprs,
  });
}

class ExprExpected implements Expr {
  const ExprExpected();
}

class ExprNegated implements Expr {
  final Expr child;
  final int line;

  const ExprNegated({
    required final this.child,
    required final this.line,
  });
}

class ExprNot implements Expr {
  final Expr child;
  final int line;

  const ExprNot({
    required final this.child,
    required final this.line,
  });
}

class ExprMinus implements Expr {
  final Expr child;
  final int line;

  const ExprMinus({
    required final this.child,
    required final this.line,
  });
}

class ExprPlus implements Expr {
  final Expr child;
  final int line;

  const ExprPlus({
    required final this.child,
    required final this.line,
  });
}

class ExprSlash implements Expr {
  final Expr child;
  final int line;

  const ExprSlash({
    required final this.child,
    required final this.line,
  });
}

class ExprStar implements Expr {
  final Expr child;
  final int line;

  const ExprStar({
    required final this.child,
    required final this.line,
  });
}

class ExprAnd implements Expr {
  final Token token;
  final Expr child;
  final int line;

  const ExprAnd({
    required final this.token,
    required final this.child,
    required final this.line,
  });
}

class ExprOr implements Expr {
  final Token token;
  final Expr child;
  final int line;

  const ExprOr({
    required final this.token,
    required final this.child,
    required final this.line,
  });
}

class ExprG implements Expr {
  final Expr child;
  final int line;

  const ExprG({
    required final this.child,
    required final this.line,
  });
}

class ExprGeq implements Expr {
  final Expr child;
  final int line;

  const ExprGeq({
    required final this.child,
    required final this.line,
  });
}

class ExprL implements Expr {
  final Expr child;
  final int line;

  const ExprL({
    required final this.child,
    required final this.line,
  });
}

class ExprLeq implements Expr {
  final Expr child;
  final int line;

  const ExprLeq({
    required final this.child,
    required final this.line,
  });
}

class ExprPow implements Expr {
  final Expr child;
  final int line;

  const ExprPow({
    required final this.child,
    required final this.line,
  });
}

class ExprModulo implements Expr {
  final Expr child;
  final int line;

  const ExprModulo({
    required final this.child,
    required final this.line,
  });
}

class ExprNeq implements Expr {
  final Expr child;
  final int line;

  const ExprNeq({
    required final this.child,
    required final this.line,
  });
}

class ExprEq implements Expr {
  final Expr child;
  final int line;

  const ExprEq({
    required final this.child,
    required final this.line,
  });
}


Z match_expr<Z>({
  required final Expr expr,
  required final Z Function(ExprMap) map,
  required final Z Function(ExprCall) call,
  required final Z Function(ExprInvoke) invoke,
  required final Z Function(ExprGet) get,
  required final Z Function(ExprSet) set,
  required final Z Function(ExprSet2) set2,
  required final Z Function(ExprGetSet2) getset2,
  required final Z Function(ExprList) list,
  required final Z Function(ExprNil) nil,
  required final Z Function(ExprString) string,
  required final Z Function(ExprNumber) number,
  required final Z Function(ExprObject) object,
  required final Z Function(ExprListGetter) listgetter,
  required final Z Function(ExprListSetter) listsetter,
  required final Z Function(ExprSuperaccess) superaccess,
  required final Z Function(ExprTruth) truth,
  required final Z Function(ExprFalsity) falsity,
  required final Z Function(ExprSelf) self,
  required final Z Function(ExprComposite) composite,
  required final Z Function(ExprExpected) expected,
  required final Z Function(ExprNegated) negated,
  required final Z Function(ExprNot) not,
  required final Z Function(ExprMinus) minus,
  required final Z Function(ExprPlus) plus,
  required final Z Function(ExprSlash) slash,
  required final Z Function(ExprStar) star,
  required final Z Function(ExprAnd) and,
  required final Z Function(ExprOr) or,
  required final Z Function(ExprG) g,
  required final Z Function(ExprGeq) geq,
  required final Z Function(ExprL) l,
  required final Z Function(ExprLeq) leq,
  required final Z Function(ExprPow) pow,
  required final Z Function(ExprModulo) modulo,
  required final Z Function(ExprNeq) neq,
  required final Z Function(ExprEq) eq,
}) {
  if (expr is ExprMap) return map(expr);
  if (expr is ExprMap) return map(expr);
  if (expr is ExprMap) return map(expr);
  if (expr is ExprCall) return call(expr);
  if (expr is ExprInvoke) return invoke(expr);
  if (expr is ExprGet) return get(expr);
  if (expr is ExprSet) return set(expr);
  if (expr is ExprSet2) return set2(expr);
  if (expr is ExprGetSet2) return getset2(expr);
  if (expr is ExprList) return list(expr);
  if (expr is ExprNil) return nil(expr);
  if (expr is ExprString) return string(expr);
  if (expr is ExprNumber) return number(expr);
  if (expr is ExprObject) return object(expr);
  if (expr is ExprListGetter) return listgetter(expr);
  if (expr is ExprListSetter) return listsetter(expr);
  if (expr is ExprSuperaccess) return superaccess(expr);
  if (expr is ExprTruth) return truth(expr);
  if (expr is ExprFalsity) return falsity(expr);
  if (expr is ExprSelf) return self(expr);
  if (expr is ExprComposite) return composite(expr);
  if (expr is ExprExpected) return expected(expr);
  if (expr is ExprNegated) return negated(expr);
  if (expr is ExprNot) return not(expr);
  if (expr is ExprMinus) return minus(expr);
  if (expr is ExprPlus) return plus(expr);
  if (expr is ExprSlash) return slash(expr);
  if (expr is ExprStar) return star(expr);
  if (expr is ExprAnd) return and(expr);
  if (expr is ExprOr) return or(expr);
  if (expr is ExprG) return g(expr);
  if (expr is ExprGeq) return geq(expr);
  if (expr is ExprL) return l(expr);
  if (expr is ExprLeq) return leq(expr);
  if (expr is ExprPow) return pow(expr);
  if (expr is ExprModulo) return modulo(expr);
  if (expr is ExprNeq) return neq(expr);
  if (expr is ExprEq) return eq(expr);
  throw Exception("Invalid State");
}
// endregion

// region token
// TODO the compiler should not depend on this?
// TODO  once parser and compilation are separate processes.
abstract class Token {
  TokenType get type;

  Loc get loc;

  String get lexeme;

  String get info;
}

class TokenImpl implements Token {
  @override
  final TokenType type;
  @override
  final String lexeme;
  @override
  final Loc loc;

  const TokenImpl({
    required final this.type,
    required final this.lexeme,
    required final this.loc,
  });

  @override
  String get info {
    return '<${toString()} at $loc>';
  }

  @override
  String toString() {
    if (!_TOKEN_REPR.containsKey(type)) {
      throw Exception('Representation not found: $type');
    } else {
      if (type == TokenType.EOF) {
        return '';
      } else if (type == TokenType.NUMBER || type == TokenType.STRING || type == TokenType.IDENTIFIER) {
        return lexeme;
      } else {
        return _TOKEN_REPR[type]!;
      }
    }
  }

  @override
  bool operator ==(
      final Object o,
      ) => o is Token && o.type == type && o.loc == loc && o.lexeme == lexeme;

  @override
  int get hashCode => type.hashCode ^ loc.hashCode ^ lexeme.hashCode;

  static const _TOKEN_REPR = {
    // Symbols
    TokenType.LEFT_PAREN: '(',
    TokenType.RIGHT_PAREN: ')',
    TokenType.LEFT_BRACE: '{',
    TokenType.RIGHT_BRACE: '}',
    TokenType.LEFT_BRACK: '[',
    TokenType.RIGHT_BRACK: ']',
    TokenType.COMMA: ',',
    TokenType.DOT: '.',
    TokenType.SEMICOLON: ';',
    TokenType.COLON: ':',
    TokenType.BANG: '!',

    // Operators
    TokenType.MINUS: '-',
    TokenType.PLUS: '+',
    TokenType.SLASH: '/',
    TokenType.STAR: '*',
    TokenType.PERCENT: '%',
    TokenType.CARET: '^',
    TokenType.EQUAL: '=',
    TokenType.AND: 'and',
    TokenType.OR: 'or',

    // Comparators
    TokenType.BANG_EQUAL: '!=',
    TokenType.EQUAL_EQUAL: '==',
    TokenType.GREATER: '>',
    TokenType.GREATER_EQUAL: '>=',
    TokenType.LESS: '<',
    TokenType.LESS_EQUAL: '<=',

    // Literals
    TokenType.IDENTIFIER: '<identifier>',
    TokenType.STRING: '<str>',
    TokenType.NUMBER: '<num>',
    TokenType.OBJECT: '<obj>',

    // Keywords
    TokenType.CLASS: 'class',
    TokenType.ELSE: 'else',
    TokenType.FALSE: 'false',
    TokenType.FOR: 'for',
    TokenType.FUN: 'fun',
    TokenType.IF: 'if',
    TokenType.NIL: 'nil',
    TokenType.PRINT: 'print',
    TokenType.RETURN: 'rtn',
    TokenType.SUPER: 'super',
    TokenType.THIS: 'this',
    TokenType.TRUE: 'true',
    TokenType.VAR: 'var',
    TokenType.WHILE: 'while',
    TokenType.IN: 'in',
    TokenType.BREAK: 'break',
    TokenType.CONTINUE: 'continue',

    // Editor syntactic sugar (dummy tokens)
    TokenType.COMMENT: '<//>',
    TokenType.EOF: 'eof',
    TokenType.ERROR: '<error>',
  };
}

enum TokenType {
  // Single-char tokens.
  LEFT_PAREN,
  RIGHT_PAREN,
  LEFT_BRACE,
  RIGHT_BRACE,
  LEFT_BRACK,
  RIGHT_BRACK,
  COMMA,
  DOT,
  MINUS,
  PLUS,
  SEMICOLON,
  SLASH,
  STAR,
  COLON,
  PERCENT,
  CARET,

  // One or two char tokens.
  BANG,
  BANG_EQUAL,
  EQUAL,
  EQUAL_EQUAL,
  GREATER,
  GREATER_EQUAL,
  LESS,
  LESS_EQUAL,

  // Literals.
  IDENTIFIER,
  STRING,
  NUMBER,
  OBJECT,

  // Keywords.
  AND,
  CLASS,
  ELSE,
  FALSE,
  FOR,
  FUN,
  IF,
  NIL,
  OR,
  PRINT,
  RETURN,
  SUPER,
  THIS,
  TRUE,
  VAR,
  WHILE,
  IN,
  BREAK, // TODO: add in dlox?
  CONTINUE, // TODO: add in dlox?

  // Editor syntactic sugar & helpers (dummy tokens)
  ERROR,
  COMMENT,
  EOF,
}

// TODO migrate to an absolute offset and no line information.
abstract class Loc {
  int get line;
}

class LocImpl implements Loc {
  @override
  final int line;

  const LocImpl(
    final this.line,
  );

  @override
  String toString() => line.toString();

  @override
  bool operator ==(
    final Object other,
  ) {
    return (other is Loc) && other.line == line;
  }

  @override
  int get hashCode {
    return line.hashCode;
  }
}
// endregion
