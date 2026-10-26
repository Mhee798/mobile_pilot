import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

class ScreenPreview extends StatelessWidget {
  const ScreenPreview({
    super.key,
    required this.image,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.selectedX,
    required this.selectedY,
    required this.isTapping,
    required this.onPointSelected,
    required this.onTapPoint,
  });

  final Uint8List image;
  final int sourceWidth;
  final int sourceHeight;
  final double? selectedX;
  final double? selectedY;
  final bool isTapping;
  final void Function(double x, double y) onPointSelected;
  final VoidCallback onTapPoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const frameHeight = 180.0;
        final scale = math
            .min(constraints.maxWidth / sourceWidth, frameHeight / sourceHeight)
            .toDouble();
        final imageWidth = sourceWidth * scale;
        final imageHeight = sourceHeight * scale;
        final left = (constraints.maxWidth - imageWidth) / 2;
        final top = (frameHeight - imageHeight) / 2;

        return Column(
          children: [
            SizedBox(
              width: constraints.maxWidth,
              height: frameHeight,
              child: GestureDetector(
                onTapDown: (details) {
                  final dx = details.localPosition.dx - left;
                  final dy = details.localPosition.dy - top;
                  if (dx < 0 || dy < 0 || dx > imageWidth || dy > imageHeight) {
                    return;
                  }
                  onPointSelected(dx / imageWidth, dy / imageHeight);
                },
                child: Center(
                  child: SizedBox(
                    width: imageWidth,
                    height: imageHeight,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.memory(image, fit: BoxFit.fill),
                        if (selectedX != null && selectedY != null)
                          Positioned(
                            left: selectedX! * imageWidth - 12,
                            top: selectedY! * imageHeight - 24,
                            child: const Icon(
                              Icons.location_on,
                              color: Colors.red,
                              size: 24,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (selectedX != null && selectedY != null)
              Text(
                'พิกัด normalized: x=${selectedX!.toStringAsFixed(3)}, y=${selectedY!.toStringAsFixed(3)}',
              ),
            OutlinedButton.icon(
              onPressed: isTapping ? null : onTapPoint,
              icon: const Icon(Icons.gesture),
              label: const Text('เตรียมแตะพิกัดนี้'),
            ),
          ],
        );
      },
    );
  }
}
