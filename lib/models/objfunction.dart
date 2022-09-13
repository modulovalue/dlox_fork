import 'op_code.dart';

class ObjFunction {
  final String? name;
  final Chunk chunk;
  int arity;
  int upvalue_count;

  ObjFunction({
    required final this.name,
  })  : upvalue_count = 0,
        arity = 0,
        chunk = Chunk();
}

class Chunk {
  final List<int> code;
  final List<Object?> constants;
  final Map<Object?, int> _constant_map;
  final List<int> lines;

  Chunk()
      : lines = [],
        constants = [],
        code = [],
        _constant_map = {};

  int get count => code.length;

  int add_constant(
    final Object? value,
  ) {
    final idx = _constant_map[value];
    if (idx != null) {
      return idx;
    } else {
      constants.add(value);
      _constant_map[value] = constants.length - 1;
      return constants.length - 1;
    }
  }

  // TODO hide once not referred to outside of this class.
  void write(
    final int byte,
    final int line,
  ) {
    code.add(byte);
    lines.add(line);
  }

  // region emitter
  void emit_constant(
    final int constant,
    final int line,
  ) {
    write(OpCode.CONSTANT.index, line);
    write(constant, line);
  }

  void emit_loop(
    final int offset,
    final int line,
  ) {
    write(OpCode.LOOP.index, line);
    write((offset >> 8) & 0xff, line);
    write(offset & 0xff, line);
  }

  int emit_jump_if_false(
    final int line,
  ) {
    write(OpCode.JUMP_IF_FALSE.index, line);
    write(0xff, line);
    write(0xff, line);
    return count - 2;
  }

  int emit_jump(
    final int line,
  ) {
    write(OpCode.JUMP.index, line);
    write(0xff, line);
    write(0xff, line);
    return count - 2;
  }

  void emit_return_local(
    final int line,
  ) {
    write(OpCode.GET_LOCAL.index, line);
    write(0, line);
    write(OpCode.RETURN.index, line);
  }

  void emit_return_nil(
    final int line,
  ) {
    write(OpCode.NIL.index, line);
    write(OpCode.RETURN.index, line);
  }
  // endregion
}

class ObjNative {
  String name;
  int arity;
  NativeFunction fn;

  ObjNative(
    this.name,
    this.arity,
    this.fn,
  );
}

class ObjUpvalue {
  int? location;
  Object? closed;
  ObjUpvalue? next;

  ObjUpvalue(
    final this.location,
  ) : closed = Nil;
}

class ObjClosure {
  ObjFunction function;
  late List<ObjUpvalue?> upvalues;
  late int upvalue_count;

  ObjClosure(
    final this.function,
  ) {
    upvalues = List<ObjUpvalue?>.generate(
      function.upvalue_count,
      (final index) => null,
    );
    upvalue_count = function.upvalue_count;
  }
}

class ObjClass {
  String? name;
  Table methods;

  ObjClass(
    final this.name,
  ) : methods = Table();
}

class ObjInstance {
  String? klass_name; // For dynamic class lookup
  ObjClass? klass;
  Table fields;

  ObjInstance({
    final this.klass,
    final this.klass_name,
  }) : fields = Table();
}

class ObjBoundMethod {
  Object? receiver;
  ObjClosure method;

  ObjBoundMethod({
    required final this.receiver,
    required final this.method,
  });
}

typedef NativeFunction = Object? Function(
  List<Object?> stack,
  int arg_idx,
  int arg_count,
);

class Nil {}

class Table {
  final Map<String?, Object?> data;

  Table() : data = {};

  Object? get_val(
    final String? key,
  ) {
    return data[key];
  }

  bool set_val(
    final String? key,
    final Object? val,
  ) {
    final had_key = data.containsKey(key);
    data[key] = val;
    return !had_key;
  }

  void delete(
    final String? key,
  ) {
    data.remove(key);
  }

  void add_all(
    final Table other,
  ) {
    data.addAll(other.data);
  }

  Object? find_string(
    final String str,
  ) {
    // Optimisation: key on hashKeys
    return data[str];
  }
}
