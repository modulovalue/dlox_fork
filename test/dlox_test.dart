import 'package:dlox/arrows/fundamental/code_to_tokens.dart';
import 'package:dlox/arrows/fundamental/tokens_to_ast.dart';
import 'package:dlox/test_suite/runner.dart';
import 'package:test/test.dart';

void main() {
  DLoxTestSuite.run(
    deps: DLoxTestSuiteDependencies(
      code_to_tokens: (final source) => source_to_tokens(
        source: source,
      ),
      tokens_to_ast: (final tokens, final debug) => tokens_to_ast(
        tokens: tokens,
        debug: debug,
      ),
    ),
    wrapper: DLoxTestSuiteWrapper<void>(
      run_group: (final name, final fn) => group(
        name,
        () => fn(),
      ),
      run_test: (final name, final fn) {
        final test_context = DLoxTestSuiteContext(
          failed: fail,
          success: () => expect(true, true),
        );
        test(
          name,
          () => fn(test_context),
        );
      },
    ),
  );
}
