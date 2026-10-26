import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_pilot/features/device/widgets/screen_preview.dart';

void main() {
  testWidgets(
    'Preview ignores letterboxing and returns normalized image points',
    (tester) async {
      final points = <Offset>[];
      var tapRequests = 0;
      final pixel = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jMioAAAAASUVORK5CYII=',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                child: ScreenPreview(
                  image: pixel,
                  sourceWidth: 1280,
                  sourceHeight: 2800,
                  selectedX: 0.5,
                  selectedY: 0.5,
                  isTapping: false,
                  onPointSelected: (x, y) => points.add(Offset(x, y)),
                  onTapPoint: () => tapRequests++,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final frame = tester.getRect(
        find
            .descendant(
              of: find.byType(ScreenPreview),
              matching: find.byType(GestureDetector),
            )
            .first,
      );
      expect(frame.height, 180);
      await tester.tapAt(Offset(frame.left + 10, frame.center.dy));
      expect(points, isEmpty);

      final imageWidth = 1280 * 180 / 2800;
      await tester.tapAt(
        Offset(frame.center.dx + imageWidth * 0.25, frame.top + 45),
      );
      expect(points.single.dx, closeTo(0.75, 0.000001));
      expect(points.single.dy, closeTo(0.25, 0.000001));
      expect(find.byIcon(Icons.location_on), findsOneWidget);
      await tester.tap(find.text('เตรียมแตะพิกัดนี้'));
      expect(tapRequests, 1);
    },
  );
}
