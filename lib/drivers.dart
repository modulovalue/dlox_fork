import 'dart:convert';
import 'dart:io';

import 'compiler.dart';
import 'lexer.dart';

void run_file(
  final String path,
) {
  final vm = VM(
    silent: false,
  );
  final source = File(path).readAsStringSync();
  final compilerResult = compile(lex(source));
  if (compilerResult.errors.isNotEmpty) exit(65);
  vm.set_function(compilerResult, const FunctionParams());
  final intepreterResult = vm.run();
  if (intepreterResult.errors.isNotEmpty) exit(70);
}

void run_repl() {
  final vm = VM(
    silent: false,
  );
  for (;;) {
    stdout.write('> ');
    final line = stdin.readLineSync(encoding: Encoding.getByName('utf-8')!);
    if (line == null) break;
    final compilerResult = compile(lex(line));
    if (compilerResult.errors.isNotEmpty) continue;
    final globals = Map.fromEntries(vm.globals.data.entries);
    vm.set_function(compilerResult, FunctionParams(globals: globals));
    vm.run();
  }
}
