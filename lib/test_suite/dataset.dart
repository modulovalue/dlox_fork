import 'model.dart';

// TODO migrate to this.
// TODO remove filesystem stored testsuite.
class DloxDatasetAll with DloxDatasetInternal {
  const DloxDatasetAll();

  @override
  String get name => "all";

  @override
  List<DloxDataset> get children => const [
        set_assignment,
        set_block,
        set_bool,
        set_call,
        set_class,
        set_closure,
        set_comments,
        set_constructor,
        set_field,
        set_for,
        set_function,
        set_if,
        set_inheritance,
        set_logical_operator,
        set_method,
        set_misc,
        set_nil,
        set_number,
        set_operator,
        set_print,
        set_regression,
        set_return,
        set_string,
        set_super,
        set_this,
        set_variable,
        set_while,
      ];

  static const set_assignment = DloxDataset_assignment();
  static const set_block = DloxDataset_block();
  static const set_bool = DloxDataset_bool();
  static const set_call = DloxDataset_call();
  static const set_class = DloxDataset_class();
  static const set_closure = DloxDataset_closure();
  static const set_comments = DloxDataset_comments();
  static const set_constructor = DloxDataset_constructor();
  static const set_field = DloxDataset_field();
  static const set_for = DloxDataset_for();
  static const set_function = DloxDataset_function();
  static const set_if = DloxDataset_if();
  static const set_inheritance = DloxDataset_inheritance();
  static const set_logical_operator = DloxDataset_logical_operator();
  static const set_method = DloxDataset_method();
  static const set_misc = DloxDataset_misc();
  static const set_nil = DloxDataset_nil();
  static const set_number = DloxDataset_number();
  static const set_operator = DloxDataset_operator();
  static const set_print = DloxDataset_print();
  static const set_regression = DloxDataset_regression();
  static const set_return = DloxDataset_return();
  static const set_string = DloxDataset_string();
  static const set_super = DloxDataset_super();
  static const set_this = DloxDataset_this();
  static const set_variable = DloxDataset_variable();
  static const set_while = DloxDataset_while();
}

class DloxDataset_closure with DloxDatasetInternal {
  const DloxDataset_closure();

  @override
  String get name => "closure";

  @override
  List<DloxDataset> get children => const [
        DloxDatasetLeafImpl(
          name: "reuse_closure_slot",
          source: r"""
{
  var f;

  {
    var a = "a";
    fun f_() { print a; }
    f = f_;
  }

  {
    // Since a is out of scope, the local slot will be reused by b. Make sure
    // that f still closes over a.
    var b = "b";
    f(); // expect: a
  }
}
""",
        ),
        DloxDatasetLeafImpl(
          name: "assign_to_shadowed_later",
          source: r"""
var a = "global";

{
  fun assign() {
    a = "assigned";
  }

  var a = "inner";
  assign();
  print a; // expect: inner
}

print a; // expect: assigned
""",
        ),
        DloxDatasetLeafImpl(
          name: "close_over_later_variable",
          source: r"""
// This is a regression test. There was a bug where if an upvalue for an
// earlier local (here "a") was captured *after* a later one ("b"), then it
// would crash because it walked to the end of the upvalue list (correct), but
// then didn't handle not finding the variable.

fun f() {
  var a = "a";
  var b = "b";
  fun g() {
    print b; // expect: b
    print a; // expect: a
  }
  g();
}
f();
""",
        ),
        DloxDatasetLeafImpl(
          name: "closed_closure_in_function",
          source: r"""
var f;

{
  var local = "local";
  fun f_() {
    print local;
  }
  f = f_;
}

f(); // expect: local
""",
        ),
        DloxDatasetLeafImpl(
          name: "unused_later_closure",
          source: r"""
// This is a regression test. When closing upvalues for discarded locals, it
// wouldn't make sure it discarded the upvalue for the correct stack slot.
//
// Here we create two locals that can be closed over, but only the first one
// actually is. When "b" goes out of scope, we need to make sure we don't
// prematurely close "a".
var closure;

{
  var a = "a";

  {
    var b = "b";
    fun returnA() {
      return a;
    }

    closure = returnA;

    if (false) {
      fun returnB() {
        return b;
      }
    }
  }

  print closure(); // expect: a
}
""",
        ),
        DloxDatasetLeafImpl(
          name: "shadow_closure_with_local",
          source: r"""
{
  var foo = "closure";
  fun f() {
    {
      print foo; // expect: closure
      var foo = "shadow";
      print foo; // expect: shadow
    }
    print foo; // expect: closure
  }
  f();
}
""",
        ),
        DloxDatasetLeafImpl(
          name: "unused_closure",
          source: r"""
// This is a regression test. There was a bug where the VM would try to close
// an upvalue even if the upvalue was never created because the codepath for
// the closure was not executed.

{
  var a = "a";
  if (false) {
    fun foo() { a; }
  }
}

// If we get here, we didn't segfault when a went out of scope.
print "ok"; // expect: ok
""",
        ),
        DloxDatasetLeafImpl(
          name: "close_over_function_parameter",
          source: r"""
var f;

fun foo(param) {
  fun f_() {
    print param;
  }
  f = f_;
}
foo("param");

f(); // expect: param
""",
        ),
        DloxDatasetLeafImpl(
          name: "close_over_method_parameter",
          source: r"""
var f;

class Foo {
  method(param) {
    fun f_() {
      print param;
    }
    f = f_;
  }
}

Foo().method("param");
f(); // expect: param
""",
        ),
        DloxDatasetLeafImpl(
          name: "open_closure_in_function",
          source: r"""
{
  var local = "local";
  fun f() {
    print local; // expect: local
  }
  f();
}
""",
        ),
        DloxDatasetLeafImpl(
          name: "reference_closure_multiple_times",
          source: r"""
var f;

{
  var a = "a";
  fun f_() {
    print a;
    print a;
  }
  f = f_;
}

f();
// expect: a
// expect: a
""",
        ),
        DloxDatasetLeafImpl(
          name: "nested_closure",
          source: r"""
var f;

fun f1() {
  var a = "a";
  fun f2() {
    var b = "b";
    fun f3() {
      var c = "c";
      fun f4() {
        print a;
        print b;
        print c;
      }
      f = f4;
    }
    f3();
  }
  f2();
}
f1();

f();
// expect: a
// expect: b
// expect: c
""",
        ),
        DloxDatasetLeafImpl(
          name: "assign_to_closure",
          source: r"""
var f;
var g;

{
  var local = "local";
  fun f_() {
    print local;
    local = "after f";
    print local;
  }
  f = f_;

  fun g_() {
    print local;
    local = "after g";
    print local;
  }
  g = g_;
}

f();
// expect: local
// expect: after f

g();
// expect: after f
// expect: after g
""",
        ),
      ];
}

class DloxDataset_misc with DloxDatasetInternal {
  const DloxDataset_misc();

  @override
  String get name => "misc";

  @override
  List<DloxDataset> get children => const [
        DloxDatasetLeafImpl(
          name: "empty_file",
          source: r"""
""",
        ),
        DloxDatasetLeafImpl(
          name: "unexpected_character",
          source: r"""
foo(a or b); // Runtime error: Undefined variable 'foo'.
""",
        ),
        DloxDatasetLeafImpl(
          name: "precedence",
          source: r"""
// * has higher precedence than +.
print 2 + 3 * 4; // expect: 14

// * has higher precedence than -.
print 20 - 3 * 4; // expect: 8

// / has higher precedence than +.
print 2 + 6 / 3; // expect: 4

// / has higher precedence than -.
print 2 - 6 / 3; // expect: 0

// < has higher precedence than ==.
print false == 2 < 1; // expect: true

// > has higher precedence than ==.
print false == 1 > 2; // expect: true

// <= has higher precedence than ==.
print false == 2 <= 1; // expect: true

// >= has higher precedence than ==.
print false == 1 >= 2; // expect: true

// 1 - 1 is not space-sensitive.
print 1 - 1; // expect: 0
print 1 -1;  // expect: 0
print 1- 1;  // expect: 0
print 1-1;   // expect: 0

// Using () for grouping.
print (2 * (6 - (2 + 2))); // expect: 4
""",
        ),
      ];
}

class DloxDataset_comments with DloxDatasetInternal {
  const DloxDataset_comments();

  @override
  String get name => "comments";

  @override
  List<DloxDataset> get children => const [
        DloxDatasetLeafImpl(
          name: "line_at_eof",
          source: r"""
print "ok"; // expect: ok
// comment""",
        ),
        DloxDatasetLeafImpl(
          name: "only_line_comment",
          source: r"""
// comment""",
        ),
        DloxDatasetLeafImpl(
          name: "unicode",
          source: r"""
// Unicode characters are allowed in comments.
//
// Latin 1 Supplement: £§¶ÜÞ
// Latin Extended-A: ĐĦŋœ
// Latin Extended-B: ƂƢƩǁ
// Other stuff: ឃᢆ᯽₪ℜ↩⊗┺░
// Emoji: ☃☺♣

print "ok"; // expect: ok
""",
        ),
        DloxDatasetLeafImpl(
          name: "only_line_comment_and_line",
          source: r"""
// comment
""",
        ),
      ];
}

class DloxDataset_variable with DloxDatasetInternal {
  const DloxDataset_variable();

  @override
  String get name => "variable";

  @override
  List<DloxDataset> get children => const [
        DloxDatasetLeafImpl(
          name: "in_nested_block",
          source: r"""
{
  var a = "outer";
  {
    print a; // expect: outer
  }
}""",
        ),
        DloxDatasetLeafImpl(
          name: "scope_reuse_in_different_blocks",
          source: r"""
{
  var a = "first";
  print a; // expect: first
}

{
  var a = "second";
  print a; // expect: second
}
""",
        ),
        DloxDatasetLeafImpl(
          name: "local_from_method",
          source: r"""
var foo = "variable";

class Foo {
  method() {
    print foo;
  }
}

Foo().method(); // expect: variable
""",
        ),
        DloxDatasetLeafImpl(
          name: "use_global_in_initializer",
          source: r"""
var a = "value";
var a = a;
print a; // expect: value
""",
        ),
        DloxDatasetLeafImpl(
          name: "use_this_as_var",
          source: r"""
var this = "value"; // Error at 'this': Expect variable name.""",
        ),
        DloxDatasetLeafImpl(
          name: "redeclare_global",
          source: r"""
var a = "1";
var a;
print a; // expect: nil
""",
        ),
        DloxDatasetLeafImpl(
          name: "use_nil_as_var",
          source: r"""
var nil = "value"; // Error at 'nil': Expect variable name.""",
        ),
        DloxDatasetLeafImpl(
          name: "undefined_global",
          source: r"""
print notDefined;  // Runtime error: Undefined variable 'notDefined'.
""",
        ),
        DloxDatasetLeafImpl(
          name: "shadow_and_local",
          source: r"""
{
  var a = "outer";
  {
    print a; // expect: outer
    var a = "inner";
    print a; // expect: inner
  }
}""",
        ),
        DloxDatasetLeafImpl(
          name: "early_bound",
          source: r"""
var a = "outer";
{
  fun foo() {
    print a;
  }

  foo(); // expect: outer
  var a = "inner";
  foo(); // expect: outer
}
""",
        ),
        DloxDatasetLeafImpl(
          name: "duplicate_parameter",
          source: r"""
fun foo(arg,
        arg) { // Error at 'arg': Already variable with this name in this scope.
  "body";
}
""",
        ),
        DloxDatasetLeafImpl(
          name: "uninitialized",
          source: r"""
var a;
print a; // expect: nil
""",
        ),
        DloxDatasetLeafImpl(
          name: "use_false_as_var",
          source: r"""
var false = "value"; // Error at 'false': Expect variable name.
""",
        ),
        DloxDatasetLeafImpl(
          name: "shadow_global",
          source: r"""
var a = "global";
{
  var a = "shadow";
  print a; // expect: shadow
}
print a; // expect: global
""",
        ),
        DloxDatasetLeafImpl(
          name: "duplicate_local",
          source: r"""
{
  var a = "value";
  var a = "other"; // Error at 'a': Already variable with this name in this scope.
}
""",
        ),
        DloxDatasetLeafImpl(
          name: "in_middle_of_block",
          source: r"""
{
  var a = "a";
  print a; // expect: a
  var b = a + " b";
  print b; // expect: a b
  var c = a + " c";
  print c; // expect: a c
  var d = b + " d";
  print d; // expect: a b d
}
""",
        ),
        DloxDatasetLeafImpl(
          name: "shadow_local",
          source: r"""
{
  var a = "local";
  {
    var a = "shadow";
    print a; // expect: shadow
  }
  print a; // expect: local
}
""",
        ),
        DloxDatasetLeafImpl(
          name: "unreached_undefined",
          source: r"""
if (false) {
  print notDefined;
}

print "ok"; // expect: ok
""",
        ),
        DloxDatasetLeafImpl(
          name: "collide_with_parameter",
          source: r"""
fun foo(a) {
  var a; // Error at 'a': Already variable with this name in this scope.
}
""",
        ),
        DloxDatasetLeafImpl(
          name: "use_local_in_initializer",
          source: r"""
var a = "outer";
{
  var a = a; // Error at 'a': Can't read local variable in its own initializer.
}
""",
        ),
        DloxDatasetLeafImpl(
          name: "redefine_global",
          source: r"""
var a = "1";
var a = "2";
print a; // expect: 2
""",
        ),
        DloxDatasetLeafImpl(
          name: "undefined_local",
          source: r"""
{
  print notDefined;  // Runtime error: Undefined variable 'notDefined'.
}
""",
        ),
      ];
}

class DloxDataset_nil with DloxDatasetInternal {
  const DloxDataset_nil();

  @override
  String get name => "nil";

  @override
  List<DloxDataset> get children => const [
        DloxDatasetLeafImpl(
          name: "literal",
          source: r"""
print nil; // expect: nil
""",
        ),
      ];
}

class DloxDataset_if with DloxDatasetInternal {
  const DloxDataset_if();

  @override
  String get name => "if";

  @override
  List<DloxDataset> get children => const [
        DloxDatasetLeafImpl(
          name: "var_in_then",
          source: r"""
if (true) var foo; // Error at 'var': Expect expression.
""",
        ),
        DloxDatasetLeafImpl(
          name: "dangling_else",
          source: r"""
// A dangling else binds to the right-most if.
if (true) if (false) print "bad"; else print "good"; // expect: good
if (false) if (true) print "bad"; else print "bad";
""",
        ),
        DloxDatasetLeafImpl(
          name: "truth",
          source: r"""
// False and nil are false.
if (false) print "bad"; else print "false"; // expect: false
if (nil) print "bad"; else print "nil"; // expect: nil

// Everything else is true.
if (true) print true; // expect: true
if (0) print 0; // expect: 0
if ("") print "empty"; // expect: empty
""",
        ),
        DloxDatasetLeafImpl(
          name: "fun_in_else",
          source: r"""
if (true) "ok"; else fun foo() {} // Error at 'fun': Expect expression.

""",
        ),
        DloxDatasetLeafImpl(
          name: "class_in_else",
          source: r"""
if (true) "ok"; else class Foo {} // Error at 'class': Expect expression.

""",
        ),
        DloxDatasetLeafImpl(
          name: "else",
          source: r"""
// Evaluate the 'else' expression if the condition is false.
if (true) print "good"; else print "bad"; // expect: good
if (false) print "bad"; else print "good"; // expect: good

// Allow block body.
if (false) nil; else { print "block"; } // expect: block
""",
        ),
        DloxDatasetLeafImpl(
          name: "fun_in_then",
          source: r"""
if (true) fun foo() {} // Error at 'fun': Expect expression.

""",
        ),
        DloxDatasetLeafImpl(
          name: "class_in_then",
          source: r"""
if (true) class Foo {} // Error at 'class': Expect expression.

""",
        ),
        DloxDatasetLeafImpl(
          name: "var_in_else",
          source: r"""
if (true) "ok"; else var foo; // Error at 'var': Expect expression.

""",
        ),
        DloxDatasetLeafImpl(
          name: "if",
          source: r"""
// Evaluate the 'then' expression if the condition is true.
if (true) print "good"; // expect: good
if (false) print "bad";

// Allow block body.
if (true) { print "block"; } // expect: block

// Assignment in if condition.
var a = false;
if (a = true) print a; // expect: true
""",
        ),
      ];
}

class DloxDataset_assignment with DloxDatasetInternal {
  const DloxDataset_assignment();

  @override
  String get name => "assignment";

  @override
  List<DloxDataset> get children => const [
        DloxDatasetLeafImpl(
          name: "grouping",
          source: r"""
var a = "a";
(a) = "value"; // Error at '=': Invalid assignment target.
""",
        ),
        DloxDatasetLeafImpl(
          name: "syntax",
          source: r"""
// Assignment on RHS of variable.
var a = "before";
var c = a = "var";
print a; // expect: var
print c; // expect: var
""",
        ),
        DloxDatasetLeafImpl(
          name: "global",
          source: r"""
var a = "before";
print a; // expect: before

a = "after";
print a; // expect: after

print a = "arg"; // expect: arg
print a; // expect: arg
""",
        ),
        DloxDatasetLeafImpl(
          name: "prefix_operator",
          source: r"""
var a = "a";
!a = "value"; // Error at '=': Invalid assignment target.
""",
        ),
        DloxDatasetLeafImpl(
          name: "associativity",
          source: r"""
var a = "a";
var b = "b";
var c = "c";

// Assignment is right-associative.
a = b = c;
print a; // expect: c
print b; // expect: c
print c; // expect: c
""",
        ),
        DloxDatasetLeafImpl(
          name: "to_this",
          source: r"""
class Foo {
  Foo() {
    this = "value"; // Error at '=': Invalid assignment target.
  }
}

Foo();
""",
        ),
        DloxDatasetLeafImpl(
          name: "infix_operator",
          source: r"""
var a = "a";
var b = "b";
a + b = "value"; // Error at '=': Invalid assignment target.
""",
        ),
        DloxDatasetLeafImpl(
          name: "local",
          source: r"""
{
  var a = "before";
  print a; // expect: before

  a = "after";
  print a; // expect: after

  print a = "arg"; // expect: arg
  print a; // expect: arg
}
""",
        ),
        DloxDatasetLeafImpl(
          name: "undefined",
          source: r"""
unknown = "what"; // Runtime error: Undefined variable 'unknown'.
""",
        ),
      ];
}

class DloxDataset_return with DloxDatasetInternal {
  const DloxDataset_return();

  @override
  String get name => "return";

  @override
  List<DloxDataset> get children => const [
        DloxDatasetLeafImpl(
          name: "after_if",
          source: r"""
fun f() {
  if (true) return "ok";
}

print f(); // expect: ok
""",
        ),
        DloxDatasetLeafImpl(
          name: "after_else",
          source: r"""
fun f() {
  if (false) "no"; else return "ok";
}

print f(); // expect: ok
""",
        ),
        DloxDatasetLeafImpl(
          name: "return_nil_if_no_value",
          source: r"""
fun f() {
  return;
  print "bad";
}

print f(); // expect: nil
""",
        ),
        DloxDatasetLeafImpl(
          name: "in_method",
          source: r"""
class Foo {
  method() {
    return "ok";
    print "bad";
  }
}

print Foo().method(); // expect: ok
""",
        ),
        DloxDatasetLeafImpl(
          name: "in_function",
          source: r"""
fun f() {
  return "ok";
  print "bad";
}

print f(); // expect: ok
""",
        ),
        DloxDatasetLeafImpl(
          name: "after_while",
          source: r"""
fun f() {
  while (true) return "ok";
}

print f(); // expect: ok
""",
        ),
      ];
}

class DloxDataset_function with DloxDatasetInternal {
  const DloxDataset_function();

  @override
  String get name => "function";

  @override
  List<DloxDataset> get children => const [
        DloxDatasetLeafImpl(
          name: "local_mutual_recursion",
          source: r"""
{
  fun isEven(n) {
    if (n == 0) return true;
    return isOdd(n - 1); // Runtime error: Undefined variable 'isOdd'.
  }

  fun isOdd(n) {
    if (n == 0) return false;
    return isEven(n - 1);
  }

  isEven(4);
}""",
        ),
        DloxDatasetLeafImpl(
          name: "empty_body",
          source: r"""
fun f() {}
print f(); // expect: nil
""",
        ),
        DloxDatasetLeafImpl(
          name: "too_many_arguments",
          source: r"""
fun foo() {}
{
  var a = 1;
  foo(
     a, // 1
     a, // 2
     a, // 3
     a, // 4
     a, // 5
     a, // 6
     a, // 7
     a, // 8
     a, // 9
     a, // 10
     a, // 11
     a, // 12
     a, // 13
     a, // 14
     a, // 15
     a, // 16
     a, // 17
     a, // 18
     a, // 19
     a, // 20
     a, // 21
     a, // 22
     a, // 23
     a, // 24
     a, // 25
     a, // 26
     a, // 27
     a, // 28
     a, // 29
     a, // 30
     a, // 31
     a, // 32
     a, // 33
     a, // 34
     a, // 35
     a, // 36
     a, // 37
     a, // 38
     a, // 39
     a, // 40
     a, // 41
     a, // 42
     a, // 43
     a, // 44
     a, // 45
     a, // 46
     a, // 47
     a, // 48
     a, // 49
     a, // 50
     a, // 51
     a, // 52
     a, // 53
     a, // 54
     a, // 55
     a, // 56
     a, // 57
     a, // 58
     a, // 59
     a, // 60
     a, // 61
     a, // 62
     a, // 63
     a, // 64
     a, // 65
     a, // 66
     a, // 67
     a, // 68
     a, // 69
     a, // 70
     a, // 71
     a, // 72
     a, // 73
     a, // 74
     a, // 75
     a, // 76
     a, // 77
     a, // 78
     a, // 79
     a, // 80
     a, // 81
     a, // 82
     a, // 83
     a, // 84
     a, // 85
     a, // 86
     a, // 87
     a, // 88
     a, // 89
     a, // 90
     a, // 91
     a, // 92
     a, // 93
     a, // 94
     a, // 95
     a, // 96
     a, // 97
     a, // 98
     a, // 99
     a, // 100
     a, // 101
     a, // 102
     a, // 103
     a, // 104
     a, // 105
     a, // 106
     a, // 107
     a, // 108
     a, // 109
     a, // 110
     a, // 111
     a, // 112
     a, // 113
     a, // 114
     a, // 115
     a, // 116
     a, // 117
     a, // 118
     a, // 119
     a, // 120
     a, // 121
     a, // 122
     a, // 123
     a, // 124
     a, // 125
     a, // 126
     a, // 127
     a, // 128
     a, // 129
     a, // 130
     a, // 131
     a, // 132
     a, // 133
     a, // 134
     a, // 135
     a, // 136
     a, // 137
     a, // 138
     a, // 139
     a, // 140
     a, // 141
     a, // 142
     a, // 143
     a, // 144
     a, // 145
     a, // 146
     a, // 147
     a, // 148
     a, // 149
     a, // 150
     a, // 151
     a, // 152
     a, // 153
     a, // 154
     a, // 155
     a, // 156
     a, // 157
     a, // 158
     a, // 159
     a, // 160
     a, // 161
     a, // 162
     a, // 163
     a, // 164
     a, // 165
     a, // 166
     a, // 167
     a, // 168
     a, // 169
     a, // 170
     a, // 171
     a, // 172
     a, // 173
     a, // 174
     a, // 175
     a, // 176
     a, // 177
     a, // 178
     a, // 179
     a, // 180
     a, // 181
     a, // 182
     a, // 183
     a, // 184
     a, // 185
     a, // 186
     a, // 187
     a, // 188
     a, // 189
     a, // 190
     a, // 191
     a, // 192
     a, // 193
     a, // 194
     a, // 195
     a, // 196
     a, // 197
     a, // 198
     a, // 199
     a, // 200
     a, // 201
     a, // 202
     a, // 203
     a, // 204
     a, // 205
     a, // 206
     a, // 207
     a, // 208
     a, // 209
     a, // 210
     a, // 211
     a, // 212
     a, // 213
     a, // 214
     a, // 215
     a, // 216
     a, // 217
     a, // 218
     a, // 219
     a, // 220
     a, // 221
     a, // 222
     a, // 223
     a, // 224
     a, // 225
     a, // 226
     a, // 227
     a, // 228
     a, // 229
     a, // 230
     a, // 231
     a, // 232
     a, // 233
     a, // 234
     a, // 235
     a, // 236
     a, // 237
     a, // 238
     a, // 239
     a, // 240
     a, // 241
     a, // 242
     a, // 243
     a, // 244
     a, // 245
     a, // 246
     a, // 247
     a, // 248
     a, // 249
     a, // 250
     a, // 251
     a, // 252
     a, // 253
     a, // 254
     a, // 255
     a); // Error at 'a': Can't have more than 255 arguments.
}
""",
        ),
        DloxDatasetLeafImpl(
          name: "missing_comma_in_parameters",
          source: r"""
fun foo(a, b c, d, e, f) // Error at 'c': Expect ')' after parameters.
{}
// Error at end: Unterminated block.""",
        ),
        DloxDatasetLeafImpl(
          name: "body_must_be_block",
          source: r"""
fun f() 123; // Error at '123': Expect function body.
// Error at end: Unterminated block""",
        ),
        DloxDatasetLeafImpl(
          name: "missing_arguments",
          source: r"""
fun f(a, b) {}

f(1); // Runtime error: Expected 2 arguments but got 1.
""",
        ),
        DloxDatasetLeafImpl(
          name: "parameters",
          source: r"""
fun f0() { return 0; }
print f0(); // expect: 0

fun f1(a) { return a; }
print f1(1); // expect: 1

fun f2(a, b) { return a + b; }
print f2(1, 2); // expect: 3

fun f3(a, b, c) { return a + b + c; }
print f3(1, 2, 3); // expect: 6

fun f4(a, b, c, d) { return a + b + c + d; }
print f4(1, 2, 3, 4); // expect: 10

fun f5(a, b, c, d, e) { return a + b + c + d + e; }
print f5(1, 2, 3, 4, 5); // expect: 15

fun f6(a, b, c, d, e, f) { return a + b + c + d + e + f; }
print f6(1, 2, 3, 4, 5, 6); // expect: 21

fun f7(a, b, c, d, e, f, g) { return a + b + c + d + e + f + g; }
print f7(1, 2, 3, 4, 5, 6, 7); // expect: 28

fun f8(a, b, c, d, e, f, g, h) { return a + b + c + d + e + f + g + h; }
print f8(1, 2, 3, 4, 5, 6, 7, 8); // expect: 36
""",
        ),
        DloxDatasetLeafImpl(
          name: "local_recursion",
          source: r"""
{
  fun fib(n) {
    if (n < 2) return n;
    return fib(n - 1) + fib(n - 2);
  }

  print fib(8); // expect: 21
}
""",
        ),
        DloxDatasetLeafImpl(
          name: "recursion",
          source: r"""
fun fib(n) {
  if (n < 2) return n;
  return fib(n - 1) + fib(n - 2);
}

print fib(8); // expect: 21
""",
        ),
        DloxDatasetLeafImpl(
          name: "print",
          source: r"""
fun foo() {}
print foo; // expect: <fn foo>
""",
        ),
        DloxDatasetLeafImpl(
          name: "too_many_parameters",
          source: r"""
// 256 parameters.
fun f(
    a1,
    a2,
    a3,
    a4,
    a5,
    a6,
    a7,
    a8,
    a9,
    a10,
    a11,
    a12,
    a13,
    a14,
    a15,
    a16,
    a17,
    a18,
    a19,
    a20,
    a21,
    a22,
    a23,
    a24,
    a25,
    a26,
    a27,
    a28,
    a29,
    a30,
    a31,
    a32,
    a33,
    a34,
    a35,
    a36,
    a37,
    a38,
    a39,
    a40,
    a41,
    a42,
    a43,
    a44,
    a45,
    a46,
    a47,
    a48,
    a49,
    a50,
    a51,
    a52,
    a53,
    a54,
    a55,
    a56,
    a57,
    a58,
    a59,
    a60,
    a61,
    a62,
    a63,
    a64,
    a65,
    a66,
    a67,
    a68,
    a69,
    a70,
    a71,
    a72,
    a73,
    a74,
    a75,
    a76,
    a77,
    a78,
    a79,
    a80,
    a81,
    a82,
    a83,
    a84,
    a85,
    a86,
    a87,
    a88,
    a89,
    a90,
    a91,
    a92,
    a93,
    a94,
    a95,
    a96,
    a97,
    a98,
    a99,
    a100,
    a101,
    a102,
    a103,
    a104,
    a105,
    a106,
    a107,
    a108,
    a109,
    a110,
    a111,
    a112,
    a113,
    a114,
    a115,
    a116,
    a117,
    a118,
    a119,
    a120,
    a121,
    a122,
    a123,
    a124,
    a125,
    a126,
    a127,
    a128,
    a129,
    a130,
    a131,
    a132,
    a133,
    a134,
    a135,
    a136,
    a137,
    a138,
    a139,
    a140,
    a141,
    a142,
    a143,
    a144,
    a145,
    a146,
    a147,
    a148,
    a149,
    a150,
    a151,
    a152,
    a153,
    a154,
    a155,
    a156,
    a157,
    a158,
    a159,
    a160,
    a161,
    a162,
    a163,
    a164,
    a165,
    a166,
    a167,
    a168,
    a169,
    a170,
    a171,
    a172,
    a173,
    a174,
    a175,
    a176,
    a177,
    a178,
    a179,
    a180,
    a181,
    a182,
    a183,
    a184,
    a185,
    a186,
    a187,
    a188,
    a189,
    a190,
    a191,
    a192,
    a193,
    a194,
    a195,
    a196,
    a197,
    a198,
    a199,
    a200,
    a201,
    a202,
    a203,
    a204,
    a205,
    a206,
    a207,
    a208,
    a209,
    a210,
    a211,
    a212,
    a213,
    a214,
    a215,
    a216,
    a217,
    a218,
    a219,
    a220,
    a221,
    a222,
    a223,
    a224,
    a225,
    a226,
    a227,
    a228,
    a229,
    a230,
    a231,
    a232,
    a233,
    a234,
    a235,
    a236,
    a237,
    a238,
    a239,
    a240,
    a241,
    a242,
    a243,
    a244,
    a245,
    a246,
    a247,
    a248,
    a249,
    a250,
    a251,
    a252,
    a253,
    a254,
    a255, a) {} // Error at 'a': Can't have more than 255 parameters.
""",
        ),
        DloxDatasetLeafImpl(
          name: "mutual_recursion",
          source: r"""
fun isEven(n) {
  if (n == 0) return true;
  return isOdd(n - 1);
}

fun isOdd(n) {
  if (n == 0) return false;
  return isEven(n - 1);
}

print isEven(4); // expect: true
print isOdd(3); // expect: true
""",
        ),
        DloxDatasetLeafImpl(
          name: "extra_arguments",
          source: r"""
fun f(a, b) {
  print a;
  print b;
}

f(1, 2, 3, 4); // Runtime error: Expected 2 arguments but got 4.
""",
        ),
      ];
}

class DloxDataset_field with DloxDatasetInternal {
  const DloxDataset_field();

  @override
  String get name => "field";

  @override
  List<DloxDataset> get children => const [
        DloxDatasetLeafImpl(
          name: "set_on_nil",
          source: r"""
nil.foo = "value"; // Runtime error: Only instances have fields.
""",
        ),
        DloxDatasetLeafImpl(
          name: "get_on_string",
          source: r"""
"str".foo; // Runtime error: Only instances have properties.
""",
        ),
        DloxDatasetLeafImpl(
          name: "many",
          source: r"""
class Foo {}

var foo = Foo();
fun setFields() {
  foo.bilberry = "bilberry";
  foo.lime = "lime";
  foo.elderberry = "elderberry";
  foo.raspberry = "raspberry";
  foo.gooseberry = "gooseberry";
  foo.longan = "longan";
  foo.mandarine = "mandarine";
  foo.kiwifruit = "kiwifruit";
  foo.orange = "orange";
  foo.pomegranate = "pomegranate";
  foo.tomato = "tomato";
  foo.banana = "banana";
  foo.juniper = "juniper";
  foo.damson = "damson";
  foo.blackcurrant = "blackcurrant";
  foo.peach = "peach";
  foo.grape = "grape";
  foo.mango = "mango";
  foo.redcurrant = "redcurrant";
  foo.watermelon = "watermelon";
  foo.plumcot = "plumcot";
  foo.papaya = "papaya";
  foo.cloudberry = "cloudberry";
  foo.rambutan = "rambutan";
  foo.salak = "salak";
  foo.physalis = "physalis";
  foo.huckleberry = "huckleberry";
  foo.coconut = "coconut";
  foo.date = "date";
  foo.tamarind = "tamarind";
  foo.lychee = "lychee";
  foo.raisin = "raisin";
  foo.apple = "apple";
  foo.avocado = "avocado";
  foo.nectarine = "nectarine";
  foo.pomelo = "pomelo";
  foo.melon = "melon";
  foo.currant = "currant";
  foo.plum = "plum";
  foo.persimmon = "persimmon";
  foo.olive = "olive";
  foo.cranberry = "cranberry";
  foo.boysenberry = "boysenberry";
  foo.blackberry = "blackberry";
  foo.passionfruit = "passionfruit";
  foo.mulberry = "mulberry";
  foo.marionberry = "marionberry";
  foo.plantain = "plantain";
  foo.lemon = "lemon";
  foo.yuzu = "yuzu";
  foo.loquat = "loquat";
  foo.kumquat = "kumquat";
  foo.salmonberry = "salmonberry";
  foo.tangerine = "tangerine";
  foo.durian = "durian";
  foo.pear = "pear";
  foo.cantaloupe = "cantaloupe";
  foo.quince = "quince";
  foo.guava = "guava";
  foo.strawberry = "strawberry";
  foo.nance = "nance";
  foo.apricot = "apricot";
  foo.jambul = "jambul";
  foo.grapefruit = "grapefruit";
  foo.clementine = "clementine";
  foo.jujube = "jujube";
  foo.cherry = "cherry";
  foo.feijoa = "feijoa";
  foo.jackfruit = "jackfruit";
  foo.fig = "fig";
  foo.cherimoya = "cherimoya";
  foo.pineapple = "pineapple";
  foo.blueberry = "blueberry";
  foo.jabuticaba = "jabuticaba";
  foo.miracle = "miracle";
  foo.dragonfruit = "dragonfruit";
  foo.satsuma = "satsuma";
  foo.tamarillo = "tamarillo";
  foo.honeydew = "honeydew";
}

setFields();

fun printFields() {
  print foo.apple; // expect: apple
  print foo.apricot; // expect: apricot
  print foo.avocado; // expect: avocado
  print foo.banana; // expect: banana
  print foo.bilberry; // expect: bilberry
  print foo.blackberry; // expect: blackberry
  print foo.blackcurrant; // expect: blackcurrant
  print foo.blueberry; // expect: blueberry
  print foo.boysenberry; // expect: boysenberry
  print foo.cantaloupe; // expect: cantaloupe
  print foo.cherimoya; // expect: cherimoya
  print foo.cherry; // expect: cherry
  print foo.clementine; // expect: clementine
  print foo.cloudberry; // expect: cloudberry
  print foo.coconut; // expect: coconut
  print foo.cranberry; // expect: cranberry
  print foo.currant; // expect: currant
  print foo.damson; // expect: damson
  print foo.date; // expect: date
  print foo.dragonfruit; // expect: dragonfruit
  print foo.durian; // expect: durian
  print foo.elderberry; // expect: elderberry
  print foo.feijoa; // expect: feijoa
  print foo.fig; // expect: fig
  print foo.gooseberry; // expect: gooseberry
  print foo.grape; // expect: grape
  print foo.grapefruit; // expect: grapefruit
  print foo.guava; // expect: guava
  print foo.honeydew; // expect: honeydew
  print foo.huckleberry; // expect: huckleberry
  print foo.jabuticaba; // expect: jabuticaba
  print foo.jackfruit; // expect: jackfruit
  print foo.jambul; // expect: jambul
  print foo.jujube; // expect: jujube
  print foo.juniper; // expect: juniper
  print foo.kiwifruit; // expect: kiwifruit
  print foo.kumquat; // expect: kumquat
  print foo.lemon; // expect: lemon
  print foo.lime; // expect: lime
  print foo.longan; // expect: longan
  print foo.loquat; // expect: loquat
  print foo.lychee; // expect: lychee
  print foo.mandarine; // expect: mandarine
  print foo.mango; // expect: mango
  print foo.marionberry; // expect: marionberry
  print foo.melon; // expect: melon
  print foo.miracle; // expect: miracle
  print foo.mulberry; // expect: mulberry
  print foo.nance; // expect: nance
  print foo.nectarine; // expect: nectarine
  print foo.olive; // expect: olive
  print foo.orange; // expect: orange
  print foo.papaya; // expect: papaya
  print foo.passionfruit; // expect: passionfruit
  print foo.peach; // expect: peach
  print foo.pear; // expect: pear
  print foo.persimmon; // expect: persimmon
  print foo.physalis; // expect: physalis
  print foo.pineapple; // expect: pineapple
  print foo.plantain; // expect: plantain
  print foo.plum; // expect: plum
  print foo.plumcot; // expect: plumcot
  print foo.pomegranate; // expect: pomegranate
  print foo.pomelo; // expect: pomelo
  print foo.quince; // expect: quince
  print foo.raisin; // expect: raisin
  print foo.rambutan; // expect: rambutan
  print foo.raspberry; // expect: raspberry
  print foo.redcurrant; // expect: redcurrant
  print foo.salak; // expect: salak
  print foo.salmonberry; // expect: salmonberry
  print foo.satsuma; // expect: satsuma
  print foo.strawberry; // expect: strawberry
  print foo.tamarillo; // expect: tamarillo
  print foo.tamarind; // expect: tamarind
  print foo.tangerine; // expect: tangerine
  print foo.tomato; // expect: tomato
  print foo.watermelon; // expect: watermelon
  print foo.yuzu; // expect: yuzu
}

printFields();
""",
        ),
        DloxDatasetLeafImpl(
          name: "set_on_function",
          source: r"""
fun foo() {}

foo.bar = "value"; // Runtime error: Only instances have fields.
""",
        ),
        DloxDatasetLeafImpl(
          name: "set_on_bool",
          source: r"""
true.foo = "value"; // Runtime error: Only instances have fields.
""",
        ),
        DloxDatasetLeafImpl(
          name: "method",
          source: r"""
class Foo {
  bar(arg) {
    print arg;
  }
}

var bar = Foo().bar;
print "got method"; // expect: got method
bar("arg");          // expect: arg
""",
        ),
        DloxDatasetLeafImpl(
          name: "call_nonfunction_field",
          source: r"""
class Foo {}

var foo = Foo();
foo.bar = "not fn";

foo.bar(); // Runtime error: Can only call functions and classes.
""",
        ),
        DloxDatasetLeafImpl(
          name: "get_on_nil",
          source: r"""
nil.foo; // Runtime error: Only instances have properties.
""",
        ),
        DloxDatasetLeafImpl(
          name: "set_on_class",
          source: r"""
class Foo {}
Foo.bar = "value"; // Runtime error: Only instances have fields.
""",
        ),
        DloxDatasetLeafImpl(
          name: "set_on_string",
          source: r"""
"str".foo = "value"; // Runtime error: Only instances have fields.
""",
        ),
        DloxDatasetLeafImpl(
          name: "on_instance",
          source: r"""
class Foo {}

var foo = Foo();

print foo.bar = "bar value"; // expect: bar value
print foo.baz = "baz value"; // expect: baz value

print foo.bar; // expect: bar value
print foo.baz; // expect: baz value
""",
        ),
        DloxDatasetLeafImpl(
          name: "get_on_function",
          source: r"""
fun foo() {}

foo.bar; // Runtime error: Only instances have properties.
""",
        ),
        DloxDatasetLeafImpl(
          name: "call_function_field",
          source: r"""
class Foo {}

fun bar(a, b) {
  print "bar";
  print a;
  print b;
}

var foo = Foo();
foo.bar = bar;

foo.bar(1, 2);
// expect: bar
// expect: 1
// expect: 2
""",
        ),
        DloxDatasetLeafImpl(
          name: "set_evaluation_order",
          source: r"""
undefined1.bar // Runtime error: Undefined variable 'undefined1'.
  = undefined2;
""",
        ),
        DloxDatasetLeafImpl(
          name: "method_binds_this",
          source: r"""
class Foo {
  sayName(a) {
    print this.name;
    print a;
  }
}

var foo1 = Foo();
foo1.name = "foo1";

var foo2 = Foo();
foo2.name = "foo2";

// Store the method reference on another object.
foo2.fn = foo1.sayName;
// Still retains original receiver.
foo2.fn(1);
// expect: foo1
// expect: 1
""",
        ),
        DloxDatasetLeafImpl(
          name: "set_on_num",
          source: r"""
123.foo = "value"; // Runtime error: Only instances have fields.
""",
        ),
        DloxDatasetLeafImpl(
          name: "get_on_class",
          source: r"""
class Foo {}
Foo.bar; // Runtime error: Only instances have properties.
""",
        ),
        DloxDatasetLeafImpl(
          name: "get_and_set_method",
          source: r"""
// Bound methods have identity equality.
class Foo {
  method(a) {
    print "method";
    print a;
  }
  other(a) {
    print "other";
    print a;
  }
}

var foo = Foo();
var method = foo.method;

// Setting a property shadows the instance method.
foo.method = foo.other;
foo.method(1);
// expect: other
// expect: 1

// The old method handle still points to the original method.
method(2);
// expect: method
// expect: 2
""",
        ),
        DloxDatasetLeafImpl(
          name: "get_on_bool",
          source: r"""
true.foo; // Runtime error: Only instances have properties.
""",
        ),
        DloxDatasetLeafImpl(
          name: "get_on_num",
          source: r"""
123.foo; // Runtime error: Only instances have properties.
""",
        ),
        DloxDatasetLeafImpl(
          name: "undefined",
          source: r"""
class Foo {}
var foo = Foo();

foo.bar; // Runtime error: Undefined property 'bar'.
""",
        ),
      ];
}

class DloxDataset_print with DloxDatasetInternal {
  const DloxDataset_print();

  @override
  String get name => "print";

  @override
  List<DloxDataset> get children => const [
        DloxDatasetLeafImpl(
          name: "missing_argument",
          source: r"""
print; // Error at ';': Expect expression.

""",
        ),
      ];
}

class DloxDataset_number with DloxDatasetInternal {
  const DloxDataset_number();

  @override
  String get name => "number";

  @override
  List<DloxDataset> get children => const [
        DloxDatasetLeafImpl(
          name: "decimal_point_at_eof",
          source: r"""
123.
// Error at end: Expect property name after '.'.""",
        ),
        DloxDatasetLeafImpl(
          name: "nan_equality",
          source: r"""
var nan = 0/0;

print nan == 0; // expect: false
print nan != 1; // expect: true

// NaN is not equal to self.
print nan == nan; // expect: false
print nan != nan; // expect: true
""",
        ),
        DloxDatasetLeafImpl(
          name: "literals",
          source: r"""
print 123;     // expect: 123
print 987654;  // expect: 987654
print 0;       // expect: 0
print -0;      // expect: 0

print 123.456; // expect: 123.456
print -0.001;  // expect: -0.001
""",
        ),
        DloxDatasetLeafImpl(
          name: "leading_dot",
          source: r"""
.123; // Error at '.': Expect expression.

""",
        ),
        DloxDatasetLeafImpl(
          name: "trailing_dot",
          source: r"""
123.; // Error at ';': Expect property name after '.'.

""",
        ),
      ];
}

class DloxDataset_call with DloxDatasetInternal {
  const DloxDataset_call();

  @override
  String get name => "call";

  @override
  List<DloxDataset> get children => const [
        DloxDatasetLeafImpl(
          name: "nil",
          source: r"""
nil(); // Runtime error: Can only call functions and classes.
""",
        ),
        DloxDatasetLeafImpl(
          name: "bool",
          source: r"""
true(); // Runtime error: Can only call functions and classes.
""",
        ),
        DloxDatasetLeafImpl(
          name: "num",
          source: r"""
123(); // Runtime error: Can only call functions and classes.
""",
        ),
        DloxDatasetLeafImpl(
          name: "object",
          source: r"""
class Foo {}

var foo = Foo();
foo(); // Runtime error: Can only call functions and classes.
""",
        ),
        DloxDatasetLeafImpl(
          name: "string",
          source: r"""
"str"(); // Runtime error: Can only call functions and classes.
""",
        ),
      ];
}

class DloxDataset_logical_operator with DloxDatasetInternal {
  const DloxDataset_logical_operator();

  @override
  String get name => "logical_operator";

  @override
  List<DloxDataset> get children => const [
        DloxDatasetLeafImpl(
          name: "and",
          source: r"""
// Note: These tests implicitly depend on ints being truthy.

// Return the first non-true argument.
print false and 1; // expect: false
print true and 1; // expect: 1
print 1 and 2 and false; // expect: false

// Return the last argument if all are true.
print 1 and true; // expect: true
print 1 and 2 and 3; // expect: 3

// Short-circuit at the first false argument.
var a = "before";
var b = "before";
(a = true) and
    (b = false) and
    (a = "bad");
print a; // expect: true
print b; // expect: false
""",
        ),
        DloxDatasetLeafImpl(
          name: "or",
          source: r"""
// Note: These tests implicitly depend on ints being truthy.

// Return the first true argument.
print 1 or true; // expect: 1
print false or 1; // expect: 1
print false or false or true; // expect: true

// Return the last argument if all are false.
print false or false; // expect: false
print false or false or false; // expect: false

// Short-circuit at the first true argument.
var a = "before";
var b = "before";
(a = false) or
    (b = true) or
    (a = "bad");
print a; // expect: false
print b; // expect: true
""",
        ),
        DloxDatasetLeafImpl(
          name: "and_truth",
          source: r"""
// False and nil are false.
print false and "bad"; // expect: false
print nil and "bad"; // expect: nil

// Everything else is true.
print true and "ok"; // expect: ok
print 0 and "ok"; // expect: ok
print "" and "ok"; // expect: ok
""",
        ),
        DloxDatasetLeafImpl(
          name: "or_truth",
          source: r"""
// False and nil are false.
print false or "ok"; // expect: ok
print nil or "ok"; // expect: ok

// Everything else is true.
print true or "ok"; // expect: true
print 0 or "ok"; // expect: 0
print "s" or "ok"; // expect: s
""",
        ),
      ];
}

class DloxDataset_inheritance with DloxDatasetInternal {
  const DloxDataset_inheritance();

  @override
  String get name => "inheritance";

  @override
  List<DloxDataset> get children => const [
        DloxDatasetLeafImpl(
          name: "inherit_from_nil",
          source: r"""
var Nil = nil;
class Foo < Nil {} // Runtime error: Superclass must be a class.
""",
        ),
        DloxDatasetLeafImpl(
          name: "inherit_from_function",
          source: r"""
fun foo() {}

class Subclass < foo {} // Runtime error: Superclass must be a class.
""",
        ),
        DloxDatasetLeafImpl(
          name: "parenthesized_superclass",
          source: r"""
class Foo {}

class Bar < (Foo) {} // Error at '(': Expect superclass name.

""",
        ),
        DloxDatasetLeafImpl(
          name: "set_fields_from_base_class",
          source: r"""
class Foo {
  foo(a, b) {
    this.field1 = a;
    this.field2 = b;
  }

  fooPrint() {
    print this.field1;
    print this.field2;
  }
}

class Bar < Foo {
  bar(a, b) {
    this.field1 = a;
    this.field2 = b;
  }

  barPrint() {
    print this.field1;
    print this.field2;
  }
}

var bar = Bar();
bar.foo("foo 1", "foo 2");
bar.fooPrint();
// expect: foo 1
// expect: foo 2

bar.bar("bar 1", "bar 2");
bar.barPrint();
// expect: bar 1
// expect: bar 2

bar.fooPrint();
// expect: bar 1
// expect: bar 2
""",
        ),
        DloxDatasetLeafImpl(
          name: "inherit_from_number",
          source: r"""
var Number = 123;
class Foo < Number {} // Runtime error: Superclass must be a class.
""",
        ),
        DloxDatasetLeafImpl(
          name: "inherit_methods",
          source: r"""
class Foo {
  methodOnFoo() { print "foo"; }
  override() { print "foo"; }
}

class Bar < Foo {
  methodOnBar() { print "bar"; }
  override() { print "bar"; }
}

var bar = Bar();
bar.methodOnFoo(); // expect: foo
bar.methodOnBar(); // expect: bar
bar.override(); // expect: bar
""",
        ),
        DloxDatasetLeafImpl(
          name: "constructor",
          source: r"""
class A {
  init(param) {
    this.field = param;
  }

  test() {
    print this.field;
  }
}

class B < A {}

var b = B("value");
b.test(); // expect: value
""",
        ),
      ];
}

class DloxDataset_super with DloxDatasetInternal {
  const DloxDataset_super();

  @override
  String get name => "super";

  @override
  List<DloxDataset> get children => const [
        DloxDatasetLeafImpl(
          name: "no_superclass_method",
          source: r"""
class Base {}

class Derived < Base {
  foo() {
    super.doesNotExist(1); // Runtime error: Undefined property 'doesNotExist'.
  }
}

Derived().foo();
""",
        ),
        DloxDatasetLeafImpl(
          name: "call_same_method",
          source: r"""
class Base {
  foo() {
    print "Base.foo()";
  }
}

class Derived < Base {
  foo() {
    print "Derived.foo()";
    super.foo();
  }
}

Derived().foo();
// expect: Derived.foo()
// expect: Base.foo()
""",
        ),
        DloxDatasetLeafImpl(
          name: "no_superclass_call",
          source: r"""
class Base {
  foo() {
    super.doesNotExist(1); // Error at 'super': Can't use 'super' in a class with no superclass.
  }
}

Base().foo();
""",
        ),
        DloxDatasetLeafImpl(
          name: "no_superclass_bind",
          source: r"""
class Base {
  foo() {
    super.doesNotExist; // Error at 'super': Can't use 'super' in a class with no superclass.
  }
}

Base().foo();
""",
        ),
        DloxDatasetLeafImpl(
          name: "parenthesized",
          source: r"""
class A {
  method() {}
}

class B < A {
  method() {
    (super).method();  // Error at ')': Expect '.' after 'super'.
  }
}
""",
        ),
        DloxDatasetLeafImpl(
          name: "this_in_superclass_method",
          source: r"""
class Base {
  init(a) {
    this.a = a;
  }
}

class Derived < Base {
  init(a, b) {
    super.init(a);
    this.b = b;
  }
}

var derived = Derived("a", "b");
print derived.a; // expect: a
print derived.b; // expect: b
""",
        ),
        DloxDatasetLeafImpl(
          name: "closure",
          source: r"""
class Base {
  toString() { return "Base"; }
}

class Derived < Base {
  getClosure() {
    fun closure() {
      return super.toString();
    }
    return closure;
  }

  toString() { return "Derived"; }
}

var closure = Derived().getClosure();
print closure(); // expect: Base
""",
        ),
        DloxDatasetLeafImpl(
          name: "super_in_top_level_function",
          source: r"""
  super.bar(); // Error at 'super': Can't use 'super' outside of a class.
fun foo() {
}""",
        ),
        DloxDatasetLeafImpl(
          name: "call_other_method",
          source: r"""
class Base {
  foo() {
    print "Base.foo()";
  }
}

class Derived < Base {
  bar() {
    print "Derived.bar()";
    super.foo();
  }
}

Derived().bar();
// expect: Derived.bar()
// expect: Base.foo()
""",
        ),
        DloxDatasetLeafImpl(
          name: "missing_arguments",
          source: r"""
class Base {
  foo(a, b) {
    print "Base.foo(" + a + ", " + b + ")";
  }
}

class Derived < Base {
  foo() {
    super.foo(1); // Runtime error: Expected 2 arguments but got 1.
  }
}

Derived().foo();
""",
        ),
        DloxDatasetLeafImpl(
          name: "super_in_closure_in_inherited_method",
          source: r"""
class A {
  say() {
    print "A";
  }
}

class B < A {
  getClosure() {
    fun closure() {
      super.say();
    }
    return closure;
  }

  say() {
    print "B";
  }
}

class C < B {
  say() {
    print "C";
  }
}

C().getClosure()(); // expect: A
""",
        ),
        DloxDatasetLeafImpl(
          name: "super_in_inherited_method",
          source: r"""
class A {
  say() {
    print "A";
  }
}

class B < A {
  test() {
    super.say();
  }

  say() {
    print "B";
  }
}

class C < B {
  say() {
    print "C";
  }
}

C().test(); // expect: A
""",
        ),
        DloxDatasetLeafImpl(
          name: "super_without_dot",
          source: r"""
class A {}

class B < A {
  method() {
    super; // Error at ';': Expect '.' after 'super'.
  }
}
""",
        ),
        DloxDatasetLeafImpl(
          name: "indirectly_inherited",
          source: r"""
class A {
  foo() {
    print "A.foo()";
  }
}

class B < A {}

class C < B {
  foo() {
    print "C.foo()";
    super.foo();
  }
}

C().foo();
// expect: C.foo()
// expect: A.foo()
""",
        ),
        DloxDatasetLeafImpl(
          name: "super_at_top_level",
          source: r"""
super.foo("bar"); // Error at 'super': Can't use 'super' outside of a class.
super.foo; // Error at 'super': Can't use 'super' outside of a class.
""",
        ),
        DloxDatasetLeafImpl(
          name: "super_without_name",
          source: r"""
class A {}

class B < A {
  method() {
    super.; // Error at ';': Expect superclass method name.
  }
}
""",
        ),
        DloxDatasetLeafImpl(
          name: "extra_arguments",
          source: r"""
class Base {
  foo(a, b) {
    print "Base.foo(" + a + ", " + b + ")";
  }
}

class Derived < Base {
  foo() {
    print "Derived.foo()"; // expect: Derived.foo()
    super.foo("a", "b", "c", "d"); // Runtime error: Expected 2 arguments but got 4.
  }
}

Derived().foo();
""",
        ),
        DloxDatasetLeafImpl(
          name: "bound_method",
          source: r"""
class A {
  method(arg) {
    print "A.method(" + arg + ")";
  }
}

class B < A {
  getClosure() {
    return super.method;
  }

  method(arg) {
    print "B.method(" + arg + ")";
  }
}


var closure = B().getClosure();
closure("arg"); // expect: A.method(arg)
""",
        ),
        DloxDatasetLeafImpl(
          name: "constructor",
          source: r"""
class Base {
  init(a, b) {
    print "Base.init(" + a + ", " + b + ")";
  }
}

class Derived < Base {
  init() {
    print "Derived.init()";
    super.init("a", "b");
  }
}

Derived();
// expect: Derived.init()
// expect: Base.init(a, b)
""",
        ),
        DloxDatasetLeafImpl(
          name: "reassign_superclass",
          source: r"""
class Base {
  method() {
    print "Base.method()";
  }
}

class Derived < Base {
  method() {
    super.method();
  }
}

class OtherBase {
  method() {
    print "OtherBase.method()";
  }
}

var derived = Derived();
derived.method(); // expect: Base.method()
Base = OtherBase;
derived.method(); // expect: Base.method()
""",
        ),
      ];
}

class DloxDataset_bool with DloxDatasetInternal {
  const DloxDataset_bool();

  @override
  String get name => "bool";

  @override
  List<DloxDataset> get children => const [
        DloxDatasetLeafImpl(
          name: "equality",
          source: r"""
print true == true;    // expect: true
print true == false;   // expect: false
print false == true;   // expect: false
print false == false;  // expect: true

// Not equal to other types.
print true == 1;        // expect: false
print false == 0;       // expect: false
print true == "true";   // expect: false
print false == "false"; // expect: false
print false == "";      // expect: false

print true != true;    // expect: false
print true != false;   // expect: true
print false != true;   // expect: true
print false != false;  // expect: false

// Not equal to other types.
print true != 1;        // expect: true
print false != 0;       // expect: true
print true != "true";   // expect: true
print false != "false"; // expect: true
print false != "";      // expect: true
""",
        ),
        DloxDatasetLeafImpl(
          name: "not",
          source: r"""
print !true;    // expect: false
print !false;   // expect: true
print !!true;   // expect: true
""",
        ),
      ];
}

class DloxDataset_for with DloxDatasetInternal {
  const DloxDataset_for();

  @override
  String get name => "for";

  @override
  List<DloxDataset> get children => const [
        DloxDatasetLeafImpl(
          name: "return_closure",
          source: r"""
fun f() {
  for (;;) {
    var i = "i";
    fun g() { print i; }
    return g;
  }
}

var h = f();
h(); // expect: i
""",
        ),
        DloxDatasetLeafImpl(
          name: "scope",
          source: r"""
{
  var i = "before";

  // New variable is in inner scope.
  for (var i = 0; i < 1; i = i + 1) {
    print i; // expect: 0

    // Loop body is in second inner scope.
    var i = -1;
    print i; // expect: -1
  }
}

{
  // New variable shadows outer variable.
  for (var i = 0; i > 0; i = i + 1) {}

  // Goes out of scope after loop.
  var i = "after";
  print i; // expect: after

  // Can reuse an existing variable.
  for (i = 0; i < 1; i = i + 1) {
    print i; // expect: 0
  }
}
""",
        ),
        DloxDatasetLeafImpl(
          name: "var_in_body",
          source: r"""
for (;;) var foo; // Error at 'var': Expect expression.

""",
        ),
        DloxDatasetLeafImpl(
          name: "syntax",
          source: r"""
// Single-expression body.
for (var c = 0; c < 3;) print c = c + 1;
// expect: 1
// expect: 2
// expect: 3

// Block body.
for (var a = 0; a < 3; a = a + 1) {
  print a;
}
// expect: 0
// expect: 1
// expect: 2

// No clauses.
fun foo() {
  for (;;) return "done";
}
print foo(); // expect: done

// No variable.
var i = 0;
for (; i < 2; i = i + 1) print i;
// expect: 0
// expect: 1

// No condition.
fun bar() {
  for (var i = 0;; i = i + 1) {
    print i;
    if (i >= 2) return;
  }
}
bar();
// expect: 0
// expect: 1
// expect: 2

// No increment.
for (var i = 0; i < 2;) {
  print i;
  i = i + 1;
}
// expect: 0
// expect: 1

// Statement bodies.
for (; false;) if (true) 1; else 2;
for (; false;) while (true) 1;
for (; false;) for (;;) 1;
""",
        ),
        DloxDatasetLeafImpl(
          name: "return_inside",
          source: r"""
fun f() {
  for (;;) {
    var i = "i";
    return i;
  }
}

print f();
// expect: i
""",
        ),
        DloxDatasetLeafImpl(
          name: "statement_initializer",
          source: r"""
// [disabled] Error at '{': Expect expression.
// [disabled] Error at ')': Expect ';' after expression.
// for ({}; a < 2; a = a + 1) {}
""",
        ),
        DloxDatasetLeafImpl(
          name: "statement_increment",
          source: r"""

// for (var a = 1; a < 2; {}) {} // [disabled] Error at '{': Expect expression.
""",
        ),
        DloxDatasetLeafImpl(
          name: "statement_condition",
          source: r"""
// [disabled] Error at '{': Expect expression.
// [disabled] Error at ')': Expect ';' after expression.
// for (var a = 1; {}; a = a + 1) {}
""",
        ),
        DloxDatasetLeafImpl(
          name: "closure_in_body",
          source: r"""
var f1;
var f2;
var f3;

for (var i = 1; i < 4; i = i + 1) {
  var j = i;
  fun f() {
    print i;
    print j;
  }

  if (j == 1) f1 = f;
  else if (j == 2) f2 = f;
  else f3 = f;
}

f1(); // expect: 4
      // expect: 1
f2(); // expect: 4
      // expect: 2
f3(); // expect: 4
      // expect: 3
""",
        ),
        DloxDatasetLeafImpl(
          name: "class_in_body",
          source: r"""
for (;;) class Foo {} // Error at 'class': Expect expression.
""",
        ),
        DloxDatasetLeafImpl(
          name: "fun_in_body",
          source: r"""
for (;;) fun foo() {} // Error at 'fun': Expect expression.
""",
        ),
      ];
}

class DloxDataset_class with DloxDatasetInternal {
  const DloxDataset_class();

  @override
  String get name => "class";

  @override
  List<DloxDataset> get children => const [
        DloxDatasetLeafImpl(
          name: "empty",
          source: r"""
class Foo {}

print Foo; // expect: Foo
""",
        ),
        DloxDatasetLeafImpl(
          name: "local_inherit_self",
          source: r"""
{
  class Foo < Foo {} // Error at 'Foo': A class can't inherit from itself.
}
""",
        ),
        DloxDatasetLeafImpl(
          name: "local_inherit_other",
          source: r"""
class A {}

fun f() {
  class B < A {}
  return B;
}

print f(); // expect: B
""",
        ),
        DloxDatasetLeafImpl(
          name: "inherited_method",
          source: r"""
class Foo {
  inFoo() {
    print "in foo";
  }
}

class Bar < Foo {
  inBar() {
    print "in bar";
  }
}

class Baz < Bar {
  inBaz() {
    print "in baz";
  }
}

var baz = Baz();
baz.inFoo(); // expect: in foo
baz.inBar(); // expect: in bar
baz.inBaz(); // expect: in baz
""",
        ),
        DloxDatasetLeafImpl(
          name: "reference_self",
          source: r"""
class Foo {
  returnSelf() {
    return Foo;
  }
}

print Foo().returnSelf(); // expect: Foo
""",
        ),
        DloxDatasetLeafImpl(
          name: "inherit_self",
          source: r"""
class Foo < Foo {} // Error at 'Foo': A class can't inherit from itself.
""",
        ),
        DloxDatasetLeafImpl(
          name: "local_reference_self",
          source: r"""
{
  class Foo {
    returnSelf() {
      return Foo;
    }
  }

  print Foo().returnSelf(); // expect: Foo
}
""",
        ),
      ];
}

class DloxDataset_this with DloxDatasetInternal {
  const DloxDataset_this();

  @override
  String get name => "this";

  @override
  List<DloxDataset> get children => const [
        DloxDatasetLeafImpl(
          name: "this_in_method",
          source: r"""
class Foo {
  bar() { return this; }
  baz() { return "baz"; }
}

print Foo().bar().baz(); // expect: baz
""",
        ),
        DloxDatasetLeafImpl(
          name: "this_at_top_level",
          source: r"""
this; // Error at 'this': Can't use 'this' outside of a class.
""",
        ),
        DloxDatasetLeafImpl(
          name: "closure",
          source: r"""
class Foo {
  getClosure() {
    fun closure() {
      return this.toString();
    }
    return closure;
  }

  toString() { return "Foo"; }
}

var closure = Foo().getClosure();
print closure(); // expect: Foo
""",
        ),
        DloxDatasetLeafImpl(
          name: "this_in_top_level_function",
          source: r"""
fun foo() {
  this; // Error at 'this': Can't use 'this' outside of a class.
}
""",
        ),
        DloxDatasetLeafImpl(
          name: "nested_closure",
          source: r"""
class Foo {
  getClosure() {
    fun f() {
      fun g() {
        fun h() {
          return this.toString();
        }
        return h;
      }
      return g;
    }
    return f;
  }

  toString() { return "Foo"; }
}

var closure = Foo().getClosure();
print closure()()(); // expect: Foo
""",
        ),
        DloxDatasetLeafImpl(
          name: "nested_class",
          source: r"""
class Outer {
  method() {
    print this; // expect: Outer instance

    fun f() {
      print this; // expect: Outer instance

      class Inner {
        method() {
          print this; // expect: Inner instance
        }
      }

      Inner().method();
    }
    f();
  }
}

Outer().method();
""",
        ),
      ];
}

class DloxDataset_string with DloxDatasetInternal {
  const DloxDataset_string();

  @override
  String get name => "string";

  @override
  List<DloxDataset> get children => const [
        DloxDatasetLeafImpl(
          name: "error_after_multiline",
          source: r"""
// Tests that we correctly track the line info across multiline strings.
var a = "1
2
3
";

err; // // Runtime error: Undefined variable 'err'.""",
        ),
        DloxDatasetLeafImpl(
          name: "literals",
          source: r"""
print "(" + "" + ")";   // expect: ()
print "a string"; // expect: a string

// Non-ASCII.
print "A~¶Þॐஃ"; // expect: A~¶Þॐஃ
""",
        ),
        DloxDatasetLeafImpl(
          name: "multiline",
          source: r"""
var a = "1
2
3";
print a;
// expect: 1
// expect: 2
// expect: 3
""",
        ),
      ];
}

class DloxDataset_regression with DloxDatasetInternal {
  const DloxDataset_regression();

  @override
  String get name => "regression";

  @override
  List<DloxDataset> get children => const [
        DloxDatasetLeafImpl(
          name: "40",
          source: r"""
fun caller(g) {
  g();
  // g should be a function, not nil.
  print g == nil; // expect: false
}

fun callCaller() {
  var capturedVar = "before";
  var a = "a";

  fun f() {
    // Commenting the next line out prevents the bug!
    capturedVar = "after";

    // Returning anything also fixes it, even nil:
    //return nil;
  }

  caller(f);
}

callCaller();
""",
        ),
        DloxDatasetLeafImpl(
          name: "394",
          source: r"""
{
  class A {}
  class B < A {}
  print B; // expect: B
}
""",
        ),
      ];
}

class DloxDataset_while with DloxDatasetInternal {
  const DloxDataset_while();

  @override
  String get name => "while";

  @override
  List<DloxDataset> get children => const [
        DloxDatasetLeafImpl(
          name: "return_closure",
          source: r"""
fun f() {
  while (true) {
    var i = "i";
    fun g() { print i; }
    return g;
  }
}

var h = f();
h(); // expect: i
""",
        ),
        DloxDatasetLeafImpl(
          name: "var_in_body",
          source: r"""
while (true) var foo; // Error at 'var': Expect expression.

""",
        ),
        DloxDatasetLeafImpl(
          name: "syntax",
          source: r"""
// Single-expression body.
var c = 0;
while (c < 3) print c = c + 1;
// expect: 1
// expect: 2
// expect: 3

// Block body.
var a = 0;
while (a < 3) {
  print a;
  a = a + 1;
}
// expect: 0
// expect: 1
// expect: 2

// Statement bodies.
while (false) if (true) 1; else 2;
while (false) while (true) 1;
while (false) for (;;) 1;
""",
        ),
        DloxDatasetLeafImpl(
          name: "return_inside",
          source: r"""
fun f() {
  while (true) {
    var i = "i";
    return i;
  }
}

print f();
// expect: i
""",
        ),
        DloxDatasetLeafImpl(
          name: "closure_in_body",
          source: r"""
var f1;
var f2;
var f3;

var i = 1;
while (i < 4) {
  var j = i;
  fun f() { print j; }

  if (j == 1) f1 = f;
  else if (j == 2) f2 = f;
  else f3 = f;

  i = i + 1;
}

f1(); // expect: 1
f2(); // expect: 2
f3(); // expect: 3
""",
        ),
        DloxDatasetLeafImpl(
          name: "class_in_body",
          source: r"""
while (true) class Foo {} // Error at 'class': Expect expression.

""",
        ),
        DloxDatasetLeafImpl(
          name: "fun_in_body",
          source: r"""
while (true) fun foo() {} // Error at 'fun': Expect expression.

""",
        ),
      ];
}

class DloxDataset_method with DloxDatasetInternal {
  const DloxDataset_method();

  @override
  String get name => "method";

  @override
  List<DloxDataset> get children => const [
        DloxDatasetLeafImpl(
          name: "empty_block",
          source: r"""
class Foo {
  bar() {}
}

print Foo().bar(); // expect: nil
""",
        ),
        DloxDatasetLeafImpl(
          name: "arity",
          source: r"""
class Foo {
  method0() { return "no args"; }
  method1(a) { return a; }
  method2(a, b) { return a + b; }
  method3(a, b, c) { return a + b + c; }
  method4(a, b, c, d) { return a + b + c + d; }
  method5(a, b, c, d, e) { return a + b + c + d + e; }
  method6(a, b, c, d, e, f) { return a + b + c + d + e + f; }
  method7(a, b, c, d, e, f, g) { return a + b + c + d + e + f + g; }
  method8(a, b, c, d, e, f, g, h) { return a + b + c + d + e + f + g + h; }
}

var foo = Foo();
print foo.method0(); // expect: no args
print foo.method1(1); // expect: 1
print foo.method2(1, 2); // expect: 3
print foo.method3(1, 2, 3); // expect: 6
print foo.method4(1, 2, 3, 4); // expect: 10
print foo.method5(1, 2, 3, 4, 5); // expect: 15
print foo.method6(1, 2, 3, 4, 5, 6); // expect: 21
print foo.method7(1, 2, 3, 4, 5, 6, 7); // expect: 28
print foo.method8(1, 2, 3, 4, 5, 6, 7, 8); // expect: 36
""",
        ),
        DloxDatasetLeafImpl(
          name: "refer_to_name",
          source: r"""
class Foo {
  method() {
    print method; // Runtime error: Undefined variable 'method'.
  }
}

Foo().method();
""",
        ),
        DloxDatasetLeafImpl(
          name: "too_many_arguments",
          source: r"""
{
  var a = 1;
  true.method(
     a, // 1
     a, // 2
     a, // 3
     a, // 4
     a, // 5
     a, // 6
     a, // 7
     a, // 8
     a, // 9
     a, // 10
     a, // 11
     a, // 12
     a, // 13
     a, // 14
     a, // 15
     a, // 16
     a, // 17
     a, // 18
     a, // 19
     a, // 20
     a, // 21
     a, // 22
     a, // 23
     a, // 24
     a, // 25
     a, // 26
     a, // 27
     a, // 28
     a, // 29
     a, // 30
     a, // 31
     a, // 32
     a, // 33
     a, // 34
     a, // 35
     a, // 36
     a, // 37
     a, // 38
     a, // 39
     a, // 40
     a, // 41
     a, // 42
     a, // 43
     a, // 44
     a, // 45
     a, // 46
     a, // 47
     a, // 48
     a, // 49
     a, // 50
     a, // 51
     a, // 52
     a, // 53
     a, // 54
     a, // 55
     a, // 56
     a, // 57
     a, // 58
     a, // 59
     a, // 60
     a, // 61
     a, // 62
     a, // 63
     a, // 64
     a, // 65
     a, // 66
     a, // 67
     a, // 68
     a, // 69
     a, // 70
     a, // 71
     a, // 72
     a, // 73
     a, // 74
     a, // 75
     a, // 76
     a, // 77
     a, // 78
     a, // 79
     a, // 80
     a, // 81
     a, // 82
     a, // 83
     a, // 84
     a, // 85
     a, // 86
     a, // 87
     a, // 88
     a, // 89
     a, // 90
     a, // 91
     a, // 92
     a, // 93
     a, // 94
     a, // 95
     a, // 96
     a, // 97
     a, // 98
     a, // 99
     a, // 100
     a, // 101
     a, // 102
     a, // 103
     a, // 104
     a, // 105
     a, // 106
     a, // 107
     a, // 108
     a, // 109
     a, // 110
     a, // 111
     a, // 112
     a, // 113
     a, // 114
     a, // 115
     a, // 116
     a, // 117
     a, // 118
     a, // 119
     a, // 120
     a, // 121
     a, // 122
     a, // 123
     a, // 124
     a, // 125
     a, // 126
     a, // 127
     a, // 128
     a, // 129
     a, // 130
     a, // 131
     a, // 132
     a, // 133
     a, // 134
     a, // 135
     a, // 136
     a, // 137
     a, // 138
     a, // 139
     a, // 140
     a, // 141
     a, // 142
     a, // 143
     a, // 144
     a, // 145
     a, // 146
     a, // 147
     a, // 148
     a, // 149
     a, // 150
     a, // 151
     a, // 152
     a, // 153
     a, // 154
     a, // 155
     a, // 156
     a, // 157
     a, // 158
     a, // 159
     a, // 160
     a, // 161
     a, // 162
     a, // 163
     a, // 164
     a, // 165
     a, // 166
     a, // 167
     a, // 168
     a, // 169
     a, // 170
     a, // 171
     a, // 172
     a, // 173
     a, // 174
     a, // 175
     a, // 176
     a, // 177
     a, // 178
     a, // 179
     a, // 180
     a, // 181
     a, // 182
     a, // 183
     a, // 184
     a, // 185
     a, // 186
     a, // 187
     a, // 188
     a, // 189
     a, // 190
     a, // 191
     a, // 192
     a, // 193
     a, // 194
     a, // 195
     a, // 196
     a, // 197
     a, // 198
     a, // 199
     a, // 200
     a, // 201
     a, // 202
     a, // 203
     a, // 204
     a, // 205
     a, // 206
     a, // 207
     a, // 208
     a, // 209
     a, // 210
     a, // 211
     a, // 212
     a, // 213
     a, // 214
     a, // 215
     a, // 216
     a, // 217
     a, // 218
     a, // 219
     a, // 220
     a, // 221
     a, // 222
     a, // 223
     a, // 224
     a, // 225
     a, // 226
     a, // 227
     a, // 228
     a, // 229
     a, // 230
     a, // 231
     a, // 232
     a, // 233
     a, // 234
     a, // 235
     a, // 236
     a, // 237
     a, // 238
     a, // 239
     a, // 240
     a, // 241
     a, // 242
     a, // 243
     a, // 244
     a, // 245
     a, // 246
     a, // 247
     a, // 248
     a, // 249
     a, // 250
     a, // 251
     a, // 252
     a, // 253
     a, // 254
     a, // 255
     a); // Error at 'a': Can't have more than 255 arguments.
}
""",
        ),
        DloxDatasetLeafImpl(
          name: "print_bound_method",
          source: r"""
class Foo {
  method() { }
}
var foo = Foo();
print foo.method; // expect: <fn method>
""",
        ),
        DloxDatasetLeafImpl(
          name: "missing_arguments",
          source: r"""
class Foo {
  method(a, b) {}
}

Foo().method(1); // Runtime error: Expected 2 arguments but got 1.
""",
        ),
        DloxDatasetLeafImpl(
          name: "not_found",
          source: r"""
class Foo {}

Foo().unknown(); // Runtime error: Undefined property 'unknown'.
""",
        ),
        DloxDatasetLeafImpl(
          name: "too_many_parameters",
          source: r"""
class Foo {
  // 256 parameters.
  method(
    a1,
    a2,
    a3,
    a4,
    a5,
    a6,
    a7,
    a8,
    a9,
    a10,
    a11,
    a12,
    a13,
    a14,
    a15,
    a16,
    a17,
    a18,
    a19,
    a20,
    a21,
    a22,
    a23,
    a24,
    a25,
    a26,
    a27,
    a28,
    a29,
    a30,
    a31,
    a32,
    a33,
    a34,
    a35,
    a36,
    a37,
    a38,
    a39,
    a40,
    a41,
    a42,
    a43,
    a44,
    a45,
    a46,
    a47,
    a48,
    a49,
    a50,
    a51,
    a52,
    a53,
    a54,
    a55,
    a56,
    a57,
    a58,
    a59,
    a60,
    a61,
    a62,
    a63,
    a64,
    a65,
    a66,
    a67,
    a68,
    a69,
    a70,
    a71,
    a72,
    a73,
    a74,
    a75,
    a76,
    a77,
    a78,
    a79,
    a80,
    a81,
    a82,
    a83,
    a84,
    a85,
    a86,
    a87,
    a88,
    a89,
    a90,
    a91,
    a92,
    a93,
    a94,
    a95,
    a96,
    a97,
    a98,
    a99,
    a100,
    a101,
    a102,
    a103,
    a104,
    a105,
    a106,
    a107,
    a108,
    a109,
    a110,
    a111,
    a112,
    a113,
    a114,
    a115,
    a116,
    a117,
    a118,
    a119,
    a120,
    a121,
    a122,
    a123,
    a124,
    a125,
    a126,
    a127,
    a128,
    a129,
    a130,
    a131,
    a132,
    a133,
    a134,
    a135,
    a136,
    a137,
    a138,
    a139,
    a140,
    a141,
    a142,
    a143,
    a144,
    a145,
    a146,
    a147,
    a148,
    a149,
    a150,
    a151,
    a152,
    a153,
    a154,
    a155,
    a156,
    a157,
    a158,
    a159,
    a160,
    a161,
    a162,
    a163,
    a164,
    a165,
    a166,
    a167,
    a168,
    a169,
    a170,
    a171,
    a172,
    a173,
    a174,
    a175,
    a176,
    a177,
    a178,
    a179,
    a180,
    a181,
    a182,
    a183,
    a184,
    a185,
    a186,
    a187,
    a188,
    a189,
    a190,
    a191,
    a192,
    a193,
    a194,
    a195,
    a196,
    a197,
    a198,
    a199,
    a200,
    a201,
    a202,
    a203,
    a204,
    a205,
    a206,
    a207,
    a208,
    a209,
    a210,
    a211,
    a212,
    a213,
    a214,
    a215,
    a216,
    a217,
    a218,
    a219,
    a220,
    a221,
    a222,
    a223,
    a224,
    a225,
    a226,
    a227,
    a228,
    a229,
    a230,
    a231,
    a232,
    a233,
    a234,
    a235,
    a236,
    a237,
    a238,
    a239,
    a240,
    a241,
    a242,
    a243,
    a244,
    a245,
    a246,
    a247,
    a248,
    a249,
    a250,
    a251,
    a252,
    a253,
    a254,
    a255, a) {} // Error at 'a': Can't have more than 255 parameters.
}
""",
        ),
        DloxDatasetLeafImpl(
          name: "extra_arguments",
          source: r"""
class Foo {
  method(a, b) {
    print a;
    print b;
  }
}

Foo().method(1, 2, 3, 4); // Runtime error: Expected 2 arguments but got 4.
""",
        ),
      ];
}

class DloxDataset_operator with DloxDatasetInternal {
  const DloxDataset_operator();

  @override
  String get name => "operator";

  @override
  List<DloxDataset> get children => const [
        DloxDatasetLeafImpl(
          name: "add_num_nil",
          source: r"""
1 + nil; // Runtime error: Operands must numbers, strings, lists or maps.
""",
        ),
        DloxDatasetLeafImpl(
          name: "equals_method",
          source: r"""
// Bound methods have identity equality.
class Foo {
  method() {}
}

var foo = Foo();
var fooMethod = foo.method;

// Same bound method.
print fooMethod == fooMethod; // expect: true

// Different closurizations.
print foo.method == foo.method; // expect: false
""",
        ),
        DloxDatasetLeafImpl(
          name: "equals_class",
          source: r"""
// Bound methods have identity equality.
class Foo {}
class Bar {}

print Foo == Foo; // expect: true
print Foo == Bar; // expect: false
print Bar == Foo; // expect: false
print Bar == Bar; // expect: true

print Foo == "Foo"; // expect: false
print Foo == nil;   // expect: false
print Foo == 123;   // expect: false
print Foo == true;  // expect: false
""",
        ),
        DloxDatasetLeafImpl(
          name: "subtract_num_nonnum",
          source: r"""
1 - "1"; // Runtime error: Operands must be numbers.
""",
        ),
        DloxDatasetLeafImpl(
          name: "multiply",
          source: r"""
print 5 * 3; // expect: 15
print 12.34 * 0.3; // expect: 3.702
""",
        ),
        DloxDatasetLeafImpl(
          name: "negate",
          source: r"""
print -(3); // expect: -3
print --(3); // expect: 3
print ---(3); // expect: -3
""",
        ),
        DloxDatasetLeafImpl(
          name: "divide_nonnum_num",
          source: r"""
"1" / 1; // Runtime error: Operands must be numbers.
""",
        ),
        DloxDatasetLeafImpl(
          name: "comparison",
          source: r"""
print 1 < 2;    // expect: true
print 2 < 2;    // expect: false
print 2 < 1;    // expect: false

print 1 <= 2;    // expect: true
print 2 <= 2;    // expect: true
print 2 <= 1;    // expect: false

print 1 > 2;    // expect: false
print 2 > 2;    // expect: false
print 2 > 1;    // expect: true

print 1 >= 2;    // expect: false
print 2 >= 2;    // expect: true
print 2 >= 1;    // expect: true

// Zero and negative zero compare the same.
print 0 < -0; // expect: false
print -0 < 0; // expect: false
print 0 > -0; // expect: false
print -0 > 0; // expect: false
print 0 <= -0; // expect: true
print -0 <= 0; // expect: true
print 0 >= -0; // expect: true
print -0 >= 0; // expect: true
""",
        ),
        DloxDatasetLeafImpl(
          name: "greater_num_nonnum",
          source: r"""
1 > "1"; // Runtime error: Operands must be numbers or strings.
""",
        ),
        DloxDatasetLeafImpl(
          name: "less_or_equal_nonnum_num",
          source: r"""
"1" <= 1; // Runtime error: Operands must be numbers or strings.
""",
        ),
        DloxDatasetLeafImpl(
          name: "multiply_nonnum_num",
          source: r"""
"1" * 1; // Runtime error: Operands must be numbers.
""",
        ),
        DloxDatasetLeafImpl(
          name: "not_equals",
          source: r"""
print nil != nil; // expect: false

print true != true; // expect: false
print true != false; // expect: true

print 1 != 1; // expect: false
print 1 != 2; // expect: true

print "str" != "str"; // expect: false
print "str" != "ing"; // expect: true

print nil != false; // expect: true
print false != 0; // expect: true
print 0 != "0"; // expect: true
""",
        ),
        DloxDatasetLeafImpl(
          name: "add_bool_num",
          source: r"""
true + 123; // Runtime error: Operands must numbers, strings, lists or maps.
""",
        ),
        DloxDatasetLeafImpl(
          name: "negate_nonnum",
          source: r"""
-"s"; // Runtime error: Operand must be a number.
""",
        ),
        DloxDatasetLeafImpl(
          name: "add",
          source: r"""
print 123 + 456; // expect: 579
print "str" + "ing"; // expect: string
""",
        ),
        DloxDatasetLeafImpl(
          name: "greater_or_equal_nonnum_num",
          source: r"""
"1" >= 1; // Runtime error: Operands must be numbers or strings.
""",
        ),
        DloxDatasetLeafImpl(
          name: "equals",
          source: r"""
print nil == nil; // expect: true

print true == true; // expect: true
print true == false; // expect: false

print 1 == 1; // expect: true
print 1 == 2; // expect: false

print "str" == "str"; // expect: true
print "str" == "ing"; // expect: false

print nil == false; // expect: false
print false == 0; // expect: false
print 0 == "0"; // expect: false
""",
        ),
        DloxDatasetLeafImpl(
          name: "less_nonnum_num",
          source: r"""
"1" < 1; // Runtime error: Operands must be numbers or strings.
""",
        ),
        DloxDatasetLeafImpl(
          name: "divide",
          source: r"""
print 8 / 2;         // expect: 4
print 12.34 / 12.34;  // expect: 1
""",
        ),
        DloxDatasetLeafImpl(
          name: "add_bool_nil",
          source: r"""
true + nil; // Runtime error: Operands must numbers, strings, lists or maps.
""",
        ),
        DloxDatasetLeafImpl(
          name: "divide_num_nonnum",
          source: r"""
1 / "1"; // Runtime error: Operands must be numbers.
""",
        ),
        DloxDatasetLeafImpl(
          name: "multiply_num_nonnum",
          source: r"""
1 * "1"; // Runtime error: Operands must be numbers.
""",
        ),
        DloxDatasetLeafImpl(
          name: "less_or_equal_num_nonnum",
          source: r"""
1 <= "1"; // Runtime error: Operands must be numbers or strings.
""",
        ),
        DloxDatasetLeafImpl(
          name: "greater_nonnum_num",
          source: r"""
"1" > 1; // Runtime error: Operands must be numbers or strings.
""",
        ),
        DloxDatasetLeafImpl(
          name: "not",
          source: r"""
print !true;     // expect: false
print !false;    // expect: true
print !!true;    // expect: true

print !123;      // expect: false
print !0;        // expect: false

print !nil;     // expect: true

print !"";       // expect: false

fun foo() {}
print !foo;      // expect: false
""",
        ),
        DloxDatasetLeafImpl(
          name: "add_nil_nil",
          source: r"""
nil + nil; // Runtime error: Operands must numbers, strings, lists or maps.
""",
        ),
        DloxDatasetLeafImpl(
          name: "subtract",
          source: r"""
print 4 - 3; // expect: 1
print 1.2 - 1.2; // expect: 0
""",
        ),
        DloxDatasetLeafImpl(
          name: "subtract_nonnum_num",
          source: r"""
"1" - 1; // Runtime error: Operands must be numbers.
""",
        ),
        DloxDatasetLeafImpl(
          name: "not_class",
          source: r"""
class Bar {}
print !Bar;      // expect: false
print !Bar();    // expect: false
""",
        ),
        DloxDatasetLeafImpl(
          name: "greater_or_equal_num_nonnum",
          source: r"""
1 >= "1"; // Runtime error: Operands must be numbers or strings.
""",
        ),
        DloxDatasetLeafImpl(
          name: "less_num_nonnum",
          source: r"""
1 < "1"; // Runtime error: Operands must be numbers or strings.
""",
        ),
      ];
}

class DloxDataset_constructor with DloxDatasetInternal {
  const DloxDataset_constructor();

  @override
  String get name => "constructor";

  @override
  List<DloxDataset> get children => const [
        DloxDatasetLeafImpl(
          name: "call_init_explicitly",
          source: r"""
class Foo {
  init(arg) {
    print "Foo.init(" + arg + ")";
    this.field = "init";
  }
}

var foo = Foo("one"); // expect: Foo.init(one)
foo.field = "field";

var foo2 = foo.init("two"); // expect: Foo.init(two)
print foo2; // expect: Foo instance

// Make sure init() doesn't create a fresh instance.
print foo.field; // expect: init
""",
        ),
        DloxDatasetLeafImpl(
          name: "return_value",
          source: r"""
class Foo {
  init() {
    return "result"; // Error at 'return': Can't return a value from an initializer.
  }
}
""",
        ),
        DloxDatasetLeafImpl(
          name: "init_not_method",
          source: r"""
class Foo {
  init(arg) {
    print "Foo.init(" + arg + ")";
    this.field = "init";
  }
}

fun init() {
  print "not initializer";
}

init(); // expect: not initializer
""",
        ),
        DloxDatasetLeafImpl(
          name: "missing_arguments",
          source: r"""
class Foo {
  init(a, b) {}
}

var foo = Foo(1); // Runtime error: Expected 2 arguments but got 1.
""",
        ),
        DloxDatasetLeafImpl(
          name: "default",
          source: r"""
class Foo {}

var foo = Foo();
print foo; // expect: Foo instance
""",
        ),
        DloxDatasetLeafImpl(
          name: "arguments",
          source: r"""
class Foo {
  init(a, b) {
    print "init"; // expect: init
    this.a = a;
    this.b = b;
  }
}

var foo = Foo(1, 2);
print foo.a; // expect: 1
print foo.b; // expect: 2
""",
        ),
        DloxDatasetLeafImpl(
          name: "default_arguments",
          source: r"""
class Foo {}

var foo = Foo(1, 2, 3); // Runtime error: Expected 0 arguments but got 3.
""",
        ),
        DloxDatasetLeafImpl(
          name: "call_init_early_return",
          source: r"""
class Foo {
  init() {
    print "init";
    return;
    print "nope";
  }
}

var foo = Foo(); // expect: init
print foo.init(); // expect: init
// expect: Foo instance
""",
        ),
        DloxDatasetLeafImpl(
          name: "extra_arguments",
          source: r"""
class Foo {
  init(a, b) {
    this.a = a;
    this.b = b;
  }
}

var foo = Foo(1, 2, 3, 4); // Runtime error: Expected 2 arguments but got 4.""",
        ),
        DloxDatasetLeafImpl(
          name: "return_in_nested_function",
          source: r"""
class Foo {
  init() {
    fun init() {
      return "bar";
    }
    print init(); // expect: bar
  }
}

print Foo(); // expect: Foo instance
""",
        ),
        DloxDatasetLeafImpl(
          name: "early_return",
          source: r"""
class Foo {
  init() {
    print "init";
    return;
    print "nope";
  }
}

var foo = Foo(); // expect: init
print foo; // expect: Foo instance
""",
        ),
      ];
}

class DloxDataset_block with DloxDatasetInternal {
  const DloxDataset_block();

  @override
  String get name => "block";

  @override
  List<DloxDataset> get children => const [
        DloxDatasetLeafImpl(
          name: "empty",
          source: r"""
{} // By itself.

// In a statement.
if (true) {}
if (false) {} else {}

print "ok"; // expect: ok
""",
        ),
        DloxDatasetLeafImpl(
          name: "scope",
          source: r"""
var a = "outer";

{
  var a = "inner";
  print a; // expect: inner
}

print a; // expect: outer
""",
        ),
      ];
}
