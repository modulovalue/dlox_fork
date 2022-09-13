// TODO remove
import 'package:sprintf/sprintf.dart' show sprintf;

import '../arrows/fundamental/objfunction_to_output.dart';
import 'objfunction.dart';
import 'tokens.dart';

// TODO have two classes of errors: runtime and compiler and make them independent from each other.
// TODO  retuse tostring by calling a function not via inheritance.
mixin LangError {
  String get type;

  Token? get token;

  int? get line;

  String? get msg;

  void dump(
    final Debug debug,
  ) {
    debug.stdwriteln(toString());
  }

  @override
  String toString() {
    final buf = StringBuffer();
    if (token != null) {
      buf.write('[${token!.loc.line + 1}] $type error');
      if (token!.type == TokenType.EOF) {
        buf.write(' at end');
      } else if (token!.type == TokenType.ERROR) {
        // Nothing.
      } else {
        buf.write(' at \'${token!.lexeme}\'');
      }
    } else if (line != null) {
      buf.write('[$line] $type error');
    } else {
      buf.write('$type error');
    }
    buf.write(': $msg');
    return buf.toString();
  }
}

class CompilerError with LangError {
  @override
  final Token token;
  @override
  final String? msg;

  const CompilerError({
    required final this.token,
    required final this.msg,
  });

  @override
  String get type => "Compile";

  @override
  int? get line => token.loc.line;
}

class RuntimeError with LangError {
  final RuntimeError? link;
  @override
  final int line;
  @override
  final String? msg;

  const RuntimeError({
    required final this.line,
    required final this.msg,
    final this.link,
  });

  @override
  String get type => "Runtime";

  @override
  Null get token => null;
}

class Debug {
  final bool silent;
  final StringBuffer buf;
  final List<CompilerError> errors;

  // TODO make silent named once editor is migrated to nnbd
  Debug(
    final this.silent,
  )   : buf = StringBuffer(),
        errors = [];

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

  void stdwriteln([
    final String? string,
  ]) {
    return stdwrite((string ?? '') + '\n');
  }

  void print_value(
    final Object? value,
  ) {
    stdwrite(value_to_string(value));
  }

  void disassemble_chunk(
    final DloxChunk chunk,
    final String name,
  ) {
    stdwrite("==" + name + "==\n");
    int? prev_line = -1;
    for (int offset = 0; offset < chunk.code.length;) {
      offset = disassemble_instruction(prev_line, chunk, offset);
      prev_line = offset > 0 ? chunk.lines[offset - 1] : null;
    }
  }

  int constant_instruction(
    final String name,
    final DloxChunk chunk,
    final int offset,
  ) {
    final constant = chunk.code[offset + 1];
    stdwrite(sprintf('%-16s %4d \'', [name, constant]));
    print_value(chunk.constants[constant]);
    stdwrite('\'\n');
    return offset + 2;
  }

  int initializer_list_instruction(
    final String name,
    final DloxChunk chunk,
    final int offset,
  ) {
    final nArgs = chunk.code[offset + 1];
    stdwriteln(sprintf('%-16s %4d', [name, nArgs]));
    return offset + 2;
  }

  int invoke_instruction(
    final String name,
    final DloxChunk chunk,
    final int offset,
  ) {
    final constant = chunk.code[offset + 1];
    final arg_count = chunk.code[offset + 2];
    stdwrite(sprintf('%-16s (%d args) %4d \'', [name, arg_count, constant]));
    print_value(chunk.constants[constant]);
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
    final DloxChunk chunk,
    final int offset,
  ) {
    final slot = chunk.code[offset + 1];
    stdwrite(sprintf('%-16s %4d\n', [name, slot]));
    return offset + 2; // [debug]
  }

  int jump_instruction(
    final String name,
    final int sign,
    final DloxChunk chunk,
    final int offset,
  ) {
    int jump = chunk.code[offset + 1] << 8;
    jump |= chunk.code[offset + 2];
    stdwrite(sprintf('%-16s %4d -> %d\n', [name, offset, offset + 3 + sign * jump]));
    return offset + 3;
  }

  int disassemble_instruction(
    final int? prevLine,
    final DloxChunk chunk,
    int offset,
  ) {
    stdwrite(sprintf('%04d ', [offset]));
    final i = chunk.lines[offset];
    // stdwrite("${chunk.trace[offset].token.info} "); // temp
    // final prevLoc = offset > 0 ? chunk.trace[offset - 1].token.loc : null;
    if (offset > 0 && i == prevLine) {
      stdwrite('   | ');
    } else {
      stdwrite(sprintf('%4d ', [i]));
    }
    final instruction = chunk.code[offset];
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
        final constant = chunk.code[offset++];
        stdwrite(sprintf('%-16s %4d ', ['OP_CLOSURE', constant]));
        print_value(chunk.constants[constant]);
        stdwrite('\n');
        final function = (chunk.constants[constant] as DloxFunction?)!;
        for (var j = 0; j < function.upvalue_count; j++) {
          // ignore: parameter_assignments
          final isLocal = chunk.code[offset++] == 1;
          // ignore: parameter_assignments
          final index = chunk.code[offset++];
          stdwrite(
            sprintf(
              '%04d      |                     %s %d\n',
              [
                offset - 2,
                () {
                  if (isLocal) {
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
}

String? value_to_string(
  final Object? value, {
  final int max_chars = 100,
  final bool quoteEmpty = true,
}) {
  if (value is bool) {
    return value ? 'true' : 'false';
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
    return map_to_string(value, maxChars: max_chars);
  } else {
    return object_to_string(value, maxChars: max_chars);
  }
}

String list_to_string(
  final List<dynamic> list, {
  final int maxChars = 100,
}) {
  final buf = StringBuffer('[');
  for (var k = 0; k < list.length; k++) {
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
  final int maxChars = 100,
}) {
  final buf = StringBuffer('{');
  final entries = map.entries.toList();
  for (var k = 0; k < entries.length; k++) {
    if (k > 0) buf.write(',');
    buf.write(value_to_string(entries[k].key, max_chars: maxChars - buf.length));
    buf.write(':');
    buf.write(value_to_string(
      entries[k].value,
      max_chars: maxChars - buf.length,
    ));
    if (buf.length > maxChars) {
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
