import 'dart:collection';
import 'dart:math';

import '../../domains/errors.dart';
import '../../domains/objfunction.dart';

// region vm
class DloxVM {
  static const String INIT_STRING = 'init';

  // region data
  final List<_Dlox_VMCallFrame?> frames;
  final List<Object?> stack;

  // endregion
  // region vm state
  final List<RuntimeError> errors;
  final DloxTable globals;
  final DloxTable strings;
  DloxFunction? compiled_function;
  int frame_count;
  int stack_top;
  DloxUpvalue? open_upvalues;

  // endregion
  // region debug variables
  int step_count;
  int line;
  bool has_op;

  // endregion
  // region debug api
  bool trace_execution;
  bool step_code;
  final Debug err_debug;
  final Debug trace_debug;
  final Debug stdout;

  // endregion

  DloxVM({
    required final bool silent,
  })  : err_debug = Debug(
          silent: silent,
        ),
        trace_debug = Debug(
          silent: silent,
        ),
        stdout = Debug(
          silent: silent,
        ),
        step_code = false,
        trace_execution = false,
        has_op = false,
        line = -1,
        step_count = 0,
        stack_top = 0,
        frame_count = 0,
        strings = DloxTable(),
        globals = DloxTable(),
        errors = [],
        stack = List<Object?>.filled(_DLOXVM_STACK_MAX, null),
        frames = List<_Dlox_VMCallFrame?>.filled(_DLOXVM_FRAMES_MAX, null) {
    _reset();
    for (int k = 0; k < frames.length; k++) {
      frames[k] = _Dlox_VMCallFrame();
    }
  }

  RuntimeError add_error({
    required final String msg,
    required final RuntimeError? link,
    required final int line,
  }) {
    final error = RuntimeError(
      line: line,
      msg: msg,
      link: link,
    );
    errors.add(error);
    err_debug.write_error(error);
    return error;
  }

  DloxVMInterpreterResult get_result({
    required final int line,
    final Object? return_value,
  }) {
    return DloxVMInterpreterResult(
      errors: errors,
      last_line: line,
      step_count: step_count,
      return_value: return_value,
    );
  }

  DloxVMInterpreterResult get result {
    return get_result(
      line: line,
    );
  }

  void _reset() {
    // Reset data
    errors.clear();
    globals.data.clear();
    strings.data.clear();
    stack_top = 0;
    frame_count = 0;
    open_upvalues = null;
    // Reset debug values
    step_count = 0;
    line = -1;
    has_op = false;
    stdout.clear();
    err_debug.clear();
    trace_debug.clear();
    // Reset flags
    step_code = false;
    // Define natives
    define_natives();
  }

  void set_function(
    final DloxFunction? function,
    final List<LangError> errors,
    [
      final DLoxVMFunctionParams params = const DLoxVMFunctionParams(),
    ]
  ) {
    _reset();
    // Set compiler result
    if (errors.isNotEmpty) {
      throw Exception('Compiler result had errors');
    } else {
      this.compiled_function = function;
      // Set function
      DloxFunction? fun = function;
      if (params.function != null) {
        final found_fun = () {
          for (final x in function!.chunk.heap.all_constants) {
            if (x is DloxFunction && x.name == params.function) {
              return x;
            }
          }
          return null;
        }();
        if (found_fun == null) {
          throw Exception('Function not found ${params.function}');
        } else {
          fun = found_fun;
        }
      }
      // Set globals.
      if (params.globals != null) {
        globals.data.addAll(params.globals!);
      }
      // Init VM.
      final closure = DloxClosure(fun!);
      push(closure);
      if (params.args != null) {
        params.args!.forEach(push);
      }
      call_value(closure, params.args?.length ?? 0);
    }
  }

  void define_natives() {
    for (final function in _NATIVE_FUNCTIONS) {
      globals.set_val(function.name, function);
    }
    _NATIVE_VALUES.forEach((final key, final value) {
      globals.set_val(key, value);
    });
    _NATIVE_CLASSES.forEach((final key, final value) {
      globals.set_val(key, value);
    });
  }

  void push(
    final Object? value,
  ) {
    stack[stack_top++] = value;
  }

  Object? pop() {
    return stack[--stack_top];
  }

  Object? peek(
    final int distance,
  ) {
    return stack[stack_top - distance - 1];
  }

  bool call(
    final DloxClosure closure,
    final int arg_count,
  ) {
    if (arg_count != closure.function.arity) {
      runtime_error('Expected ${closure.function.arity} arguments but got ${arg_count}');
      return false;
    } else {
      if (frame_count == _DLOXVM_FRAMES_MAX) {
        runtime_error('Stack overflow');
        return false;
      } else {
        final frame = frames[frame_count++]!;
        frame.closure = closure;
        frame.chunk = closure.function.chunk;
        frame.ip = 0;
        frame.slots_idx = stack_top - arg_count - 1;
        return true;
      }
    }
  }

  bool call_value(
    final Object? callee,
    final int arg_count,
  ) {
    if (callee is DloxBoundMethod) {
      stack[stack_top - arg_count - 1] = callee.receiver;
      return call(callee.method, arg_count);
    } else if (callee is DloxClass) {
      stack[stack_top - arg_count - 1] = DloxInstance(klass: callee);
      final initializer = callee.methods.get_val(INIT_STRING);
      if (initializer != null) {
        return call(initializer as DloxClosure, arg_count);
      } else if (arg_count != 0) {
        runtime_error('Expected 0 arguments but got ' + arg_count.toString());
        return false;
      }
      return true;
    } else if (callee is DloxClosure) {
      return call(callee, arg_count);
    } else if (callee is DloxNative) {
      final res = callee.fn(stack, stack_top - arg_count, arg_count);
      stack_top -= arg_count + 1;
      push(res);
      return true;
    } else if (callee is NativeClassCreator) {
      try {
        final res = callee(stack, stack_top - arg_count, arg_count);
        stack_top -= arg_count + 1;
        push(res);
      } on _NativeError catch (e) {
        runtime_error(e.error);
        return false;
      }
      return true;
    } else {
      runtime_error('Can only call functions and classes');
      return false;
    }
  }

  bool invoke_from_class(
    final DloxClass klass,
    final String? name,
    final int arg_count,
  ) {
    final method = klass.methods.get_val(name);
    if (method == null) {
      runtime_error("Undefined property '" + name.toString() + "'");
      return false;
    } else {
      return call(method as DloxClosure, arg_count);
    }
  }

  bool invoke_map(
    final Map<dynamic, dynamic> map,
    final String? name,
    final int arg_count,
  ) {
    if (!_MAP_NATIVE_FUNCTIONS.containsKey(name)) {
      runtime_error('Unknown method for map');
      return false;
    } else {
      final function = _MAP_NATIVE_FUNCTIONS[name!]!;
      try {
        final rtn = function(map, stack, stack_top - arg_count, arg_count);
        stack_top -= arg_count + 1;
        push(rtn);
        return true;
      } on _NativeError catch (e) {
        runtime_error(e.error);
        return false;
      }
    }
  }

  bool invoke_list(
    final List<dynamic> list,
    final String? name,
    final int arg_count,
  ) {
    if (!_LIST_NATIVE_FUNCTIONS.containsKey(name)) {
      runtime_error('Unknown method for list');
      return false;
    } else {
      final function = _LIST_NATIVE_FUNCTIONS[name!]!;
      try {
        final rtn = function(list, stack, stack_top - arg_count, arg_count);
        stack_top -= arg_count + 1;
        push(rtn);
        return true;
      } on _NativeError catch (e) {
        runtime_error(e.error);
        return false;
      }
    }
  }

  bool invoke_string(
    final String str,
    final String? name,
    final int arg_count,
  ) {
    if (!_STRING_NATIVE_FUNCTIONS.containsKey(name)) {
      runtime_error('Unknown method for string');
      return false;
    } else {
      final function = _STRING_NATIVE_FUNCTIONS[name!]!;
      try {
        final rtn = function(str, stack, stack_top - arg_count, arg_count);
        stack_top -= arg_count + 1;
        push(rtn);
        return true;
      } on _NativeError catch (e) {
        runtime_error(e.error);
        return false;
      }
    }
  }

  bool invoke_native_class(
    final ObjNativeClass klass,
    final String? name,
    final int arg_count,
  ) {
    try {
      final rtn = klass.call_(name, stack, stack_top - arg_count, arg_count);
      stack_top -= arg_count + 1;
      push(rtn);
      return true;
    } on _NativeError catch (e) {
      runtime_error(e.error);
      return false;
    }
  }

  bool invoke(
    final String? name,
    final int arg_count,
  ) {
    final receiver = peek(arg_count);
    if (receiver is List) {
      return invoke_list(receiver, name, arg_count);
    } else if (receiver is Map) {
      return invoke_map(receiver, name, arg_count);
    } else if (receiver is String) {
      return invoke_string(receiver, name, arg_count);
    } else if (receiver is ObjNativeClass) {
      return invoke_native_class(receiver, name, arg_count);
    } else if (!(receiver is DloxInstance)) {
      runtime_error('Only instances have methods');
      return false;
    } else {
      final instance = receiver;
      final value = instance.fields.get_val(name);
      if (value != null) {
        stack[stack_top - arg_count - 1] = value;
        return call_value(value, arg_count);
      } else {
        if (instance.klass == null) {
          final klass = globals.get_val(instance.klass_name);
          if (klass is! DloxClass) {
            runtime_error('Class ${instance.klass_name} not found');
            return false;
          }
          instance.klass = klass;
        }
        return invoke_from_class(instance.klass!, name, arg_count);
      }
    }
  }

  bool bind_method(
    final DloxClass klass,
    final String? name,
  ) {
    final method = klass.methods.get_val(name);
    if (method == null) {
      runtime_error("Undefined property '${name}'");
      return false;
    } else {
      final bound = DloxBoundMethod(
        receiver: peek(0),
        method: method as DloxClosure,
      );
      pop();
      push(bound);
      return true;
    }
  }

  DloxUpvalue capture_upvalue(
    final int localIdx,
  ) {
    DloxUpvalue? prev_upvalue;
    DloxUpvalue? upvalue = open_upvalues;
    while (upvalue != null && upvalue.location! > localIdx) {
      prev_upvalue = upvalue;
      upvalue = upvalue.next;
    }
    if (upvalue != null && upvalue.location == localIdx) {
      return upvalue;
    } else {
      final created_upvalue = DloxUpvalue(localIdx);
      created_upvalue.next = upvalue;
      if (prev_upvalue == null) {
        open_upvalues = created_upvalue;
      } else {
        prev_upvalue.next = created_upvalue;
      }
      return created_upvalue;
    }
  }

  void close_upvalues(
    final int? lastIdx,
  ) {
    while (open_upvalues != null && open_upvalues!.location! >= lastIdx!) {
      final upvalue = open_upvalues!;
      upvalue.closed = stack[upvalue.location!];
      upvalue.location = null;
      open_upvalues = upvalue.next;
    }
  }

  void define_method(
    final String? name,
  ) {
    final method = peek(0);
    final klass = (peek(1) as DloxClass?)!;
    klass.methods.set_val(name, method);
    pop();
  }

  bool is_falsey(
    final Object? value,
  ) {
    return value == DloxNil || (value is bool && !value);
  }

  int read_byte(
    final _Dlox_VMCallFrame frame,
  ) {
    return frame.chunk.code[frame.ip++].key;
  }

  int read_short(
    final _Dlox_VMCallFrame frame,
  ) {
    frame.ip += 2;
    return frame.chunk.code[frame.ip - 2].key << 8 | frame.chunk.code[frame.ip - 1].key;
  }

  Object? read_constant(
    final _Dlox_VMCallFrame frame,
  ) {
    return frame.closure.function.chunk.heap.constant_at(read_byte(frame));
  }

  String? read_string(
    final _Dlox_VMCallFrame frame,
  ) {
    return read_constant(frame) as String?;
  }

  bool assert_number(
    final dynamic a,
    final dynamic b,
  ) {
    if (!(a is double) || !(b is double)) {
      runtime_error('Operands must be numbers');
      return false;
    } else {
      return true;
    }
  }

  int? check_index(
    final int length,
    Object? idxObj, {
    final bool fromStart = true,
  }) {
    if (idxObj == DloxNil) {
      if (fromStart) {
        // ignore: parameter_assignments
        idxObj = 0.0;
      } else {
        // ignore: parameter_assignments
        idxObj = length.toDouble();
      }
    }
    if (idxObj is! double) {
      runtime_error('Index must be a number');
      return null;
    } else {
      var idx = idxObj.toInt();
      if (idx < 0) idx = length + idx;
      final max = fromStart ? length - 1 : length;
      if (idx < 0 || idx > max) {
        runtime_error('Index $idx out of bounds [0, $max]');
        return null;
      } else {
        return idx;
      }
    }
  }

  bool get done {
    return frame_count == 0;
  }

  DloxVMInterpreterResult run() {
    DloxVMInterpreterResult? res;
    do {
      res = step_batch();
    } while (res == null);
    return res;
  }

  DloxVMInterpreterResult? step_batch({
    final int batch_count = _DLOXVM_BATCH_COUNT,
  }) {
    // Setup
    if (frame_count == 0) {
      add_error(
        msg: 'No call frame',
        line: line,
        link: null,
      );
      return result;
    } else {
      _Dlox_VMCallFrame? frame = frames[frame_count - 1];
      final step_count_limit = step_count + batch_count;
      // Main loop
      while (step_count++ < step_count_limit) {
        // Setup current line
        final frame_line = frame!.chunk.code[frame.ip].value;
        // Step code helper
        if (step_code) {
          final instruction = frame.chunk.code[frame.ip].key;
          final op = DloxOpCode.values[instruction];
          // Pause execution on demand
          if (frame_line != line && has_op) {
            // Newline detected, return
            // No need to set line to frameLine thanks to hasOp
            has_op = false;
            return get_result(
              line: line,
            );
          }
          // A line is worth stopping on if it has one of those opts
          has_op |= op != DloxOpCode.POP && op != DloxOpCode.LOOP && op != DloxOpCode.JUMP;
        }
        // Update line
        final prevLine = line;
        line = frame_line;
        // Trace execution if needed
        if (trace_execution) {
          trace_debug.stdwrite('          ');
          for (var k = 0; k < stack_top; k++) {
            trace_debug.stdwrite('[ ');
            trace_debug.print_value(stack[k]);
            trace_debug.stdwrite(' ]');
          }
          trace_debug.stdwrite('\n');
          trace_debug.disassemble_instruction(prevLine, frame.closure.function.chunk, frame.ip);
        }
        final instruction = read_byte(frame);
        switch (DloxOpCode.values[instruction]) {
          case DloxOpCode.CONSTANT:
            final constant = read_constant(frame);
            push(constant);
            break;
          case DloxOpCode.NIL:
            push(DloxNil);
            break;
          case DloxOpCode.TRUE:
            push(true);
            break;
          case DloxOpCode.FALSE:
            push(false);
            break;
          case DloxOpCode.POP:
            pop();
            break;
          case DloxOpCode.GET_LOCAL:
            final slot = read_byte(frame);
            push(stack[frame.slots_idx + slot]);
            break;
          case DloxOpCode.SET_LOCAL:
            final slot = read_byte(frame);
            stack[frame.slots_idx + slot] = peek(0);
            break;
          case DloxOpCode.GET_GLOBAL:
            final name = read_string(frame)!;
            final value = globals.get_val(name);
            if (value == null) {
              return runtime_error("Undefined variable '" + name + "'");
            } else {
              push(value);
              break;
            }
          case DloxOpCode.DEFINE_GLOBAL:
            final name = read_string(frame);
            globals.set_val(name, peek(0));
            pop();
            break;
          case DloxOpCode.SET_GLOBAL:
            final name = read_string(frame)!;
            if (globals.set_val(name, peek(0))) {
              globals.delete(name); // [delete]
              return runtime_error("Undefined variable '" + name + "'");
            } else {
              break;
            }
          case DloxOpCode.GET_UPVALUE:
            final slot = read_byte(frame);
            final upvalue = frame.closure.upvalues[slot]!;
            push(
              () {
                if (upvalue.location != null) {
                  return stack[upvalue.location!];
                } else {
                  return upvalue.closed;
                }
              }(),
            );
            break;
          case DloxOpCode.SET_UPVALUE:
            final slot = read_byte(frame);
            final upvalue = frame.closure.upvalues[slot]!;
            if (upvalue.location != null) {
              stack[upvalue.location!] = peek(0);
            } else {
              upvalue.closed = peek(0);
            }
            break;
          case DloxOpCode.GET_PROPERTY:
            Object? value;
            if (peek(0) is DloxInstance) {
              final instance = (peek(0) as DloxInstance?)!;
              final name = read_string(frame);
              value = instance.fields.get_val(name);
              if (value == null && !bind_method(instance.klass!, name)) {
                return result;
              }
            } else if (peek(0) is ObjNativeClass) {
              final instance = (peek(0) as ObjNativeClass?)!;
              final name = read_string(frame);
              try {
                value = instance.get_val(name);
              } on _NativeError catch (e) {
                return runtime_error(e.error);
              }
            } else {
              return runtime_error('Only instances have properties');
            }
            if (value != null) {
              pop(); // Instance.
              push(value);
            }
            break;
          case DloxOpCode.SET_PROPERTY:
            if (peek(1) is DloxInstance) {
              final DloxInstance instance = (peek(1) as DloxInstance?)!;
              instance.fields.set_val(read_string(frame), peek(0));
            } else if (peek(1) is ObjNativeClass) {
              final ObjNativeClass instance = (peek(1) as ObjNativeClass?)!;
              instance.set_val(read_string(frame), peek(0));
            } else {
              return runtime_error('Only instances have fields');
            }
            final value = pop();
            pop();
            push(value);
            break;
          case DloxOpCode.GET_SUPER:
            final name = read_string(frame);
            final DloxClass superclass = (pop() as DloxClass?)!;
            if (!bind_method(superclass, name)) {
              return result;
            }
            break;
          case DloxOpCode.EQUAL:
            final b = pop();
            final a = pop();
            push(_values_equal(a, b));
            break;
          // Optimisation create greater_or_equal
          case DloxOpCode.GREATER:
            final b = pop();
            final a = pop();
            if (a is String && b is String) {
              push(a.compareTo(b));
            } else if (a is double && b is double) {
              push(a > b);
            } else {
              return runtime_error('Operands must be numbers or strings');
            }
            break;
          // Optimisation create less_or_equal
          case DloxOpCode.LESS:
            final b = pop();
            final a = pop();
            if (a is String && b is String) {
              push(b.compareTo(a));
            } else if (a is double && b is double) {
              push(a < b);
            } else {
              return runtime_error('Operands must be numbers or strings');
            }
            break;
          case DloxOpCode.ADD:
            final b = pop();
            final a = pop();
            if ((a is double) && (b is double)) {
              push(a + b);
            } else if ((a is String) && (b is String)) {
              push(a + b);
            } else if ((a is List) && (b is List)) {
              push(a + b);
            } else if ((a is Map) && (b is Map)) {
              final res = <dynamic, dynamic>{};
              res.addAll(a);
              res.addAll(b);
              push(res);
            } else if ((a is String) || (b is String)) {
              push(value_to_string(a, quoteEmpty: false)! + value_to_string(b, quoteEmpty: false)!);
            } else {
              return runtime_error('Operands must numbers, strings, lists or maps');
            }
            break;
          case DloxOpCode.SUBTRACT:
            final b = pop();
            final a = pop();
            if (!assert_number(a, b)) return result;
            push((a as double?)! - (b as double?)!);
            break;
          case DloxOpCode.MULTIPLY:
            final b = pop();
            final a = pop();
            if (!assert_number(a, b)) return result;
            push((a as double?)! * (b as double?)!);
            break;
          case DloxOpCode.DIVIDE:
            final b = pop();
            final a = pop();
            if (!assert_number(a, b)) return result;
            push((a as double?)! / (b as double?)!);
            break;
          case DloxOpCode.POW:
            final b = pop();
            final a = pop();
            if (!assert_number(a, b)) return result;
            push(pow((a as double?)!, (b as double?)!));
            break;
          case DloxOpCode.MOD:
            final b = pop();
            final a = pop();
            if (!assert_number(a, b)) return result;
            push((a as double?)! % (b as double?)!);
            break;
          case DloxOpCode.NOT:
            push(is_falsey(pop()));
            break;
          case DloxOpCode.NEGATE:
            if (!(peek(0) is double)) {
              return runtime_error('Operand must be a number');
            } else {
              push(-(pop() as double?)!);
              break;
            }
          case DloxOpCode.PRINT:
            final val = value_to_string(pop());
            stdout.stdwriteln(val ?? "");
            break;
          case DloxOpCode.JUMP:
            final offset = read_short(frame);
            frame.ip += offset;
            break;
          case DloxOpCode.JUMP_IF_FALSE:
            final offset = read_short(frame);
            if (is_falsey(peek(0))) frame.ip += offset;
            break;
          case DloxOpCode.LOOP:
            final offset = read_short(frame);
            frame.ip -= offset;
            break;
          case DloxOpCode.CALL:
            final arg_count = read_byte(frame);
            if (!call_value(peek(arg_count), arg_count)) {
              return result;
            } else {
              frame = frames[frame_count - 1];
              break;
            }
          case DloxOpCode.INVOKE:
            final method = read_string(frame);
            final arg_count = read_byte(frame);
            if (!invoke(method, arg_count)) {
              return result;
            } else {
              frame = frames[frame_count - 1];
              break;
            }
          case DloxOpCode.SUPER_INVOKE:
            final method = read_string(frame);
            final arg_count = read_byte(frame);
            final superclass = (pop() as DloxClass?)!;
            if (!invoke_from_class(superclass, method, arg_count)) {
              return result;
            } else {
              frame = frames[frame_count - 1];
              break;
            }
          case DloxOpCode.CLOSURE:
            final function = (read_constant(frame) as DloxFunction?)!;
            final closure = DloxClosure(function);
            push(closure);
            for (int i = 0; i < closure.upvalue_count; i++) {
              final isLocal = read_byte(frame);
              final index = read_byte(frame);
              if (isLocal == 1) {
                closure.upvalues[i] = capture_upvalue(frame.slots_idx + index);
              } else {
                closure.upvalues[i] = frame.closure.upvalues[index];
              }
            }
            break;
          case DloxOpCode.CLOSE_UPVALUE:
            close_upvalues(stack_top - 1);
            pop();
            break;
          case DloxOpCode.RETURN:
            final res = pop();
            close_upvalues(frame.slots_idx);
            frame_count--;
            // ignore: invariant_booleans
            if (frame_count == 0) {
              pop();
              return get_result(
                line: line,
                return_value: res,
              );
            } else {
              stack_top = frame.slots_idx;
              push(res);
              frame = frames[frame_count - 1];
              break;
            }
          case DloxOpCode.CLASS:
            push(DloxClass(read_string(frame)));
            break;
          case DloxOpCode.INHERIT:
            final sup = peek(1);
            if (!(sup is DloxClass)) {
              return runtime_error('Superclass must be a class');
            } else {
              final DloxClass superclass = sup;
              final DloxClass subclass = (peek(0) as DloxClass?)!;
              subclass.methods.add_all(superclass.methods);
              pop(); // Subclass.
              break;
            }
          case DloxOpCode.METHOD:
            define_method(read_string(frame));
            break;
          case DloxOpCode.LIST_INIT:
            final valCount = read_byte(frame);
            final arr = <dynamic>[];
            for (var k = 0; k < valCount; k++) {
              arr.add(peek(valCount - k - 1));
            }
            stack_top -= valCount;
            push(arr);
            break;
          case DloxOpCode.LIST_INIT_RANGE:
            if (!(peek(0) is double) || !(peek(1) is double)) {
              return runtime_error('List initializer bounds must be number');
            } else {
              final start = (peek(1) as double?)!;
              final end = (peek(0) as double?)!;
              if (end - start == double.infinity) {
                return runtime_error('Invalid list initializer');
              } else {
                final arr = <dynamic>[];
                for (var k = start; k < end; k++) {
                  arr.add(k);
                }
                stack_top -= 2;
                push(arr);
                break;
              }
            }
          case DloxOpCode.MAP_INIT:
            final valCount = read_byte(frame);
            final map = <dynamic, dynamic>{};
            for (var k = 0; k < valCount; k++) {
              map[peek((valCount - k - 1) * 2 + 1)] = peek((valCount - k - 1) * 2);
            }
            stack_top -= 2 * valCount;
            push(map);
            break;
          case DloxOpCode.CONTAINER_GET:
            final idxObj = pop();
            final container = pop();
            if (container is List) {
              final idx = check_index(container.length, idxObj);
              if (idx == null) return result;
              push(container[idx]);
            } else if (container is Map) {
              push(container[idxObj]);
            } else if (container is String) {
              final idx = check_index(container.length, idxObj);
              if (idx == null) return result;
              push(container[idx]);
            } else {
              return runtime_error(
                'Indexing targets must be Strings, Lists or Maps',
              );
            }
            break;
          case DloxOpCode.CONTAINER_SET:
            final val = pop();
            final idx_obj = pop();
            final container = pop();
            if (container is List) {
              final idx = check_index(container.length, idx_obj);
              if (idx == null) return result;
              container[idx] = val;
            } else if (container is Map) {
              container[idx_obj] = val;
            } else {
              return runtime_error('Indexing targets must be Lists or Maps');
            }
            push(val);
            break;
          case DloxOpCode.CONTAINER_GET_RANGE:
            var bIdx = pop();
            var aIdx = pop();
            final container = pop();
            var length = 0;
            if (container is List) {
              length = container.length;
            } else if (container is String) {
              length = container.length;
            } else {
              return runtime_error('Range indexing targets must be Lists or Strings');
            }
            aIdx = check_index(length, aIdx);
            bIdx = check_index(length, bIdx, fromStart: false);
            if (aIdx == null || bIdx == null) return result;
            if (container is List) {
              push(container.sublist(aIdx as int, bIdx as int?));
            } else if (container is String) {
              push(container.substring(aIdx as int, bIdx as int?));
            }
            break;
          case DloxOpCode.CONTAINER_ITERATE:
            // Init stack indexes
            final valIdx = read_byte(frame);
            final keyIdx = valIdx + 1;
            final idxIdx = valIdx + 2;
            final iterableIdx = valIdx + 3;
            final containerIdx = valIdx + 4;
            // Retreive data
            var idxObj = stack[frame.slots_idx + idxIdx];
            // Initialize
            if (idxObj == DloxNil) {
              final container = stack[frame.slots_idx + containerIdx];
              idxObj = 0.0;
              if (container is String) {
                stack[frame.slots_idx + iterableIdx] = container.split('');
              } else if (container is List) {
                stack[frame.slots_idx + iterableIdx] = container;
              } else if (container is Map) {
                stack[frame.slots_idx + iterableIdx] = container.entries.toList();
              } else {
                return runtime_error('Iterable must be Strings, Lists or Maps');
              }
              // Pop container from stack
              pop();
            }
            // Iterate
            final idx = (idxObj as double?)!;
            final iterable = (stack[frame.slots_idx + iterableIdx] as List?)!;
            if (idx >= iterable.length) {
              // Return early
              push(false);
              break;
            } else {
              // Populate key & value
              final dynamic item = iterable[idx.toInt()];
              if (item is MapEntry) {
                stack[frame.slots_idx + keyIdx] = item.key;
                stack[frame.slots_idx + valIdx] = item.value;
              } else {
                stack[frame.slots_idx + keyIdx] = idx;
                stack[frame.slots_idx + valIdx] = item;
              }
              // Increment index
              stack[frame.slots_idx + idxIdx] = idx + 1;
              push(true);
              break;
            }
        }
      }
      return null;
    }
  }

  DloxVMInterpreterResult runtime_error(
    final String format,
  ) {
    RuntimeError error = add_error(
      msg: format,
      link: null,
      line: line,
    );
    for (int i = frame_count - 2; i >= 0; i--) {
      final frame = frames[i]!;
      final function = frame.closure.function;
      // frame.ip is sitting on the next instruction
      final line = function.chunk.code[frame.ip - 1].value;
      final fun = () {
        if (function.name == null) {
          return '<script>';
        } else {
          return '<' + function.name.toString() + '>';
        }
      }();
      final msg = 'during $fun execution';
      error = add_error(
        msg: msg,
        line: line,
        link: error,
      );
    }
    return result;
  }
}

class DloxVMInterpreterResult {
  final List<LangError> errors;
  final int last_line;
  final int step_count;
  final Object? return_value;

  DloxVMInterpreterResult({
    required final List<LangError> errors,
    required this.last_line,
    required this.step_count,
    required this.return_value,
  }) : errors = List<LangError>.from(errors);

  bool get done {
    return errors.isNotEmpty || return_value != null;
  }
}

class DLoxVMFunctionParams {
  final String? function;
  final List<Object>? args;
  final Map<String?, Object?>? globals;

  const DLoxVMFunctionParams({
    final this.function,
    final this.args,
    final this.globals,
  });
}

const int _DLOXVM_FRAMES_MAX = 64;
const int _DLOXVM_STACK_MAX = _DLOXVM_FRAMES_MAX * DLOX_UINT8_COUNT;
const int _DLOXVM_BATCH_COUNT = 1000000; // Must be fast enough

class _Dlox_VMCallFrame {
  late DloxClosure closure;
  late int ip;
  late DloxChunk<int> chunk; // Additionnal reference
  late int slots_idx; // Index in stack of the frame slot

  _Dlox_VMCallFrame();
}

bool _values_equal(
  final Object? a,
  final Object? b,
) {
  // Equality relied on this function, but not hashmap indexing
  // It might trigger strange cases where two equal lists don't have the same hashcode
  if (a is List<dynamic> && b is List<dynamic>) {
    return _list_equals<dynamic>(a, b);
  } else if (a is Map<dynamic, dynamic> && b is Map<dynamic, dynamic>) {
    return _map_equals<dynamic, dynamic>(a, b);
  } else {
    return a == b;
  }
}

bool _list_equals<T>(
  final List<T>? a,
  final List<T>? b,
) {
  if (a == null) {
    return b == null;
  } else if (b == null || a.length != b.length) {
    return false;
  } else if (identical(a, b)) {
    return true;
  } else {
    for (int index = 0; index < a.length; index += 1) {
      if (a[index] != b[index]) {
        return false;
      }
    }
    return true;
  }
}

bool _map_equals<T, U>(
  final Map<T, U>? a,
  final Map<T, U>? b,
) {
  if (a == null) {
    return b == null;
  } else if (b == null || a.length != b.length) {
    return false;
  } else if (identical(a, b)) {
    return true;
  } else {
    for (final key in a.keys) {
      if (!b.containsKey(key) || b[key] != a[key]) {
        return false;
      }
    }
    return true;
  }
}
// endregion

// region native classes
abstract class ObjNativeClass {
  String? get name;

  Map<String?, Object?> get properties;

  Map<String, Type>? get properties_types;

  List<String> get init_arg_keys;

  Object call_(
    final String? key,
    final List<Object?> stack,
    final int arg_idx,
    final int arg_count,
  );

  void set_val(
    final String? key,
    final Object? value,
  );

  Object get_val(
    final String? key,
  );

  String string_expr({
    final int max_chars,
  });
}

mixin _ObjNativeClassMixin implements ObjNativeClass {
  @override
  Object call_(
    final String? key,
    final List<Object?> stack,
    final int arg_idx,
    final int arg_count,
  ) {
    throw _NativeError('Undefined function $key');
  }

  @override
  void set_val(
    final String? key,
    final Object? value,
  ) {
    if (!properties_types!.containsKey(key)) {
      throw _NativeError('Undefined property $key');
    } else if (value.runtimeType != properties_types![key!]) {
      throw _NativeError(
        'Invalid object type, expected <${_type_to_string(properties_types![key])}>, but received <${_type_to_string(value.runtimeType)}>',
      );
    } else {
      properties[key] = value;
    }
  }

  @override
  Object get_val(
    final String? key,
  ) {
    if (!properties.containsKey(key)) {
      throw _NativeError('Undefined property $key');
    } else {
      return properties[key] ?? DloxNil;
    }
  }
}

Map<String?, Object?> _make_properties({
  required final int arg_count,
  required final List<String> init_arg_keys,
  required final Map<String, Type>? properties_types,
  required final List<Object?>? stack,
  required final int? arg_idx,
}) {
  final properties = <String, Object?>{};
  if (arg_count != init_arg_keys.length) {
    _arg_count_error(init_arg_keys.length, arg_count);
  }
  for (int k = 0; k < init_arg_keys.length; k++) {
    final expected = properties_types![init_arg_keys[k]];
    if (expected != Object && stack![arg_idx! + k].runtimeType != expected) {
      _arg_type_error(0, expected, stack[arg_idx + k].runtimeType);
    }
    properties[init_arg_keys[k]] = stack![arg_idx! + k];
  }
  return properties;
}

class _ListNode with _ObjNativeClassMixin {
  @override
  final Map<String?, Object?> properties;
  @override
  final Map<String, Type>? properties_types;
  @override
  final List<String> init_arg_keys;

  _ListNode(
    final List<Object?> stack,
    final int arg_idx,
    final int arg_count,
  )   : properties = _make_properties(
          arg_count: arg_count,
          init_arg_keys: [
            'val',
          ],
          properties_types: {
            'val': Object,
            'next': _ListNode,
          },
          stack: stack,
          arg_idx: arg_idx,
        ),
        properties_types = {
          'val': Object,
          'next': _ListNode,
        },
        init_arg_keys = [
          'val',
        ];

  @override
  String get name => 'ListNode';

  Object? get val {
    return properties['val'];
  }

  _ListNode? get next {
    return properties['next'] as _ListNode?;
  }

  List<_ListNode?> link_to_list({
    final int max_length = 100,
  }) {
    // ignore: prefer_collection_literals
    final visited = LinkedHashSet<_ListNode?>();
    _ListNode? node = this;
    while (node != null && !visited.contains(node) && visited.length <= max_length) {
      visited.add(node);
      node = node.next;
    }
    // Mark list as infinite
    if (node == this) {
      visited.add(null);
    }
    return visited.toList();
  }

  @override
  String string_expr({
    final int max_chars = 100,
  }) {
    final str = StringBuffer('[');
    final list = link_to_list(
      max_length: max_chars ~/ 2,
    );
    for (int k = 0; k < list.length; k++) {
      final val = list[k]!.val;
      if (k > 0) {
        str.write(' → ');
      }
      str.write(
        () {
          if (val == null) {
            return '⮐';
          } else {
            return value_to_string(
              val,
              max_chars: max_chars - str.length,
            );
          }
        }(),
      );
      if (str.length > max_chars) {
        str.write('...');
        break;
      }
    }
    str.write(']');
    return str.toString();
  }
}

typedef NativeClassCreator = ObjNativeClass Function(
  List<Object?> stack,
  int arg_idx,
  int arg_count,
);

_ListNode _list_node(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  return _ListNode(
    stack,
    arg_idx,
    arg_count,
  );
}

const Map<String, NativeClassCreator> _NATIVE_CLASSES = <String, NativeClassCreator>{
  'ListNode': _list_node,
};
// endregion

// region support
class _NativeError implements Exception {
  final String error;

  const _NativeError(
    final this.error,
  );
}

String _type_to_string(
  final Type? type,
) {
  if (type == double) {
    return 'Number';
  } else {
    return type.toString();
  }
}

void _arg_count_error(
  final int expected,
  final int? received,
) {
  throw _NativeError(
    'Expected ${expected} arguments, but got ${received}',
  );
}

void _arg_type_error(
  final int index,
  final Type? expected,
  final Type? received,
) {
  throw _NativeError(
    'Invalid argument ${index + 1} type, expected <${_type_to_string(expected)}>, but received <${_type_to_string(received)}>',
  );
}

void _assert_types(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
  final List<Type> types,
) {
  if (arg_count != types.length) {
    _arg_count_error(
      types.length,
      arg_count,
    );
  }
  for (int k = 0; k < types.length; k++) {
    if (types[k] != Object && stack[arg_idx + k].runtimeType != types[k]) {
      _arg_type_error(
        0,
        double,
        stack[arg_idx + k] as Type?,
      );
    }
  }
}

double _assert1double(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  _assert_types(
    stack,
    arg_idx,
    arg_count,
    <Type>[double],
  );
  return (stack[arg_idx] as double?)!;
}

void _assert2doubles(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  _assert_types(
    stack,
    arg_idx,
    arg_count,
    <Type>[double, double],
  );
}
// endregion

// region native functions
// region functions
const _NATIVE_FUNCTIONS = <DloxNative>[
  DloxNative('clock', 0, _clock_native),
  DloxNative('min', 2, _min_native),
  DloxNative('max', 2, _max_native),
  DloxNative('floor', 1, _floor_native),
  DloxNative('ceil', 1, _ceil_native),
  DloxNative('abs', 1, _abs_native),
  DloxNative('round', 1, _round_native),
  DloxNative('sqrt', 1, _sqrt_native),
  DloxNative('sign', 1, _sign_native),
  DloxNative('exp', 1, _exp_native),
  DloxNative('log', 1, _log_native),
  DloxNative('sin', 1, _sin_native),
  DloxNative('asin', 1, _asin_native),
  DloxNative('cos', 1, _cos_native),
  DloxNative('acos', 1, _acos_native),
  DloxNative('tan', 1, _tan_native),
  DloxNative('atan', 1, _atan_native),
];

double _clock_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  if (arg_count != 0) {
    _arg_count_error(0, arg_count);
  }
  return DateTime.now().millisecondsSinceEpoch.toDouble();
}

double _min_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  _assert2doubles(stack, arg_idx, arg_count);
  return min((stack[arg_idx] as double?)!, (stack[arg_idx + 1] as double?)!);
}

double _max_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  _assert2doubles(stack, arg_idx, arg_count);
  return max(
    (stack[arg_idx] as double?)!,
    (stack[arg_idx + 1] as double?)!,
  );
}

double _floor_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  final arg_0 = _assert1double(stack, arg_idx, arg_count);
  return arg_0.floorToDouble();
}

double _ceil_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  final arg_0 = _assert1double(stack, arg_idx, arg_count);
  return arg_0.ceilToDouble();
}

double _abs_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  final arg_0 = _assert1double(stack, arg_idx, arg_count);
  return arg_0.abs();
}

double _round_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  final arg_0 = _assert1double(stack, arg_idx, arg_count);
  return arg_0.roundToDouble();
}

double _sqrt_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  final arg_0 = _assert1double(stack, arg_idx, arg_count);
  return sqrt(arg_0);
}

double _sign_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  return _assert1double(stack, arg_idx, arg_count).sign;
}

double _exp_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  return exp(_assert1double(stack, arg_idx, arg_count));
}

double _log_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  return log(_assert1double(stack, arg_idx, arg_count));
}

double _sin_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  return sin(_assert1double(stack, arg_idx, arg_count));
}

double _asin_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  return asin(_assert1double(stack, arg_idx, arg_count));
}

double _cos_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  return cos(_assert1double(stack, arg_idx, arg_count));
}

double _acos_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  return acos(_assert1double(stack, arg_idx, arg_count));
}

double _tan_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  return tan(_assert1double(stack, arg_idx, arg_count));
}

double _atan_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  return atan(_assert1double(stack, arg_idx, arg_count));
}
// endregion

// region native values
const _NATIVE_VALUES = <String, Object>{
  'π': pi,
  '𝘦': e,
  '∞': double.infinity,
};
// endregion

// region native list functions
const _LIST_NATIVE_FUNCTIONS = <String, _ListNativeFunction>{
  'length': _list_length,
  'add': _list_add,
  'insert': _list_insert,
  'remove': _list_remove,
  'pop': _list_pop,
  'clear': _list_clear,
};

double _list_length(
  final List<dynamic> list,
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  if (arg_count != 0) {
    _arg_count_error(0, arg_count);
  }
  return list.length.toDouble();
}

void _list_add(
  final List<dynamic> list,
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  if (arg_count != 1) {
    _arg_count_error(1, arg_count);
  }
  list.add(stack[arg_idx]);
}

void _list_insert(
  final List<dynamic> list,
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  _assert_types(stack, arg_idx, arg_count, [double, Object]);
  final idx = (stack[arg_idx] as double?)!.toInt();
  if (idx < 0 || idx > list.length) {
    throw _NativeError('Index ${idx} out of bounds [0, ${list.length}]');
  } else {
    list.insert(idx, stack[arg_idx + 1]);
  }
}

Object? _list_remove(
  final List<dynamic> list,
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  _assert_types(stack, arg_idx, arg_count, [double]);
  final idx = (stack[arg_idx] as double?)!.toInt();
  if (idx < 0 || idx > list.length) {
    throw _NativeError('Index ${idx} out of bounds [0, ${list.length}]');
  } else {
    return list.removeAt(idx);
  }
}

Object? _list_pop(
  final List<dynamic> list,
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  if (arg_count != 0) {
    _arg_count_error(0, arg_count);
  }
  return list.removeLast();
}

void _list_clear(
  final List<dynamic> list,
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  if (arg_count != 0) {
    _arg_count_error(0, arg_count);
  }
  list.clear();
}

typedef _ListNativeFunction = Object? Function(
  List<dynamic> list,
  List<Object?> stack,
  int arg_idx,
  int arg_count,
);
// endregion

// region map
const _MAP_NATIVE_FUNCTIONS = <String, _MapNativeFunction>{
  'length': _map_length,
  'keys': _map_keys,
  'values': _map_values,
  'has': _map_has,
};

double _map_length(
  final Map<dynamic, dynamic> map,
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  if (arg_count != 0) {
    _arg_count_error(0, arg_count);
  }
  return map.length.toDouble();
}

List<dynamic> _map_keys(
  final Map<dynamic, dynamic> map,
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  if (arg_count != 0) {
    _arg_count_error(0, arg_count);
  }
  return map.keys.toList();
}

List<dynamic> _map_values(
  final Map<dynamic, dynamic> map,
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  if (arg_count != 0) {
    _arg_count_error(0, arg_count);
  }
  return map.values.toList();
}

bool _map_has(
  final Map<dynamic, dynamic> map,
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  if (arg_count != 1) {
    _arg_count_error(1, arg_count);
  }
  return map.containsKey(stack[arg_idx]);
}

typedef _MapNativeFunction = Object Function(
  Map<dynamic, dynamic> list,
  List<Object?> stack,
  int arg_idx,
  int arg_count,
);
// endregion

// region string functions
const _STRING_NATIVE_FUNCTIONS = <String, _StringNativeFunction>{
  'length': _str_length,
};

double _str_length(
  final String str,
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  if (arg_count != 0) {
    _arg_count_error(0, arg_count);
  }
  return str.length.toDouble();
}

typedef _StringNativeFunction = Object Function(
  String list,
  List<Object?> stack,
  int arg_idx,
  int arg_count,
);
// endregion
// endregion
