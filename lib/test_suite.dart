import 'dart:io';

import 'package:path/path.dart';

import 'compiler.dart';
import 'model.dart';

// TODO have fixtures for the lexer in the style of esprima.
// TODO have a benchmark suite that exposes just files.
abstract class DLoxTestSuite {
  static void run<R>({
    required final DLoxTestSuiteDependencies deps,
    required final DLoxTestSuiteWrapper<R> wrapper,
  }) {
    final vm = VM(
      silent: true,
    );
    final dir_list = dir_contents(Directory(deps.dlox_lib_path.resolve("test").path));
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
                final compiler_result = compile(
                  deps.lexer(source),
                  silent: true,
                );
                // Compiler error
                RegExp err_exp = RegExp(r'// Error at (.+):(.+)');
                Iterable<RegExpMatch> err_matches = err_exp.allMatches(source);
                Set<String> err_ref = err_matches.map((final e) {
                  final line = line_number[e.start];
                  String msg = e.group(2)!.trim();
                  if (msg.endsWith('.')) msg = msg.substring(0, msg.length - 1);
                  return line.toString() + ':' + msg;
                }).toSet();
                Set<String> errList =
                    compiler_result.errors.map((final e) => '${e.token!.loc.line}:${e.msg}').toSet();
                wrapper.run_test("test", (final test_context) {
                  if (set_eq(err_ref, errList)) {
                    if (errList.isEmpty) {
                      // Run test
                      vm.stdout.clear();
                      vm.setFunction(compiler_result, FunctionParams());
                      final intepreter_result = vm.run();
                      // Interpreter errors
                      err_exp = RegExp(r'// Runtime error:(.+)');
                      err_matches = err_exp.allMatches(source);
                      err_ref = err_matches.map((final e) {
                        final line = line_number[e.start];
                        String msg = e.group(1)!.trim();
                        if (msg.endsWith('.')) msg = msg.substring(0, msg.length - 1);
                        return '$line:$msg';
                      }).toSet();
                      errList = intepreter_result.errors
                          .map((final e) => '${e.line}:${e.msg}')
                          // filter out stack traces
                          .where((final el) => !el.contains(RegExp('during(.+)execution')))
                          .toSet();
                      if (set_eq(err_ref, errList)) {
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
                            '$tab -> expected: $err_ref',
                            '$tab -> got     : $errList',
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
                        '$tab -> expected: $err_ref',
                        '$tab -> got: $errList',
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
  final List<NaturalToken> Function(String) lexer;
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
