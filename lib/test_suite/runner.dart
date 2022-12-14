import '../arrows/fundamental/ast_to_objfunction.dart' show ast_to_objfunction;
import '../arrows/fundamental/objfunction_to_output.dart' show DloxVM;
import '../domains/ast.dart' show CompilationUnit;
import '../domains/errors.dart' show Debug;
import '../domains/tokens.dart' show Token, TokenAug;
import 'dataset.dart' show DloxDatasetAll;
import 'model.dart' show DloxDatasetInternal, DloxDatasetLeafImpl;

// TODO have fixtures for the lexer in the style of esprima.
abstract class DLoxTestSuite {
  static void run<R>({
    required final DLoxTestSuiteDependencies deps,
    required final DLoxTestSuiteWrapper<R> wrapper,
  }) {
    final runtime_error_regexp = RegExp(r'// Runtime error:(.+)');
    final error_at_regexp = RegExp(r'// Error at (.+):(.+)');
    final during_execution_regexp = RegExp('during(.+)execution');
    final expect_regexp = RegExp(r'// expect: (.+)');
    final vm = DloxVM(
      silent: true,
    );
    for (final x in const DloxDatasetAll().children) {
      wrapper.run_group(
        x.name,
        () {
            // Skip file.
            for (final y in (x as DloxDatasetInternal).children) {
              final file = y as DloxDatasetLeafImpl;
              const tab = "  ";
              wrapper.run_group(
                file.name,
                () {
                  final source = file.source;
                  // Create line map
                  final line_number = <int>[];
                  for (int k = 0, line = 0; k < source.length; k++) {
                    if (source[k] == '\n') line += 1;
                    line_number.add(line);
                  }
                  // Compile test
                  final debug = Debug(
                    silent: true,
                  );
                  final tokens = deps.code_to_tokens(source);
                  final parser = deps.tokens_to_ast(tokens, debug);
                  final compiler_result = ast_to_objfunction(
                    compilation_unit: parser.key,
                    last_line: parser.value,
                    debug: debug,
                    trace_bytecode: false,
                  );
                  // Compiler error
                  final err_matches1 = error_at_regexp.allMatches(source);
                  final err_ref1 = err_matches1.map(
                    (final e) {
                      final line = line_number[e.start];
                      String msg = e.group(2)!.trim();
                      if (msg.endsWith('.')) {
                        msg = msg.substring(0, msg.length - 1);
                      }
                      return line.toString() + ':' + msg;
                    },
                  ).toSet();
                  final err_list1 = debug.errors
                      .map(
                        (final e) => '${e.token.aug.line}:${e.msg}',
                      )
                      .toSet();
                  wrapper.run_test("test", (final test_context) {
                    if (_set_eq(err_ref1, err_list1)) {
                      if (err_list1.isEmpty) {
                        // Run test
                        vm.stdout.clear();
                        vm.set_function(
                          compiler_result,
                          debug.errors,
                        );
                        final interpreter_result = vm.run();
                        // Interpreter errors
                        final err_matches2 = runtime_error_regexp.allMatches(source);
                        final err_ref2 = err_matches2.map((final e) {
                          final line = line_number[e.start];
                          final msg = e.group(1)!.trim();
                          if (msg.endsWith('.')) {
                            return '$line:' + msg.substring(0, msg.length - 1);
                          } else {
                            return '$line:' + msg;
                          }
                        }).toSet();
                        final err_list2 = interpreter_result.errors
                            .map((final e) => '${e.line}:${e.msg}')
                            // filter out stack traces
                            .where((final el) => !el.contains(during_execution_regexp))
                            .toSet();
                        if (_set_eq(err_ref2, err_list2)) {
                          // Extract test reqs
                          final rtn_matches = expect_regexp.allMatches(source);
                          final stdout_ref = rtn_matches.map((final e) => e.group(1)).toList();
                          final stdout = vm.stdout.buf
                              .toString()
                              .trim()
                              .split('\n')
                              .where((final str) => str.isNotEmpty)
                              .toList();
                          if (!_list_eq(stdout_ref, stdout)) {
                            return test_context.failed(
                              [
                                '$tab stdout mismatch',
                                '$tab -> expected: $stdout_ref',
                                '$tab -> got     : $stdout',
                              ].join("\n"),
                            );
                          } else {
                            return test_context.success();
                          }
                        } else {
                          return test_context.failed(
                            [
                              '$tab Runtime error mismatch',
                              '$tab -> expected: $err_ref2',
                              '$tab -> got     : $err_list2',
                            ].join("\n"),
                          );
                        }
                      } else {
                        return test_context.success();
                      }
                    } else {
                      return test_context.failed(
                        [
                          '$tab Compile error mismatch',
                          '$tab -> expected: $err_ref1',
                          '$tab -> got: $err_list1',
                        ].join("\n"),
                      );
                    }
                  });
                },
              );
            }
        },
      );
    }
  }

  static bool _set_eq(
    final Set<dynamic> s1,
    final Set<dynamic> s2,
  ) {
    return s1.length == s2.length && s1.every(s2.contains);
  }

  static bool _list_eq(
    final List<dynamic> l1,
    final List<dynamic> l2,
  ) {
    if (l1.length != l2.length) {
      return false;
    } else {
      for (int k = 0; k < l1.length; k++) {
        if (l1[k] != l2[k]) {
          return false;
        }
      }
      return true;
    }
  }
}

class DLoxTestSuiteDependencies {
  final List<Token<TokenAug>> Function(String) code_to_tokens;
  final MapEntry<CompilationUnit<int>, int> Function(
    List<Token<TokenAug>> tokens,
    Debug debug,
  ) tokens_to_ast;

  const DLoxTestSuiteDependencies({
    required final this.code_to_tokens,
    required final this.tokens_to_ast,
  });
}

class DLoxTestSuiteWrapper<R> {
  final void Function(
    String name,
    void Function() fn,
  ) run_group;
  final void Function(
    String name,
    R Function(DLoxTestSuiteContext<R>) test_context,
  ) run_test;

  const DLoxTestSuiteWrapper({
    required final this.run_group,
    required final this.run_test,
  });
}

class DLoxTestSuiteContext<R> {
  final R Function(String) failed;
  final R Function() success;

  const DLoxTestSuiteContext({
    required final this.failed,
    required final this.success,
  });
}
