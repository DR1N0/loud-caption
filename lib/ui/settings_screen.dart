import 'package:flutter/material.dart';

import '../captions/caption_controller.dart';

/// Placeholder settings screen; populated again by a future feature.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.controller});

  final CaptionController controller;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: Semantics(
        label: '返回',
        button: true,
        child: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      title: const Text('设置'),
    ),
    body: const Center(child: Text('暂无可配置项')),
  );
}
