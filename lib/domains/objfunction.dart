class DloxFunction {
  final String? name;
  final DloxChunk<int> chunk;
  final int arity;

  const DloxFunction({
    required final this.name,
    required final this.arity,
    required final this.chunk,
  });
}

class DloxChunk<INDEX> {
  final List<MapEntry<int, INDEX>> code;
  final DloxHeap heap;
  int upvalue_count;

  DloxChunk() : code = [], heap = DloxHeap(), upvalue_count = 0;

  void _write(
    final int byte,
    final INDEX line,
  ) {
    code.add(MapEntry(byte, line));
  }

  // region instructions
  void emit_upvalue(
    final int is_local,
    final int index,
    final INDEX line,
  ) {
    _write(is_local, line);
    _write(index, line);
  }

  void emit_close_upvalue(
    final INDEX line,
  ) {
    _write(DloxOpCode.CLOSE_UPVALUE.index, line);
  }

  void emit_container_set(
    final INDEX line,
  ) {
    _write(DloxOpCode.CONTAINER_SET.index, line);
  }

  void emit_container_get(
    final INDEX line,
  ) {
    _write(DloxOpCode.CONTAINER_GET.index, line);
  }

  void emit_container_get_range(
    final INDEX line,
  ) {
    _write(DloxOpCode.CONTAINER_GET_RANGE.index, line);
  }

  void emit_container_iterate(
    final int stack_idx,
    final INDEX line,
  ) {
    _write(DloxOpCode.CONTAINER_ITERATE.index, line);
    _write(stack_idx, line);
  }

  void emit_get_super(
    final int name,
    final INDEX line,
  ) {
    _write(DloxOpCode.GET_SUPER.index, line);
    _write(name, line);
  }

  void emit_super_invoke(
    final int name,
    final int args,
    final INDEX line,
  ) {
    _write(DloxOpCode.SUPER_INVOKE.index, line);
    _write(name, line);
    _write(args, line);
  }

  void emit_divide(
    final INDEX line,
  ) {
    _write(DloxOpCode.DIVIDE.index, line);
  }

  void emit_multiply(
    final INDEX line,
  ) {
    _write(DloxOpCode.MULTIPLY.index, line);
  }

  void emit_greater(
    final INDEX line,
  ) {
    _write(DloxOpCode.GREATER.index, line);
  }

  void emit_add(
    final INDEX line,
  ) {
    _write(DloxOpCode.ADD.index, line);
  }

  void emit_subtract(
    final INDEX line,
  ) {
    _write(DloxOpCode.SUBTRACT.index, line);
  }

  void emit_list_init_range(
    final INDEX line,
  ) {
    _write(DloxOpCode.LIST_INIT_RANGE.index, line);
  }

  void emit_map_init(
    final int val_count,
    final INDEX line,
  ) {
    _write(DloxOpCode.MAP_INIT.index, line);
    _write(val_count, line);
  }

  void emit_list_init(
    final int val_count,
    final INDEX line,
  ) {
    _write(DloxOpCode.LIST_INIT.index, line);
    _write(val_count, line);
  }

  void emit_set_property(
    final int value,
    final INDEX line,
  ) {
    _write(DloxOpCode.SET_PROPERTY.index, line);
    _write(value, line);
  }

  void emit_call(
    final int args,
    final INDEX line,
  ) {
    _write(DloxOpCode.CALL.index, line);
    _write(args, line);
  }

  void emit_negate(
    final INDEX line,
  ) {
    _write(DloxOpCode.NEGATE.index, line);
  }

  void emit_not(
    final INDEX line,
  ) {
    _write(DloxOpCode.NOT.index, line);
  }

  void emit_false(
    final INDEX line,
  ) {
    _write(DloxOpCode.FALSE.index, line);
  }

  void emit_true(
    final INDEX line,
  ) {
    _write(DloxOpCode.TRUE.index, line);
  }

  void emit_inherit(
    final INDEX line,
  ) {
    _write(DloxOpCode.INHERIT.index, line);
  }

  void emit_print(
    final INDEX line,
  ) {
    _write(DloxOpCode.PRINT.index, line);
  }

  void emit_return(
    final INDEX line,
  ) {
    _write(DloxOpCode.RETURN.index, line);
  }

  void emit_get_local(
    final int arg,
    final INDEX line,
  ) {
    _write(DloxOpCode.GET_LOCAL.index, line);
    _write(arg, line);
  }

  void emit_set_local(
    final int arg,
    final INDEX line,
  ) {
    _write(DloxOpCode.SET_LOCAL.index, line);
    _write(arg, line);
  }

  void emit_get_upvalue(
    final int arg,
    final INDEX line,
  ) {
    _write(DloxOpCode.GET_UPVALUE.index, line);
    _write(arg, line);
  }

  void emit_set_upvalue(
    final int arg,
    final INDEX line,
  ) {
    _write(DloxOpCode.SET_UPVALUE.index, line);
    _write(arg, line);
  }

  void emit_get_global(
    final int arg,
    final INDEX line,
  ) {
    _write(DloxOpCode.GET_GLOBAL.index, line);
    _write(arg, line);
  }

  void emit_set_global(
    final int arg,
    final INDEX line,
  ) {
    _write(DloxOpCode.SET_GLOBAL.index, line);
    _write(arg, line);
  }

  void emit_not_less(
    final INDEX line,
  ) {
    _write(DloxOpCode.LESS.index, line);
    _write(DloxOpCode.NOT.index, line);
  }

  void emit_not_greater(
    final INDEX line,
  ) {
    _write(DloxOpCode.GREATER.index, line);
    _write(DloxOpCode.NOT.index, line);
  }

  void emit_less(
    final INDEX line,
  ) {
    _write(DloxOpCode.LESS.index, line);
  }

  void emit_pow(
    final INDEX line,
  ) {
    _write(DloxOpCode.POW.index, line);
  }

  void emit_mod(
    final INDEX line,
  ) {
    _write(DloxOpCode.MOD.index, line);
  }

  void emit_equal(
    final INDEX line,
  ) {
    _write(DloxOpCode.EQUAL.index, line);
  }

  void emit_notequal(
    final INDEX line,
  ) {
    _write(DloxOpCode.EQUAL.index, line);
    _write(DloxOpCode.NOT.index, line);
  }

  void emit_get_property(
    final int constant,
    final INDEX line,
  ) {
    _write(DloxOpCode.GET_PROPERTY.index, line);
    _write(constant, line);
  }

  void emit_invoke(
    final int constant,
    final int args,
    final INDEX line,
  ) {
    _write(DloxOpCode.INVOKE.index, line);
    _write(constant, line);
    _write(args, line);
  }

  void emit_closure(
    final int constant,
    final INDEX line,
  ) {
    _write(DloxOpCode.CLOSURE.index, line);
    _write(constant, line);
  }

  void emit_method(
    final int constant,
    final INDEX line,
  ) {
    _write(DloxOpCode.METHOD.index, line);
    _write(constant, line);
  }

  void emit_class(
    final int constant,
    final INDEX line,
  ) {
    _write(DloxOpCode.CLASS.index, line);
    _write(constant, line);
  }

  void emit_nil(
    final INDEX line,
  ) {
    _write(DloxOpCode.NIL.index, line);
  }

  void emit_pop(
    final INDEX line,
  ) {
    _write(DloxOpCode.POP.index, line);
  }

  void emit_global(
    final int global,
    final INDEX line,
  ) {
    _write(DloxOpCode.DEFINE_GLOBAL.index, line);
    _write(global, line);
  }

  void emit_constant(
    final int constant,
    final INDEX line,
  ) {
    _write(DloxOpCode.CONSTANT.index, line);
    _write(constant, line);
  }

  void emit_loop(
    final int offset,
    final INDEX line,
  ) {
    _write(DloxOpCode.LOOP.index, line);
    _write((offset >> 8) & 0xff, line);
    _write(offset & 0xff, line);
  }

  int emit_jump_if_false(
    final INDEX line,
  ) {
    _write(DloxOpCode.JUMP_IF_FALSE.index, line);
    _write(0xff, line);
    _write(0xff, line);
    return code.length - 2;
  }

  int emit_jump(
    final INDEX line,
  ) {
    _write(DloxOpCode.JUMP.index, line);
    _write(0xff, line);
    _write(0xff, line);
    return code.length - 2;
  }

  void emit_return_local(
    final INDEX line,
  ) {
    _write(DloxOpCode.GET_LOCAL.index, line);
    _write(0, line);
    _write(DloxOpCode.RETURN.index, line);
  }

  void emit_return_nil(
    final INDEX line,
  ) {
    _write(DloxOpCode.NIL.index, line);
    _write(DloxOpCode.RETURN.index, line);
  }
  // endregion
}

class DloxHeap {
  final List<Object?> _constants;
  final Map<Object?, int> _constant_map;

  DloxHeap() :
    _constants = [],
    _constant_map = {};

  int add_constant(
    final Object? value,
  ) {
    final idx = _constant_map[value];
    if (idx != null) {
      return idx;
    } else {
      _constants.add(value);
      _constant_map[value] = _constants.length - 1;
      return _constants.length - 1;
    }
  }

  Object? constant_at(
    final int constant,
  ) {
    return _constants[constant];
  }

  Iterable<Object?> get all_constants {
    return _constants;
  }
}

class DloxNative {
  final String name;
  final int arity;
  final DloxNativeFunction fn;

  const DloxNative(
    final this.name,
    final this.arity,
    final this.fn,
  );
}

typedef DloxNativeFunction = Object? Function(
  List<Object?> stack,
  int arg_idx,
  int arg_count,
);

class DloxUpvalue {
  int? location;
  Object? closed;
  DloxUpvalue? next;

  DloxUpvalue(
    final this.location,
    final this.closed,
  );
}

class DloxClosure {
  final DloxFunction function;
  final List<DloxUpvalue?> upvalues;

  const DloxClosure({
    required final this.function,
    required final this.upvalues,
  });
}

class DloxClass {
  String? name;
  DloxTable methods;

  DloxClass(
    final this.name,
  ) : methods = DloxTable();
}

class DloxInstance {
  final String? klass_name; // For dynamic class lookup
  final DloxTable fields;
  DloxClass? klass;

  DloxInstance({
    required final this.fields,
    final this.klass,
    final this.klass_name,
  });
}

class DloxBoundMethod {
  final Object? receiver;
  final DloxClosure method;

  const DloxBoundMethod({
    required final this.receiver,
    required final this.method,
  });
}

class DloxNil {
  const DloxNil();
}

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

const int DLOX_UINT8_COUNT = 256;
const int DLOX_UINT8_MAX = DLOX_UINT8_COUNT - 1;
const int DLOX_UINT16_MAX = 65535;
