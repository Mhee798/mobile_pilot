import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_pilot/features/models/presentation/model_selection_scope.dart';

/// Startup reads the model library from disk; let that I/O finish in real time.
Future<void> pumpReadyApp(WidgetTester tester, Widget app) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(app);
    await tester.pump();
    final scope = tester.widget<ModelSelectionScope>(
      find.byType(ModelSelectionScope),
    );
    await scope.notifier!.initialize();
  });
  await tester.pumpAndSettle();
}
