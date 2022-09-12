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
  final List<Method> functions;
  final NaturalToken name;

  const DeclarationClazz({
    required final this.functions,
    required final this.name,
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
  final Block block;
  final NaturalToken name;

  const DeclarationFun({
    required this.block,
    required this.name,
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
  final List<Expr> exprs;

  const DeclarationVari({
    required final this.exprs,
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
  final NaturalToken name;
  final Block block;

  const Method({
    required final this.name,
    required final this.block,
  });
}
// endregion

// region block
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

  const StmtOutput({
    required final this.expr,
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

  const StmtLoop({
    required final this.left,
    required final this.center,
    required final this.right,
    required final this.body,
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
  final NaturalToken key_name;
  final NaturalToken? value_name;
  final Expr center;
  final Stmt body;

  const StmtLoop2({
    required final this.center,
    required final this.body,
    required final this.key_name,
    required final this.value_name,
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
  final Stmt? other;

  const StmtConditional({
    required final this.expr,
    required final this.stmt,
    required final this.other,
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
  final Expr? expr;

  const StmtRet({
    required final this.expr,
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

  const StmtWhil({
    required final this.expr,
    required final this.stmt,
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
  final Block block;

  const StmtBlock({
    required final this.block,
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

  const StmtExpr({
    required this.expr,
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
abstract class LoopLeft {}

class LoopLeftVari implements LoopLeft {
  final DeclarationVari decl;

  const LoopLeftVari({
    required final this.decl,
  });
}

class LoopLeftExpr implements LoopLeft {
  final Expr expr;

  const LoopLeftExpr({
    required final this.expr,
  });
}
// endregion

// region expr
abstract class Expr {}

class ExprMap implements Expr {
  final List<MapEntry<Expr, Expr>> entries;

  const ExprMap({
    required final this.entries,
  });
}

class ExprCall implements Expr {
  final List<Expr> args;

  const ExprCall({
    required final this.args,
  });
}

class ExprInvoke implements Expr {
  final List<Expr> args;
  final NaturalToken name;

  const ExprInvoke({
    required final this.args,
    required final this.name,
  });
}

class ExprGet implements Expr {
  final NaturalToken name;

  const ExprGet({
    required final this.name,
  });
}

class ExprSet implements Expr {
  final Expr arg;
  final NaturalToken name;

  const ExprSet({
    required final this.arg,
    required final this.name,
  });
}

class ExprSet2 implements Expr {
  final Expr arg;
  final NaturalToken name;

  const ExprSet2({
    required final this.arg,
    required final this.name,
  });
}

class ExprGetSet2 implements Expr {
  final Expr? arg;
  final NaturalToken name;

  const ExprGetSet2({
    required final this.arg,
    required final this.name,
  });
}

class ExprGet2 implements Expr {
  final NaturalToken name;

  const ExprGet2({
    required final this.name,
  });
}

class ExprList implements Expr {
  final List<Expr> values;
  final int val_count;

  const ExprList({
    required final this.values,
    required final this.val_count,
  });
}

class ExprNil implements Expr {
  const ExprNil();
}

class ExprString implements Expr {
  final NaturalToken token;

  const ExprString({
    required final this.token,
  });
}

class ExprNumber implements Expr {
  final NaturalToken value;

  const ExprNumber({
    required final this.value,
  });
}

class ExprObject implements Expr {
  const ExprObject();
}

class ExprListGetter implements Expr {
  final Expr? first;
  final Expr? second;

  const ExprListGetter({
    required final this.first,
    required final this.second,
  });
}

class ExprListSetter implements Expr {
  final Expr? first;
  final Expr? second;

  const ExprListSetter({
    required final this.first,
    required final this.second,
  });
}

class ExprSuperaccess implements Expr {
  final NaturalToken kw;
  final List<Expr>? args;

  const ExprSuperaccess({
    required final this.kw,
    required final this.args,
});
}

class ExprTruth implements Expr {
  const ExprTruth();
}

class ExprFalsity implements Expr {
  const ExprFalsity();
}

class ExprSelf implements Expr {
  const ExprSelf();
}

class ExprComposite implements Expr {
  final List<Expr?> exprs;

  const ExprComposite({
    required final this.exprs,
  });
}

class ExprExpected implements Expr {
  const ExprExpected();
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
  required final Z Function(ExprGet2) get2,
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
  if (expr is ExprGet2) return get2(expr);
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
  throw Exception("Invalid State");
}
// endregion

abstract class SyntheticToken {
  TokenType get type;

  String? get lexeme;
}

// TODO the compiler should not depend on this?
abstract class NaturalToken implements SyntheticToken {
  Loc get loc;

  @override
  String get lexeme;
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

class SyntheticTokenImpl implements SyntheticToken {
  @override
  final TokenType type;
  @override
  final String? lexeme;

  const SyntheticTokenImpl({
    required final this.type,
    required final this.lexeme,
  });

  @override
  bool operator ==(final Object other) =>
      identical(this, other) ||
          other is SyntheticTokenImpl &&
              runtimeType == other.runtimeType &&
              type == other.type &&
              lexeme == other.lexeme;

  @override
  int get hashCode => type.hashCode ^ lexeme.hashCode;
}

class NaturalTokenImpl implements NaturalToken {
  @override
  final TokenType type;
  @override
  final String lexeme;
  @override
  final Loc loc;

  const NaturalTokenImpl({
    required final this.type,
    required final this.lexeme,
    required final this.loc,
  });

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
      ) => o is NaturalToken && o.type == type && o.loc == loc && o.lexeme == lexeme;

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

class LocImpl implements Loc {
  @override
  final int line;

  const LocImpl(
      final this.line,
      );

  @override
  String toString() {
    return '$line';
  }

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
