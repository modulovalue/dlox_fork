class DloxFunction {
  final String? name;
  final DloxChunk chunk;
  int arity;
  int upvalue_count;

  DloxFunction({
    required final this.name,
  })  : upvalue_count = 0,
        arity = 0,
        chunk = DloxChunk();
}

class DloxChunk {
  final List<int> code;
  final List<Object?> constants;
  final Map<Object?, int> _constant_map;
  final List<int> lines;

  DloxChunk()
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
    write(DloxOpCode.CONSTANT.index, line);
    write(constant, line);
  }

  void emit_loop(
    final int offset,
    final int line,
  ) {
    write(DloxOpCode.LOOP.index, line);
    write((offset >> 8) & 0xff, line);
    write(offset & 0xff, line);
  }

  int emit_jump_if_false(
    final int line,
  ) {
    write(DloxOpCode.JUMP_IF_FALSE.index, line);
    write(0xff, line);
    write(0xff, line);
    return count - 2;
  }

  int emit_jump(
    final int line,
  ) {
    write(DloxOpCode.JUMP.index, line);
    write(0xff, line);
    write(0xff, line);
    return count - 2;
  }

  void emit_return_local(
    final int line,
  ) {
    write(DloxOpCode.GET_LOCAL.index, line);
    write(0, line);
    write(DloxOpCode.RETURN.index, line);
  }

  void emit_return_nil(
    final int line,
  ) {
    write(DloxOpCode.NIL.index, line);
    write(DloxOpCode.RETURN.index, line);
  }
  // endregion
}

class DloxNative {
  String name;
  int arity;
  DloxNativeFunction fn;

  DloxNative(
    this.name,
    this.arity,
    this.fn,
  );
}

class DloxUpvalue {
  int? location;
  Object? closed;
  DloxUpvalue? next;

  DloxUpvalue(
    final this.location,
  ) : closed = DloxNil;
}

class DloxClosure {
  DloxFunction function;
  late List<DloxUpvalue?> upvalues;
  late int upvalue_count;

  DloxClosure(
    final this.function,
  ) {
    upvalues = List<DloxUpvalue?>.generate(
      function.upvalue_count,
      (final index) => null,
    );
    upvalue_count = function.upvalue_count;
  }
}

class DloxClass {
  String? name;
  DloxTable methods;

  DloxClass(
    final this.name,
  ) : methods = DloxTable();
}

class DloxInstance {
  String? klass_name; // For dynamic class lookup
  DloxClass? klass;
  DloxTable fields;

  DloxInstance({
    final this.klass,
    final this.klass_name,
  }) : fields = DloxTable();
}

class DloxBoundMethod {
  Object? receiver;
  DloxClosure method;

  DloxBoundMethod({
    required final this.receiver,
    required final this.method,
  });
}

class DloxNil {}

class DloxTable {
  final Map<String?, Object?> data;

  DloxTable() : data = {};

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
    final DloxTable other,
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

enum DloxOpCode {
  CONSTANT,
  NIL,
  TRUE,
  FALSE,
  POP,
  GET_LOCAL,
  SET_LOCAL,
  GET_GLOBAL,
  DEFINE_GLOBAL,
  SET_GLOBAL,
  GET_UPVALUE,
  SET_UPVALUE,
  GET_PROPERTY,
  SET_PROPERTY,
  GET_SUPER,
  EQUAL,
  GREATER,
  LESS,
  ADD,
  SUBTRACT,
  MULTIPLY,
  DIVIDE,
  POW,
  MOD,
  NOT,
  NEGATE,
  PRINT,
  JUMP,
  JUMP_IF_FALSE,
  LOOP,
  CALL,
  INVOKE,
  SUPER_INVOKE,
  CLOSURE,
  CLOSE_UPVALUE,
  RETURN,
  CLASS,
  INHERIT,
  METHOD,
  LIST_INIT,
  LIST_INIT_RANGE,
  MAP_INIT,
  CONTAINER_GET,
  CONTAINER_SET,
  CONTAINER_GET_RANGE,
  CONTAINER_ITERATE,
}

typedef DloxNativeFunction = Object? Function(
  List<Object?> stack,
  int arg_idx,
  int arg_count,
);

const DLOX_UINT8_COUNT = 256;
const DLOX_UINT8_MAX = DLOX_UINT8_COUNT - 1;
const DLOX_UINT16_MAX = 65535;
