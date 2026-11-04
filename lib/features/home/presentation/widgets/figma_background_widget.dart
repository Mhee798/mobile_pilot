import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// CustomPainter that renders ambient background gradients adapted to the active theme:
/// - Base color: matches voidBase token (dark void or clean light)
/// - Top Ellipse: radial primary accent gradient
/// - Bottom Ellipse: radial ambient glow gradient
class FigmaBackgroundPainter extends CustomPainter {
  final Color voidBase;
  final Color primaryCyan;
  final Color glowDeep;
  final bool isDark;

  const FigmaBackgroundPainter({
    required this.voidBase,
    required this.primaryCyan,
    required this.glowDeep,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // 1. Base solid background
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = voidBase,
    );

    // 2. Top Radial Gradient (Elliptical):
    // In SVG: center = (239, 170.32), scale = (1094.52, 729.079) relative to 402 x 874
    final topCenterX = size.width * 0.50;
    final topCenterY = size.height * 0.180;
    final topRx = size.width * (1094.52 / 402.0);
    final topRy = size.height * (729.079 / 874.0);
    final topAlpha = isDark ? 0.16 : 0.2;

    canvas.save();
    canvas.translate(topCenterX, topCenterY);
    canvas.scale(1.0, topRy / topRx);
    final topPaint = Paint()
      ..shader = ui.Gradient.radial(
        Offset.zero,
        topRx,
        [
          primaryCyan.withValues(alpha: topAlpha),
          primaryCyan.withValues(alpha: 0.0),
        ],
        [0.0, 0.55],
      );
    canvas.drawCircle(Offset.zero, topRx, topPaint);
    canvas.restore();

    // 3. Bottom Radial Gradient (Elliptical):
    // In SVG: center = (239, 887), scale = (284.257, 1236.02) relative to 402 x 874
    final bottomCenterX = size.width * 0.50;
    final bottomCenterY = size.height;
    final bottomRx = size.width * (284.257 / 402.0);
    final bottomRy = size.height * (1236.02 / 874.0);
    final bottomAlpha = isDark ? 0.36 : 0.24;

    canvas.save();
    canvas.translate(bottomCenterX, bottomCenterY);
    canvas.scale(1.0, bottomRy / bottomRx);
    final bottomPaint = Paint()
      ..shader = ui.Gradient.radial(
        Offset.zero,
        bottomRx,
        [
          glowDeep.withValues(alpha: bottomAlpha),
          glowDeep.withValues(alpha: 0.0),
        ],
        [0.0, 0.70],
      );
    canvas.drawCircle(Offset.zero, bottomRx, bottomPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant FigmaBackgroundPainter oldDelegate) =>
      voidBase != oldDelegate.voidBase ||
      primaryCyan != oldDelegate.primaryCyan ||
      glowDeep != oldDelegate.glowDeep ||
      isDark != oldDelegate.isDark;
}

/// Widget providing the accurate ambient background adapted to the active theme.
class FigmaBackgroundWidget extends StatelessWidget {
  const FigmaBackgroundWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return CustomPaint(
      painter: FigmaBackgroundPainter(
        voidBase: colors.voidBase,
        primaryCyan: colors.primaryCyan,
        glowDeep: colors.glowDeep,
        isDark: isDark,
      ),
      size: Size.infinite,
    );
  }
}
