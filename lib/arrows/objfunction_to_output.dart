import 'dart:collection';
import 'dart:math';

import 'package:sprintf/sprintf.dart';

import '../models/errors.dart';
import '../models/objfunction.dart';
import '../models/op_code.dart';

class VM {
  static const String INIT_STRING = 'init';
  final List<CallFrame?> frames = List<CallFrame?>.filled(FRAMES_MAX, null);
  final List<Object?> stack = List<Object?>.filled(STACK_MAX, null);

  // VM state
  final List<RuntimeError> errors = [];
  final Table globals = Table();
  final Table strings = Table();
  ObjFunction? compiled_function;
  int frame_count = 0;
  int stack_top = 0;
  ObjUpvalue? open_upvalues;

  // Debug variables
  int step_count = 0;
  int line = -1;

  // int skipLine = -1;
  bool has_op = false;

  // Debug API
  bool trace_execution = false;
  bool step_code = false;
  final Debug err_debug;
  final Debug trace_debug;
  final Debug stdout;

  VM({
    required final bool silent,
  }) :
    err_debug = Debug(
      silent,
    ),
    trace_debug = Debug(
      silent,
    ),
    stdout = Debug(
      silent,
    ) {
    _reset();
    for (var k = 0; k < frames.length; k++) {
      frames[k] = CallFrame();
    }
  }

  RuntimeError addError(
    final String? msg, {
    final RuntimeError? link,
    final int? line,
  }) {
    // int line = -1;
    // if (frameCount > 0) {
    //   final frame = frames[frameCount - 1];
    //   final lines = frame.chunk.lines;
    //   if (frame.ip < lines.length) line = lines[frame.ip];
    // }
    final err = RuntimeError(line ?? this.line, msg, link: link);
    errors.add(err);
    err.dump(err_debug);
    return err;
  }

  InterpreterResult getResult(
    final int line, {
    final Object? returnValue,
  }) {
    return InterpreterResult(
      errors,
      line,
      step_count,
      returnValue,
    );
  }

  InterpreterResult get result {
    return getResult(line);
  }

  InterpreterResult withError(
    final String msg,
  ) {
    addError(msg);
    return result;
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
    final ObjFunction function,
    final List<CompilerError> errors,
    final FunctionParams params,
  ) {
    _reset();
    // Set compiler result
    if (errors.isNotEmpty) {
      throw Exception('Compiler result had errors');
    } else {
      this.compiled_function = function;
      // Set function
      ObjFunction? fun = function;
      if (params.function != null) {
        final found_fun = () {
          for (final x in function.chunk.constants) {
            if (x is ObjFunction && x.name == params.function) {
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
      final closure = ObjClosure(fun);
      push(closure);
      if (params.args != null) {
        params.args!.forEach(push);
      }
      callValue(closure, params.args?.length ?? 0);
    }
  }

  void define_natives() {
    for (final function in NATIVE_FUNCTIONS) {
      globals.set_val(function.name, function);
    }
    NATIVE_VALUES.forEach((final key, final value) {
      globals.set_val(key, value);
    });
    NATIVE_CLASSES.forEach((final key, final value) {
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
    final ObjClosure closure,
    final int arg_count,
  ) {
    if (arg_count != closure.function.arity) {
      runtime_error('Expected %d arguments but got %d', [closure.function.arity, arg_count]);
      return false;
    } else {
      if (frame_count == FRAMES_MAX) {
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

  bool callValue(
    final Object? callee,
    final int arg_count,
  ) {
    if (callee is ObjBoundMethod) {
      stack[stack_top - arg_count - 1] = callee.receiver;
      return call(callee.method, arg_count);
    } else if (callee is ObjClass) {
      stack[stack_top - arg_count - 1] = ObjInstance(klass: callee);
      final initializer = callee.methods.get_val(INIT_STRING);
      if (initializer != null) {
        return call(initializer as ObjClosure, arg_count);
      } else if (arg_count != 0) {
        runtime_error('Expected 0 arguments but got %d', [arg_count]);
        return false;
      }
      return true;
    } else if (callee is ObjClosure) {
      return call(callee, arg_count);
    } else if (callee is ObjNative) {
      final res = callee.fn(stack, stack_top - arg_count, arg_count);
      stack_top -= arg_count + 1;
      push(res);
      return true;
    } else if (callee is NativeClassCreator) {
      try {
        final res = callee(stack, stack_top - arg_count, arg_count);
        stack_top -= arg_count + 1;
        push(res);
      } on NativeError catch (e) {
        runtime_error(e.format, e.args);
        return false;
      }
      return true;
    } else {
      runtime_error('Can only call functions and classes');
      return false;
    }
  }

  bool invoke_from_class(
    final ObjClass klass,
    final String? name,
    final int arg_count,
  ) {
    final method = klass.methods.get_val(name);
    if (method == null) {
      runtime_error("Undefined property '%s'", [name]);
      return false;
    } else {
      return call(method as ObjClosure, arg_count);
    }
  }

  bool invokeMap(
    final Map<dynamic, dynamic> map,
    final String? name,
    final int arg_count,
  ) {
    if (!MAP_NATIVE_FUNCTIONS.containsKey(name)) {
      runtime_error('Unknown method for map');
      return false;
    } else {
      final function = MAP_NATIVE_FUNCTIONS[name!]!;
      try {
        final rtn = function(map, stack, stack_top - arg_count, arg_count);
        stack_top -= arg_count + 1;
        push(rtn);
        return true;
      } on NativeError catch (e) {
        runtime_error(e.format, e.args);
        return false;
      }
    }
  }

  bool invoke_list(
    final List<dynamic> list,
    final String? name,
    final int arg_count,
  ) {
    if (!LIST_NATIVE_FUNCTIONS.containsKey(name)) {
      runtime_error('Unknown method for list');
      return false;
    } else {
      final function = LIST_NATIVE_FUNCTIONS[name!]!;
      try {
        final rtn = function(list, stack, stack_top - arg_count, arg_count);
        stack_top -= arg_count + 1;
        push(rtn);
        return true;
      } on NativeError catch (e) {
        runtime_error(e.format, e.args);
        return false;
      }
    }
  }

  bool invoke_string(
    final String str,
    final String? name,
    final int arg_count,
  ) {
    if (!STRING_NATIVE_FUNCTIONS.containsKey(name)) {
      runtime_error('Unknown method for string');
      return false;
    } else {
      final function = STRING_NATIVE_FUNCTIONS[name!]!;
      try {
        final rtn = function(str, stack, stack_top - arg_count, arg_count);
        stack_top -= arg_count + 1;
        push(rtn);
        return true;
      } on NativeError catch (e) {
        runtime_error(e.format, e.args);
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
      final rtn = klass.call(name, stack, stack_top - arg_count, arg_count);
      stack_top -= arg_count + 1;
      push(rtn);
      return true;
    } on NativeError catch (e) {
      runtime_error(e.format, e.args);
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
      return invokeMap(receiver, name, arg_count);
    } else if (receiver is String) {
      return invoke_string(receiver, name, arg_count);
    } else if (receiver is ObjNativeClass) {
      return invoke_native_class(receiver, name, arg_count);
    } else if (!(receiver is ObjInstance)) {
      runtime_error('Only instances have methods');
      return false;
    } else {
      final instance = receiver;
      final value = instance.fields.get_val(name);
      if (value != null) {
        stack[stack_top - arg_count - 1] = value;
        return callValue(value, arg_count);
      } else {
        if (instance.klass == null) {
          final klass = globals.get_val(instance.klass_name);
          if (klass is! ObjClass) {
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
    final ObjClass klass,
    final String? name,
  ) {
    final method = klass.methods.get_val(name);
    if (method == null) {
      runtime_error("Undefined property '%s'", [name]);
      return false;
    } else {
      final bound = ObjBoundMethod(
        receiver: peek(0),
        method: method as ObjClosure,
      );
      pop();
      push(bound);
      return true;
    }
  }

  ObjUpvalue capture_upvalue(
    final int localIdx,
  ) {
    ObjUpvalue? prev_upvalue;
    ObjUpvalue? upvalue = open_upvalues;
    while (upvalue != null && upvalue.location! > localIdx) {
      prev_upvalue = upvalue;
      upvalue = upvalue.next;
    }
    if (upvalue != null && upvalue.location == localIdx) {
      return upvalue;
    } else {
      final created_upvalue = ObjUpvalue(localIdx);
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
    final klass = (peek(1) as ObjClass?)!;
    klass.methods.set_val(name, method);
    pop();
  }

  bool is_falsey(
    final Object? value,
  ) {
    return value == Nil || (value is bool && !value);
  }

  // Repace macros (slower -> try inlining)
  int read_byte(
    final CallFrame frame,
  ) {
    return frame.chunk.code[frame.ip++];
  }

  int read_short(
    final CallFrame frame,
  ) {
    // TODO: Optimisation - remove
    frame.ip += 2;
    return frame.chunk.code[frame.ip - 2] << 8 | frame.chunk.code[frame.ip - 1];
  }

  Object? read_constant(
    final CallFrame frame,
  ) {
    return frame.closure.function.chunk.constants[read_byte(frame)];
  }

  String? read_string(
    final CallFrame frame,
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
    // ignore: parameter_assignments
    if (idxObj == Nil) idxObj = fromStart ? 0.0 : length.toDouble();
    if (!(idxObj is double)) {
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

  InterpreterResult run() {
    InterpreterResult? res;
    do {
      res = step_batch();
    } while (res == null);
    return res;
  }

  InterpreterResult? step_batch({
    final int batch_count = BATCH_COUNT,
  }) {
    // Setup
    if (frame_count == 0) {
      return withError('No call frame');
    } else {
      CallFrame? frame = frames[frame_count - 1];
      final stepCountLimit = step_count + batch_count;
      // Main loop
      while (step_count++ < stepCountLimit) {
        // Setup current line
        final frameLine = frame!.chunk.lines[frame.ip];
        // Step code helper
        if (step_code) {
          final instruction = frame.chunk.code[frame.ip];
          final op = OpCode.values[instruction];
          // Pause execution on demand
          if (frameLine != line && has_op) {
            // Newline detected, return
            // No need to set line to frameLine thanks to hasOp
            has_op = false;
            return getResult(line);
          }
          // A line is worth stopping on if it has one of those opts
          has_op |= op != OpCode.POP && op != OpCode.LOOP && op != OpCode.JUMP;
        }
        // Update line
        final prevLine = line;
        line = frameLine;
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
        switch (OpCode.values[instruction]) {
          case OpCode.CONSTANT:
            final constant = read_constant(frame);
            push(constant);
            break;
          case OpCode.NIL:
            push(Nil);
            break;
          case OpCode.TRUE:
            push(true);
            break;
          case OpCode.FALSE:
            push(false);
            break;
          case OpCode.POP:
            pop();
            break;
          case OpCode.GET_LOCAL:
            final slot = read_byte(frame);
            push(stack[frame.slots_idx + slot]);
            break;
          case OpCode.SET_LOCAL:
            final slot = read_byte(frame);
            stack[frame.slots_idx + slot] = peek(0);
            break;
          case OpCode.GET_GLOBAL:
            final name = read_string(frame);
            final value = globals.get_val(name);
            if (value == null) {
              return runtime_error("Undefined variable '%s'", [name]);
            }
            push(value);
            break;
          case OpCode.DEFINE_GLOBAL:
            final name = read_string(frame);
            globals.set_val(name, peek(0));
            pop();
            break;
          case OpCode.SET_GLOBAL:
            final name = read_string(frame);
            if (globals.set_val(name, peek(0))) {
              globals.delete(name); // [delete]
              return runtime_error("Undefined variable '%s'", [name]);
            } else {
              break;
            }
          case OpCode.GET_UPVALUE:
            final slot = read_byte(frame);
            final upvalue = frame.closure.upvalues[slot]!;
            push(upvalue.location != null ? stack[upvalue.location!] : upvalue.closed);
            break;
          case OpCode.SET_UPVALUE:
            final slot = read_byte(frame);
            final upvalue = frame.closure.upvalues[slot]!;
            if (upvalue.location != null) {
              stack[upvalue.location!] = peek(0);
            } else {
              upvalue.closed = peek(0);
            }
            break;
          case OpCode.GET_PROPERTY:
            Object? value;
            if (peek(0) is ObjInstance) {
              final ObjInstance instance = (peek(0) as ObjInstance?)!;
              final name = read_string(frame);
              value = instance.fields.get_val(name);
              if (value == null && !bind_method(instance.klass!, name)) {
                return result;
              }
            } else if (peek(0) is ObjNativeClass) {
              final ObjNativeClass instance = (peek(0) as ObjNativeClass?)!;
              final name = read_string(frame);
              try {
                value = instance.get_val(name);
              } on NativeError catch (e) {
                return runtime_error(e.format, e.args);
              }
            } else {
              return runtime_error('Only instances have properties');
            }
            if (value != null) {
              pop(); // Instance.
              push(value);
            }
            break;
          case OpCode.SET_PROPERTY:
            if (peek(1) is ObjInstance) {
              final ObjInstance instance = (peek(1) as ObjInstance?)!;
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
          case OpCode.GET_SUPER:
            final name = read_string(frame);
            final ObjClass superclass = (pop() as ObjClass?)!;
            if (!bind_method(superclass, name)) {
              return result;
            }
            break;
          case OpCode.EQUAL:
            final b = pop();
            final a = pop();
            push(values_equal(a, b));
            break;
          // Optimisation create greater_or_equal
          case OpCode.GREATER:
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
          case OpCode.LESS:
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
          case OpCode.ADD:
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
          case OpCode.SUBTRACT:
            final b = pop();
            final a = pop();
            if (!assert_number(a, b)) return result;
            push((a as double?)! - (b as double?)!);
            break;
          case OpCode.MULTIPLY:
            final b = pop();
            final a = pop();
            if (!assert_number(a, b)) return result;
            push((a as double?)! * (b as double?)!);
            break;
          case OpCode.DIVIDE:
            final b = pop();
            final a = pop();
            if (!assert_number(a, b)) return result;
            push((a as double?)! / (b as double?)!);
            break;
          case OpCode.POW:
            final b = pop();
            final a = pop();
            if (!assert_number(a, b)) return result;
            push(pow((a as double?)!, (b as double?)!));
            break;
          case OpCode.MOD:
            final b = pop();
            final a = pop();
            if (!assert_number(a, b)) return result;
            push((a as double?)! % (b as double?)!);
            break;
          case OpCode.NOT:
            push(is_falsey(pop()));
            break;
          case OpCode.NEGATE:
            if (!(peek(0) is double)) {
              return runtime_error('Operand must be a number');
            } else {
              push(-(pop() as double?)!);
              break;
            }
          case OpCode.PRINT:
            final val = value_to_string(pop());
            stdout.stdwriteln(val);
            break;
          case OpCode.JUMP:
            final offset = read_short(frame);
            frame.ip += offset;
            break;
          case OpCode.JUMP_IF_FALSE:
            final offset = read_short(frame);
            if (is_falsey(peek(0))) frame.ip += offset;
            break;
          case OpCode.LOOP:
            final offset = read_short(frame);
            frame.ip -= offset;
            break;
          case OpCode.CALL:
            final arg_count = read_byte(frame);
            if (!callValue(peek(arg_count), arg_count)) {
              return result;
            } else {
              frame = frames[frame_count - 1];
              break;
            }
          case OpCode.INVOKE:
            final method = read_string(frame);
            final arg_count = read_byte(frame);
            if (!invoke(method, arg_count)) {
              return result;
            } else {
              frame = frames[frame_count - 1];
              break;
            }
          case OpCode.SUPER_INVOKE:
            final method = read_string(frame);
            final arg_count = read_byte(frame);
            final superclass = (pop() as ObjClass?)!;
            if (!invoke_from_class(superclass, method, arg_count)) {
              return result;
            } else {
              frame = frames[frame_count - 1];
              break;
            }
          case OpCode.CLOSURE:
            final function = (read_constant(frame) as ObjFunction?)!;
            final closure = ObjClosure(function);
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
          case OpCode.CLOSE_UPVALUE:
            close_upvalues(stack_top - 1);
            pop();
            break;
          case OpCode.RETURN:
            final res = pop();
            close_upvalues(frame.slots_idx);
            frame_count--;
            // ignore: invariant_booleans
            if (frame_count == 0) {
              pop();
              return getResult(line, returnValue: res);
            } else {
              stack_top = frame.slots_idx;
              push(res);
              frame = frames[frame_count - 1];
              break;
            }
          case OpCode.CLASS:
            push(ObjClass(read_string(frame)));
            break;
          case OpCode.INHERIT:
            final sup = peek(1);
            if (!(sup is ObjClass)) {
              return runtime_error('Superclass must be a class');
            } else {
              final ObjClass superclass = sup;
              final ObjClass subclass = (peek(0) as ObjClass?)!;
              subclass.methods.add_all(superclass.methods);
              pop(); // Subclass.
              break;
            }
          case OpCode.METHOD:
            define_method(read_string(frame));
            break;
          case OpCode.LIST_INIT:
            final valCount = read_byte(frame);
            final arr = <dynamic>[];
            for (var k = 0; k < valCount; k++) {
              arr.add(peek(valCount - k - 1));
            }
            stack_top -= valCount;
            push(arr);
            break;
          case OpCode.LIST_INIT_RANGE:
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
          case OpCode.MAP_INIT:
            final valCount = read_byte(frame);
            final map = <dynamic, dynamic>{};
            for (var k = 0; k < valCount; k++) {
              map[peek((valCount - k - 1) * 2 + 1)] = peek((valCount - k - 1) * 2);
            }
            stack_top -= 2 * valCount;
            push(map);
            break;
          case OpCode.CONTAINER_GET:
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
          case OpCode.CONTAINER_SET:
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
          case OpCode.CONTAINER_GET_RANGE:
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
          case OpCode.CONTAINER_ITERATE:
            // Init stack indexes
            final valIdx = read_byte(frame);
            final keyIdx = valIdx + 1;
            final idxIdx = valIdx + 2;
            final iterableIdx = valIdx + 3;
            final containerIdx = valIdx + 4;
            // Retreive data
            var idxObj = stack[frame.slots_idx + idxIdx];
            // Initialize
            if (idxObj == Nil) {
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

  InterpreterResult runtime_error(
    final String format, [
    final List<Object?>? args,
  ]) {
    RuntimeError error = addError(sprintf(format, args ?? []));
    for (int i = frame_count - 2; i >= 0; i--) {
      final frame = frames[i]!;
      final function = frame.closure.function;
      // frame.ip is sitting on the next instruction
      final line = function.chunk.lines[frame.ip - 1];
      final fun = function.name == null ? '<script>' : '<${function.name}>';
      final msg = 'during $fun execution';
      error = addError(msg, line: line, link: error);
    }
    return result;
  }
}

const int FRAMES_MAX = 64;
const int STACK_MAX = FRAMES_MAX * UINT8_COUNT;
const int BATCH_COUNT = 1000000; // Must be fast enough

class CallFrame {
  late ObjClosure closure;
  late int ip;
  late Chunk chunk; // Additionnal reference
  late int slots_idx; // Index in stack of the frame slot

  CallFrame();
}

class InterpreterResult {
  final List<LangError> errors;
  final int last_line;
  final int step_count;
  final Object? return_value;

  InterpreterResult(
    final List<LangError> errors,
    this.last_line,
    this.step_count,
    this.return_value,
  ) : errors = List<LangError>.from(errors);

  bool get done {
    return errors.isNotEmpty || return_value != null;
  }
}

class FunctionParams {
  final String? function;
  final List<Object>? args;
  final Map<String?, Object?>? globals;

  const FunctionParams({
    final this.function,
    final this.args,
    final this.globals,
  });
}

bool values_equal(
  final Object? a,
  final Object? b,
) {
  // TODO: confirm behavior (especially for deep equality).
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

int hash_string(
  final String key,
) {
  int hash = 2166136261;
  for (int i = 0; i < key.length; i++) {
    hash ^= key.codeUnitAt(i);
    hash *= 16777619;
  }
  return hash;
}

// region native classes
abstract class ObjNativeClass {
  final String? name;
  final Map<String?, Object?> properties;
  final Map<String, Type>? properties_types;
  final List<String> init_arg_keys;

  ObjNativeClass({
    required this.init_arg_keys,
    this.name,
    this.properties_types,
    final List<Object?>? stack,
    final int? arg_idx,
    final int? arg_count,
  }) : properties = {} {
    if (arg_count != init_arg_keys.length) {
      arg_count_error(init_arg_keys.length, arg_count);
    }
    for (int k = 0; k < init_arg_keys.length; k++) {
      final expected = properties_types![init_arg_keys[k]];
      if (expected != Object && stack![arg_idx! + k].runtimeType != expected) {
        arg_type_error(0, expected, stack[arg_idx + k].runtimeType);
      }
      properties[init_arg_keys[k]] = stack![arg_idx! + k];
    }
  }

  Object call(
    final String? key,
    final List<Object?> stack,
    final int arg_idx,
    final int arg_count,
  ) {
    throw NativeError('Undefined function $key');
  }

  void set_val(
    final String? key,
    final Object? value,
  ) {
    if (!properties_types!.containsKey(key)) {
      throw NativeError('Undefined property $key');
    } else if (value.runtimeType != properties_types![key!]) {
      throw NativeError(
        'Invalid object type, expected <%s>, but received <%s>',
        [type_to_string(properties_types![key]), type_to_string(value.runtimeType)],
      );
    } else {
      properties[key] = value;
    }
  }

  Object get_val(
    final String? key,
  ) {
    if (!properties.containsKey(key)) {
      throw NativeError('Undefined property $key');
    } else {
      return properties[key] ?? Nil;
    }
  }

  String string_expr({
    final int max_chars,
  });
}

class ListNode extends ObjNativeClass {
  ListNode(
    final List<Object?> stack,
    final int arg_idx,
    final int arg_count,
  ) : super(
          name: 'ListNode',
          properties_types: {
            'val': Object,
            'next': ListNode,
          },
          init_arg_keys: [
            'val',
          ],
          stack: stack,
          arg_idx: arg_idx,
          arg_count: arg_count,
        );

  Object? get val {
    return properties['val'];
  }

  ListNode? get next {
    return properties['next'] as ListNode?;
  }

  List<ListNode?> link_to_list({
    final int max_length = 100,
  }) {
    // ignore: prefer_collection_literals
    final visited = LinkedHashSet<ListNode?>();
    ListNode? node = this;
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

ListNode list_node(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  return ListNode(
    stack,
    arg_idx,
    arg_count,
  );
}

const Map<String, ObjNativeClass Function(List<Object>, int, int)> NATIVE_CLASSES =
    <String, NativeClassCreator>{
  'ListNode': list_node,
};
// endregion

// region native
class NativeError implements Exception {
  String format;
  List<Object?>? args;

  NativeError(
    final this.format, [
    final this.args,
  ]);
}

String type_to_string(
  final Type? type,
) {
  if (type == double) {
    return 'Number';
  } else {
    return type.toString();
  }
}

void arg_count_error(
  final int expected,
  final int? received,
) {
  throw NativeError(
    'Expected %d arguments, but got %d',
    [expected, received],
  );
}

void arg_type_error(
  final int index,
  final Type? expected,
  final Type? received,
) {
  throw NativeError(
    'Invalid argument %d type, expected <%s>, but received <%s>',
    [
      index + 1,
      type_to_string(expected),
      type_to_string(received),
    ],
  );
}

void assert_types(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
  final List<Type> types,
) {
  if (arg_count != types.length) {
    arg_count_error(
      types.length,
      arg_count,
    );
  }
  for (int k = 0; k < types.length; k++) {
    if (types[k] != Object && stack[arg_idx + k].runtimeType != types[k]) {
      arg_type_error(
        0,
        double,
        stack[arg_idx + k] as Type?,
      );
    }
  }
}

double assert1double(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  assert_types(
    stack,
    arg_idx,
    arg_count,
    <Type>[double],
  );
  return (stack[arg_idx] as double?)!;
}

void assert2doubles(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  assert_types(
    stack,
    arg_idx,
    arg_count,
    <Type>[double, double],
  );
}

// Native functions

double clock_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  if (arg_count != 0) {
    arg_count_error(0, arg_count);
  }
  return DateTime.now().millisecondsSinceEpoch.toDouble();
}

double min_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  assert2doubles(stack, arg_idx, arg_count);
  return min((stack[arg_idx] as double?)!, (stack[arg_idx + 1] as double?)!);
}

double max_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  assert2doubles(stack, arg_idx, arg_count);
  return max(
    (stack[arg_idx] as double?)!,
    (stack[arg_idx + 1] as double?)!,
  );
}

double floor_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  final arg_0 = assert1double(stack, arg_idx, arg_count);
  return arg_0.floorToDouble();
}

double ceil_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  final arg_0 = assert1double(stack, arg_idx, arg_count);
  return arg_0.ceilToDouble();
}

double abs_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  final arg_0 = assert1double(stack, arg_idx, arg_count);
  return arg_0.abs();
}

double round_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  final arg_0 = assert1double(stack, arg_idx, arg_count);
  return arg_0.roundToDouble();
}

double sqrt_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  final arg_0 = assert1double(stack, arg_idx, arg_count);
  return sqrt(arg_0);
}

double sign_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  return assert1double(stack, arg_idx, arg_count).sign;
}

double exp_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  return exp(assert1double(stack, arg_idx, arg_count));
}

double log_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  return log(assert1double(stack, arg_idx, arg_count));
}

double sin_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  return sin(assert1double(stack, arg_idx, arg_count));
}

double asin_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  return asin(assert1double(stack, arg_idx, arg_count));
}

double cos_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  return cos(assert1double(stack, arg_idx, arg_count));
}

double acos_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  return acos(assert1double(stack, arg_idx, arg_count));
}

double tan_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  return tan(assert1double(stack, arg_idx, arg_count));
}

double atan_native(
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  return atan(assert1double(stack, arg_idx, arg_count));
}

// ignore: non_constant_identifier_names
final NATIVE_FUNCTIONS = <ObjNative>[
  ObjNative('clock', 0, clock_native),
  ObjNative('min', 2, min_native),
  ObjNative('max', 2, max_native),
  ObjNative('floor', 1, floor_native),
  ObjNative('ceil', 1, ceil_native),
  ObjNative('abs', 1, abs_native),
  ObjNative('round', 1, round_native),
  ObjNative('sqrt', 1, sqrt_native),
  ObjNative('sign', 1, sign_native),
  ObjNative('exp', 1, exp_native),
  ObjNative('log', 1, log_native),
  ObjNative('sin', 1, sin_native),
  ObjNative('asin', 1, asin_native),
  ObjNative('cos', 1, cos_native),
  ObjNative('acos', 1, acos_native),
  ObjNative('tan', 1, tan_native),
  ObjNative('atan', 1, atan_native),
];

const NATIVE_VALUES = <String, Object>{
  'π': pi,
  '𝘦': e,
  '∞': double.infinity,
};

// List native functions
double list_length(
  final List<dynamic> list,
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  if (arg_count != 0) {
    arg_count_error(0, arg_count);
  }
  return list.length.toDouble();
}

void list_add(
  final List<dynamic> list,
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  if (arg_count != 1) {
    arg_count_error(1, arg_count);
  }
  list.add(stack[arg_idx]);
}

void list_insert(
  final List<dynamic> list,
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  assert_types(stack, arg_idx, arg_count, [double, Object]);
  final idx = (stack[arg_idx] as double?)!.toInt();
  if (idx < 0 || idx > list.length) {
    throw NativeError('Index %d out of bounds [0, %d]', [idx, list.length]);
  } else {
    list.insert(idx, stack[arg_idx + 1]);
  }
}

Object? list_remove(
  final List<dynamic> list,
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  assert_types(stack, arg_idx, arg_count, [double]);
  final idx = (stack[arg_idx] as double?)!.toInt();
  if (idx < 0 || idx > list.length) {
    throw NativeError('Index %d out of bounds [0, %d]', [idx, list.length]);
  } else {
    return list.removeAt(idx);
  }
}

Object? list_pop(
  final List<dynamic> list,
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  if (arg_count != 0) {
    arg_count_error(0, arg_count);
  }
  return list.removeLast();
}

void list_clear(final List<dynamic> list, final List<Object?> stack, final int arg_idx, final int arg_count) {
  if (arg_count != 0) {
    arg_count_error(0, arg_count);
  }
  list.clear();
}

typedef ListNativeFunction = Object? Function(
  List<dynamic> list,
  List<Object?> stack,
  int arg_idx,
  int arg_count,
);

const LIST_NATIVE_FUNCTIONS = <String, ListNativeFunction>{
  'length': list_length,
  'add': list_add,
  'insert': list_insert,
  'remove': list_remove,
  'pop': list_pop,
  'clear': list_clear,
};

// Map native functions
double map_length(
  final Map<dynamic, dynamic> map,
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  if (arg_count != 0) {
    arg_count_error(0, arg_count);
  }
  return map.length.toDouble();
}

List<dynamic> map_keys(
  final Map<dynamic, dynamic> map,
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  if (arg_count != 0) {
    arg_count_error(0, arg_count);
  }
  return map.keys.toList();
}

List<dynamic> map_values(
  final Map<dynamic, dynamic> map,
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  if (arg_count != 0) arg_count_error(0, arg_count);
  return map.values.toList();
}

bool map_has(
  final Map<dynamic, dynamic> map,
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  if (arg_count != 1) {
    arg_count_error(1, arg_count);
  }
  return map.containsKey(stack[arg_idx]);
}

typedef MapNativeFunction = Object Function(
  Map<dynamic, dynamic> list,
  List<Object?> stack,
  int arg_idx,
  int arg_count,
);

const MAP_NATIVE_FUNCTIONS = <String, MapNativeFunction>{
  'length': map_length,
  'keys': map_keys,
  'values': map_values,
  'has': map_has,
};

// String native functions
double str_length(
  final String str,
  final List<Object?> stack,
  final int arg_idx,
  final int arg_count,
) {
  if (arg_count != 0) {
    arg_count_error(0, arg_count);
  }
  return str.length.toDouble();
}

typedef StringNativeFunction = Object Function(
  String list,
  List<Object?> stack,
  int arg_idx,
  int arg_count,
);

const STRING_NATIVE_FUNCTIONS = <String, StringNativeFunction>{
  'length': str_length,
};
// endregion
