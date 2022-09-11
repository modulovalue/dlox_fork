import 'dart:isolate';

import 'package:dlox/lexer.dart';
import 'package:dlox/test_suite.dart';
import 'package:test/test.dart';

Future<void> main() async {
  DLoxTestSuite.run(
    deps: DLoxTestSuiteDependencies(
      lexer: (final source) => run_lexer(
        source: source,
      ),
      dlox_lib_path: (await Isolate.resolvePackageUri(Uri.parse("package:dlox/")))!,
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
