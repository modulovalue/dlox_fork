import 'dart:io';

import 'package:dlox/arrows/code_to_output.dart';

void main(
  final List<String> args,
) {
  if (args.isEmpty) {
    run_repl();
  } else if (args.length == 1) {
    run_file(
      path: args[0],
    );
  } else {
    print(
      'Usage: dart main.dart [path]',
    );
    exit(64);
  }
}
