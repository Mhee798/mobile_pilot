import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'core/localization/app_localization.dart';
import 'core/platform/ai_task_overlay.dart';
import 'core/settings/app_settings.dart';
import 'core/theme/app_theme.dart';
import 'features/ai/application/ai_task_controller.dart';
import 'features/ai/data/ai_model_service.dart';
import 'features/ai/data/ai_run_history.dart';
import 'features/ai/data/ai_task_journal.dart';
import 'features/home/presentation/screen/mobile_pilot_home_page.dart';
import 'features/models/presentation/model_selection_scope.dart';
import 'features/setup/presentation/screen/accessibility_setup_page.dart';

class MobilePilotApp extends StatefulWidget {
  const MobilePilotApp({
    super.key,
    this.useDebugUi = true,
    this.translationLoader = const RootBundleAssetLoader(),
  });

  final bool useDebugUi;
  final AssetLoader translationLoader;

  @override
  State<MobilePilotApp> createState() => _MobilePilotAppState();
}

class _MobilePilotAppState extends State<MobilePilotApp> {
  final _settings = AppSettings();

  @override
  void initState() {
    super.initState();
    unawaited(
      _settings.load().catchError((Object error) {
        debugPrint('Settings unavailable: $error');
      }),
    );
  }

  @override
  void dispose() {
    _settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppLocalization(
      assetLoader: widget.translationLoader,
      child: Builder(
        builder: (context) => BlocProvider<AiTaskController>(
          create: (_) => AiTaskController(
            AiModelService(history: AiRunHistory()),
            overlay: AiTaskOverlay(),
            journal: AiTaskJournal(),
          ),
          child: ModelSelectionHost(
            child: AppSettingsScope(
              settings: _settings,
              child: ListenableBuilder(
                listenable: _settings,
                builder: (context, _) => GestureDetector(
                  onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                  child: MaterialApp(
                    title: 'MobilePilot',
                    locale: context.locale,
                    supportedLocales: context.supportedLocales,
                    localizationsDelegates: context.localizationDelegates,
                    debugShowCheckedModeBanner: widget.useDebugUi,
                    theme: AppTheme.light,
                    darkTheme: AppTheme.dark,
                    themeMode: _settings.themeMode,
                    home: widget.useDebugUi
                        ? const AccessibilitySetupPage()
                        : const MobilePilotHomePage(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
