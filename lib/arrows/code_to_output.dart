import 'dart:convert';
import 'dart:io';

import '../compiler.dart';
import '../models/errors.dart';
import 'code_to_tokens.dart';
import 'objfunction_to_output.dart';

void run_file(
    final String path,
    ) {
  final vm = VM(
    silent: false,
  );
  final source = File(path).readAsStringSync();
  final compiler_result = run_dlox_compiler(
    tokens: run_lexer(
      source: source,
    ),
    debug: Debug(
      false,
    ),
    trace_bytecode: false,
  );
  if (compiler_result.errors.isNotEmpty) {
    exit(65);
  } else {
    vm.set_function(
      compiler_result,
      const FunctionParams(),
    );
    final intepreter_result = vm.run();
    if (intepreter_result.errors.isNotEmpty) {
      exit(70);
    }
  }
}

void run_repl() {
  final vm = VM(
    silent: false,
  );
  for (;;) {
    stdout.write('> ');
    final line = stdin.readLineSync(encoding: Encoding.getByName('utf-8')!);
    if (line == null) {
      break;
    }
    final compilerResult = run_dlox_compiler(
      tokens: run_lexer(
        source: line,
      ),
      debug: Debug(
        false,
      ),
      trace_bytecode: false,
    );
    if (compilerResult.errors.isNotEmpty) {
      continue;
    }
    final globals = Map.fromEntries(vm.globals.data.entries);
    vm.set_function(compilerResult, FunctionParams(globals: globals));
    vm.run();
  }
}
