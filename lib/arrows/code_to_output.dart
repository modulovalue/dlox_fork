import 'dart:convert';
import 'dart:io';

import '../domains/errors.dart';
import 'code_to_objfunction.dart';
import 'fundamental/objfunction_to_output.dart';

void run_dlox_from_file({
  required final String source,
}) {
  final debug = Debug(
    silent: false,
  );
  final compiler_result = source_to_dlox(
    source: source,
    debug: debug,
    trace_bytecode: false,
  );
  if (debug.errors.isNotEmpty) {
    exit(65);
  } else {
    final vm = DloxVM(
      silent: false,
    );
    vm.set_function(
      compiler_result,
      debug.errors,
      const DLoxVMFunctionParams(),
    );
    final interpreter_result = vm.run();
    if (interpreter_result.errors.isNotEmpty) {
      exit(70);
    } else {
      // Success.
    }
  }
}

void run_dlox_repl() {
  final vm = DloxVM(
    silent: false,
  );
  for (;;) {
    stdout.write('> ');
    final line = stdin.readLineSync(
      encoding: utf8,
    );
    if (line == null) {
      break;
    } else {
      final debug = Debug(
        silent: false,
      );
      final compiler_result = source_to_dlox(
        source: line,
        debug: debug,
        trace_bytecode: false,
      );
      if (debug.errors.isNotEmpty) {
        continue;
      } else {
        final globals = Map.fromEntries(
          vm.globals.data.entries,
        );
        vm.set_function(
          compiler_result,
          debug.errors,
          DLoxVMFunctionParams(
            globals: globals,
          ),
        );
        vm.run();
      }
    }
  }
}
