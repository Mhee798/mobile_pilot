import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show listEquals;

import '../../../core/platform/mobile_pilot_platform.dart';
import 'ai_ui_nodes.dart';

/// Validates model arguments and serializes native mutations under a lease.
class AiDeviceActions {
  AiDeviceActions(this.platform);
  final MobilePilotPlatform platform;
  String? _session;
  String? _wait;
  int _epoch = 0;
  bool _cancelled = false;
  Map<String, dynamic>? _capture;
  int _captureSequence = 0;
  DateTime? _capturedAt;
  Uint8List? _pendingImage;
  String? _captureTree;
  List<Map<String, dynamic>>? _captureNodes;
  Uint8List? _referencePixels;
  String _treeSignature(List<Map<String, dynamic>> nodes) => jsonEncode(
    nodes
        .map(
          (n) => {
            for (final key in [
              'nodeId',
              'text',
              'contentDescription',
              'bounds',
              'checked',
              'enabled',
              'visible',
            ])
              key: n[key],
          },
        )
        .toList(),
  );

  String _treeAtPoint(
    List<Map<String, dynamic>> nodes,
    double x,
    double y,
    int width,
    int height,
  ) {
    final px = x * width;
    final py = y * height;
    return _treeSignature(
      nodes.where((node) {
        final bounds = node['bounds'];
        if (bounds is! Map) return true;
        final l = bounds['left'];
        final t = bounds['top'];
        final r = bounds['right'];
        final b = bounds['bottom'];
        if (l is! num || t is! num || r is! num || b is! num) return true;
        return px >= l && px < r && py >= t && py < b;
      }).toList(),
    );
  }

  Future<bool> _sameTargetPixels(
    Uint8List before,
    Uint8List after,
    double x,
    double y,
  ) async {
    if (listEquals(before, after)) return true;
    ui.Image? a;
    ui.Image? b;
    try {
      final codecA = await ui.instantiateImageCodec(before);
      try {
        a = (await codecA.getNextFrame()).image;
      } finally {
        codecA.dispose();
      }
      final codecB = await ui.instantiateImageCodec(after);
      try {
        b = (await codecB.getNextFrame()).image;
      } finally {
        codecB.dispose();
      }
      if (a.width != b.width || a.height != b.height) return false;
      final first = await a.toByteData(format: ui.ImageByteFormat.rawRgba);
      final second = await b.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (first == null || second == null) return false;
      final left = ((x * a.width) - a.width * .05).floor().clamp(
        0,
        a.width - 1,
      );
      final right = ((x * a.width) + a.width * .05).ceil().clamp(
        0,
        a.width - 1,
      );
      final top = ((y * a.height) - a.height * .05).floor().clamp(
        0,
        a.height - 1,
      );
      final bottom = ((y * a.height) + a.height * .05).ceil().clamp(
        0,
        a.height - 1,
      );
      for (var row = top; row <= bottom; row++) {
        for (var col = left; col <= right; col++) {
          final offset = (row * a.width + col) * 4;
          for (var channel = 0; channel < 3; channel++) {
            if (first.getUint8(offset + channel) !=
                second.getUint8(offset + channel)) {
              return false;
            }
          }
        }
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      a?.dispose();
      b?.dispose();
    }
  }

  void beginTurn() => _cancelled = false;
  Future<void> openTarget(String target) async {
    await platform.launchApp(target, runId: _session);
  }

  void invalidate() {
    _capture = null;
    _captureTree = null;
    _captureNodes = null;
    _referencePixels = null;
    _capturedAt = null;
    _pendingImage = null;
  }

  Uint8List? takeImage() {
    final image = _pendingImage;
    _pendingImage = null;
    return image;
  }

  Future<void> cancel() async {
    _cancelled = true;
    _epoch++;
    invalidate();
    // Attempt every cancellation even when one native request fails.
    await Future.wait([
      if (_session case final id?) platform.cancelCommandSession(id),
      if (_wait case final id?) platform.cancelUiWait(id),
      platform.cancelScreenActions(),
      platform.cancelScreenCapture(),
    ]);
  }

  void _check(int epoch) {
    if (_cancelled || epoch != _epoch) throw StateError('AI action cancelled');
  }

  Future<Map<String, dynamic>> _lease(
    String target,
    Future<Map<String, dynamic>> Function(String id, int epoch) work,
  ) async {
    final epoch = _epoch;
    _check(epoch);
    if (_session != null) throw StateError('An AI action is already running');
    final id = 'ai-action-${DateTime.now().microsecondsSinceEpoch}';
    _session = id;
    var completed = false;
    try {
      var readiness = await platform.getDeviceReadiness();
      _check(epoch);
      // Waiting here is safe: no command session/action has been dispatched.
      for (
        var attempt = 0;
        readiness?['connected'] == false && attempt < 4;
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        _check(epoch);
        readiness = await platform.getDeviceReadiness();
        _check(epoch);
      }
      if (readiness?['connected'] == false) {
        throw PlatformException(
          code: 'SERVICE_NOT_READY',
          message: 'Accessibility permission may be enabled, but the service is not connected. No action dispatched.',
        );
      }
      await platform
          .beginCommandSession(id, target)
          .timeout(const Duration(seconds: 3));
      _check(epoch);
      final result = await work(id, epoch);
      _check(epoch);
      completed = true;
      return result;
    } finally {
      try {
        if (completed) {
          await platform
              .finishCommandSession(id)
              .timeout(const Duration(seconds: 3));
        } else {
          await platform
              .cancelCommandSession(id)
              .timeout(const Duration(seconds: 3));
        }
      } finally {
        if (_session == id) _session = null;
      }
    }
  }

  Future<Map<String, dynamic>> execute(
    String name,
    Map<String, dynamic> args, {
    required String? target,
    required String? snapshotId,
    required String? nativeSnapshotId,
    required List<Map<String, dynamic>>? nodes,
  }) async {
    if (name == 'device_status') {
      final readiness = await platform.getDeviceReadiness();
      return {
        'accessibility_connected': readiness?['connected'],
        'active_window_available': readiness?['hasWindow'],
        'accessibility_enabled': await platform.isAccessibilityServiceEnabled(),
        'floating_enabled': await platform.getFloatingControlsEnabled(),
        'target_package': target,
      };
    }
    if (name == 'floating_controls') {
      final enabled = args['enabled'];
      if (enabled is! bool) {
        throw const FormatException('enabled must be boolean');
      }
      return await platform.setFloatingControlsEnabled(enabled) ??
          {'error': 'No overlay result'};
    }
    if (name == 'cancel_actions') {
      await cancel();
      return {
        'status': 'cancelled',
        'note': 'Previously dispatched actions may already have happened.',
      };
    }
    _check(_epoch);
    if (name == 'navigate' && {'home', 'recents'}.contains(args['action'])) {
      invalidate();
      return await platform.navigateGlobally(args['action'] as String) ??
          {'error': 'No navigation result'};
    }
    if (target == null || target.isEmpty) {
      throw const FormatException('Open/select a target app first');
    }
    return _lease(target, (id, epoch) async {
      Future<Map<String, dynamic>?> dispatch(
        String method,
        Map<String, dynamic> values,
      ) {
        _check(epoch);
        return platform.dispatchSessionAction(method, values, runId: id);
      }

      switch (name) {
        case 'keyboard_action':
          final key = args['key'];
          if (!{'default', 'search', 'next', 'enter'}.contains(key)) {
            throw const FormatException('Invalid keyboard key');
          }
          invalidate();
          return _observed(
            await dispatch('aiKeyboard', {
              'targetPackage': target,
              'key': key,
            }).timeout(const Duration(seconds: 13)),
          );
        case 'ui_action':
          var nodeId = args['node_id'];
          final action = args['action'];
          if (snapshotId == null ||
              args['snapshot_id'] != snapshotId ||
              nodes == null) {
            throw FormatException(
              'Snapshot reference does not match: received ${args['snapshot_id']}, current $snapshotId. Read the current UI and copy snapshot_id exactly.',
            );
          }
          final matches = nodes.where((n) => n['nodeId'] == nodeId).toList();
          if (nodeId is! String ||
              nodeId.isEmpty ||
              matches.length != 1 ||
              !{'tap', 'focus', 'replace', 'clear'}.contains(action)) {
            throw const FormatException('Invalid node or action');
          }
          final node = matches.single;
          if (node['password'] == true ||
              node['enabled'] == false ||
              node['visible'] == false) {
            throw const FormatException(
              'Node is hidden, disabled, or a password',
            );
          }
          final text = args['text'] ?? '';
          if (text is! String ||
              text.length > 2000 ||
              (action == 'replace' && !args.containsKey('text'))) {
            throw const FormatException(
              'replace requires text, max 2000 characters',
            );
          }
          final method = action == 'tap' ? 'tapElementById' : 'editElementById';
          if (action == 'tap') {
            nodeId = tapNodeId(node, nodes);
            if (nodeId == null) {
              throw const FormatException(
                'No clickable node/ancestor. Use focus for editable fields or a fresh screenshot.',
              );
            }
          }
          final values = <String, dynamic>{
            'targetPackage': target,
            'screenId': nativeSnapshotId,
            'nodeId': nodeId,
          };
          if (action != 'tap') {
            if (node['editable'] != true) {
              throw const FormatException('Node is not editable');
            }
            values.addAll({'action': action, 'text': text});
          }
          invalidate();
          final result = await dispatch(
            method,
            values,
          ).timeout(const Duration(seconds: 13));
          return _observed(result);
        case 'capture_screen':
          invalidate();
          final beforeCapture = _treeSignature(
            await platform.getUiTree(targetPackage: target, runId: id),
          );
          _check(epoch);
          await dispatch('armScreenCapture', {
            'targetPackage': target,
          }).timeout(const Duration(seconds: 3));
          for (var i = 0; i < 60; i++) {
            _check(epoch);
            final data = await platform.getCapturedScreen().timeout(
              const Duration(seconds: 2),
            );
            _check(epoch);
            if (data != null) {
              final bytes = data['jpeg'];
              final width = data['width'];
              final height = data['height'];
              final rotation = data['rotation'];
              if (data['packageName'] != target ||
                  bytes is! Uint8List ||
                  bytes.isEmpty ||
                  width is! int ||
                  width <= 0 ||
                  height is! int ||
                  height <= 0 ||
                  rotation is! int ||
                  rotation < 0 ||
                  rotation > 3) {
                throw const FormatException(
                  'Incomplete or wrong-target screenshot',
                );
              }
              _pendingImage = bytes;
              _referencePixels = bytes;
              _captureNodes = await platform.getUiTree(
                targetPackage: target,
                runId: id,
              );
              _captureTree = _treeSignature(_captureNodes!);
              _check(epoch);
              if (_captureTree != beforeCapture) {
                invalidate();
                throw const FormatException(
                  'Screen changed during capture. Capture again.',
                );
              }
              _capturedAt = DateTime.now();
              _capture = {
                'capture_id': 'img${++_captureSequence}',
                'packageName': target,
                'width': width,
                'height': height,
                'rotation': rotation,
              };
              return {'status': 'captured', ..._capture!};
            }
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
          throw TimeoutException('Screenshot timed out');
        case 'screen_action':
          final capture = _capture;
          if (capture == null ||
              capture['capture_id'] != args['capture_id'] ||
              capture['packageName'] != target ||
              DateTime.now().difference(_capturedAt!) >
                  const Duration(seconds: 30)) {
            throw const FormatException(
              'Capture is missing/expired. Capture the screen again.',
            );
          }
          final action = args['action'];
          const coordinateMethods = {
            'tap': 'queuePointTap',
            'double_tap': 'queueDoubleTap',
            'long_press': 'queueLongPress',
            'swipe': 'queueSwipe',
            'drag': 'queueDrag',
            'pinch': 'queuePinch',
          };
          final method = coordinateMethods[action];
          final pointAction = {
            'tap',
            'double_tap',
            'long_press',
          }.contains(action);
          final x = pointAction ? _number(args, 'x', 0, 1) : null;
          final y = pointAction ? _number(args, 'y', 0, 1) : null;
          final currentTree = await platform.getUiTree(
            targetPackage: target,
            runId: id,
          );
          _check(epoch);
          final treeMatches = pointAction && _captureNodes != null
              ? _treeAtPoint(
                      _captureNodes!,
                      x!,
                      y!,
                      capture['width'] as int,
                      capture['height'] as int,
                    ) ==
                    _treeAtPoint(
                      currentTree,
                      x,
                      y,
                      capture['width'] as int,
                      capture['height'] as int,
                    )
              : _captureTree == _treeSignature(currentTree);
          if (!treeMatches) {
            invalidate();
            throw const FormatException(
              'Screen content changed after capture. Capture again before acting.',
            );
          }
          if (method != null) {
            await dispatch('armScreenCapture', {
              'targetPackage': target,
            }).timeout(const Duration(seconds: 3));
            Map<dynamic, dynamic>? latest;
            for (var attempt = 0; attempt < 20; attempt++) {
              _check(epoch);
              latest = await platform.getCapturedScreen().timeout(
                const Duration(seconds: 2),
              );
              _check(epoch);
              if (latest != null) break;
              await Future<void>.delayed(const Duration(milliseconds: 250));
            }
            if (latest == null ||
                latest['packageName'] != target ||
                latest['width'] != capture['width'] ||
                latest['height'] != capture['height'] ||
                latest['rotation'] != capture['rotation'] ||
                latest['jpeg'] is! Uint8List ||
                _referencePixels == null ||
                !(pointAction
                    ? await _sameTargetPixels(
                        _referencePixels!,
                        latest['jpeg'] as Uint8List,
                        x!,
                        y!,
                      )
                    : listEquals(
                        _referencePixels,
                        latest['jpeg'] as Uint8List,
                      ))) {
              invalidate();
              throw const FormatException(
                'Screen pixels changed before coordinate action. Capture again; no gesture dispatched.',
              );
            }
          }
          final values = <String, dynamic>{
            for (final key in ['packageName', 'width', 'height', 'rotation'])
              key: capture[key],
          };
          if (method != null) {
            values['x'] = _number(args, 'x', 0, 1);
            values['y'] = _number(args, 'y', 0, 1);
            if (action == 'long_press' ||
                action == 'swipe' ||
                action == 'drag' ||
                action == 'pinch') {
              values['durationMs'] = _integer(
                args,
                'duration_ms',
                action == 'long_press' ? 500 : 100,
                3000,
                action == 'long_press' ? 1000 : 400,
              );
            }
            if (action == 'swipe' || action == 'drag') {
              values['endX'] = _number(args, 'end_x', 0, 1);
              values['endY'] = _number(args, 'end_y', 0, 1);
              if (values['x'] == values['endX'] &&
                  values['y'] == values['endY']) {
                throw const FormatException('Gesture endpoints must differ');
              }
            }
            if (action == 'drag') {
              values['holdMs'] = _integer(args, 'hold_ms', 500, 2000, 750);
            }
            if (action == 'pinch') {
              values['scale'] = _number(args, 'scale', 0.25, 4);
              if (values['scale'] == 1) {
                throw const FormatException('Pinch scale must differ from 1');
              }
              values['startSpan'] = _number(args, 'start_span', 0.05, 0.8, 0.3);
              values['axis'] = args['axis'] ?? 'horizontal';
              if (!{'horizontal', 'vertical'}.contains(values['axis'])) {
                throw const FormatException('Invalid pinch axis');
              }
            }
          } else {
            if (!{
              'scroll_up',
              'scroll_down',
              'swipe_left',
              'swipe_right',
              'back',
              'type_text',
              'keyboard',
            }.contains(action)) {
              throw const FormatException('Unknown screen action');
            }
            values['action'] = action;
            if (action == 'type_text' || action == 'keyboard') {
              final text = args['text'];
              if (text is! String ||
                  text.isEmpty ||
                  text.length > 2000 ||
                  (action == 'keyboard' &&
                      !{'default', 'search', 'next', 'enter'}.contains(text))) {
                throw const FormatException('Invalid text or keyboard key');
              }
              values['text'] = text;
            }
          }
          invalidate();
          final queued = await dispatch(
            method ?? 'queueScreenAction',
            values,
          ).timeout(const Duration(seconds: 3));
          if (queued?['code'] == null) {
            return {'error': 'No queue acknowledgement'};
          }
          for (var i = 0; i < 60; i++) {
            _check(epoch);
            final result = await platform.getPointTapResult().timeout(
              const Duration(seconds: 2),
            );
            _check(epoch);
            final code = result?['code'];
            if (code is String &&
                !{
                  'TAP_QUEUED',
                  'TAP_SENDING',
                  'TAP_WAITING_FOR_TARGET',
                  'ACTION_QUEUED',
                  'ACTION_SENDING',
                  'ACTION_WAITING_FOR_TARGET',
                }.contains(code)) {
              return _observed(result);
            }
            await Future<void>.delayed(const Duration(milliseconds: 250));
          }
          throw TimeoutException(
            'Queued action did not finish; cancellation requested',
          );
        case 'navigate':
          if (args['action'] != 'back') {
            throw const FormatException('Use back/home/recents');
          }
          // Native back is target-bound through a queued action with fresh metadata.
          final tree = await platform.getUiTree(
            targetPackage: target,
            runId: id,
          );
          _check(epoch);
          if (tree.isEmpty) {
            throw const FormatException('Target has no readable window');
          }
          return _observed(await dispatch('aiBack', {'targetPackage': target}));
        case 'scroll_until_ui':
          final selector = args['selector'];
          final value = args['value'];
          final direction = args['direction'];
          final distance = args['distance'] ?? 'long';
          if (!{
                'text',
                'contentDescription',
                'resourceId',
              }.contains(selector) ||
              value is! String ||
              value.trim().isEmpty ||
              value.length > 200 ||
              !{'up', 'down'}.contains(direction) ||
              !{'app', 'short', 'long'}.contains(distance)) {
            throw const FormatException(
              'Invalid scroll selector/direction/distance',
            );
          }
          final count = _integer(args, 'max_scrolls', 1, 40, 10);
          final seconds = _integer(args, 'timeout_seconds', 1, 60, 20);
          final request = 'ai-scroll-${DateTime.now().microsecondsSinceEpoch}';
          _wait = request;
          invalidate();
          try {
            final result = await dispatch('scrollUntilUi', {
              'requestId': request,
              'targetPackage': target,
              'selector': selector,
              'value': value.trim(),
              'direction': direction,
              'maxScrolls': count,
              'timeoutMs': seconds * 1000,
              'distance': distance,
            }).timeout(Duration(seconds: seconds + 2));
            return _observed(result);
          } finally {
            await platform.cancelUiWait(request);
            if (_wait == request) _wait = null;
          }
        default:
          throw const FormatException('Unknown action tool');
      }
    });
  }

  static Map<String, dynamic> _observed(Map<String, dynamic>? result) =>
      result == null || result['code'] is! String
      ? {'error': 'No result from Android'}
      : {
          for (final key in ['code', 'message', 'matchSeen'])
            if (result[key] != null) key: result[key],
          'verification_required': true,
          if (!{
            'ACTION_DISPATCHED',
            'INPUT_DISPATCHED',
            'TEXT_SET',
            'IME_DISPATCHED',
            'GESTURE_COMPLETED',
            'BACK_DISPATCHED',
            'UI_FOUND',
          }.contains(result['code']))
            'error': result['message'] ?? result['code'],
          'note': 'This is a dispatch/condition result, not proof the user goal succeeded. Read the UI again.',
        };

  static int _integer(
    Map<String, dynamic> args,
    String key,
    int min,
    int max,
    int fallback,
  ) {
    final value = args[key] ?? fallback;
    if (value is! int || value < min || value > max) {
      throw FormatException('$key must be an integer $min..$max');
    }
    return value;
  }

  static double _number(
    Map<String, dynamic> args,
    String key,
    double min,
    double max, [
    double? fallback,
  ]) {
    final value = args[key] ?? fallback;
    if (value is! num || !value.isFinite || value < min || value > max) {
      throw FormatException('$key must be $min..$max');
    }
    return value.toDouble();
  }
}
