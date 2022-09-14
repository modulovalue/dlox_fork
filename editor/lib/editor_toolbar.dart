import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_font_icons/flutter_font_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import 'constants.dart';
import 'runtime_toolbar.dart';
import 'widgets/toggle_button.dart';

class EditorToolbar extends StatefulWidget {
  final Layout layout;
  final void Function(String) onSnippet;

  const EditorToolbar({
    required final this.layout,
    required final this.onSnippet,
    final Key? key,
  }) : super(
          key: key,
        );

  @override
  _EditorToolbarState createState() => _EditorToolbarState();
}

class _EditorToolbarState extends State<EditorToolbar> {
  String? snippet_fname;
  late List<String> snippet_list;
  final Map<String, String> path_map = {};

  @override
  void initState() {
    super.initState();
    load_manifest();
  }

  Future<void> load_manifest() async {
    final manifestContent = await rootBundle.loadString('AssetManifest.json');
    final manifestMap = json.decode(manifestContent) as Map<String, dynamic>;
    snippet_list = manifestMap.keys
        .where(
          (final String key) => key.contains('snippets/'),
        )
        .toList();
    path_map.clear();
    snippet_list.forEach((final el) {
      path_map[fname(el)] = el;
    });
    // Set first snippet
    await set_snippet("fibonacci"); // Default file
  }

  Future<void> set_snippet(
    final String fname,
  ) async {
    setState(() => snippet_fname = fname);
    final source = await rootBundle.loadString(path_map[snippet_fname]!);
    widget.onSnippet(source);
  }

  String fname(
    final String path,
  ) {
    final split = path.split("/");
    return split.last.replaceAll("_", " ").replaceAll(".lox", "");
  }

  Widget build_dropdown() {
    final dropdown = DropdownButton<String>(
      value: snippet_fname,
      items: path_map.keys.map((final String value) {
        return DropdownMenuItem<String>(
          value: value,
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16.0,
            ),
          ),
        );
      },).toList(),
      onChanged: (final a) => set_snippet(a!),
      iconEnabledColor: Colors.white,
      dropdownColor: Colors.black87,
      underline: const SizedBox.shrink(),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: dropdown,
    );
  }

  Future<void> _launch_in_browser(
    final String url,
  ) async {
    if (await canLaunch(url)) {
      await launch(
        url,
        forceSafariVC: false,
        forceWebView: false,
        headers: <String, String>{'my_header_key': 'my_header_value'},
      );
    } else {
      throw Exception('Could not launch $url');
    }
  }

  @override
  Widget build(
    final BuildContext context,
  ) {
    final github = IconButton(
      padding: const EdgeInsets.only(left: 8.0),
      icon: const Icon(FontAwesome5Brands.github, color: Colors.white),
      onPressed: () => _launch_in_browser("https://github.com/BertrandBev/dlox"),
    );
    final snippets = build_dropdown();
    final toggleBtn = ToggleButton(
      leftIcon: MaterialCommunityIcons.code_tags,
      leftEnabled: widget.layout.showEditor,
      leftToggle: widget.layout.toggleEditor,
      rightIcon: MaterialCommunityIcons.matrix,
      rightEnabled: widget.layout.showCompiler,
      rightToggle: widget.layout.toggleCompiler,
    );
    final row = Row(
      children: [
        github,
        snippets,
        const Spacer(),
        toggleBtn,
      ],
    );
    return Container(
      decoration: BoxDecoration(
        border: Border.symmetric(
          vertical: BorderSide(color: Colors.grey.shade700, width: 0.5),
        ),
        color: ColorTheme.sidebar,
      ),
      child: row,
    );
  }
}
