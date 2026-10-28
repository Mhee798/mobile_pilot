import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'features/ai/application/ai_task_controller.dart';
import 'features/ai/data/ai_model_service.dart';
import 'core/platform/ai_task_overlay.dart';
import 'features/ai/data/ai_task_journal.dart';
import 'features/ai/data/ai_run_history.dart';

import 'features/setup/presentation/accessibility_setup_page.dart';

class MobilePilotApp extends StatelessWidget {
  const MobilePilotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AiTaskController>(
      create: (_) => AiTaskController(
        AiModelService(history: AiRunHistory()),
        overlay: AiTaskOverlay(),
        journal: AiTaskJournal(),
      ),
      child: MaterialApp(
        title: 'MobilePilot',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3157D5)),
          useMaterial3: true,
        ),
        home: const AccessibilitySetupPage(),
      ),
    );
  }
}
