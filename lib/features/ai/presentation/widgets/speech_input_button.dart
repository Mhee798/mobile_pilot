import 'dart:async';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Dictation is inserted into the draft only; it never submits a command.
class SpeechInputButton extends StatefulWidget {
  const SpeechInputButton({
    super.key,
    required this.controller,
    required this.enabled,
  });
  final TextEditingController controller;
  final bool enabled;

  @override
  State<SpeechInputButton> createState() => _SpeechInputButtonState();
}

class _SpeechInputButtonState extends State<SpeechInputButton>
    with WidgetsBindingObserver {
  final _speech = SpeechToText();
  bool _listening = false;
  bool _starting = false;
  double _soundLevel = 0;
  int _session = 0;
  Timer? _startTimeout;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _cancelListening() {
    if (!_listening && !_starting) return;
    _session++;
    _startTimeout?.cancel();
    _listening = false;
    _soundLevel = 0;
    _starting = false;
    unawaited(_speech.cancel().catchError((_) {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.of(context)?.isCurrent == false) _cancelListening();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && (_listening || _starting)) {
      setState(_cancelListening);
    }
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _start() async {
    if (_starting || _listening) return;
    final session = ++_session;
    setState(() => _starting = true);
    try {
      final available = await _speech.initialize();
      if (!mounted || session != _session || !widget.enabled) return;
      if (!available) {
        _message(
          'ไม่สามารถใช้ไมค์ได้ ตรวจสิทธิ์ไมโครโฟนและบริการรู้จำเสียงของเครื่อง',
        );
        return;
      }
      _speech.statusListener = (status) {
        if (mounted && session == _session && status == 'listening') {
          _startTimeout?.cancel();
        }
        if (mounted &&
            session == _session &&
            (status == 'done' || status == 'notListening')) {
          _startTimeout?.cancel();
          setState(() {
            _listening = false;
            _soundLevel = 0;
          });
        }
      };
      _speech.errorListener = (error) {
        if (mounted && session == _session) {
          _startTimeout?.cancel();
          setState(() {
            _listening = false;
            _soundLevel = 0;
          });
          _message('รู้จำเสียงไม่สำเร็จ: ${error.errorMsg}');
        }
      };
      setState(() => _listening = true);
      await _speech.listen(
        onSoundLevelChange: (level) {
          if (mounted && session == _session && _listening && level.isFinite) {
            // Android recognizers report different ranges. Clamp to a visual
            // range rather than treating this value as a calibrated meter.
            final normalized = (level / 10).clamp(0.0, 1.0);
            if ((normalized - _soundLevel).abs() >= 0.05) {
              setState(() => _soundLevel = normalized);
            }
          }
        },
        listenOptions: SpeechListenOptions(
          localeId: 'th_TH',
          partialResults: true,
          listenFor: const Duration(minutes: 1),
          pauseFor: const Duration(seconds: 8),
        ),
        onResult: (result) {
          if (!mounted ||
              session != _session ||
              !widget.enabled ||
              !result.finalResult) {
            return;
          }
          final text = result.recognizedWords.trim();
          if (text.isEmpty) return;
          final existing = widget.controller.text;
          final separator =
              existing.isEmpty ||
                  existing.endsWith(' ') ||
                  existing.endsWith('\n')
              ? ''
              : ' ';
          final combined = '$existing$separator$text';
          widget.controller.value = TextEditingValue(
            text: combined,
            selection: TextSelection.collapsed(offset: combined.length),
          );
        },
      );
      if (!mounted || session != _session || !widget.enabled) return;
      if (!_speech.isListening) {
        _startTimeout = Timer(const Duration(seconds: 3), () {
          if (mounted && session == _session && !_speech.isListening) {
            setState(() {
              _listening = false;
              _soundLevel = 0;
            });
            _message('เริ่มฟังเสียงไม่สำเร็จ กรุณาลองใหม่');
          }
        });
      }
    } catch (error) {
      if (mounted && session == _session) {
        setState(() {
          _listening = false;
          _soundLevel = 0;
        });
        _message('เปิดไมค์ไม่สำเร็จ: $error');
      }
    } finally {
      if (mounted && session == _session) setState(() => _starting = false);
    }
  }

  @override
  void didUpdateWidget(SpeechInputButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && oldWidget.enabled && (_listening || _starting)) {
      _cancelListening();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelListening();
    _session++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 48,
    height: 48,
    child: Stack(
      alignment: Alignment.center,
      children: [
        if (_listening)
          AnimatedContainer(
            key: const ValueKey('mic-level-ring'),
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            width: 30 + 16 * _soundLevel,
            height: 30 + 16 * _soundLevel,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).colorScheme.error
                    .withValues(alpha: .6),
                width: 2,
              ),
            ),
          ),
        IconButton(
          tooltip: _listening ? 'หยุดฟังเสียง' : 'พูดเป็นข้อความ',
          onPressed: !widget.enabled || _starting
              ? null
              : _listening
              ? () => unawaited(_speech.stop())
              : _start,
          icon: Icon(_listening ? Icons.mic : Icons.mic_none),
          color: _listening ? Theme.of(context).colorScheme.error : null,
        ),
      ],
    ),
  );
}
