import 'package:sprintf/sprintf.dart' show sprintf;

import '../arrows/fundamental/objfunction_to_output.dart';
import 'objfunction.dart';
import 'tokens.dart';

abstract class LangError {
  int get line;

  String get msg;

  R match<R>({
    required final R Function(CompilerError) compiler,
    required final R Function(RuntimeError) runtime,
  });
}

class CompilerError implements LangError {
  final Token token;
  @override
  final String msg;

  const CompilerError({
    required final this.token,
    required final this.msg,
  });

  @override
  int get line => token.loc.line;

  @override
  R match<R>({
    required final R Function(CompilerError) compiler,
    required final R Function(RuntimeError) runtime,
  }) =>
      compiler(this);
}

class RuntimeError implements LangError {
  final RuntimeError? link;
  @override
  final int line;
  @override
  final String msg;

  const RuntimeError({
    required final this.line,
    required final this.msg,
    required final this.link,
  });

  @override
  R match<R>({
    required final R Function(CompilerError) compiler,
    required final R Function(RuntimeError) runtime,
  }) =>
      runtime(this);
}

// region debug
class Debug {
  final bool silent;
  final StringBuffer buf;
  final List<CompilerError> errors;
  bool panic_mode;

  Debug({
    required final this.silent,
  })  : buf = StringBuffer(),
        errors = [],
        panic_mode = false;

  // region infrastructure
  void restore() {
    panic_mode = false;
  }

  void write_error(
    final LangError err,
  ) {
    String describe_error(
      final Token? token,
      final String type,
      final String? msg,
      final int line,
    ) {
      final buf = StringBuffer();
      if (token != null) {
        buf.write('[${token.loc.line + 1}] ${type} error');
        if (token.type == TokenType.EOF) {
          buf.write(' at end');
        } else if (token.type == TokenType.ERROR) {
          // Nothing.
        } else {
          buf.write(' at \'${token.lexeme}\'');
        }
      } else {
        buf.write('[${line}] ${type} error');
      }
      buf.write(': ${msg}');
      return buf.toString();
    }

    err.match(
      compiler: (final a) => stdwriteln(
        describe_error(
          a.token,
          "Compile",
          a.msg,
          a.line,
        ),
      ),
      runtime: (final a) => stdwriteln(describe_error(
        null,
        "Runtime",
        a.msg,
        a.line,
      ),
      ),
    );
  }

  void error_at(
    final Token token,
    final String message,
  ) {
    if (panic_mode) {
      // Ignore
    } else {
      panic_mode = true;
      final error = CompilerError(
        token: token,
        msg: message,
      );
      write_error(error);
      errors.add(
        error,
      );
    }
  }

  String clear() {
    final str = buf.toString();
    buf.clear();
    return str;
  }

  void stdwrite(
    final String? string,
  ) {
    buf.write(string);
    if (!silent) {
      // Print buffer
      final str = clear();
      final split = str.split('\n');
      while (split.length > 1) {
        print(split[0]);
        split.removeAt(0);
      }
      buf.write(split.join(''));
    }
  }

  void stdwriteln(
    final String string,
  ) {
    return stdwrite(string + '\n');
  }

  void print_value(
    final Object? value,
  ) {
    stdwrite(value_to_string(value));
  }

  // endregion

  // region disassembler
  void disassemble_chunk(
    final DloxChunk<int> chunk,
    final String name,
  ) {
    stdwrite("==" + name + "==\n");
    int? prev_line = -1;
    for (int offset = 0; offset < chunk.code.length;) {
      offset = disassemble_instruction(prev_line, chunk, offset);
      if (offset > 0) {
        prev_line = chunk.code[offset - 1].value;
      } else {
        prev_line = null;
      }
    }
  }

  int constant_instruction(
    final String name,
    final DloxChunk<int> chunk,
    final int offset,
  ) {
    final constant = chunk.code[offset + 1].key;
    stdwrite(sprintf('%-16s %4d \'', [name, constant]));
    print_value(chunk.heap.constant_at(constant));
    stdwrite('\'\n');
    return offset + 2;
  }

  int initializer_list_instruction(
    final String name,
    final DloxChunk<int> chunk,
    final int offset,
  ) {
    final nArgs = chunk.code[offset + 1];
    stdwriteln(sprintf('%-16s %4d', [name, nArgs]));
    return offset + 2;
  }

  int invoke_instruction(
    final String name,
    final DloxChunk<int> chunk,
    final int offset,
  ) {
    final constant = chunk.code[offset + 1].key;
    final arg_count = chunk.code[offset + 2];
    stdwrite(sprintf('%-16s (%d args) %4d \'', [name, arg_count, constant]));
    print_value(chunk.heap.constant_at(constant));
    stdwrite('\'\n');
    return offset + 3;
  }

  int simple_instruction(
    final String name,
    final int offset,
  ) {
    stdwrite(name + '\n');
    return offset + 1;
  }

  int byte_instruction(
    final String name,
    final DloxChunk<int> chunk,
    final int offset,
  ) {
    final slot = chunk.code[offset + 1];
    stdwrite(sprintf('%-16s %4d\n', [name, slot]));
    return offset + 2; // [debug]
  }

  int jump_instruction(
    final String name,
    final int sign,
    final DloxChunk<int> chunk,
    final int offset,
  ) {
    final jump = (chunk.code[offset + 1].key << 8) | chunk.code[offset + 2].key;
    stdwrite(sprintf('%-16s %4d -> %d\n', [name, offset, offset + 3 + sign * jump]));
    return offset + 3;
  }

  int disassemble_instruction(
    final int? prevLine,
    final DloxChunk<int> chunk,
    int offset,
  ) {
    stdwrite(sprintf('%04d ', [offset]));
    final i = chunk.code[offset].value;
    // stdwrite("${chunk.trace[offset].token.info} "); // temp
    // final prevLoc = offset > 0 ? chunk.trace[offset - 1].token.loc : null;
    if (offset > 0 && i == prevLine) {
      stdwrite('   | ');
    } else {
      stdwrite(sprintf('%4d ', [i]));
    }
    final instruction = chunk.code[offset].key;
    switch (DloxOpCode.values[instruction]) {
      case DloxOpCode.CONSTANT:
        return constant_instruction('OP_CONSTANT', chunk, offset);
      case DloxOpCode.NIL:
        return simple_instruction('OP_NIL', offset);
      case DloxOpCode.TRUE:
        return simple_instruction('OP_TRUE', offset);
      case DloxOpCode.FALSE:
        return simple_instruction('OP_FALSE', offset);
      case DloxOpCode.POP:
        return simple_instruction('OP_POP', offset);
      case DloxOpCode.GET_LOCAL:
        return byte_instruction('OP_GET_LOCAL', chunk, offset);
      case DloxOpCode.SET_LOCAL:
        return byte_instruction('OP_SET_LOCAL', chunk, offset);
      case DloxOpCode.GET_GLOBAL:
        return constant_instruction('OP_GET_GLOBAL', chunk, offset);
      case DloxOpCode.DEFINE_GLOBAL:
        return constant_instruction('OP_DEFINE_GLOBAL', chunk, offset);
      case DloxOpCode.SET_GLOBAL:
        return constant_instruction('OP_SET_GLOBAL', chunk, offset);
      case DloxOpCode.GET_UPVALUE:
        return byte_instruction('OP_GET_UPVALUE', chunk, offset);
      case DloxOpCode.SET_UPVALUE:
        return byte_instruction('OP_SET_UPVALUE', chunk, offset);
      case DloxOpCode.GET_PROPERTY:
        return constant_instruction('OP_GET_PROPERTY', chunk, offset);
      case DloxOpCode.SET_PROPERTY:
        return constant_instruction('OP_SET_PROPERTY', chunk, offset);
      case DloxOpCode.GET_SUPER:
        return constant_instruction('OP_GET_SUPER', chunk, offset);
      case DloxOpCode.EQUAL:
        return simple_instruction('OP_EQUAL', offset);
      case DloxOpCode.GREATER:
        return simple_instruction('OP_GREATER', offset);
      case DloxOpCode.LESS:
        return simple_instruction('OP_LESS', offset);
      case DloxOpCode.ADD:
        return simple_instruction('OP_ADD', offset);
      case DloxOpCode.SUBTRACT:
        return simple_instruction('OP_SUBTRACT', offset);
      case DloxOpCode.MULTIPLY:
        return simple_instruction('OP_MULTIPLY', offset);
      case DloxOpCode.DIVIDE:
        return simple_instruction('OP_DIVIDE', offset);
      case DloxOpCode.POW:
        return simple_instruction('OP_POW', offset);
      case DloxOpCode.NOT:
        return simple_instruction('OP_NOT', offset);
      case DloxOpCode.NEGATE:
        return simple_instruction('OP_NEGATE', offset);
      case DloxOpCode.PRINT:
        return simple_instruction('OP_PRINT', offset);
      case DloxOpCode.JUMP:
        return jump_instruction('OP_JUMP', 1, chunk, offset);
      case DloxOpCode.JUMP_IF_FALSE:
        return jump_instruction('OP_JUMP_IF_FALSE', 1, chunk, offset);
      case DloxOpCode.LOOP:
        return jump_instruction('OP_LOOP', -1, chunk, offset);
      case DloxOpCode.CALL:
        return byte_instruction('OP_CALL', chunk, offset);
      case DloxOpCode.INVOKE:
        return invoke_instruction('OP_INVOKE', chunk, offset);
      case DloxOpCode.SUPER_INVOKE:
        return invoke_instruction('OP_SUPER_INVOKE', chunk, offset);
      case DloxOpCode.CLOSURE:
        // ignore: parameter_assignments
        offset++;
        // ignore: parameter_assignments
        final constant = chunk.code[offset++].key;
        stdwrite(sprintf('%-16s %4d ', ['OP_CLOSURE', constant]));
        print_value(chunk.heap.constant_at(constant));
        stdwrite('\n');
        final function = (chunk.heap.constant_at(constant) as DloxFunction?)!;
        for (int j = 0; j < function.upvalue_count; j++) {
          // ignore: parameter_assignments
          final is_local = chunk.code[offset++].key == 1;
          // ignore: parameter_assignments
          final index = chunk.code[offset++];
          stdwrite(
            sprintf(
              '%04d      |                     %s %d\n',
              [
                offset - 2,
                () {
                  if (is_local) {
                    return 'local';
                  } else {
                    return 'upvalue';
                  }
                }(),
                index,
              ],
            ),
          );
        }
        return offset;
      case DloxOpCode.CLOSE_UPVALUE:
        return simple_instruction('OP_CLOSE_UPVALUE', offset);
      case DloxOpCode.RETURN:
        return simple_instruction('OP_RETURN', offset);
      case DloxOpCode.CLASS:
        return constant_instruction('OP_CLASS', chunk, offset);
      case DloxOpCode.INHERIT:
        return simple_instruction('OP_INHERIT', offset);
      case DloxOpCode.METHOD:
        return constant_instruction('OP_METHOD', chunk, offset);
      case DloxOpCode.LIST_INIT:
        return initializer_list_instruction('OP_LIST_INIT', chunk, offset);
      case DloxOpCode.LIST_INIT_RANGE:
        return simple_instruction('LIST_INIT_RANGE', offset);
      case DloxOpCode.MAP_INIT:
        return initializer_list_instruction('OP_MAP_INIT', chunk, offset);
      case DloxOpCode.CONTAINER_GET:
        return simple_instruction('OP_CONTAINER_GET', offset);
      case DloxOpCode.CONTAINER_SET:
        return simple_instruction('OP_CONTAINER_SET', offset);
      case DloxOpCode.CONTAINER_GET_RANGE:
        return simple_instruction('CONTAINER_GET_RANGE', offset);
      case DloxOpCode.CONTAINER_ITERATE:
        return simple_instruction('CONTAINER_ITERATE', offset);
      case DloxOpCode.MOD:
        throw Exception('Unknown opcode $instruction');
    }
  }
// endregion
}

String? value_to_string(
  final Object? value, {
  final int max_chars = 100,
  final bool quoteEmpty = true,
}) {
  if (value is bool) {
    if (value) {
      return 'true';
    } else {
      return 'false';
    }
  } else if (value == DloxNil) {
    return 'nil';
  } else if (value is double) {
    if (value.isInfinite) {
      return '∞';
    } else if (value.isNaN) {
      return 'NaN';
    }
    return sprintf('%g', [value]);
  } else if (value is String) {
    if (value.trim().isEmpty && quoteEmpty) {
      return '\'$value\'';
    } else {
      return value;
    }
  } else if (value is List) {
    return list_to_string(value, maxChars: max_chars);
  } else if (value is Map) {
    return map_to_string(value, max_chars: max_chars);
  } else {
    return object_to_string(value, maxChars: max_chars);
  }
}

String list_to_string(
  final List<dynamic> list, {
  final int maxChars = 100,
}) {
  final buf = StringBuffer('[');
  for (int k = 0; k < list.length; k++) {
    if (k > 0) buf.write(',');
    buf.write(value_to_string(list[k], max_chars: maxChars - buf.length));
    if (buf.length > maxChars) {
      buf.write('...');
      break;
    }
  }
  buf.write(']');
  return buf.toString();
}

String map_to_string(
  final Map<dynamic, dynamic> map, {
  final int max_chars = 100,
}) {
  final buf = StringBuffer('{');
  final entries = map.entries.toList();
  for (int k = 0; k < entries.length; k++) {
    if (k > 0) buf.write(',');
    buf.write(value_to_string(entries[k].key, max_chars: max_chars - buf.length));
    buf.write(':');
    buf.write(value_to_string(
      entries[k].value,
      max_chars: max_chars - buf.length,
    ));
    if (buf.length > max_chars) {
      buf.write('...');
      break;
    }
  }
  buf.write('}');
  return buf.toString();
}

String? object_to_string(
  final Object? value, {
  final int maxChars = 100,
}) {
  if (value is DloxClass) {
    return value.name;
  } else if (value is DloxBoundMethod) {
    return function_to_string(value.method.function);
  } else if (value is DloxClosure) {
    return function_to_string(value.function);
  } else if (value is DloxFunction) {
    return function_to_string(value);
  } else if (value is DloxInstance) {
    return '${value.klass!.name} instance';
    // return instanceToString(value, maxChars: maxChars);
  } else if (value is DloxNative) {
    return '<native fn>';
  } else if (value is DloxUpvalue) {
    return 'upvalue';
  } else if (value is ObjNativeClass) {
    return value.string_expr(max_chars: maxChars);
  } else if (value is NativeClassCreator) {
    return '<native class>';
  }
  return value.toString();
}

String function_to_string(
  final DloxFunction function,
) {
  if (function.name == null) {
    return '<script>';
  } else {
    return '<fn ' + function.name.toString() + '>';
  }
}
// endregion
