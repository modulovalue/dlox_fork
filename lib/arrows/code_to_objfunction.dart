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
  final parser = DloxParserImpl(
    tokens: run_lexer(
      source: source,
    ),
    debug: debug,
  );
  // TODO have a custom error delegate dont pass on parser delegate.
  // TODO use hidden parser
  final parsed = parser.parse_compilation_unit();
  return ast_to_objfunction(
    compilation_unit: parsed,
    error_delegate: parser,
    last_line: parser.previous_line,
    trace_bytecode: trace_bytecode,
  );
}
