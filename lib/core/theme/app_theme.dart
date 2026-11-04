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
          backgroundColor: scheme.surfaceContainerHigh,
          contentTextStyle: TextStyle(color: colors.textPrimary),
        ),
        extensions: [colors],
        progressIndicatorTheme: ProgressIndicatorThemeData(
          borderRadius: BorderRadius.circular(10),
          color: colors.primaryCyan,
          refreshBackgroundColor: colors.tertiaryBlue,
        ),
      );
}
