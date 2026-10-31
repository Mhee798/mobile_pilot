import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';

import '../../../core/platform/mobile_pilot_platform.dart';
import 'ai_action_definitions.dart';
import 'ai_device_actions.dart';
import 'ai_ui_nodes.dart';
import 'ai_goal_check.dart';
import 'ai_model_payload.dart';
import 'system_settings_destinations.dart';

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
  String? _selectedFileText;
  String? _selectedFileName;
  void selectTextFile(String? name, String? content) {
    _selectedFileName = name;
    _selectedFileText = content;
  }

  String _userRequest = '';
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
  void invalidateObservations() {
    _actions.invalidate();
    _liveTree = null;
    _liveSnapshotId = null;
    _nativeSnapshotId = null;
    _refs.clear();
  }

  void beginTurn({String userRequest = ''}) {
    _turnCancelled = false;
    _userRequest = userRequest;
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
      name: 'read_selected_file',
      description: 'Read the text file explicitly selected by the user in this chat. No file access is possible unless the user selected it. Content may be sent to the model.',
      parameters: {'type': 'object', 'properties': {}},
    ),
    Tool(
      name: 'media_control',
      description: 'Dispatch media play, pause, next, or previous to the Android media session. The target and effect are not verified; do not claim playback changed.',
      parameters: {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'enum': ['play', 'pause', 'next', 'previous'],
          },
        },
        'required': ['action'],
      },
    ),
    Tool(
      name: 'open_map',
      description: 'Open a map search for a location explicitly given by the user. Android chooses the app. Opening does not verify location.',
      parameters: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string'},
        },
        'required': ['query'],
      },
    ),
    Tool(
      name: 'prepare_alarm',
      description: 'Open a clock app with an explicitly requested time, 24-hour hour and minute. The user reviews the alarm; do not claim it was saved.',
      parameters: {
        'type': 'object',
        'properties': {
          'hour': {'type': 'integer'},
          'minute': {'type': 'integer'},
        },
        'required': ['hour', 'minute'],
      },
    ),
    Tool(
      name: 'open_link',
      description: 'Open an http or https link provided verbatim in the current user request. Android chooses the app; dispatch does not prove which page opened. Never invent links.',
      parameters: {
        'type': 'object',
        'properties': {
          'url': {'type': 'string'},
        },
        'required': ['url'],
      },
    ),
    Tool(
      name: 'device_info',
      description: 'Read device model, Android version, battery percentage, charging and internal storage capacity. Does not change settings.',
      parameters: {'type': 'object', 'properties': {}},
    ),
    Tool(
      name: 'media_volume',
      description: 'Read media volume, or set it to an integer from 0 to the reported maximum. Read first when the maximum is unknown.',
      parameters: {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'enum': ['get', 'set'],
          },
          'value': {'type': 'integer'},
        },
        'required': ['action'],
      },
    ),
    Tool(
      name: 'report_observation',
      description: 'Finish an information-reading request by reporting observed UI facts. Only use when the user asked to read/list/explain and all requested navigation is done. NEVER use to claim an unfinished action such as playing music succeeded. The app attaches the latest observed UI as evidence automatically. Give a concise answer in the user language. Mention unread pages and uncertainty.',
      parameters: {
        'type': 'object',
        'properties': {
          'summary': {'type': 'string'},
        },
        'required': ['summary'],
      },
    ),
    Tool(
      name: 'verify_goal',
      description: 'Verify evidence on the destination with a NEW read. REQUIRED ref: copy the actual ref alias from the latest UI element. Set complete=true only if the entire original user request is complete; use false for intermediate evidence. A match confirms only the chosen evidence, not the full task.',
      parameters: {
        'type': 'object',
        'properties': {
          'ref': {'type': 'string'},
          'complete': {'type': 'boolean'},
        },
        'required': ['ref', 'complete'],
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
      name: 'open_system_settings',
      description: 'Open a documented Android settings page directly; opening a page does not change a setting. Read the page afterwards. If unavailable, use open_app to navigate Settings normally. For app_details use a packageName from find_apps.',
      parameters: {
        'type': 'object',
        'properties': {
          'destination': {'type': 'string', 'enum': systemSettingsDestinations},
          'packageName': {
            'type': 'string',
            'description': 'Required only for app_details; use a packageName from find_apps.',
          },
        },
        'required': ['destination'],
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
      'keyboard_action',
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
        if (args.containsKey('label') && !args.containsKey('ref')) {
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
                'Invalid or expired ref=$ref (${ref.runtimeType}); copy a ref value from the latest UI read, not its list position. Current first-page refs: ${_refs.keys.take(_livePageSize).map(uiRefAlias).toList()}.',
              );
            }
            final node = _liveTree!.singleWhere(
              (n) => n['nodeId'] == _refs[key],
            );
            if (node['editable'] == true) {
              return {
                'status': 'insufficient_evidence',
                'code': 'EDITABLE_EVIDENCE',
                'error': 'An editable field only proves text is present in the input. It does not establish search results or completion of the full request. Choose non-editable evidence of the requested result, or report that it cannot be confirmed.',
              };
            }
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
      if (name == 'report_observation') {
        final summary = args['summary'];
        if (_liveTree == null ||
            summary is! String ||
            summary.trim().isEmpty ||
            summary.length > 4000 ||
            _refs.isEmpty) {
          throw const FormatException(
            'Read current UI if unavailable, then correct only the summary (1..4000 characters). Do not navigate or change the device to repair a report.',
          );
        }
        final evidence = modelPayload('read_current_ui', _livePage(0));
        final elements = (evidence['elements'] as List).whereType<Map>();
        final labels = <String>{};
        for (final item in elements) {
          final label = item['label'];
          if (label is String && label.trim().isNotEmpty) {
            labels.add(label.trim());
          }
        }
        if (labels.isEmpty) {
          throw const FormatException(
            'No readable UI labels on the current page. Read another page or report that the data is unavailable.',
          );
        }
        return {
          'status': 'observation_report',
          'summary':
              'ข้อมูลที่อ่านได้จากหน้าจอ (รายการข้อความซ้ำถูกรวม):\n${labels.map((label) => '- $label').join('\n')}${evidence['next_offset'] != null ? '\nยังมีรายการหน้าถัดไปที่ไม่ได้แสดง' : ''}',
          'evidence': evidence,
          'snapshot_id': _liveSnapshotId,
          'goal_completion_not_proven': true,
        };
      }
      if (aiActionDefinitions.any((tool) => tool.name == name)) {
        if (name == 'ui_action' &&
            !args.containsKey('ref') &&
            !args.containsKey('label') &&
            !args.containsKey('node_id')) {
          throw const FormatException(
            'ui_action requires ref copied from the latest UI element or an exact unique label. '
            'text is replacement content only, never a tap target. '
            'Call read_current_ui, then use {"ref": <actual ref>, "action": "tap"}. '
            'No action performed. Do not invent snapshot_id or a target.',
          );
        }
        if (name == 'ui_action' &&
            args.containsKey('label') &&
            !args.containsKey('ref')) {
          args = {...args, 'ref': _refByLabel(args['label'])};
        }
        if (name == 'ui_action' && args.containsKey('ref')) {
          final ref = parseUiRef(args['ref']);
          if (ref == null || !_refs.containsKey(ref) || _liveTree == null) {
            throw FormatException(
              'Expired or invalid ref=${args['ref']}. Copy a current ref value, not its list position. Current first-page refs: ${_liveTree == null ? <int>[] : _refs.keys.take(_livePageSize).map(uiRefAlias).toList()}. No action performed.',
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
        if (name == 'ui_action' &&
            args['action'] == 'replace' &&
            result['error'] == null) {
          result['text_replacement_dispatched'] = true;
        }
        if (name == 'capture_screen' && result['status'] == 'captured') {
          // Capturing reads native trees internally, consuming the older native
          // snapshot. Publish and cache one new UI reference set with the image.
          final page = await execute('read_current_ui', {});
          if (page['status'] == 'ok') {
            result['ui_after_capture'] = modelPayload('read_current_ui', page);
          } else {
            _liveTree = null;
            _liveSnapshotId = null;
            _nativeSnapshotId = null;
            _refs.clear();
            result['ui_refresh_error'] =
                page['error'] ??
                'UI refresh unavailable; read UI before using labels.';
          }
        }
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
        case 'read_selected_file':
          if (_selectedFileName == null || _selectedFileText == null) {
            return {
              'error': 'No text file selected by the user.',
              'code': 'NO_FILE_SELECTED',
            };
          }
          return {
            'status': 'ok',
            'name': _selectedFileName,
            'file_text': _selectedFileText,
          };
        case 'media_control':
          final action = args['action'];
          if (action is! String ||
              !{'play', 'pause', 'next', 'previous'}.contains(action)) {
            return {
              'error': 'Unknown media action',
              'code': 'INVALID_ARGUMENT',
            };
          }
          final response = await _platform.mediaControl(action);
          return response == null
              ? {'error': 'No media result'}
              : {'status': 'dispatched_unconfirmed', ...response};
        case 'open_map':
          final query = args['query'];
          if (query is! String ||
              query.trim().isEmpty ||
              query.length > 500 ||
              !_userRequest.contains(query)) {
            return {
              'error': 'Provide a location explicitly stated in the current request.',
              'code': 'INVALID_ARGUMENT',
            };
          }
          _setTarget(null);
          final response = await _platform.openMap(query);
          return response == null
              ? {'error': 'No map launch result'}
              : {'status': 'dispatched_unconfirmed', ...response};
        case 'prepare_alarm':
          final hour = args['hour'];
          final minute = args['minute'];
          if (hour is! int ||
              hour < 0 ||
              hour > 23 ||
              minute is! int ||
              minute < 0 ||
              minute > 59) {
            return {
              'error': 'Provide a valid hour and minute.',
              'code': 'INVALID_ARGUMENT',
            };
          }
          _setTarget(null);
          final response = await _platform.prepareAlarm(hour, minute);
          return response == null
              ? {'error': 'No alarm launch result'}
              : {'status': 'dispatched_unconfirmed', ...response};
        case 'open_link':
          final url = args['url'];
          final uri = url is String ? Uri.tryParse(url) : null;
          if (url is! String ||
              url.length > 2048 ||
              uri == null ||
              !{'http', 'https'}.contains(uri.scheme) ||
              uri.host.isEmpty ||
              uri.userInfo.isNotEmpty ||
              !RegExp(r'https?://[^\s<>"\[\]()]+')
                  .allMatches(_userRequest)
                  .any((m) => m.group(0) == url)) {
            return {
              'code': 'INVALID_ARGUMENT',
              'error': 'Only an HTTP(S) link supplied in the current user request can be opened.',
            };
          }
          _setTarget(null);
          final response = await _platform.openLink(url);
          return response == null
              ? {'error': 'No link launch result'}
              : {'status': 'dispatched_unconfirmed', ...response};
        case 'device_info':
          final info = await _platform.getDeviceInfo();
          return info == null
              ? {'error': 'Device information unavailable'}
              : {'status': 'ok', ...info};
        case 'media_volume':
          final action = args['action'];
          final value = args['value'];
          if (action == 'get') {
            final volume = await _platform.getMediaVolume();
            return volume == null
                ? {'error': 'Media volume unavailable'}
                : {'status': 'ok', ...volume};
          }
          if (action != 'set' || value is! int || value < 0) {
            return {
              'code': 'INVALID_ARGUMENT',
              'error': 'Use get, or set with a non-negative integer volume.',
            };
          }
          final volume = await _platform.setMediaVolume(value);
          return volume == null
              ? {'error': 'Media volume unavailable'}
              : {'status': 'ok', ...volume};
        case 'open_system_settings':
          final destination = args['destination'];
          final packageName = args['packageName'];
          if (destination is! String ||
              !systemSettingsDestinations.contains(destination) ||
              (destination == 'app_details' &&
                  (packageName is! String ||
                      packageName.isEmpty ||
                      packageName.length > 200))) {
            return {
              'status': 'error',
              'code': 'INVALID_ARGUMENT',
              'message': 'Choose a supported destination; app_details requires an app package from find_apps.',
            };
          }
          _setTarget(null);
          final response = await _platform.openSystemSettings(
            destination,
            packageName: destination == 'app_details'
                ? packageName as String
                : null,
          );
          if (_turnCancelled) {
            return {
              'status': 'cancelled',
              'message':
                  'Cancelled; the settings page might already have opened.',
            };
          }
          if (response?['code'] != 'TARGET_READY' ||
              response?['packageName'] is! String ||
              (response!['packageName'] as String).isEmpty) {
            return {
              'status': 'unconfirmed',
              'message': 'Settings opened but the foreground app was not confirmed. Do not act until a target is confirmed.',
            };
          }
          _setTarget(response['packageName'] as String);
          return {
            'status': 'opened',
            'destination': destination,
            'packageName': response['packageName'],
            'note': 'Page opened; setting values have not been changed or verified.',
          };
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
              .where(
                (node) => node['password'] != true && node['visible'] != false,
              )
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
          // Native traversal order can place a visible toolbar after a feed.
          // Prefer editable controls, then visual top-to-bottom label order.
          final sourceOrder = {
            for (var i = 0; i < visible.length; i++) visible[i]['nodeId']: i,
          };
          final labelled = visible.where(informative).toList()
            ..sort((a, b) {
              final inputOrder =
                  (b['editable'] == true ? 1 : 0) -
                  (a['editable'] == true ? 1 : 0);
              if (inputOrder != 0) return inputOrder;
              int position(Map node, String axis) {
                final bounds = node['bounds'];
                return bounds is Map && bounds[axis] is num
                    ? (bounds[axis] as num).toInt()
                    : 0;
              }

              final vertical = position(a, 'top').compareTo(position(b, 'top'));
              if (vertical != 0) return vertical;
              final horizontal = position(
                a,
                'left',
              ).compareTo(position(b, 'left'));
              return horizontal != 0
                  ? horizontal
                  : sourceOrder[a['nodeId']]!.compareTo(
                      sourceOrder[b['nodeId']]!,
                    );
            });
          _liveTree = [
            ...labelled,
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
      if (error.code == 'SERVICE_NOT_READY' ||
          error.code == 'SERVICE_UNAVAILABLE') {
        try {
          if (await _platform.isAccessibilityServiceEnabled() == false) {
            return {
              'code': 'ACCESSIBILITY_DISABLED',
              'error': 'MobilePilot Accessibility is disabled. Ask the user to enable it in Android settings before using this tool.',
            };
          }
        } catch (_) {
          // Preserve the original service error when status cannot be checked.
        }
      }
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
      final counts = <String, int>{};
      for (final node in _liveTree!) {
        if (node['visible'] == false) continue;
        final value = uiNodeLabel(node);
        if (value.isNotEmpty && value.length <= 2000) {
          counts.update(value, (count) => count + 1, ifAbsent: () => 1);
        }
      }
      final candidates = _liveTree!
          .where(
            (node) => node['visible'] != false && uiNodeLabel(node).isNotEmpty,
          )
          .take(6)
          .map(
            (node) => {
              'ref': _refFor(node),
              'label': uiNodeLabel(node),
              if (node['editable'] == true) 'editable': true,
            },
          )
          .toList();
      throw FormatException(
        'Label ${jsonEncode(label)} matched ${matches.length} nodes; no action performed. '
        'Candidates on the last observed UI: ${jsonEncode(candidates)}. '
        'Use ref to distinguish duplicates, or an exact unique label. Read fresh UI if needed.',
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
