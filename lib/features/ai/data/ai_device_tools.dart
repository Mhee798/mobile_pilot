import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';

import '../../../core/platform/mobile_pilot_platform.dart';
import 'ai_action_definitions.dart';
import 'ai_device_actions.dart';
import 'ai_ui_nodes.dart';
import 'ai_goal_check.dart';

/// Tools exposed to the model. Screen data is a previously captured snapshot.
class AiDeviceTools {
  static const _livePageSize = 10;
  AiDeviceTools({
    MobilePilotPlatform? platform,
    List<Map<String, dynamic>>? snapshot,
    String? targetPackage,
  }) : _platform = platform ?? const MobilePilotPlatform(),
       // The public argument name intentionally differs from the private field.
       // ignore: prefer_initializing_formals
       _targetPackage = targetPackage,
       _snapshot = snapshot
           ?.map((item) => Map<String, dynamic>.from(item))
           .toList(growable: false);

  final MobilePilotPlatform _platform;
  late final _actions = AiDeviceActions(_platform);
  List<Map<String, dynamic>>? _snapshot;
  bool _awaitingChoice = false;
  String? _targetPackage;
  List<Map<String, dynamic>>? _liveTree;
  String? _liveSnapshotId;
  String? _nativeSnapshotId;
  int _snapshotSequence = 0;
  int _nextRef = 0;
  final _refs = <int, String>{};
  int? _refFor(Map<String, dynamic> node) {
    for (final entry in _refs.entries) {
      if (entry.value == node['nodeId']) return entry.key;
    }
    return null;
  }

  String? _activeWaitId;
  bool _turnCancelled = false;
  String? get targetPackage => _targetPackage;
  List<Tool> get modelDefinitions => definitions
      .where(
        (tool) =>
            tool.name != 'read_ui_snapshot' || (_snapshot?.isNotEmpty ?? false),
      )
      .toList();

  /// Seed a new conversation, never replace an active task's target.
  void setInitialContext({
    List<Map<String, dynamic>>? snapshot,
    String? targetPackage,
  }) {
    _snapshot = snapshot
        ?.map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
    _setTarget(targetPackage);
  }

  void _setTarget(String? packageName) {
    _actions.invalidate();
    _targetPackage = packageName;
    _liveTree = null;
    _liveSnapshotId = null;
  }

  void clearPendingChoice() => _awaitingChoice = false;
  void beginTurn() {
    _turnCancelled = false;
    _actions.beginTurn();
  }

  Uint8List? takeCapturedImage() => _actions.takeImage();
  Future<void> cancelAll() {
    _turnCancelled = true;
    return Future.wait([cancelActiveWait(), _actions.cancel()]);
  }

  Future<void> cancelActiveWait() async {
    final id = _activeWaitId;
    if (id != null) await _platform.cancelUiWait(id);
  }

  Future<void> openTargetForReading() async {
    final target = _targetPackage;
    if (target == null) throw StateError('ยังไม่ได้เลือกแอปเป้าหมาย');
    await _actions.openTarget(target);
  }

  /// Called only after the UI has checked that the user selected a candidate.
  Future<Map<String, dynamic>> openSelected(String packageName) async {
    clearPendingChoice();
    try {
      final result = await _platform.launchApp(packageName);
      _setTarget(result?['code'] == 'TARGET_READY' ? packageName : null);
      return result?['code'] == 'TARGET_READY'
          ? {'status': 'opened'}
          : {'status': 'unconfirmed'};
    } on PlatformException catch (error) {
      _setTarget(null);
      if (error.code == 'TARGET_NOT_READY') {
        return {'status': 'unconfirmed', 'message': error.message};
      }
      return {'status': 'error', 'message': error.message ?? error.code};
    } on MissingPluginException {
      _setTarget(null);
      return {'status': 'error', 'message': 'ไม่พบเครื่องมือเปิดแอป'};
    }
  }

  static const definitions = [
    Tool(
      name: 'verify_goal',
      description: 'Verify evidence on the destination with a NEW read. Copy one unique label from the latest UI that distinguishes the requested destination.',
      parameters: {
        'type': 'object',
        'properties': {
          'label': {'type': 'string'},
        },
        'required': ['label'],
      },
    ),
    ...aiActionDefinitions,
    Tool(
      name: 'wait_for_ui',
      description: 'Wait for an element in the selected foreground app. This does not tap or change the screen. Disappearance means the element was first seen and then disappeared, not that a transaction succeeded.',
      parameters: {
        'type': 'object',
        'properties': {
          'selector': {
            'type': 'string',
            'enum': ['text', 'contentDescription', 'resourceId'],
          },
          'value': {
            'type': 'string',
            'description': 'Exact element text, description, or resource ID',
          },
          'condition': {
            'type': 'string',
            'enum': ['present', 'enabled', 'disappeared', 'textChanged'],
          },
          'timeout_seconds': {
            'type': 'integer',
            'description': 'Timeout from 1 to 60 seconds',
          },
        },
        'required': ['selector', 'value', 'condition', 'timeout_seconds'],
      },
    ),
    Tool(
      name: 'read_current_ui',
      description: 'Read selected foreground app, up to 10 elements. Each has a numeric ref for ui_action/verify_goal. Refs expire on a new read/action. Page further only if the desired item is missing.',
      parameters: {'type': 'object', 'properties': {}},
    ),
    Tool(
      name: 'read_ui_page',
      description: 'Read a later page of the most recently read UI snapshot. This is saved data and may no longer match the current screen.',
      parameters: {
        'type': 'object',
        'properties': {
          'snapshot_id': {
            'type': 'string',
            'description': 'snapshot_id returned by read_current_ui',
          },
          'offset': {
            'type': 'integer',
            'description': 'Zero-based offset returned as next_offset',
          },
        },
        'required': ['offset'],
      },
    ),
    Tool(
      name: 'open_app',
      description: 'Open an installed app by its name. Searches first; if several apps match, ask the user which one. The result confirms the target app was foreground only when status is opened.',
      parameters: {
        'type': 'object',
        'properties': {
          'name': {
            'type': 'string',
            'description': 'The name of the app the user asked to open',
          },
        },
        'required': ['name'],
      },
    ),
    Tool(
      name: 'find_apps',
      description: 'Search installed launchable apps by name. This only searches, it does not open an app.',
      parameters: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': 'App name to search for'},
        },
        'required': ['query'],
      },
    ),
    Tool(
      name: 'read_ui_snapshot',
      description: 'Read the UI tree previously captured by the user. It is a possibly stale snapshot, not the current screen, and may not match an attached image.',
      parameters: {'type': 'object', 'properties': {}},
    ),
  ];

  Future<Map<String, dynamic>> execute(
    String name,
    Map<String, dynamic> args,
  ) async {
    var mutation = {
      'ui_action',
      'screen_action',
      'navigate',
      'scroll_until_ui',
      'cancel_actions',
    }.contains(name);
    try {
      if (_turnCancelled && name != 'device_status') {
        return {
          'error': 'This AI turn was cancelled. No action performed.',
          'code': 'ACTION_CANCELLED',
        };
      }
      if (name == 'verify_goal') {
        if (args.containsKey('label')) {
          args = {'ref': _refByLabel(args['label'])};
        }
        if (args.containsKey('ref')) {
          args = {
            'refs': [args['ref']],
          };
        }
        if (args.containsKey('refs')) {
          final refs = args['refs'];
          if (refs is! List ||
              refs.isEmpty ||
              refs.length > 5 ||
              _liveTree == null) {
            throw const FormatException(
              'Choose 1..5 refs from a fresh UI read',
            );
          }
          final conditions = <Map<String, dynamic>>[];
          for (final ref in refs) {
            final key = parseUiRef(ref);
            if (key == null || !_refs.containsKey(key)) {
              throw FormatException(
                'Invalid or expired ref=$ref (${ref.runtimeType}); copy a ref value from the latest UI read, not its list position. Current first-page refs: ${_refs.keys.take(_livePageSize).toList()}.',
              );
            }
            final node = _liveTree!.singleWhere(
              (n) => n['nodeId'] == _refs[key],
            );
            String? selector;
            for (final key in ['resourceId', 'text', 'contentDescription']) {
              if (node[key] is String &&
                  (node[key] as String).isNotEmpty &&
                  _liveTree!.where((n) => n[key] == node[key]).length == 1) {
                selector = key;
                break;
              }
            }
            if (selector == null) {
              throw const FormatException(
                'Evidence is ambiguous; choose a uniquely labelled ref',
              );
            }
            final property =
                node['checkable'] == true && node['checked'] is bool
                ? 'checked'
                : 'present';
            conditions.add({
              'selector': selector,
              'value': node[selector],
              'property': property,
              'expected': property == 'checked' ? node['checked'] : true,
            });
          }
          args = {'conditions': conditions};
        }
        // Validate before reading; never act or retry as part of verification.
        checkUiGoal(args['conditions'], const []);
        final page = await execute('read_current_ui', {});
        if (page['status'] != 'ok') {
          return {
            'error': page['error'] ?? 'Fresh read failed',
            'code': 'VERIFICATION_UNAVAILABLE',
          };
        }
        return {
          ...checkUiGoal(args['conditions'], _liveTree ?? const []),
          'snapshot_id': _liveSnapshotId,
        };
      }
      if (aiActionDefinitions.any((tool) => tool.name == name)) {
        if (name == 'ui_action' && args.containsKey('label')) {
          args = {...args, 'ref': _refByLabel(args['label'])};
        }
        if (name == 'ui_action' && args.containsKey('ref')) {
          final ref = parseUiRef(args['ref']);
          if (ref == null || !_refs.containsKey(ref) || _liveTree == null) {
            throw FormatException(
              'Expired or invalid ref=${args['ref']}. Copy a current ref value, not its list position. Current first-page refs: ${_liveTree == null ? <int>[] : _refs.keys.take(_livePageSize).toList()}. No action performed.',
            );
          }
          args = {
            ...args,
            'snapshot_id': _liveSnapshotId,
            'node_id': _refs[ref],
          };
        }
        if (name == 'cancel_actions') {
          _turnCancelled = true;
          await cancelActiveWait();
        }
        final result = await _actions.execute(
          name,
          args,
          target: _targetPackage,
          snapshotId: _liveSnapshotId,
          nativeSnapshotId: _nativeSnapshotId,
          nodes: _liveTree,
        );
        if (name == 'scroll_until_ui' && result['code'] == 'UI_FOUND') {
          final page = await execute('read_current_ui', {});
          if (page['status'] == 'ok' && _liveTree != null) {
            final matches = _liveTree!.where((node) {
              final candidate = node[args['selector']];
              final value = args['value'] as String;
              return args['selector'] == 'resourceId'
                  ? candidate == value
                  : candidate is String &&
                        candidate.trim().toLowerCase() ==
                            value.trim().toLowerCase();
            }).toList();
            result['snapshot_id'] = _liveSnapshotId;
            result['matched_elements'] = matches
                .take(5)
                .map(
                  (node) => {
                    ...modelUiNode(node, _liveTree!),
                    'ref': _refFor(node),
                    'snapshot_id': _liveSnapshotId,
                    'node_id': node['nodeId'],
                  },
                )
                .toList();
            result['note'] = 'Found is not tapped. Use ui_action with this snapshot_id and a matched node_id; do not scroll for it again.';
            mutation = false;
          } else {
            result['read_error'] =
                page['error'] ?? 'The item changed; read the UI again.';
          }
        }
        return result;
      }
      switch (name) {
        case 'wait_for_ui':
          final target = _targetPackage;
          final selector = args['selector'];
          final value = args['value'];
          final condition = args['condition'];
          final seconds = args['timeout_seconds'];
          if (target == null || target.isEmpty) {
            return {'error': 'No target app selected.'};
          }
          if (!{
                'text',
                'contentDescription',
                'resourceId',
              }.contains(selector) ||
              value is! String ||
              value.trim().isEmpty ||
              value.length > 200 ||
              !{
                'present',
                'enabled',
                'disappeared',
                'textChanged',
              }.contains(condition) ||
              (condition == 'textChanged' && selector == 'text') ||
              seconds is! int ||
              seconds < 1 ||
              seconds > 60) {
            return {
              'error': 'Invalid wait arguments. Use a supported selector and condition, a value of 1–200 characters, and a timeout of 1–60 seconds. textChanged requires resourceId or contentDescription.',
            };
          }
          final requestId = 'ai-wait-${DateTime.now().microsecondsSinceEpoch}';
          _activeWaitId = requestId;
          try {
            final response = await _platform
                .waitForUi(
                  requestId: requestId,
                  targetPackage: target,
                  selector: selector as String,
                  value: value.trim(),
                  condition: condition as String,
                  timeoutMs: seconds * 1000,
                )
                .timeout(Duration(seconds: seconds + 2));
            if (response?['code'] is! String) {
              return {'error': 'The wait result was incomplete.'};
            }
            return {
              'code': response!['code'],
              'message': response['message'],
              'match_seen': response['matchSeen'],
              'note': 'The result describes the UI condition only; it does not confirm a transaction.',
            };
          } on TimeoutException {
            unawaited(_platform.cancelUiWait(requestId).catchError((_) {}));
            return {
              'error': 'No response from Android; cancellation was requested.',
              'code': 'TIMEOUT',
            };
          } finally {
            if (_activeWaitId == requestId) _activeWaitId = null;
          }
        case 'open_app':
          final query = args['name'];
          if (query is! String || query.trim().isEmpty || query.length > 100) {
            return {'error': 'Provide an app name of 1 to 100 characters.'};
          }
          if (_awaitingChoice) {
            return {
              'status': 'ambiguous',
              'message': 'Wait for the user to choose an app; do not open one automatically.',
            };
          }
          final search = query.trim();
          final apps = await _platform.findLaunchableApps(search);
          if (_turnCancelled) {
            return {
              'error': 'Cancelled before app launch',
              'code': 'ACTION_CANCELLED',
            };
          }
          final exact = apps
              .where(
                (app) => app['label']!.toLowerCase() == search.toLowerCase(),
              )
              .toList();
          final matches = exact.isNotEmpty ? exact : apps;
          if (matches.isEmpty) {
            return {
              'status': 'not_found',
              'message': 'No launchable app matches this name.',
            };
          }
          if (matches.length != 1) {
            _awaitingChoice = true;
            return {
              'status': 'ambiguous',
              'message': 'Ask the user which app they mean.',
              'apps': matches.take(20).toList(),
              'truncated': matches.length > 20,
            };
          }
          final app = matches.single;
          _setTarget(null);
          final result = await _platform.launchApp(app['packageName']!);
          if (result?['code'] != 'TARGET_READY') {
            return {
              'status': 'unconfirmed',
              'message': 'The app launch could not be verified.',
              'app': app,
            };
          }
          _setTarget(app['packageName']);
          return {
            'status': 'opened',
            'app': app,
            'message':
                'The target app was confirmed in the foreground at launch.',
          };
        case 'find_apps':
          final query = args['query'];
          if (query is! String || query.trim().isEmpty || query.length > 100) {
            return {'error': 'Provide an app name of 1 to 100 characters.'};
          }
          final apps = await _platform.findLaunchableApps(query.trim());
          return {
            'apps': apps.take(20).toList(),
            'truncated': apps.length > 20,
          };
        case 'read_current_ui':
          final target = _targetPackage;
          if (target == null || target.isEmpty) {
            return {
              'error': 'No target app selected. Open an app using open_app or select one on the command page.',
            };
          }
          _liveTree = null;
          _liveSnapshotId = null;
          final nodes = await _platform
              .getUiTree(targetPackage: target)
              .timeout(const Duration(seconds: 13));
          final visible = nodes
              .where((node) => node['password'] != true)
              .toList();
          if (visible.any((node) => node['packageName'] != target)) {
            return {
              'error': 'The returned screen does not match the target app.',
            };
          }
          if (visible.isEmpty) {
            return {
              'status': 'ok',
              'packageName': target,
              'total': 0,
              'elements': <Object>[],
            };
          }
          final id = visible.first['screenId'];
          if (id is! String ||
              id.isEmpty ||
              visible.any((node) => node['screenId'] != id)) {
            return {
              'error':
                  'The screen snapshot is incomplete. Read the screen again.',
            };
          }
          // Labels first: unnamed clickable containers must not crowd them out.
          bool informative(Map<String, dynamic> node) =>
              (node['text'] is String &&
                  (node['text'] as String).trim().isNotEmpty) ||
              (node['contentDescription'] is String &&
                  (node['contentDescription'] as String).trim().isNotEmpty);
          _liveTree = [
            ...visible.where(informative),
            ...visible.where((node) => !informative(node)),
          ];
          _nativeSnapshotId = id;
          _refs.clear();
          for (final node in _liveTree!) {
            _refs[++_nextRef] = node['nodeId'] as String;
          }
          _liveSnapshotId = 'ui${++_snapshotSequence}';
          return _livePage(0);
        case 'read_ui_page':
          final id = args['snapshot_id'] ?? _liveSnapshotId;
          final offset = args['offset'];
          if (id is! String ||
              id != _liveSnapshotId ||
              _liveTree == null ||
              offset is! int ||
              offset < 0 ||
              offset >= _liveTree!.length) {
            return {
              'error': 'Invalid or expired snapshot or offset. Read the current screen again.',
            };
          }
          return _livePage(offset);
        case 'read_ui_snapshot':
          final snapshot = _snapshot;
          if (snapshot == null || snapshot.isEmpty) {
            return {
              'error': 'No saved UI tree. Read the UI tree on the command page and reopen this chat.',
            };
          }
          final visible = snapshot
              .where((node) => node['password'] != true)
              .toList();
          return {
            'source': 'previously read UI tree; may be stale and may not match the image',
            'total': visible.length,
            'truncated': visible.length > 40,
            'elements': visible
                .take(40)
                .map(
                  (node) => {
                    for (final key in [
                      'text',
                      'contentDescription',
                      'resourceId',
                      'clickable',
                      'editable',
                      'enabled',
                      'visible',
                      'bounds',
                    ])
                      if (node[key] != null)
                        key:
                            node[key] is String &&
                                (node[key] as String).length > 150
                            ? (node[key] as String).substring(0, 150)
                            : node[key],
                  },
                )
                .toList(),
          };
        default:
          return {'error': 'Unknown tool: $name'};
      }
    } on FormatException catch (error) {
      return {'error': error.message, 'code': 'INVALID_ARGUMENT'};
    } on StateError catch (error) {
      return {'error': error.message, 'code': 'ACTION_CANCELLED'};
    } on TimeoutException catch (error) {
      return {
        'error':
            error.message ??
            'The device tool timed out. The target app may not be ready.',
        'code': 'TIMEOUT',
      };
    } on PlatformException catch (error) {
      if (name == 'open_app' && error.code == 'TARGET_NOT_READY') {
        return {
          'status': 'unconfirmed',
          'message': error.message ?? 'The app may have launched but foreground status was not verified.',
        };
      }
      return {'error': error.message ?? error.code, 'code': error.code};
    } on MissingPluginException {
      return {'error': 'Device tools are unavailable on this device.'};
    } finally {
      if (mutation) {
        _liveTree = null;
        _liveSnapshotId = null;
      }
    }
  }

  int _refByLabel(Object? label) {
    if (label is! String || label.isEmpty || _liveTree == null) {
      throw const FormatException(
        'Read the current UI and copy one exact label.',
      );
    }
    final matches = _liveTree!.where((node) {
      return uiNodeLabel(node) == label;
    }).toList();
    if (matches.length != 1) {
      throw const FormatException(
        'Label is missing or ambiguous; no action performed. Read the UI and choose a unique label.',
      );
    }
    return _refFor(matches.single)!;
  }

  Map<String, dynamic> _livePage(int offset) {
    final tree = _liveTree!;
    final end = (offset + _livePageSize).clamp(0, tree.length);
    return {
      'status': 'ok',
      'source': 'UI tree read from the target foreground app; snapshot may change later',
      'packageName': _targetPackage,
      'snapshot_id': _liveSnapshotId,
      'total': tree.length,
      'offset': offset,
      'next_offset': end < tree.length ? end : null,
      'elements': tree
          .skip(offset)
          .take(_livePageSize)
          .map(
            (node) => {
              ...modelUiNode(node, tree),
              'ref': _refFor(node),
              'snapshot_id': _liveSnapshotId,
              'node_id': node['nodeId'],
            },
          )
          .toList(),
    };
  }
}
