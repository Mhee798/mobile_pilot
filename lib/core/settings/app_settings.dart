import 'package:flutter/material.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:path_provider/path_provider.dart';

/// App-wide preferences; device permissions stay owned by Android.
class AppSettings extends ChangeNotifier {
  AppSettings({Future<Box<dynamic>> Function()? openStore})
    : _openStore = openStore ?? _openDefaultStore;

  final Future<Box<dynamic>> Function() _openStore;
  Future<void>? _loading;

  static Future<Box<dynamic>> _openDefaultStore() async {
    final directory = await getApplicationSupportDirectory();
    return Hive.openBox<dynamic>('app_settings_v1', path: directory.path);
  }

  Box<dynamic>? _box;
  ThemeMode _themeMode = ThemeMode.system;
  static const speechRates = [0.25, 0.5, 0.75];
  double _speechRate = 0.5;
  bool _disposed = false;
  ThemeMode get themeMode => _themeMode;
  double get speechRate => _speechRate;

  Future<void> load() =>
      _loading ??= _load().onError((Object error, StackTrace stack) {
        _loading = null;
        Error.throwWithStackTrace(error, stack);
      });

  Future<void> _load() async {
    final box = await _openStore();
    if (_disposed) return;
    _box = box;
    final theme = box.get('theme');
    _themeMode = ThemeMode.values.firstWhere(
      (value) => value.name == theme,
      orElse: () => ThemeMode.system,
    );
    final rate = box.get('speechRate');
    if (rate is num && speechRates.contains(rate)) {
      _speechRate = rate.toDouble();
    }
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode value) =>
      _save('theme', value.name, () => _themeMode = value);

  Future<void> setSpeechRate(double value) {
    if (!speechRates.contains(value)) {
      throw ArgumentError.value(
        value,
        'value',
        'Unsupported speech-rate preset',
      );
    }
    return _save('speechRate', value, () => _speechRate = value);
  }

  Future<void> _save(String key, Object value, VoidCallback apply) async {
    await load();
    final box = _box;
    if (box == null) throw StateError('Settings storage is unavailable');
    await box.put(key, value);
    if (_disposed) return;
    apply();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class AppSettingsScope extends InheritedNotifier<AppSettings> {
  const AppSettingsScope({
    super.key,
    required AppSettings settings,
    required super.child,
  }) : super(notifier: settings);

  static AppSettings? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppSettingsScope>()?.notifier;

  static AppSettings of(BuildContext context) => maybeOf(context)!;
}
