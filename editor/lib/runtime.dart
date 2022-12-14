import 'dart:async';
import 'dart:math';

import 'package:dlox/arrows/code_to_objfunction.dart';
import 'package:dlox/arrows/fundamental/objfunction_to_output.dart';
import 'package:dlox/domains/errors.dart';
import 'package:dlox/domains/objfunction.dart';
import 'package:flutter/material.dart';

class Runtime extends ChangeNotifier {
  // State hooks
  String? source;
  final void Function(DloxFunction?, List<LangError>) on_compiler_result;
  final void Function(DloxVMInterpreterResult?) on_interpreter_result;

  // Compiler timer
  Timer? compile_timer;

  // Code variables
  DloxVM vm;
  String? compiled_source;
  DloxFunction? compiler_function;
  List<LangError> compiler_errors = [];
  DloxVMInterpreterResult? interpreter_result;
  bool running = false;
  bool stop_flag = false;
  bool vm_trace_enabled = true;

  // Performance tracking
  double average_ips = 0;

  // Buffers variables
  final List<String> stdout = [];
  final List<String> vm_out = [];
  final List<String> compiler_out = [];

  Runtime({
    required final this.on_compiler_result,
    required final this.on_interpreter_result,
  }) : vm = DloxVM(
          silent: true,
        ) {
    vm.trace_execution = true;
  }

  void _populate_buffer(
    final List<String> buf,
    final String? str,
  ) {
    if (str == null) {
      return;
    }
    str
        .trim()
        .split("\n")
        .where(
          (final line) => line.isNotEmpty,
        )
        .forEach(
      (final line) {
        buf.add(line);
      },
    );
    notifyListeners();
  }

  void _process_errors(
    final List<LangError> errors,
  ) {
    if (errors.isNotEmpty) {
      errors.forEach(
        (final err) => _populate_buffer(stdout, err.toString()),
      );
      notifyListeners();
    }
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

  @override
  void dispose() {
    if (compile_timer != null) {
      compile_timer!.cancel();
    }
    super.dispose();
  }

  void set_source(
    final String source,
  ) {
    this.source = source;
    if (compile_timer != null) {
      compile_timer!.cancel();
    }
    compile_timer = Timer(
      const Duration(milliseconds: 500),
      () {
        compile_timer = null;
        run_compilation();
      },
    );
  }

  void set_tracer(
    final bool enabled,
  ) {
    vm.trace_execution = enabled;
  }

  void run_compilation() {
    if (source != null && (compiled_source != source || compiler_function == null)) {
      // Clear interpreter output.
      interpreter_result = null;
      on_interpreter_result(interpreter_result);
      // Clear monitors.
      compiler_out.clear();
      clear_output();
      // Compile.
      final debug = Debug(
        silent: true,
      );
      compiler_function = source_to_dlox(
        source: source!,
        debug: debug,
        trace_bytecode: true,
      );
      compiler_errors = debug.errors;
      compiled_source = source!;
      // Populate result
      final str = debug.buf.toString();
      _populate_buffer(compiler_out, str);
      _process_errors(debug.errors);
      on_compiler_result(compiler_function, debug.errors);
    }
  }

  bool get done {
    return interpreter_result?.done ?? false;
  }

  bool _init_code() {
    // Compile if needed
    run_compilation();
    if (compiler_function == null || compiler_errors.isNotEmpty) {
      return false;
    } else {
      vm.set_function(
        compiler_function,
        compiler_errors,
        const DLoxVMFunctionParams(),
      );
      interpreter_result = null;
      return true;
    }
  }

  void _on_interpreter_result() {
    _populate_buffer(stdout, vm.stdout.clear());
    _populate_buffer(vm_out, vm.trace_debug.clear());
    _process_errors(interpreter_result!.errors);
    on_interpreter_result(interpreter_result);
    notifyListeners();
  }

  bool step() {
    if (!_init_code() || done) {
      return false;
    } else {
      vm.step_code = true;
      interpreter_result = vm.step_batch();
      _on_interpreter_result();
      return true;
    }
  }

  Future<bool> run() async {
    if (!_init_code()) {
      return false;
    } else {
      stop_flag = false;
      running = true;
      notifyListeners();
      vm.step_code = false;
      final time_started_ms = DateTime
          .now()
          .millisecondsSinceEpoch;
      while (!done && !stop_flag) {
        interpreter_result = vm.step_batch(
          // Cope with expensive tracing
          batch_count: vm.trace_execution ? 100 : 500000,
        );
        // Update Ips counter
        final dt = DateTime
            .now()
            .millisecondsSinceEpoch - time_started_ms;
        average_ips = vm.step_count / max(dt, 1) * 1000;
        _on_interpreter_result();
        await Future<void>.delayed(
          const Duration(
            seconds: 0,
          ),
        );
      }
      stop_flag = false;
      running = false;
      notifyListeners();
      return true;
    }
  }

  void reset() {
    if (compiler_function == null) {
        // Do nothing.
    } else {
      if (compiler_errors.isNotEmpty) {
        // Do nothing.
      } else {
        // Clear output
        clear_output();
        // Set interpreter
        vm.set_function(
          compiler_function!,
          compiler_errors,
          const DLoxVMFunctionParams(),
        );
        interpreter_result = null;
        on_interpreter_result(interpreter_result);
        notifyListeners();
      }
    }
  }

  void stop() {
    if (running) {
      stop_flag = true;
    }
  }
}
