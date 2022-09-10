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
  const DeclarationVari();

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
    required final Z Function(StmtConditional) conditional,
    required final Z Function(StmtRet) ret,
    required final Z Function(StmtWhil) whil,
    required final Z Function(StmtBlock) block,
    required final Z Function(StmtExpr) expr,
  });
}

class StmtOutput implements Stmt {
  const StmtOutput();

  @override
  Z match<Z>({
    required final Z Function(StmtOutput) output,
    required final Z Function(StmtLoop) loop,
    required final Z Function(StmtConditional) conditional,
    required final Z Function(StmtRet) ret,
    required final Z Function(StmtWhil) whil,
    required final Z Function(StmtBlock) block,
    required final Z Function(StmtExpr) expr,
  }) => output(this);
}

class StmtLoop implements Stmt {
  const StmtLoop();

  @override
  Z match<Z>({
    required final Z Function(StmtOutput) output,
    required final Z Function(StmtLoop) loop,
    required final Z Function(StmtConditional) conditional,
    required final Z Function(StmtRet) ret,
    required final Z Function(StmtWhil) whil,
    required final Z Function(StmtBlock) block,
    required final Z Function(StmtExpr) expr,
  }) => loop(this);
}

class StmtConditional implements Stmt {
  const StmtConditional();

  @override
  Z match<Z>({
    required final Z Function(StmtOutput) output,
    required final Z Function(StmtLoop) loop,
    required final Z Function(StmtConditional) conditional,
    required final Z Function(StmtRet) ret,
    required final Z Function(StmtWhil) whil,
    required final Z Function(StmtBlock) block,
    required final Z Function(StmtExpr) expr,
  }) => conditional(this);
}

class StmtRet implements Stmt {
  const StmtRet();

  @override
  Z match<Z>({
    required final Z Function(StmtOutput) output,
    required final Z Function(StmtLoop) loop,
    required final Z Function(StmtConditional) conditional,
    required final Z Function(StmtRet) ret,
    required final Z Function(StmtWhil) whil,
    required final Z Function(StmtBlock) block,
    required final Z Function(StmtExpr) expr,
  }) => ret(this);
}

class StmtWhil implements Stmt {
  const StmtWhil();

  @override
  Z match<Z>({
    required final Z Function(StmtOutput) output,
    required final Z Function(StmtLoop) loop,
    required final Z Function(StmtConditional) conditional,
    required final Z Function(StmtRet) ret,
    required final Z Function(StmtWhil) whil,
    required final Z Function(StmtBlock) block,
    required final Z Function(StmtExpr) expr,
  }) => whil(this);
}

class StmtBlock implements Stmt {
  const StmtBlock();

  @override
  Z match<Z>({
    required final Z Function(StmtOutput) output,
    required final Z Function(StmtLoop) loop,
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
    required final Z Function(StmtConditional) conditional,
    required final Z Function(StmtRet) ret,
    required final Z Function(StmtWhil) whil,
    required final Z Function(StmtBlock) block,
    required final Z Function(StmtExpr) expr,
  }) => expr(this);
}
// endregion

// region expr
// TODO hierarchy
class Expr {}
// endregion
