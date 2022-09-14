import '../domains/errors.dart';
import '../domains/objfunction.dart';
import 'fundamental/ast_to_objfunction.dart';
import 'fundamental/code_to_tokens.dart';
import 'fundamental/tokens_to_ast.dart';

DloxFunction source_to_dlox({
  required final String source,
  required final Debug debug,
  required final bool trace_bytecode,
}) {
  final tokens = run_lexer(
    source: source,
  );
  final parser = tokens_to_ast(
    tokens: tokens,
    debug: debug,
  );
  return ast_to_objfunction(
    compilation_unit: parser.key,
    last_line: parser.value,
    debug: debug,
    trace_bytecode: trace_bytecode,
  );
}
