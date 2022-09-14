import 'package:code_text_field/code_text_field.dart';
import 'package:dlox/arrows/fundamental/objfunction_to_output.dart';
import 'package:dlox/domains/errors.dart';
import 'package:dlox/domains/objfunction.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart' show monokaiSublimeTheme;

import 'constants.dart';
import 'lox_mode.dart';
import 'runtime.dart';

class CodeEditor extends StatefulWidget {
  final Runtime runtime;

  const CodeEditor({
    required final this.runtime,
    final Key? key,
  }) : super(
          key: key,
        );

  @override
  CodeEditorState createState() => CodeEditorState();
}

class CodeEditorState extends State<CodeEditor> {
  late CodeController _codeController;
  DloxVMInterpreterResult? interpreterResult;
  DloxFunction? compilerResult_function;
  final errorMap = <int, List<LangError>>{};

  @override
  void initState() {
    super.initState();
    // Instantiate the CodeController
    _codeController = CodeController(
      text: widget.runtime.source,
      language: lox,
      theme: monokaiSublimeTheme,
    );
    _codeController.addListener(_onSourceChange);
  }

  @override
  void dispose() {
    _codeController.removeListener(_onSourceChange);
    _codeController.dispose();
    super.dispose();
  }

  void setSource(
    final String source,
  ) {
    _codeController.text = source;
  }

  void _onSourceChange() {
    widget.runtime.set_source(_codeController.rawText);
  }

  void _setErrors(
    final List<LangError>? errors,
  ) {
    if (errors == null) {
      return;
    }
    errorMap.clear();
    errors.forEach((final err) {
      final line = err.line + 1;
      errorMap.putIfAbsent(line, () => <LangError>[]).add(err);
    });
    setState(() {});
  }

  void setCompilerResult(
    final DloxFunction? result,
    final List<LangError> errors,
  ) {
    this.compilerResult_function = result;
    _setErrors(errors);
  }

  void setInterpreterResult(
    final DloxVMInterpreterResult? result,
  ) {
    this.interpreterResult = result;
    _setErrors(result?.errors);
  }

  String get source {
    return _codeController.text;
  }

  TextSpan _lineNumberBuilder(
    final int line,
    final TextStyle style,
  ) {
    // if (line == 2) return TextSpan(text: "@", style: style);
    if (errorMap.containsKey(line)) {
      return TextSpan(
        text: "❌",
        style: style.copyWith(color: Colors.red),
        recognizer: TapGestureRecognizer()..onTap = () => print('OnTap'),
      );
    }
    if (interpreterResult?.last_line == line - 1) {
      return TextSpan(
        text: ">",
        style: style.copyWith(
          color: ColorTheme.functions,
          fontWeight: FontWeight.bold,
        ),
      );
    }
    return TextSpan(text: "$line", style: style);
  }

  @override
  Widget build(
    final BuildContext context,
  ) {
    return CodeField(
      controller: _codeController,
      textStyle: const TextStyle(fontFamily: 'SourceCode'),
      expands: true,
      lineNumberBuilder: (final a, final b) => _lineNumberBuilder(a, b!),
    );
  }
}
