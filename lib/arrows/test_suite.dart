import 'dart:io';

import 'package:path/path.dart';

// TODO remove this
import '../arrows/objfunction_to_output.dart';
// TODO remove this
import '../compiler.dart';
// TODO remove this
import '../models/ast.dart';
// TODO remove this
import '../models/errors.dart';

// TODO have fixtures for the lexer in the style of esprima?
// TODO have a benchmark suite that exposes just files.
// TODO move into the one level up test directory once there are no dependencies here anymore.
abstract class DLoxTestSuite {
  static void run<R>({
    required final DLoxTestSuiteDependencies deps,
    required final DLoxTestSuiteWrapper<R> wrapper,
  }) {
    final vm = VM(
      silent: true,
    );
    final dir_list = dir_contents(Directory(deps.dlox_lib_path.resolve("../lib/test").path));
    for (int k = 0; k < dir_list.length; k++) {
      final dir = dir_list[k];
      wrapper.run_group(
        basename(dir.path),
        () {
          final file_list = dir_contents(dir);
          for (int k = 0; k < file_list.length; k++) {
            final file = file_list[k];
            const tab = "  ";
            wrapper.run_group(
              basename(file.path),
              () {
                final source = File(file.path).readAsStringSync();
                // Create line map
                final line_number = <int>[];
                for (int k = 0, line = 0; k < source.length; k++) {
                  if (source[k] == '\n') line += 1;
                  line_number.add(line);
                }
                // Compile test
                final debug = Debug(
                  true,
                );
                final compiler_result = run_dlox_compiler(
                  tokens: deps.lexer(
                    source,
                  ),
                  debug: debug,
                  trace_bytecode: false,
                );
                // Compiler error
                final err_matches1 = RegExp(r'// Error at (.+):(.+)').allMatches(source);
                final err_ref1 = err_matches1.map((final e) {
                  final line = line_number[e.start];
                  String msg = e.group(2)!.trim();
                  if (msg.endsWith('.')) {
                    msg = msg.substring(0, msg.length - 1);
                  }
                  return line.toString() + ':' + msg;
                }).toSet();
                final err_list1 = debug.errors.map((final e) => '${e.token.loc.line}:${e.msg}').toSet();
                wrapper.run_test("test", (final test_context) {
                  if (set_eq(err_ref1, err_list1)) {
                    if (err_list1.isEmpty) {
                      // Run test
                      vm.stdout.clear();
                      vm.set_function(
                        compiler_result,
                        debug.errors,
                        const FunctionParams(),
                      );
                      final interpreter_result = vm.run();
                      // Interpreter errors
                      final err_matches2 = RegExp(r'// Runtime error:(.+)').allMatches(source);
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
                          .where((final el) => !el.contains(RegExp('during(.+)execution')))
                          .toSet();
                      if (set_eq(err_ref2, err_list2)) {
                        // Extract test reqs
                        final rtn_exp = RegExp(r'// expect: (.+)');
                        final rtn_matches = rtn_exp.allMatches(source);
                        final stdout_ref = rtn_matches.map((final e) => e.group(1)).toList();
                        final stdout = vm.stdout.buf
                            .toString()
                            .trim()
                            .split('\n')
                            .where((final str) => str.isNotEmpty)
                            .toList();
                        if (!list_eq(stdout_ref, stdout)) {
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

  static List<FileSystemEntity> dir_contents(
    final FileSystemEntity dir,
  ) {
    return (dir as Directory).listSync(recursive: false);
  }

  static bool set_eq(
    final Set<dynamic> s1,
    final Set<dynamic> s2,
  ) {
    return s1.length == s2.length && s1.every(s2.contains);
  }

  static bool list_eq(
    final List<dynamic> l1,
    final List<dynamic> l2,
  ) {
    if (l1.length != l2.length) return false;
    for (int k = 0; k < l1.length; k++) {
      if (l1[k] != l2[k]) return false;
    }
    return true;
  }
}

class DLoxTestSuiteDependencies {
  final List<Token> Function(String) lexer;
  final Uri dlox_lib_path;

  const DLoxTestSuiteDependencies({
    required final this.lexer,
    required final this.dlox_lib_path,
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
