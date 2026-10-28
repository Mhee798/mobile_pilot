import 'package:flutter/material.dart';

import '../../ai/presentation/screen/ai_test_page.dart';

import 'controllers/app_launcher_controller.dart';
import 'controllers/pinch_controller.dart';
import 'widgets/pinch_controls_section.dart';
import 'controllers/command_sequence_controller.dart';
import 'widgets/command_sequence_section.dart';
import 'controllers/device_controller.dart';
import 'controllers/floating_controls_controller.dart';
import 'controllers/screen_action_controller.dart';
import 'controllers/screen_capture_controller.dart';
import 'controllers/settings_test_controller.dart';
import 'controllers/ui_tree_controller.dart';
import 'controllers/wait_for_ui_controller.dart';
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
  late final _sequence = CommandSequenceController(_feedback);
  late final _launcher = AppLauncherController(_feedback);
  late final _floating = FloatingControlsController(_feedback);
  late final _uiWait = WaitForUiController(_feedback);
  late final _tree = UiTreeController(_feedback);
  late final _settings = SettingsTestController(
    _feedback,
    _tree.targetController,
  );
  late final _capture = ScreenCaptureController(_feedback);
  late final _pinch = PinchController(_feedback, _capture);
  late final _actions = ScreenActionController(_feedback, _capture);
  late final _controllers = [
    _launcher,
    _sequence,
    _uiWait,
    _floating,
    _tree,
    _settings,
    _capture,
    _actions,
    _pinch,
  ];
  int _tapTestCount = 0;
  String? _lastTargetPackage;

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
    if (_lastTargetPackage != _feedback.targetPackage) {
      _lastTargetPackage = _feedback.targetPackage;
      _sequence.stop();
      _uiWait.targetChanged();
      _tree.elements = [];
      _tree.targetController.clear();
      _capture.clearForTargetChange();
    }
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
      appBar: AppBar(
        title: const Text('สั่งงาน'),
        actions: [
          IconButton(
            tooltip: 'ทดสอบ AI',
            icon: const Icon(Icons.smart_toy_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AiTestPage(
                  capturedImage: _capture.image,
                  uiSnapshot: _tree.elements,
                  targetPackage: _feedback.targetPackage,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CommandSequenceSection(controller: _sequence),
            AbsorbPointer(
              absorbing: _sequence.isRunning,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CommandControlsCard(
                    launcher: _launcher,
                    uiWait: _uiWait,
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
                      endX: _capture.swipeEndX,
                      endY: _capture.swipeEndY,
                      isTapping: _feedback.isTapping,
                      onPointSelected: _capture.selectPoint,
                      onTapPoint: _actions.tapSelectedPoint,
                    ),
                  if (_capture.image != null)
                    PinchControlsSection(
                      controller: _pinch,
                      busy: _feedback.isTapping,
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
          ],
        ),
      ),
    );
  }
}
