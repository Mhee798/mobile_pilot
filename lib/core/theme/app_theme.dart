import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';

abstract final class AppTheme {
  static ThemeData get dark =>
      _build(AppColors.darkScheme, AppColorsExtension.dark);
  static ThemeData get light =>
      _build(AppColors.lightScheme, AppColorsExtension.light);

  static ThemeData _build(ColorScheme scheme, AppColorsExtension colors) =>
      ThemeData(
        useMaterial3: true,
        brightness: scheme.brightness,
        colorScheme: scheme,
        scaffoldBackgroundColor: colors.voidBase,
        canvasColor: colors.voidBase,
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: colors.textPrimary,
          elevation: 0,
          scrolledUnderElevation: 0,
          systemOverlayStyle: scheme.brightness == Brightness.dark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark,
          iconTheme: IconThemeData(color: colors.textPrimary),
          titleTextStyle: TextStyle(
            color: colors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        dividerColor: scheme.outlineVariant,
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          backgroundColor: scheme.surfaceContainerHigh,
          elevation: 6,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: scheme.outlineVariant),
          ),
          contentTextStyle: TextStyle(
            color: colors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
          actionTextColor: scheme.primary,
        ),
        extensions: [colors],
        progressIndicatorTheme: ProgressIndicatorThemeData(
          borderRadius: BorderRadius.circular(10),
          color: colors.primaryCyan,
          refreshBackgroundColor: colors.tertiaryBlue,
          strokeCap: StrokeCap.round,
        ),
      );
}
