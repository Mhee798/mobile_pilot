import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:mobile_pilot/core/theme/app_colors.dart';

class BottomGlowWidget extends StatelessWidget {
  const BottomGlowWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
      child: Container(
        height: 350,
        decoration: ShapeDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              colors.glowDeep.withValues(alpha: 0.5),
            ],
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9999),
          ),
        ),
      ),
    );
  }
}
