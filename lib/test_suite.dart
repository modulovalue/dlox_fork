import 'dart:io';

import 'package:path/path.dart';

import 'compiler.dart';
import 'model.dart';

// TODO have fixtures for the lexer in the style of esprima.
abstract class DLoxTestSuite {
  static void run({
    required final DLoxTestSuiteDependencies deps,
    required final DLoxTestSuiteWrapper wrapper,
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
          final fileList = dir_contents(dir);
          for (int k = 0; k < fileList.length; k++) {
            final file = fileList[k];
            const tab = "  ";
            wrapper.run_group(
              basename(file.path),
              () {
                final source = File(file.path).readAsStringSync();
                // Create line map
                final lineNumber = <int>[];
                for (int k = 0, line = 0; k < source.length; k++) {
                  if (source[k] == '\n') line += 1;
                  lineNumber.add(line);
                }
                // Compile test
                final compilerResult = Compiler.compile(
                  deps.lexer(source),
                  silent: true,
                );
                // Compiler error
                RegExp errExp = RegExp(r'// Error at (.+):(.+)');
                Iterable<RegExpMatch> errMatches = errExp.allMatches(source);
                Set<String> errRef = errMatches.map((final e) {
                  final line = lineNumber[e.start];
                  String msg = e.group(2)!.trim();
                  if (msg.endsWith('.')) msg = msg.substring(0, msg.length - 1);
                  return '$line:$msg';
                }).toSet();
                Set<String> errList =
                    compilerResult.errors.map((final e) => '${e.token!.loc.i}:${e.msg}').toSet();
                wrapper.run_test("test", (final test_context) {
                  if (set_eq(errRef, errList)) {
                    if (errList.isEmpty) {
                      // Run test
                      vm.stdout.clear();
                      vm.setFunction(compilerResult, FunctionParams());
                      final intepreterResult = vm.run();
                      // Interpreter errors
                      errExp = RegExp(r'// Runtime error:(.+)');
                      errMatches = errExp.allMatches(source);
                      errRef = errMatches.map((final e) {
                        final line = lineNumber[e.start];
                        String msg = e.group(1)!.trim();
                        if (msg.endsWith('.')) msg = msg.substring(0, msg.length - 1);
                        return '$line:$msg';
                      }).toSet();
                      errList = intepreterResult.errors
                          .map((final e) => '${e.line}:${e.msg}')
                          // filter out stack traces
                          .where((final el) => !el.contains(RegExp('during(.+)execution')))
                          .toSet();
                      if (set_eq(errRef, errList)) {
                        // Extract test reqs
                        final rtnExp = RegExp(r'// expect: (.+)');
                        final rtnMatches = rtnExp.allMatches(source);
                        final stdoutRef = rtnMatches.map((final e) => e.group(1)).toList();
                        final stdout = vm.stdout.buf
                            .toString()
                            .trim()
                            .split('\n')
                            .where((final str) => str.isNotEmpty)
                            .toList();
                        if (!list_eq(stdoutRef, stdout)) {
                          test_context.failed(
                            [
                              '$tab stdout mismatch',
                              '$tab -> expected: $stdoutRef',
                              '$tab -> got: $stdout',
                            ].join("\n"),
                          );
                        } else {
                          test_context.success();
                        }
                      } else {
                        test_context.failed(
                          [
                            '$tab Runtime error mismatch',
                            '$tab -> expected: $errRef',
                            '$tab -> got: $errList',
                          ].join("\n"),
                        );
                      }
                    }
                  } else {
                    test_context.failed(
                      [
                        '$tab Compile error mismatch',
                        '$tab -> expected: $errRef',
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

class DLoxTestSuiteWrapper {
  final void Function(String name, void Function() fn) run_group;
  final void Function(
    String name,
    void Function(DLoxTestSuiteContext) test_context,
  ) run_test;

  const DLoxTestSuiteWrapper({
    required final this.run_group,
    required final this.run_test,
  });
}

class DLoxTestSuiteContext {
  final void Function(String) failed;
  final void Function() success;

  const DLoxTestSuiteContext({
    required final this.failed,
    required final this.success,
  });
}
