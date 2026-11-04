import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, String> flatten(
  Map<String, dynamic> value, [
  String prefix = '',
]) => {
  for (final entry in value.entries)
    if (entry.value is Map<String, dynamic>)
      ...flatten(entry.value as Map<String, dynamic>, '$prefix${entry.key}.')
    else
      '$prefix${entry.key}': entry.value as String,
};

void main() {
  test('Thai and English catalogs have matching keys and placeholders', () {
    Map<String, String> load(String language) => flatten(
      jsonDecode(File('assets/translations/$language.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    final thai = load('th');
    final english = load('en');
    expect(english.keys.toSet(), thai.keys.toSet());
    final placeholder = RegExp(r'\{[^{}]+\}');
    for (final key in thai.keys) {
      expect(english[key]!.trim(), isNotEmpty, reason: key);
      expect(thai[key]!.trim(), isNotEmpty, reason: key);
      expect(
        placeholder.allMatches(english[key]!).map((m) => m[0]).toSet(),
        placeholder.allMatches(thai[key]!).map((m) => m[0]).toSet(),
        reason: key,
      );
    }
  });
  testWidgets('both catalogs are bundled for the default asset loader', (
    tester,
  ) async {
    for (final language in ['th', 'en']) {
      final catalog = await tester.runAsync(
        () => const RootBundleAssetLoader().load(
          'assets/translations',
          Locale(language),
        ),
      );
      expect(
        catalog?['settings']['title'],
        language == 'th' ? 'การตั้งค่า' : 'Settings',
      );
    }
  });
}
