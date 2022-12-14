import 'tokens.dart';

// region compilation unit
class CompilationUnit<I> {
  final List<Declaration<I>> decls;

  const CompilationUnit({
    required this.decls,
  });
}
// endregion

// region decl
abstract class Declaration<I> {
  Z match<Z>({
    required final Z Function(DeclarationClazz<I>) clazz,
    required final Z Function(DeclarationFun<I>) fun,
    required final Z Function(DeclarationVari<I>) vari,
    required final Z Function(DeclarationStmt<I>) stmt,
  });
}

class DeclarationClazz<I> implements Declaration<I> {
  final Token<TokenAug> name;
  final Token<TokenAug>? superclass_name;
  final List<Method<I>> functions;
  final I aug;

  const DeclarationClazz({
    required final this.name,
    required final this.superclass_name,
    required final this.functions,
    required final this.aug,
  });

  @override
  Z match<Z>({
    required final Z Function(DeclarationClazz<I>) clazz,
    required final Z Function(DeclarationFun<I>) fun,
    required final Z Function(DeclarationVari<I>) vari,
    required final Z Function(DeclarationStmt<I>) stmt,
  }) =>
      clazz(this);
}

class DeclarationFun<I> implements Declaration<I> {
  final Functiony<I> block;
  final Token<TokenAug> name;
  final I aug;

  const DeclarationFun({
    required this.block,
    required this.name,
    required this.aug,
  });

  @override
  Z match<Z>({
    required final Z Function(DeclarationClazz<I>) clazz,
    required final Z Function(DeclarationFun<I>) fun,
    required final Z Function(DeclarationVari<I>) vari,
    required final Z Function(DeclarationStmt<I>) stmt,
  }) =>
      fun(this);
}

class DeclarationVari<I> implements Declaration<I> {
  final List<MapEntry<Token<TokenAug>, Expr<I>>> exprs;
  final I aug;

  const DeclarationVari({
    required final this.exprs,
    required final this.aug,
  });

  @override
  Z match<Z>({
    required final Z Function(DeclarationClazz<I>) clazz,
    required final Z Function(DeclarationFun<I>) fun,
    required final Z Function(DeclarationVari<I>) vari,
    required final Z Function(DeclarationStmt<I>) stmt,
  }) =>
      vari(this);
}

class DeclarationStmt<I> implements Declaration<I> {
  final Stmt<I> stmt;

  const DeclarationStmt({
    required this.stmt,
  });

  @override
  Z match<Z>({
    required final Z Function(DeclarationClazz<I>) clazz,
    required final Z Function(DeclarationFun<I>) fun,
    required final Z Function(DeclarationVari<I>) vari,
    required final Z Function(DeclarationStmt<I>) stmt,
  }) =>
      stmt(this);
}
// endregion

// region method
class Method<I> {
  final Token<TokenAug> name;
  final Functiony<I> block;
  final I aug;

  const Method({
    required final this.name,
    required final this.block,
    required final this.aug,
  });
}
// endregion

// region block
class Functiony<I> {
  final String name;
  final List<Token<TokenAug>> args;
  final List<Declaration<I>> decls;

  const Functiony({
    required final this.name,
    required final this.args,
    required final this.decls,
  });
}
// endregion

// region stmt
abstract class Stmt<I> {
  Z match<Z>({
    required final Z Function(StmtOutput<I>) output,
    required final Z Function(StmtLoop<I>) loop,
    required final Z Function(StmtLoop2<I>) loop2,
    required final Z Function(StmtConditional<I>) conditional,
    required final Z Function(StmtRet<I>) ret,
    required final Z Function(StmtWhil<I>) whil,
    required final Z Function(StmtBlock<I>) block,
    required final Z Function(StmtExpr<I>) expr,
  });
}

class StmtOutput<I> implements Stmt<I> {
  final Expr<I> expr;
  final I aug;

  const StmtOutput({
    required final this.expr,
    required final this.aug,
  });

  @override
  Z match<Z>({
    required final Z Function(StmtOutput<I>) output,
    required final Z Function(StmtLoop<I>) loop,
    required final Z Function(StmtLoop2<I>) loop2,
    required final Z Function(StmtConditional<I>) conditional,
    required final Z Function(StmtRet<I>) ret,
    required final Z Function(StmtWhil<I>) whil,
    required final Z Function(StmtBlock<I>) block,
    required final Z Function(StmtExpr<I>) expr,
  }) => output(this);
}

class StmtLoop<I> implements Stmt<I> {
  final LoopLeft<I>? left;
  final Expr<I>? center;
  final Expr<I>? right;
  final Stmt<I> body;
  final Token<TokenAug> right_kw;
  final Token<TokenAug> end_kw;
  final I aug;

  const StmtLoop({
    required final this.left,
    required final this.center,
    required final this.right,
    required final this.right_kw,
    required final this.body,
    required final this.end_kw,
    required final this.aug,
  });

  @override
  Z match<Z>({
    required final Z Function(StmtOutput<I>) output,
    required final Z Function(StmtLoop<I>) loop,
    required final Z Function(StmtLoop2<I>) loop2,
    required final Z Function(StmtConditional<I>) conditional,
    required final Z Function(StmtRet<I>) ret,
    required final Z Function(StmtWhil<I>) whil,
    required final Z Function(StmtBlock<I>) block,
    required final Z Function(StmtExpr<I>) expr,
  }) => loop(this);
}

class StmtLoop2<I> implements Stmt<I> {
  final Token<TokenAug> key_name;
  final Token<TokenAug>? value_name;
  final Expr<I> center;
  final Stmt<I> body;
  final Token<TokenAug> exit_token;
  final I aug;

  const StmtLoop2({
    required final this.center,
    required final this.key_name,
    required final this.value_name,
    required final this.body,
    required final this.exit_token,
    required final this.aug,
  });

  @override
  Z match<Z>({
    required final Z Function(StmtOutput<I>) output,
    required final Z Function(StmtLoop<I>) loop,
    required final Z Function(StmtLoop2<I>) loop2,
    required final Z Function(StmtConditional<I>) conditional,
    required final Z Function(StmtRet<I>) ret,
    required final Z Function(StmtWhil<I>) whil,
    required final Z Function(StmtBlock<I>) block,
    required final Z Function(StmtExpr<I>) expr,
  }) => loop2(this);
}

class StmtConditional<I> implements Stmt<I> {
  final Expr<I> expr;
  final Stmt<I> stmt;
  final Stmt<I>? other;
  final Token<TokenAug> if_kw;
  final Token<TokenAug> else_kw;
  final I aug;

  const StmtConditional({
    required final this.expr,
    required final this.stmt,
    required final this.other,
    required final this.if_kw,
    required final this.else_kw,
    required final this.aug,
  });

  @override
  Z match<Z>({
    required final Z Function(StmtOutput<I>) output,
    required final Z Function(StmtLoop<I>) loop,
    required final Z Function(StmtLoop2<I>) loop2,
    required final Z Function(StmtConditional<I>) conditional,
    required final Z Function(StmtRet<I>) ret,
    required final Z Function(StmtWhil<I>) whil,
    required final Z Function(StmtBlock<I>) block,
    required final Z Function(StmtExpr<I>) expr,
  }) => conditional(this);
}

class StmtRet<I> implements Stmt<I> {
  final Token<TokenAug> kw;
  final Expr<I>? expr;
  final I aug;

  const StmtRet({
    required final this.kw,
    required final this.expr,
    required final this.aug,
  });

  @override
  Z match<Z>({
    required final Z Function(StmtOutput<I>) output,
    required final Z Function(StmtLoop<I>) loop,
    required final Z Function(StmtLoop2<I>) loop2,
    required final Z Function(StmtConditional<I>) conditional,
    required final Z Function(StmtRet<I>) ret,
    required final Z Function(StmtWhil<I>) whil,
    required final Z Function(StmtBlock<I>) block,
    required final Z Function(StmtExpr<I>) expr,
  }) => ret(this);
}

class StmtWhil<I> implements Stmt<I> {
  final Expr<I> expr;
  final Stmt<I> stmt;
  final Token<TokenAug> exit_kw;
  final I aug;

  const StmtWhil({
    required final this.expr,
    required final this.stmt,
    required final this.exit_kw,
    required final this.aug,
  });

  @override
  Z match<Z>({
    required final Z Function(StmtOutput<I>) output,
    required final Z Function(StmtLoop<I>) loop,
    required final Z Function(StmtLoop2<I>) loop2,
    required final Z Function(StmtConditional<I>) conditional,
    required final Z Function(StmtRet<I>) ret,
    required final Z Function(StmtWhil<I>) whil,
    required final Z Function(StmtBlock<I>) block,
    required final Z Function(StmtExpr<I>) expr,
  }) => whil(this);
}

class StmtBlock<I> implements Stmt<I> {
  final List<Declaration<I>> block;
  final I aug;

  const StmtBlock({
    required final this.block,
    required final this.aug,
  });

  @override
  Z match<Z>({
    required final Z Function(StmtOutput<I>) output,
    required final Z Function(StmtLoop<I>) loop,
    required final Z Function(StmtLoop2<I>) loop2,
    required final Z Function(StmtConditional<I>) conditional,
    required final Z Function(StmtRet<I>) ret,
    required final Z Function(StmtWhil<I>) whil,
    required final Z Function(StmtBlock<I>) block,
    required final Z Function(StmtExpr<I>) expr,
  }) => block(this);
}

class StmtExpr<I> implements Stmt<I> {
  final Expr<I> expr;
  final I aug;

  const StmtExpr({
    required this.expr,
    required this.aug,
  });

  @override
  Z match<Z>({
    required final Z Function(StmtOutput<I>) output,
    required final Z Function(StmtLoop<I>) loop,
    required final Z Function(StmtLoop2<I>) loop2,
    required final Z Function(StmtConditional<I>) conditional,
    required final Z Function(StmtRet<I>) ret,
    required final Z Function(StmtWhil<I>) whil,
    required final Z Function(StmtBlock<I>) block,
    required final Z Function(StmtExpr<I>) expr,
  }) => expr(this);
}
// endregion

// region loop left
abstract class LoopLeft<I> {
  R match<R>({
    required final R Function(LoopLeftVari<I>) vari,
    required final R Function(LoopLeftExpr<I>) expr,
  });
}

class LoopLeftVari<I> implements LoopLeft<I> {
  final DeclarationVari<I> decl;

  const LoopLeftVari({
    required final this.decl,
  });

  @override
  R match<R>({
    required final R Function(LoopLeftVari<I>) vari,
    required final R Function(LoopLeftExpr<I>) expr,
  }) => vari(this);
}

class LoopLeftExpr<I> implements LoopLeft<I> {
  final Expr<I> expr;

  const LoopLeftExpr({
    required final this.expr,
  });

  @override
  R match<R>({
    required final R Function(LoopLeftVari<I>) vari,
    required final R Function(LoopLeftExpr<I>) expr,
  }) => expr(this);
}
// endregion

// region expr
abstract class Expr<I> {}

class ExprMap<I> implements Expr<I> {
  final List<MapEntry<Expr<I>, Expr<I>>> entries;
  final I aug;

  const ExprMap({
    required final this.entries,
    required final this.aug,
  });
}

class ExprCall<I> implements Expr<I> {
  final List<Expr<I>> args;
  final I aug;

  const ExprCall({
    required final this.args,
    required final this.aug,
  });
}

class ExprInvoke<I> implements Expr<I> {
  final List<Expr<I>> args;
  final Token<TokenAug> name;
  final I aug;

  const ExprInvoke({
    required final this.args,
    required final this.name,
    required final this.aug,
  });
}

class ExprGet<I> implements Expr<I> {
  final Token<TokenAug> name;
  final I aug;

  const ExprGet({
    required final this.name,
    required final this.aug,
  });
}

class ExprSet<I> implements Expr<I> {
  final Expr<I> arg;
  final Token<TokenAug> name;
  final I aug;

  const ExprSet({
    required final this.arg,
    required final this.name,
    required final this.aug,
  });
}

class ExprSet2<I> implements Expr<I> {
  final Expr<I> arg;
  final Token<TokenAug> name;
  final I aug;

  const ExprSet2({
    required final this.arg,
    required final this.name,
    required final this.aug,
  });
}

class ExprGetSet2<I> implements Expr<I> {
  final Token<TokenAug> name;
  final Getset<I>? child;
  final I aug;

  const ExprGetSet2({
    required final this.child,
    required final this.name,
    required final this.aug,
  });
}

class ExprList<I> implements Expr<I> {
  final List<Expr<I>> values;
  final int val_count;
  final I aug;

  const ExprList({
    required final this.values,
    required final this.val_count,
    required final this.aug,
  });
}

class ExprNil<I> implements Expr<I> {
  final I aug;

  const ExprNil({
    required final this.aug,
  });
}

class ExprString<I> implements Expr<I> {
  final Token<TokenAug> token;
  final I aug;

  const ExprString({
    required final this.token,
    required final this.aug,
  });
}

class ExprNumber<I> implements Expr<I> {
  final Token<TokenAug> value;
  final I aug;

  const ExprNumber({
    required final this.value,
    required final this.aug,
  });
}

class ExprObject<I> implements Expr<I> {
  final Token<TokenAug> token;
  final I aug;

  const ExprObject({
    required final this.token,
    required final this.aug,
  });
}

class ExprListGetter<I> implements Expr<I> {
  final Expr<I>? first;
  final Expr<I>? second;
  final Token<TokenAug> first_token;
  final Token<TokenAug> second_token;
  final I aug;

  const ExprListGetter({
    required final this.first,
    required final this.first_token,
    required final this.second,
    required final this.second_token,
    required final this.aug,
  });
}

class ExprListSetter<I> implements Expr<I> {
  final Expr<I>? first;
  final Expr<I>? second;
  final Token<TokenAug> token;
  final I aug;

  const ExprListSetter({
    required final this.first,
    required final this.second,
    required final this.token,
    required final this.aug,
  });
}

class ExprSuperaccess<I> implements Expr<I> {
  final Token<TokenAug> kw;
  final List<Expr<I>>? args;
  final I aug;

  const ExprSuperaccess({
    required final this.kw,
    required final this.args,
    required final this.aug,
  });
}

class ExprTruth<I> implements Expr<I> {
  final I aug;

  const ExprTruth({
    required final this.aug,
  });
}

class ExprFalsity<I> implements Expr<I> {
  final I aug;

  const ExprFalsity({
    required final this.aug,
  });
}

class ExprSelf<I> implements Expr<I> {
  final Token<TokenAug> previous;
  final I aug;

  const ExprSelf({
    required final this.previous,
    required final this.aug,
  });
}

class ExprComposite<I> implements Expr<I> {
  final List<Expr<I>> exprs;

  const ExprComposite({
    required final this.exprs,
  });
}

class ExprExpected<I> implements Expr<I> {
  const ExprExpected();
}

class ExprNegated<I> implements Expr<I> {
  final Expr<I> child;
  final I aug;

  const ExprNegated({
    required final this.child,
    required final this.aug,
  });
}

class ExprNot<I> implements Expr<I> {
  final Expr<I> child;
  final I aug;

  const ExprNot({
    required final this.child,
    required final this.aug,
  });
}

class ExprMinus<I> implements Expr<I> {
  final Expr<I> child;
  final I aug;

  const ExprMinus({
    required final this.child,
    required final this.aug,
  });
}

class ExprPlus<I> implements Expr<I> {
  final Expr<I> child;
  final I aug;

  const ExprPlus({
    required final this.child,
    required final this.aug,
  });
}

class ExprSlash<I> implements Expr<I> {
  final Expr<I> child;
  final I aug;

  const ExprSlash({
    required final this.child,
    required final this.aug,
  });
}

class ExprStar<I> implements Expr<I> {
  final Expr<I> child;
  final I aug;

  const ExprStar({
    required final this.child,
    required final this.aug,
  });
}

class ExprAnd<I> implements Expr<I> {
  final Token<TokenAug> token;
  final Expr<I> child;
  final I aug;

  const ExprAnd({
    required final this.token,
    required final this.child,
    required final this.aug,
  });
}

class ExprOr<I> implements Expr<I> {
  final Token<TokenAug> token;
  final Expr<I> child;
  final I aug;

  const ExprOr({
    required final this.token,
    required final this.child,
    required final this.aug,
  });
}

class ExprG<I> implements Expr<I> {
  final Expr<I> child;
  final I aug;

  const ExprG({
    required final this.child,
    required final this.aug,
  });
}

class ExprGeq<I> implements Expr<I> {
  final Expr<I> child;
  final I aug;

  const ExprGeq({
    required final this.child,
    required final this.aug,
  });
}

class ExprL<I> implements Expr<I> {
  final Expr<I> child;
  final I aug;

  const ExprL({
    required final this.child,
    required final this.aug,
  });
}

class ExprLeq<I> implements Expr<I> {
  final Expr<I> child;
  final I aug;

  const ExprLeq({
    required final this.child,
    required final this.aug,
  });
}

class ExprPow<I> implements Expr<I> {
  final Expr<I> child;
  final I aug;

  const ExprPow({
    required final this.child,
    required final this.aug,
  });
}

class ExprModulo<I> implements Expr<I> {
  final Expr<I> child;
  final I aug;

  const ExprModulo({
    required final this.child,
    required final this.aug,
  });
}

class ExprNeq<I> implements Expr<I> {
  final Expr<I> child;
  final I aug;

  const ExprNeq({
    required final this.child,
    required final this.aug,
  });
}

class ExprEq<I> implements Expr<I> {
  final Expr<I> child;
  final I aug;

  const ExprEq({
    required final this.child,
    required final this.aug,
  });
}

class Getset<I> {
  final Expr<I> child;
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

Z match_expr<Z, I>({
  required final Expr<I> expr,
  required final Z Function(ExprMap<I>) map,
  required final Z Function(ExprCall<I>) call,
  required final Z Function(ExprInvoke<I>) invoke,
  required final Z Function(ExprGet<I>) get,
  required final Z Function(ExprSet<I>) set,
  required final Z Function(ExprSet2<I>) set2,
  required final Z Function(ExprGetSet2<I>) getset2,
  required final Z Function(ExprList<I>) list,
  required final Z Function(ExprNil<I>) nil,
  required final Z Function(ExprString<I>) string,
  required final Z Function(ExprNumber<I>) number,
  required final Z Function(ExprObject<I>) object,
  required final Z Function(ExprListGetter<I>) listgetter,
  required final Z Function(ExprListSetter<I>) listsetter,
  required final Z Function(ExprSuperaccess<I>) superaccess,
  required final Z Function(ExprTruth<I>) truth,
  required final Z Function(ExprFalsity<I>) falsity,
  required final Z Function(ExprSelf<I>) self,
  required final Z Function(ExprComposite<I>) composite,
  required final Z Function(ExprExpected<I>) expected,
  required final Z Function(ExprNegated<I>) negated,
  required final Z Function(ExprNot<I>) not,
  required final Z Function(ExprMinus<I>) minus,
  required final Z Function(ExprPlus<I>) plus,
  required final Z Function(ExprSlash<I>) slash,
  required final Z Function(ExprStar<I>) star,
  required final Z Function(ExprAnd<I>) and,
  required final Z Function(ExprOr<I>) or,
  required final Z Function(ExprG<I>) g,
  required final Z Function(ExprGeq<I>) geq,
  required final Z Function(ExprL<I>) l,
  required final Z Function(ExprLeq<I>) leq,
  required final Z Function(ExprPow<I>) pow,
  required final Z Function(ExprModulo<I>) modulo,
  required final Z Function(ExprNeq<I>) neq,
  required final Z Function(ExprEq<I>) eq,
}) {
  if (expr is ExprMap<I>) return map(expr);
  if (expr is ExprMap<I>) return map(expr);
  if (expr is ExprMap<I>) return map(expr);
  if (expr is ExprCall<I>) return call(expr);
  if (expr is ExprInvoke<I>) return invoke(expr);
  if (expr is ExprGet<I>) return get(expr);
  if (expr is ExprSet<I>) return set(expr);
  if (expr is ExprSet2<I>) return set2(expr);
  if (expr is ExprGetSet2<I>) return getset2(expr);
  if (expr is ExprList<I>) return list(expr);
  if (expr is ExprNil<I>) return nil(expr);
  if (expr is ExprString<I>) return string(expr);
  if (expr is ExprNumber<I>) return number(expr);
  if (expr is ExprObject<I>) return object(expr);
  if (expr is ExprListGetter<I>) return listgetter(expr);
  if (expr is ExprListSetter<I>) return listsetter(expr);
  if (expr is ExprSuperaccess<I>) return superaccess(expr);
  if (expr is ExprTruth<I>) return truth(expr);
  if (expr is ExprFalsity<I>) return falsity(expr);
  if (expr is ExprSelf<I>) return self(expr);
  if (expr is ExprComposite<I>) return composite(expr);
  if (expr is ExprExpected<I>) return expected(expr);
  if (expr is ExprNegated<I>) return negated(expr);
  if (expr is ExprNot<I>) return not(expr);
  if (expr is ExprMinus<I>) return minus(expr);
  if (expr is ExprPlus<I>) return plus(expr);
  if (expr is ExprSlash<I>) return slash(expr);
  if (expr is ExprStar<I>) return star(expr);
  if (expr is ExprAnd<I>) return and(expr);
  if (expr is ExprOr<I>) return or(expr);
  if (expr is ExprG<I>) return g(expr);
  if (expr is ExprGeq<I>) return geq(expr);
  if (expr is ExprL<I>) return l(expr);
  if (expr is ExprLeq<I>) return leq(expr);
  if (expr is ExprPow<I>) return pow(expr);
  if (expr is ExprModulo<I>) return modulo(expr);
  if (expr is ExprNeq<I>) return neq(expr);
  if (expr is ExprEq<I>) return eq(expr);
  throw Exception("Invalid State");
}
// endregion
