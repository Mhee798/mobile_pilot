import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:mobile_pilot/core/localization/app_localization.dart';

/// Reads the real catalogs synchronously so widget tests do not wait on asset I/O.
class TestTranslationLoader extends AssetLoader {
  const TestTranslationLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) => Future.value(
    jsonDecode(File('$path/${locale.languageCode}.json').readAsStringSync())
        as Map<String, dynamic>,
  );
}

class LocalizedTestApp extends StatelessWidget {
  const LocalizedTestApp({
    super.key,
    required this.home,
    this.theme,
    this.darkTheme,
    this.themeMode = ThemeMode.system,
  });
  final Widget home;
  final ThemeData? theme;
  final ThemeData? darkTheme;
  final ThemeMode themeMode;

  @override
  Widget build(BuildContext context) => AppLocalization(
    assetLoader: const TestTranslationLoader(),
    child: Builder(
      builder: (context) => MaterialApp(
        locale: context.locale,
        supportedLocales: context.supportedLocales,
        localizationsDelegates: context.localizationDelegates,
        theme: theme,
        darkTheme: darkTheme,
        themeMode: themeMode,
        home: home,
      ),
    ),
  );
}
