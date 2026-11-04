import 'package:flutter/material.dart';

/// Color tokens and Material schemes for MobilePilot.
abstract final class AppColors {
  // Material Scheme - Dark Tokens
  static const Color surface = Color(0xFF10131E);
  static const Color surfaceDim = Color(0xFF10131E);
  static const Color surfaceBright = Color(0xFF363945);
  static const Color surfaceContainerLowest = Color(0xFF0B0E19);
  static const Color surfaceContainerLow = Color(0xFF181B27);
  static const Color surfaceContainer = Color(0xFF1C1F2B);
  static const Color surfaceContainerHigh = Color(0xFF272936);
  static const Color surfaceContainerHighest = Color(0xFF313441);
  static const Color onSurface = Color(0xFFE0E1F2);
  static const Color onSurfaceVariant = Color(0xFFBDC8D1);
  static const Color inverseSurface = Color(0xFFE0E1F2);
  static const Color inverseOnSurface = Color(0xFF2D303C);
  static const Color outline = Color(0xFF87929A);
  static const Color outlineVariant = Color(0xFF3E484F);
  static const Color surfaceTint = Color(0xFF7BD0FF);
  static const Color primary = Color(0xFF8ED5FF);
  static const Color onPrimary = Color(0xFF00354A);
  static const Color primaryContainer = Color(0xFF38BDF8);
  static const Color onPrimaryContainer = Color(0xFF004965);
  static const Color inversePrimary = Color(0xFF00668A);
  static const Color secondary = Color(0xFF7DD3FC);
  static const Color onSecondary = Color(0xFF00344A);
  static const Color secondaryContainer = Color(0xFF123B50);
  static const Color onSecondaryContainer = Color(0xFFC7EEFF);
  static const Color tertiary = Color(0xFFAFCFFF);
  static const Color onTertiary = Color(0xFF00315D);
  static const Color tertiaryContainer = Color(0xFF7BB4FF);
  static const Color onTertiaryContainer = Color(0xFF00457E);
  static const Color error = Color(0xFFFFB4AB);
  static const Color onError = Color(0xFF690005);
  static const Color errorContainer = Color(0xFF93000A);
  static const Color onErrorContainer = Color(0xFFFFDAD6);

  // Brand / void canvas tokens (Dark defaults kept for backward compatibility)
  static const Color voidBase = Color(0xFF05070E);
  static const Color voidElevated = Color(0xFF0A0D18);
  static const Color voidCard = Color(0x730F172A);
  static const Color primaryCyan = Color(0xFF38BDF8);
  static const Color secondaryIndigo = Color(0xFF818CF8);
  static const Color tertiaryBlue = Color(0xFF60A5FA);
  static const Color glowDeep = Color(0xFF2563EB);
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textTertiary = Color(0xFF475569);
  static const Color borderGlassSubtle = Color(0x1F38BDF8);
  static const Color borderGlassActive = Color(0x7338BDF8);
  static const Color glassFill = Color(0x800F172A);
  static const Color glassHairline = Color(0x14FFFFFF);

  /// Material 3 Dark ColorScheme
  static const ColorScheme darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: primary,
    onPrimary: onPrimary,
    primaryContainer: primaryContainer,
    onPrimaryContainer: onPrimaryContainer,
    secondary: secondary,
    onSecondary: onSecondary,
    secondaryContainer: secondaryContainer,
    onSecondaryContainer: onSecondaryContainer,
    tertiary: tertiary,
    onTertiary: onTertiary,
    tertiaryContainer: tertiaryContainer,
    onTertiaryContainer: onTertiaryContainer,
    error: error,
    onError: onError,
    errorContainer: errorContainer,
    onErrorContainer: onErrorContainer,
    surface: surface,
    onSurface: onSurface,
    onSurfaceVariant: onSurfaceVariant,
    outline: outline,
    outlineVariant: outlineVariant,
    inverseSurface: inverseSurface,
    onInverseSurface: inverseOnSurface,
    inversePrimary: inversePrimary,
    surfaceTint: surfaceTint,
    surfaceDim: surfaceDim,
    surfaceBright: surfaceBright,
    surfaceContainerLowest: surfaceContainerLowest,
    surfaceContainerLow: surfaceContainerLow,
    surfaceContainerHigh: surfaceContainerHigh,
    surfaceContainerHighest: surfaceContainerHighest,
    surfaceContainer: surfaceContainer,
  );

  /// Material 3 Light ColorScheme harmonized from the design system's seed tones.
  static const ColorScheme lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF00668A),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFC3E7FF),
    onPrimaryContainer: Color(0xFF001E2D),
    secondary: Color(0xFF00668A),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFD5EFFA),
    onSecondaryContainer: Color(0xFF00344A),
    tertiary: Color(0xFF00639B),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFCEE5FF),
    onTertiaryContainer: Color(0xFF001D33),
    error: Color(0xFFBA1A1A),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF410002),
    surface: Color(0xFFF8F9FE),
    onSurface: Color(0xFF191C20),
    onSurfaceVariant: Color(0xFF41474D),
    outline: Color(0xFF71787E),
    outlineVariant: Color(0xFFC1C7CE),
    inverseSurface: Color(0xFF2E3135),
    onInverseSurface: Color(0xFFEFF0F7),
    inversePrimary: Color(0xFF8ED5FF),
    surfaceTint: Color(0xFF00668A),
    surfaceDim: Color(0xFFD8DAE0),
    surfaceBright: Color(0xFFF8F9FE),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF2F3F9),
    surfaceContainer: Color(0xFFECEEF4),
    surfaceContainerHigh: Color(0xFFE6E8EE),
    surfaceContainerHighest: Color(0xFFE0E2E8),
  );

  /// Default scheme for backwards compatibility.
  static const ColorScheme scheme = darkScheme;

  /// Helper to access theme tokens from the current context.
  static AppColorsExtension of(BuildContext context) =>
      Theme.of(context).extension<AppColorsExtension>() ??
      (Theme.of(context).brightness == Brightness.dark
          ? AppColorsExtension.dark
          : AppColorsExtension.light);
}

/// Custom theme extension for brand, glassmorphism, and atmospheric canvas tokens.
@immutable
class AppColorsExtension extends ThemeExtension<AppColorsExtension> {
  final Color voidBase;
  final Color voidElevated;
  final Color voidCard;
  final Color primaryCyan;
  final Color secondaryIndigo;
  final Color tertiaryBlue;
  final Color glowDeep;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color borderGlassSubtle;
  final Color borderGlassActive;
  final Color glassFill;
  final Color glassHairline;

  const AppColorsExtension({
    required this.voidBase,
    required this.voidElevated,
    required this.voidCard,
    required this.primaryCyan,
    required this.secondaryIndigo,
    required this.tertiaryBlue,
    required this.glowDeep,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.borderGlassSubtle,
    required this.borderGlassActive,
    required this.glassFill,
    required this.glassHairline,
  });

  @override
  AppColorsExtension copyWith({
    Color? voidBase,
    Color? voidElevated,
    Color? voidCard,
    Color? primaryCyan,
    Color? secondaryIndigo,
    Color? tertiaryBlue,
    Color? glowDeep,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? borderGlassSubtle,
    Color? borderGlassActive,
    Color? glassFill,
    Color? glassHairline,
  }) {
    return AppColorsExtension(
      voidBase: voidBase ?? this.voidBase,
      voidElevated: voidElevated ?? this.voidElevated,
      voidCard: voidCard ?? this.voidCard,
      primaryCyan: primaryCyan ?? this.primaryCyan,
      secondaryIndigo: secondaryIndigo ?? this.secondaryIndigo,
      tertiaryBlue: tertiaryBlue ?? this.tertiaryBlue,
      glowDeep: glowDeep ?? this.glowDeep,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      borderGlassSubtle: borderGlassSubtle ?? this.borderGlassSubtle,
      borderGlassActive: borderGlassActive ?? this.borderGlassActive,
      glassFill: glassFill ?? this.glassFill,
      glassHairline: glassHairline ?? this.glassHairline,
    );
  }

  @override
  AppColorsExtension lerp(ThemeExtension<AppColorsExtension>? other, double t) {
    if (other is! AppColorsExtension) return this;
    return AppColorsExtension(
      voidBase: Color.lerp(voidBase, other.voidBase, t) ?? voidBase,
      voidElevated:
          Color.lerp(voidElevated, other.voidElevated, t) ?? voidElevated,
      voidCard: Color.lerp(voidCard, other.voidCard, t) ?? voidCard,
      primaryCyan: Color.lerp(primaryCyan, other.primaryCyan, t) ?? primaryCyan,
      secondaryIndigo:
          Color.lerp(secondaryIndigo, other.secondaryIndigo, t) ??
          secondaryIndigo,
      tertiaryBlue:
          Color.lerp(tertiaryBlue, other.tertiaryBlue, t) ?? tertiaryBlue,
      glowDeep: Color.lerp(glowDeep, other.glowDeep, t) ?? glowDeep,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t) ?? textPrimary,
      textSecondary:
          Color.lerp(textSecondary, other.textSecondary, t) ?? textSecondary,
      textTertiary:
          Color.lerp(textTertiary, other.textTertiary, t) ?? textTertiary,
      borderGlassSubtle:
          Color.lerp(borderGlassSubtle, other.borderGlassSubtle, t) ??
          borderGlassSubtle,
      borderGlassActive:
          Color.lerp(borderGlassActive, other.borderGlassActive, t) ??
          borderGlassActive,
      glassFill: Color.lerp(glassFill, other.glassFill, t) ?? glassFill,
      glassHairline:
          Color.lerp(glassHairline, other.glassHairline, t) ?? glassHairline,
    );
  }

  /// Dark theme brand tokens (Luminous Void AI)
  static const AppColorsExtension dark = AppColorsExtension(
    voidBase: AppColors.voidBase,
    voidElevated: AppColors.voidElevated,
    voidCard: AppColors.voidCard,
    primaryCyan: AppColors.primaryCyan,
    secondaryIndigo: AppColors.secondaryIndigo,
    tertiaryBlue: AppColors.tertiaryBlue,
    glowDeep: AppColors.glowDeep,
    textPrimary: AppColors.textPrimary,
    textSecondary: AppColors.textSecondary,
    textTertiary: AppColors.textTertiary,
    borderGlassSubtle: AppColors.borderGlassSubtle,
    borderGlassActive: AppColors.borderGlassActive,
    glassFill: AppColors.glassFill,
    glassHairline: AppColors.glassHairline,
  );

  /// Light theme brand tokens (Frost Light)
  static const AppColorsExtension light = AppColorsExtension(
    voidBase: Color(0xFFF8FAFC),
    voidElevated: Color(0xFFFFFFFF),
    voidCard: Color(0xF2FFFFFF),
    primaryCyan: Color(0xFF0284C7),
    secondaryIndigo: Color(0xFF6366F1),
    tertiaryBlue: Color(0xFF2563EB),
    glowDeep: Color(0xFF38BDF8),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF475569),
    textTertiary: Color(0xFF94A3B8),
    borderGlassSubtle: Color(0x1E0F172A),
    borderGlassActive: Color(0x660284C7),
    glassFill: Color(0xE6FFFFFF),
    glassHairline: Color(0x1A000000),
  );
}

/// Convenience context extension for accessing design tokens.
extension AppThemeContext on BuildContext {
  AppColorsExtension get appColors => AppColors.of(this);
}
