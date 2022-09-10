import 'model.dart';

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
  const DeclarationClazz();

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
  final Expr center;
  final Stmt body;

  const StmtLoop2({
    required final this.center,
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
  }) => loop2(this);
}

class StmtConditional implements Stmt {
  final Expr expr;
  final Stmt stmt;

  const StmtConditional({
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
class Expr {
  // Z match<Z>({
  //   required final Z Function(ExprMap) map,
  //   required final Z Function(ExprMap) call,
  //   required final Z Function(ExprMap) invoke,
  //   required final Z Function(ExprMap) get,
  //   required final Z Function(ExprMap) set,
  //   required final Z Function(ExprMap) list,
  // });
}

class ExprMap implements Expr {
  final List<ExprmapMapEntry> entries;

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

class ExprList implements Expr {
  final List<Expr> values;

  const ExprList({
    required final this.values,
  });
}

class ExprmapMapEntry {
  final Expr key;
  final Expr value;

  const ExprmapMapEntry({
    required final this.key,
    required final this.value,
  });
}
// endregion
