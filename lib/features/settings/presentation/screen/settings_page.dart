import 'package:easy_localization/easy_localization.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../../../core/platform/mobile_pilot_platform.dart';
import '../../../../core/settings/app_settings.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/settings_value_menu.dart';
import '../../../models/presentation/model_selection_scope.dart';
import '../../../models/presentation/screen/model_selection_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with WidgetsBindingObserver {
  static const _platform = MobilePilotPlatform();
  final _tts = FlutterTts();
  bool? _accessibility;
  bool? _floating;
  bool _updatingFloating = false;
  bool _speaking = false;
  bool _saving = false;
  int _speechOperation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshPermissions());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refreshPermissions());
    if (state != AppLifecycleState.resumed) unawaited(_stopSpeech());
  }

  Future<bool?> _readStatus(Future<bool?> Function() read) async {
    try {
      return await read();
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> _refreshPermissions() async {
    final results = await Future.wait([
      _readStatus(_platform.isAccessibilityServiceEnabled),
      _readStatus(_platform.getFloatingControlsEnabled),
    ]);
    if (!mounted) return;
    setState(() {
      _accessibility = results[0];
      _floating = results[1];
    });
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _openAccessibility() async {
    try {
      await _platform.openAccessibilitySettings();
    } catch (_) {
      if (mounted) _message(context.tr('settings.accessibility_error'));
    }
  }

  Future<void> _setFloating(bool enabled) async {
    if (_updatingFloating) return;
    setState(() => _updatingFloating = true);
    try {
      final response = await _platform.setFloatingControlsEnabled(enabled);
      if (!mounted) return;
      setState(() => _floating = response?['enabled'] as bool?);
      _message(context.tr('settings.floating_updated'));
    } catch (_) {
      if (mounted) _message(context.tr('settings.floating_error'));
    } finally {
      if (mounted) setState(() => _updatingFloating = false);
    }
  }

  Future<void> _save(Future<void> Function() save) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await save();
    } catch (_) {
      if (mounted) _message(context.tr('settings.save_error'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _stopSpeech() async {
    _speechOperation++;
    try {
      await _tts.stop();
    } catch (_) {
      // The device may not have a TTS engine.
    }
    if (mounted) setState(() => _speaking = false);
  }

  Future<void> _previewSpeech() async {
    if (_speaking) return _stopSpeech();
    final rate = AppSettingsScope.of(context).speechRate;
    final operation = ++_speechOperation;
    bool active() => mounted && operation == _speechOperation;
    setState(() => _speaking = true);
    try {
      if (await _tts.isLanguageAvailable('th-TH') != true) {
        throw StateError('ไม่พบเสียงภาษาไทย');
      }
      if (!active()) return;
      if (await _tts.setLanguage('th-TH') != 1) {
        throw StateError('ตั้งค่าภาษาไม่สำเร็จ');
      }
      if (!active()) return;
      await _tts.setSpeechRate(rate);
      if (!active()) return;
      await _tts.awaitSpeakCompletion(true);
      if (!active()) return;
      if (await _tts.speak(
            'สวัสดีค่ะ นี่คือตัวอย่างเสียงอ่านคำตอบจาก MobilePilot',
          ) !=
          1) {
        throw StateError('อ่านออกเสียงไม่สำเร็จ');
      }
    } catch (_) {
      if (mounted && active()) {
        _message(context.tr('settings.preview_error'));
      }
    } finally {
      if (active()) setState(() => _speaking = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _speechOperation++;
    if (_speaking) unawaited(_tts.stop().catchError((_) => null));
    super.dispose();
  }

  String _status(bool? enabled) => switch (enabled) {
    true => context.tr('settings.enabled'),
    false => context.tr('settings.disabled'),
    null => context.tr('settings.unknown'),
  };

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsScope.of(context);
    final models = ModelSelectionScope.maybeOf(context);
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.voidBase,
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.tr('common.back'),
          icon: const Icon(TablerIcons.chevron_left),
          onPressed: () => Navigator.of(context).pop(),
        ),
        centerTitle: true,
        title: Text(
          context.tr('settings.title'),
          style: Theme.of(context).textTheme.bodyMedium!
              .copyWith(fontSize: 15, fontWeight: FontWeight.w400),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            _group('AI', [
              ListTile(
                leading: Icon(TablerIcons.topology_star, size: 24),
                title: Text(context.tr('settings.model')),
                subtitle: Text(
                  models?.selection?.label ?? context.tr('models.none'),
                ),
                trailing: Icon(TablerIcons.chevron_right, size: 20),
                onTap: models == null
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const ModelSelectionPage(),
                        ),
                      ),
              ),
            ]),
            _group(context.tr('settings.device'), [
              ListTile(
                leading: const Icon(TablerIcons.accessible, size: 24),
                title: Text(context.tr('settings.accessibility')),
                subtitle: Text(
                  context.tr('settings.accessibility_description'),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _status(_accessibility),
                      style: Theme.of(context).textTheme.bodyMedium!
                          .copyWith(fontSize: 12, color: colors.textSecondary),
                    ),
                    const SizedBox(width: 4),
                    const Icon(TablerIcons.chevron_right, size: 20),
                  ],
                ),
                onTap: _openAccessibility,
              ),
              SwitchListTile(
                secondary: const Icon(TablerIcons.message, size: 24),
                title: Text(context.tr('settings.floating')),
                subtitle: Text(
                  _floating == null
                      ? context.tr('settings.status_unknown')
                      : context.tr('settings.floating_description'),
                ),
                value: _floating ?? false,
                onChanged: _updatingFloating || _floating == null
                    ? null
                    : _setFloating,
              ),
            ]),
            _group(context.tr('settings.appearance'), [
              ListTile(
                leading: const Icon(TablerIcons.moon, size: 24),
                title: Text(context.tr('settings.theme')),
                trailing: SettingsValueMenu<ThemeMode>(
                  tooltip: context.tr('settings.choose_theme'),
                  value: settings.themeMode,
                  options: {
                    ThemeMode.system: context.tr('settings.theme_system'),
                    ThemeMode.light: context.tr('settings.theme_light'),
                    ThemeMode.dark: context.tr('settings.theme_dark'),
                  },
                  onSelected: _saving
                      ? null
                      : (value) {
                          unawaited(_save(() => settings.setThemeMode(value)));
                        },
                ),
              ),
              ListTile(
                leading: const Icon(TablerIcons.language, size: 24),
                title: Text(context.tr('settings.language')),
                trailing: SettingsValueMenu<Locale>(
                  tooltip: context.tr('settings.choose_language'),
                  value: context.locale,
                  options: {
                    const Locale('th'): 'ไทย',
                    const Locale('en'): 'English',
                  },
                  onSelected: _saving
                      ? null
                      : (value) {
                          unawaited(_save(() => context.setLocale(value)));
                        },
                ),
              ),
            ]),
            _group(context.tr('settings.audio'), [
              ListTile(
                leading: Icon(TablerIcons.volume, size: 24),
                title: Text(context.tr('settings.voice')),
                subtitle: Text(context.tr('settings.voice_default')),
              ),
              ListTile(
                title: Text(context.tr('settings.speech_rate')),
                trailing: SettingsValueMenu<double>(
                  tooltip: context.tr('settings.choose_speech_rate'),
                  value: settings.speechRate,
                  options: {
                    0.25: context.tr('settings.rate_slow'),
                    0.5: context.tr('settings.rate_normal'),
                    0.75: context.tr('settings.rate_fast'),
                  },
                  onSelected: _saving
                      ? null
                      : (value) {
                          unawaited(_save(() => settings.setSpeechRate(value)));
                        },
                ),
              ),
              ListTile(
                leading: Icon(
                  _speaking ? TablerIcons.player_stop : TablerIcons.player_play,
                  size: 24,
                ),
                title: Text(
                  _speaking
                      ? context.tr('settings.stop_speech')
                      : context.tr('settings.preview_speech'),
                ),
                onTap: _previewSpeech,
              ),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              child: Text(
                context.tr('settings.speech_hint'),
                style: Theme.of(context).textTheme.bodyMedium!
                    .copyWith(color: colors.textSecondary, fontSize: 12),
              ),
            ),
            _group(context.tr('settings.about'), [
              ListTile(
                leading: const Icon(TablerIcons.info_circle, size: 24),
                title: Text(context.tr('settings.licenses')),
                trailing: const Icon(TablerIcons.chevron_right, size: 20),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'MobilePilot',
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _group(String title, List<Widget> children) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Text(
              title,
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                fontSize: 12,
                color: context.appColors.textSecondary,
              ),
            ),
          ),
          Material(
            color: scheme.outlineVariant.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(24),
            clipBehavior: Clip.antiAlias,
            child: ListTileTheme(
              data: ListTileThemeData(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                minLeadingWidth: 24,
                horizontalTitleGap: 12,
                textColor: scheme.onSurface,
                iconColor: scheme.onSurface,
                titleTextStyle: Theme.of(context).textTheme.bodyMedium!
                    .copyWith(fontSize: 14, color: scheme.onSurface),
                subtitleTextStyle: Theme.of(context).textTheme.bodyMedium!
                    .copyWith(
                      fontSize: 12,
                      color: context.appColors.textSecondary,
                    ),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: 1,
                        indent: 12,
                        endIndent: 12,
                        color: scheme.outlineVariant.withValues(alpha: 0.6),
                      ),
                    children[i],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
