import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../data/markdown_speech_text.dart';
import '../../../../core/settings/app_settings.dart';

/// Reads complete answers using the TTS engine installed on the device.
class AnswerSpeechControls extends StatefulWidget {
  const AnswerSpeechControls({
    super.key,
    required this.answer,
    required this.generating,
    required this.completed,
  });

  final String answer;
  final bool generating;
  final bool completed;

  @override
  State<AnswerSpeechControls> createState() => _AnswerSpeechControlsState();
}

class _AnswerSpeechControlsState extends State<AnswerSpeechControls> {
  final _tts = FlutterTts();
  bool _automatic = false;
  bool _speaking = false;
  int _operation = 0;

  @override
  void didUpdateWidget(AnswerSpeechControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_automatic &&
        oldWidget.generating &&
        !widget.generating &&
        widget.completed &&
        widget.answer.trim().isNotEmpty) {
      final answer = widget.answer;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _automatic &&
            !widget.generating &&
            widget.answer == answer) {
          unawaited(_speak(answer));
        }
      });
    }
  }

  Future<void> _stop() async {
    _operation++;
    try {
      await _tts.stop();
    } catch (_) {
      // Stopping is best effort when the platform engine is unavailable.
    }
    if (mounted) setState(() => _speaking = false);
  }

  Future<void> _speak(String text) async {
    final rate = AppSettingsScope.maybeOf(context)?.speechRate ?? 0.5;
    final operation = ++_operation;
    setState(() => _speaking = true);
    try {
      await _tts.stop();
      final available = await _tts.isLanguageAvailable('th-TH');
      if (available != true) {
        throw StateError(
          'ไม่พบเสียงภาษาไทย กรุณาติดตั้งเสียงไทยในการตั้งค่า Text-to-Speech ของเครื่อง',
        );
      }
      final language = await _tts.setLanguage('th-TH');
      if (language != 1) throw StateError('ตั้งค่าภาษาไทยไม่สำเร็จ');
      await _tts.setSpeechRate(rate);
      await _tts.awaitSpeakCompletion(true);
      if (operation != _operation || !mounted) return;
      final spoken = markdownSpeechText(text);
      if (spoken.isEmpty) throw StateError('ไม่มีข้อความให้อ่าน');
      final maxLength = Platform.isAndroid
          ? await _tts.getMaxSpeechInputLength ?? 1000
          : 1000;
      for (final chunk in speechChunks(spoken, maxLength.clamp(2, 1000))) {
        if (operation != _operation || !mounted) return;
        final result = await _tts.speak(chunk);
        if (result != 1) throw StateError('เครื่องไม่สามารถอ่านออกเสียงได้');
      }
    } catch (error) {
      if (mounted && operation == _operation) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('อ่านออกเสียงไม่สำเร็จ: $error')),
        );
      }
    } finally {
      if (mounted && operation == _operation) {
        setState(() => _speaking = false);
      }
    }
  }

  @override
  void dispose() {
    _operation++;
    if (_speaking) unawaited(_tts.stop().catchError((_) => null));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'เสียงอ่านคำตอบ',
    icon: Icon(_speaking ? Icons.volume_up : Icons.volume_up_outlined),
    onSelected: (action) {
      if (action == 'read') unawaited(_speak(widget.answer));
      if (action == 'stop') unawaited(_stop());
      if (action == 'auto') {
        setState(() => _automatic = !_automatic);
        if (!_automatic && _speaking) unawaited(_stop());
      }
    },
    itemBuilder: (context) => [
      PopupMenuItem(
        value: 'read',
        enabled: !widget.generating && widget.answer.trim().isNotEmpty,
        child: const Text('อ่านคำตอบ'),
      ),
      if (_speaking)
        const PopupMenuItem(value: 'stop', child: Text('หยุดเสียง')),
      CheckedPopupMenuItem(
        value: 'auto',
        checked: _automatic,
        child: const Text('อ่านอัตโนมัติ'),
      ),
    ],
  );
}

/// Splits on whitespace when possible, keeping UTF-16 surrogate pairs intact.
List<String> speechChunks(String text, int limit) {
  final chunks = <String>[];
  var rest = text;
  while (rest.length > limit) {
    var end = limit;
    final whitespace = rest.lastIndexOf(RegExp(r'\s'), end - 1);
    if (whitespace > 0) end = whitespace + 1;
    if (end < rest.length &&
        rest.codeUnitAt(end - 1) >= 0xD800 &&
        rest.codeUnitAt(end - 1) <= 0xDBFF) {
      end--;
    }
    chunks.add(rest.substring(0, end));
    rest = rest.substring(end);
  }
  if (rest.isNotEmpty) chunks.add(rest);
  return chunks;
}
