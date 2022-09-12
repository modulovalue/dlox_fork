import 'package:editor/lox_mode.dart';
import 'package:editor/runtime.dart';
import 'package:dlox/arrows/objfunction_to_output.dart';
import 'package:dlox/models/errors.dart';
import 'package:dlox/models/objfunction.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';
import 'package:code_text_field/code_text_field.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart'
    show monokaiSublimeTheme;

import 'constants.dart';

class CodeEditor extends StatefulWidget {
  final Runtime runtime;

  CodeEditor({Key key, this.runtime}) : super(key: key);

  @override
  CodeEditorState createState() => CodeEditorState();
}

class CodeEditorState extends State<CodeEditor> {
  CodeController _codeController;
  InterpreterResult interpreterResult;
  ObjFunction compilerResult_function;
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

  void setSource(String source) {
    _codeController.text = source;
  }

  void _onSourceChange() {
    widget.runtime.set_source(_codeController.rawText);
  }

  void _setErrors(List<LangError> errors) {
    if (errors == null) return;
    errorMap.clear();
    errors.forEach((err) {
      final line = err.line + 1;
      if (!errorMap.containsKey(line)) errorMap[line] = <LangError>[];
      errorMap[line].add(err);
    });
    setState(() {});
  }

  void setCompilerResult(ObjFunction result, List<LangError> errors,) {
    this.compilerResult_function = result;
    _setErrors(errors);
  }

  void setInterpreterResult(InterpreterResult result) {
    this.interpreterResult = result;
    _setErrors(result?.errors);
  }

  String get source {
    return _codeController.text;
  }

  TextSpan _lineNumberBuilder(int line, TextStyle style) {
    // if (line == 2) return TextSpan(text: "@", style: style);
    if (errorMap.containsKey(line))
      return TextSpan(
        text: "❌",
        style: style.copyWith(color: Colors.red),
        recognizer: TapGestureRecognizer()..onTap = () => print('OnTap'),
      );
    if (interpreterResult?.last_line == line - 1)
      return TextSpan(
        text: ">",
        style: style.copyWith(
          color: ColorTheme.functions,
          fontWeight: FontWeight.bold,
        ),
      );
    return TextSpan(text: "$line", style: style);
  }

  @override
  Widget build(BuildContext context) {
    return CodeField(
      controller: _codeController,
      textStyle: TextStyle(fontFamily: 'SourceCode'),
      expands: true,
      lineNumberBuilder: _lineNumberBuilder,
    );
  }
}
