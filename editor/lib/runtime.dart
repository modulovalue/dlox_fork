import 'dart:async';
import 'dart:math';

import 'package:dlox/compiler.dart';
import 'package:dlox/lexer.dart';
import 'package:dlox/vm.dart';
import 'package:flutter/material.dart';

class Runtime extends ChangeNotifier {
  // State hooks
  String source;
  final Function(CompilerResult) on_compiler_result;
  final Function(InterpreterResult) on_interpreter_result;

  // Compiler timer
  Timer compile_timer;

  // Code variables
  VM vm;
  String compiled_source;
  CompilerResult compiler_result;
  InterpreterResult interpreter_result;
  bool running = false;
  bool stop_flag = false;
  bool vm_trace_enabled = true;

  // Performance tracking
  int time_started_ms;
  double average_ips = 0;

  // Buffers variables
  final stdout = <String>[];
  final vm_out = <String>[];
  final compiler_out = <String>[];

  Runtime({
    this.on_compiler_result,
    this.on_interpreter_result,
  }) {
    vm = VM(
      silent: true,
    );
    vm.trace_execution = true;
  }

  void _populate_buffer(
    List<String> buf,
    String str,
  ) {
    if (str == null) {
      return;
    }
    str.trim().split("\n").where((line) => line.isNotEmpty).forEach((final line) {
      buf.add(line);
    });
    notifyListeners();
  }

  void _process_errors(
    List<LangError> errors,
  ) {
    if (errors == null) return;
    errors.forEach((err) {
      _populate_buffer(stdout, err.toString());
    });
    notifyListeners();
  }

  void toggle_vm_trace() {
    vm_trace_enabled = !vm_trace_enabled;
    vm.trace_execution = vm_trace_enabled;
    if (!vm_trace_enabled) {
      vm_out.clear();
    }
    notifyListeners();
  }

  void clear_output() {
    stdout.clear();
    vm_out.clear();
    notifyListeners();
  }

  void dispose() {
    if (compile_timer != null) {
      compile_timer.cancel();
    }
    super.dispose();
  }

  void set_source(
    String source,
  ) {
    this.source = source;
    if (compile_timer != null) {
      compile_timer.cancel();
    }
    compile_timer = Timer(Duration(milliseconds: 500), () {
      compile_timer = null;
      run_compilation();
    });
  }

  void set_tracer(
    bool enabled,
  ) {
    vm.trace_execution = enabled;
  }

  void run_compilation() {
    if (source == null || (compiled_source == source && compiler_result != null)) {
      return;
    } else {
      // Clear interpeter output
      interpreter_result = null;
      on_interpreter_result(interpreter_result);
      // Clear monitors
      compiler_out.clear();
      clear_output();
      // Compile
      compiler_result = run_compiler(
        tokens: run_lexer(
          source: source,
        ),
        silent: true,
        trace_bytecode: true,
      );
      compiled_source = source;
      // Populate result
      final str = compiler_result.debug.buf.toString();
      _populate_buffer(compiler_out, str);
      _process_errors(compiler_result.errors);
      on_compiler_result(compiler_result);
    }
  }

  bool get done {
    return interpreter_result?.done ?? false;
  }

  bool _init_code() {
    // Compile if needed
    run_compilation();
    if (compiler_result == null || compiler_result.errors.isNotEmpty) {
      return false;
    }
    if (vm.compiler_result != compiler_result) {
      vm.set_function(compiler_result, FunctionParams());
      interpreter_result = null;
    }
    return true;
  }

  void _on_interpreter_result() {
    _populate_buffer(stdout, vm.stdout.clear());
    _populate_buffer(vm_out, vm.trace_debug.clear());
    _process_errors(interpreter_result?.errors);
    on_interpreter_result(interpreter_result);
    notifyListeners();
  }

  bool step() {
    if (!_init_code() || done) {
      return false;
    }
    vm.step_code = true;
    interpreter_result = vm.step_batch();
    _on_interpreter_result();
    return true;
  }

  Future<bool> run() async {
    if (!_init_code()) {
      return false;
    }
    stop_flag = false;
    running = true;
    notifyListeners();
    vm.step_code = false;
    time_started_ms = DateTime.now().millisecondsSinceEpoch;
    while (!done && !stop_flag) {
      interpreter_result = vm.step_batch(
        // Cope with expensive tracing
        batch_count: vm.trace_execution ? 100 : 500000,
      );
      // Update Ips counter
      final dt = DateTime.now().millisecondsSinceEpoch - time_started_ms;
      average_ips = vm.step_count / max(dt, 1) * 1000;
      _on_interpreter_result();
      await Future.delayed(Duration(seconds: 0));
    }
    stop_flag = false;
    running = false;
    notifyListeners();
    return true;
  }

  void reset() {
    if (compiler_result == null) {
      return;
    }
    if (compiler_result.errors.isNotEmpty) {
      return;
    }
    // Clear output
    clear_output();
    // Set interpreter
    vm.set_function(compiler_result, FunctionParams());
    interpreter_result = null;
    on_interpreter_result(interpreter_result);
    notifyListeners();
  }

  void stop() {
    if (running) {
      stop_flag = true;
    }
  }
}
