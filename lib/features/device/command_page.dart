import 'package:flutter/material.dart';

import 'controllers/app_launcher_controller.dart';
import 'controllers/device_controller.dart';
import 'controllers/floating_controls_controller.dart';
import 'controllers/screen_action_controller.dart';
import 'controllers/screen_capture_controller.dart';
import 'controllers/settings_test_controller.dart';
import 'controllers/ui_tree_controller.dart';
import 'widgets/command_controls_card.dart';
import 'widgets/screen_actions_section.dart';
import 'widgets/screen_preview.dart';
import 'widgets/ui_tree_section.dart';

class CommandPage extends StatefulWidget {
  const CommandPage({super.key});

  @override
  State<CommandPage> createState() => _CommandPageState();
}

class _CommandPageState extends State<CommandPage> with WidgetsBindingObserver {
  final _feedback = CommandFeedback();
  late final _launcher = AppLauncherController(_feedback);
  late final _floating = FloatingControlsController(_feedback);
  late final _tree = UiTreeController(_feedback);
  late final _settings = SettingsTestController(
    _feedback,
    _tree.targetController,
  );
  late final _capture = ScreenCaptureController(_feedback);
  late final _actions = ScreenActionController(_feedback, _capture);
  late final _controllers = [
    _launcher,
    _floating,
    _tree,
    _settings,
    _capture,
    _actions,
  ];
  int _tapTestCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    for (final controller in _controllers) {
      controller.addListener(_refresh);
    }
    _settings.loadResult();
    _floating.load();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final controller in _controllers) {
      controller.removeListener(_refresh);
      controller.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _settings.loadResult();
      if (_capture.isWaiting) _capture.poll();
      _actions.loadResult();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('สั่งงาน')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CommandControlsCard(
              launcher: _launcher,
              floating: _floating,
              capture: _capture,
              settings: _settings,
              tree: _tree,
              feedback: _feedback,
              tapTestCount: _tapTestCount,
              onTestTap: () => setState(() => _tapTestCount++),
            ),
            const SizedBox(height: 8),
            if (_capture.image != null)
              ScreenPreview(
                image: _capture.image!,
                sourceWidth: _capture.width!,
                sourceHeight: _capture.height!,
                selectedX: _capture.selectedX,
                selectedY: _capture.selectedY,
                isTapping: _feedback.isTapping,
                onPointSelected: _capture.selectPoint,
                onTapPoint: _actions.tapSelectedPoint,
              ),
            ScreenActionsSection(
              capture: _capture,
              actions: _actions,
              feedback: _feedback,
              onTextChanged: _refresh,
            ),
            UiTreeSection(tree: _tree),
          ],
        ),
      ),
    );
  }
}
