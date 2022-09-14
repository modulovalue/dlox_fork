import 'package:flutter/material.dart';
import 'package:flutter_font_icons/flutter_font_icons.dart';
import 'package:provider/provider.dart';

import 'code_editor.dart';
import 'editor_toolbar.dart';
import 'runtime.dart';
import 'runtime_toolbar.dart';
import 'widgets/monitor.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(
    final BuildContext context,
  ) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'dlox',
      theme: ThemeData(
        primarySwatch: Colors.blueGrey,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({
    final Key? key,
  }) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final GlobalKey<CodeEditorState> editor_key = GlobalKey<CodeEditorState>();
  final GlobalKey<MonitorState> stdout_key = GlobalKey<MonitorState>();
  final GlobalKey<MonitorState> compiler_key = GlobalKey<MonitorState>();
  final GlobalKey<MonitorState> vm_key = GlobalKey<MonitorState>();
  late Layout layout;
  late Runtime runtime;

  @override
  void initState() {
    super.initState();
    runtime = Runtime(
      on_compiler_result: (final res, final errors) {
        editor_key.currentState?.setCompilerResult(res, errors);
      },
      on_interpreter_result: (final res) {
        editor_key.currentState?.setInterpreterResult(res);
      },
    );
    layout = Layout(
      () {
        Future.microtask(
          () => setState(() {}),
        );
      },
    );
  }

  @override
  void dispose() {
    runtime.dispose();
    super.dispose();
  }

  @override
  Widget build(
    final BuildContext context,
  ) {
    final queryData = MediaQuery.of(context);
    layout.setScreenSize(queryData.size);
    final codeEditor = CodeEditor(
      key: editor_key,
      runtime: runtime,
    );
    final stdoutMonitor = Monitor(
      key: stdout_key,
      lines: runtime.stdout,
      icon: MaterialCommunityIcons.monitor,
      title: "Terminal",
    );
    final compilerMonitor = Monitor(
      autoScroll: false,
      key: compiler_key,
      lines: runtime.compiler_out,
      icon: MaterialCommunityIcons.matrix,
      title: "Bytecode",
    );
    const monitorTitle = "VM trace";
    final vmMonitor = Monitor(
      key: vm_key,
      lines: runtime.vm_out,
      icon: MaterialCommunityIcons.magnify,
      placeholderBuilder: (final widget) {
        if (!runtime.vm_trace_enabled) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              widget,
              const SizedBox(height: 4.0,),
              const Text("disabled for performance", style: TextStyle(fontSize: 16.0, color: Colors.grey,),),
            ],
          );
        }
        return widget;
      },
      title: monitorTitle,
    );
    final runtimeToolbar = RuntimeToolbar(
      layout: layout,
      onClear: () => runtime.clear_output(),
    );
    final editorToolbar = EditorToolbar(
      layout: layout,
      onSnippet: (final source) {
        editor_key.currentState?.setSource(source);
        runtime.reset();
      },
    );
    final topRow = Row(children: [
      if (layout.showEditor) Expanded(child: codeEditor),
      if (layout.showEditor && layout.showCompiler) VerticalDivider(width: 0.5, color: Colors.grey.shade900),
      if (layout.showCompiler) Expanded(child: compilerMonitor),
    ]);
    final bottomRow = Row(
      children: [
        if (layout.showStdout) Expanded(child: stdoutMonitor),
        if (layout.showStdout && layout.showVm) VerticalDivider(width: 0.5, color: Colors.grey.shade900),
        if (layout.showVm) Expanded(child: vmMonitor),
      ],
    );
    final body = Column(
      children: [
        editorToolbar,
        Expanded(flex: 2, child: topRow),
        runtimeToolbar,
        Expanded(flex: 1, child: bottomRow),
      ],
    );
    return Scaffold(
      body: MultiProvider(
        providers: [ListenableProvider.value(value: runtime)],
        child: body,
      ),
    );
  }
}
