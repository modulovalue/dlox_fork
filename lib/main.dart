import 'dart:io';

import 'drivers.dart';

void main(
  final List<String> args,
) {
  if (args.isEmpty) {
    run_repl();
  } else if (args.length == 1) {
    run_file(args[0]);
  } else {
    print('Usage: dart main.dart [path]');
    exit(64);
  }
}
