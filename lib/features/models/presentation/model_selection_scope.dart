import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../ai/application/ai_task_controller.dart';
import '../application/model_selection_controller.dart';
import '../data/model_backend.dart';

class ModelSelectionScope extends InheritedNotifier<ModelSelectionController> {
  const ModelSelectionScope({
    super.key,
    required ModelSelectionController controller,
    required super.child,
  }) : super(notifier: controller);
  static ModelSelectionController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ModelSelectionScope>()
      ?.notifier;
  static ModelSelectionController of(BuildContext context) => maybeOf(context)!;
}

class ModelSelectionHost extends StatefulWidget {
  const ModelSelectionHost({super.key, required this.child});
  final Widget child;
  @override
  State<ModelSelectionHost> createState() => _ModelSelectionHostState();
}

class _ModelSelectionHostState extends State<ModelSelectionHost> {
  late final _controller = ModelSelectionController(
    DeviceModelBackend(context.read<AiTaskController>()),
  );
  StreamSubscription<AiTaskState>? _subscription;

  @override
  void initState() {
    super.initState();
    unawaited(_controller.initialize());
    _subscription = context.read<AiTaskController>().stream.listen(
      (_) => _controller.refreshNativeStatus(),
    );
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ModelSelectionScope(controller: _controller, child: widget.child);
}
