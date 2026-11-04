import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:mobile_pilot/core/settings/app_settings.dart';

void main() {
  test('theme and speech rate survive reopening storage', () async {
    final directory = await Directory.systemTemp.createTemp(
      'mobilepilot_settings_',
    );
    Future<Box<dynamic>> open() =>
        Hive.openBox<dynamic>('preferences_test', path: directory.path);
    final first = AppSettings(openStore: open);
    await first.load();
    expect(first.themeMode, ThemeMode.system);
    expect(first.speechRate, 0.5);
    await first.setThemeMode(ThemeMode.dark);
    await first.setSpeechRate(0.75);
    first.dispose();
    await (await open()).close();
    final second = AppSettings(openStore: open);
    await second.load();
    expect(second.themeMode, ThemeMode.dark);
    expect(second.speechRate, 0.75);
    second.dispose();
    await (await open()).close();
    expect(directory.parent.absolute.path, Directory.systemTemp.absolute.path);
    await directory.delete(recursive: true);
  });
  test(
    'preference writes can retry after transient initialization failure',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'mobilepilot_settings_retry_',
      );
      var attempts = 0;
      final settings = AppSettings(
        openStore: () async {
          if (++attempts == 1) throw StateError('temporary storage failure');
          return Hive.openBox<dynamic>(
            'preferences_retry_test',
            path: directory.path,
          );
        },
      );
      await expectLater(settings.load(), throwsStateError);
      await settings.setThemeMode(ThemeMode.dark);
      expect(settings.themeMode, ThemeMode.dark);
      expect(attempts, 2);
      expect(() => settings.setSpeechRate(0.6), throwsArgumentError);
      settings.dispose();
      await (await Hive.openBox<dynamic>(
        'preferences_retry_test',
        path: directory.path,
      )).close();
      expect(
        directory.parent.absolute.path,
        Directory.systemTemp.absolute.path,
      );
      await directory.delete(recursive: true);
    },
  );
}
