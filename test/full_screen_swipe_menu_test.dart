import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_pilot/features/home/presentation/widgets/full_screen_swipe_menu.dart';

void main() {
  testWidgets(
    'closing the menu for navigation does not refocus the offstage input',
    (tester) async {
      final focus = FocusNode();
      late VoidCallback open;
      await tester.pumpWidget(
        MaterialApp(
          home: FullScreenSwipeMenu(
            bodyBuilder: (_, openMenu) {
              open = openMenu;
              return Scaffold(body: TextField(focusNode: focus));
            },
            menuBuilder: (context, closeMenu) => Material(
              child: Center(
                child: TextButton(
                  onPressed: () {
                    closeMenu();
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            const Scaffold(body: Text('settings screen')),
                      ),
                    );
                  },
                  child: const Text('settings'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      open();
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isFalse);
      await tester.tap(find.text('settings'));
      await tester.pumpAndSettle();
      expect(find.text('settings screen'), findsOneWidget);
      expect(focus.hasFocus, isFalse);
      await tester.pumpWidget(const SizedBox());
      focus.dispose();
    },
  );

  testWidgets(
    'swiping animates sheets without rebuilding their contents each frame',
    (tester) async {
      var bodyBuilds = 0;
      var menuBuilds = 0;
      late VoidCallback open;
      await tester.pumpWidget(
        MaterialApp(
          home: FullScreenSwipeMenu(
            bodyBuilder: (_, openMenu) {
              bodyBuilds++;
              open = openMenu;
              return const Scaffold(body: Text('home'));
            },
            menuBuilder: (_, _) {
              menuBuilds++;
              return const Material(child: Text('menu'));
            },
          ),
        ),
      );
      final initialBodyBuilds = bodyBuilds;
      final initialMenuBuilds = menuBuilds;
      open();
      await tester.pump(const Duration(milliseconds: 140));
      await tester.pumpAndSettle();
      expect(bodyBuilds, initialBodyBuilds);
      expect(menuBuilds, initialMenuBuilds);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
