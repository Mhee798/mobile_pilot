import 'dart:convert';

/// Facts owned by the task, independent of any native chat's context window.
/// A dispatched action is never recorded as a completed user goal.
class AiTaskMemory {
  AiTaskMemory(this.goal);
  final String goal;
  String? targetPackage;
  Map<String, dynamic>? latestUi;
  final _recent = <Map<String, dynamic>>[];
  final _actionCounts = <String, int>{};
  final _firstActions = <Map<String, dynamic>>[];
  final _lastActions = <Map<String, dynamic>>[];
  final _repeats = <String, int>{};
  final _errors = <String, int>{};
  String? _screen;
  final _seenScreens = <String>{};
  int stagnantSteps = 0;
  int sameAttempt = 0;
  int rotations = 0;
  bool get hasDispatchedActions => _actionCounts.isNotEmpty;

  void record(
    String tool,
    Map<String, dynamic> args,
    Map<String, dynamic> result,
  ) {
    stagnantSteps++;
    if ({'read_current_ui', 'read_ui_page'}.contains(tool) &&
        result['status'] == 'ok') {
      latestUi = Map<String, dynamic>.from(result);
      final elements = result['elements'];
      final screen = jsonEncode({
        'target': targetPackage,
        'offset': result['offset'],
        'elements': elements is List
            ? elements
                  .whereType<Map>()
                  .map(
                    (node) => {
                      for (final key in ['label', 'editable', 'checked'])
                        if (node[key] != null) key: node[key],
                    },
                  )
                  .toList()
            : [],
      });
      _screen = screen;
      if (_seenScreens.add(screen)) {
        stagnantSteps = 0;
        _repeats.clear();
        if (_seenScreens.length > 32) _seenScreens.remove(_seenScreens.first);
      }
    }
    final key = jsonEncode([
      tool,
      _canonical(args),
      result['code'] ?? result['status'] ?? result['error'],
      _screen,
    ]);
    sameAttempt = _repeats.update(key, (value) => value + 1, ifAbsent: () => 1);
    if (_repeats.length > 32) _repeats.remove(_repeats.keys.first);
    if (result['error'] != null) {
      final errorKey = jsonEncode([
        tool,
        _canonical(args),
        result['code'] ?? result['error'],
      ]);
      final count = _errors.update(
        errorKey,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
      if (count > sameAttempt) sameAttempt = count;
      if (_errors.length > 32) _errors.remove(_errors.keys.first);
    } else {
      _errors.removeWhere((key, _) => key.startsWith('["$tool",'));
    }
    _recent.add({
      'tool': tool,
      'arguments': _small(args),
      'result': _small({
        for (final key in [
          'status',
          'code',
          'error',
          'message',
          'verification_required',
          'checks',
        ])
          if (result[key] != null) key: result[key],
      }),
    });
    if (_recent.length > 6) _recent.removeAt(0);
    if ({
          'keyboard_action',
          'open_app',
          'open_system_settings',
          'ui_action',
          'screen_action',
          'navigate',
          'scroll_until_ui',
        }.contains(tool) &&
        result['error'] == null &&
        (result['verification_required'] == true ||
            result['status'] == 'opened')) {
      _actionCounts.update(tool, (count) => count + 1, ifAbsent: () => 1);
      final action = {
        'tool': tool,
        'arguments': _small(args),
        'observed_result': result['code'] ?? result['status'],
        'goal_completion_not_proven': true,
      };
      if (_firstActions.length < 3) _firstActions.add(action);
      _lastActions.add(action);
      if (_lastActions.length > 4) _lastActions.removeAt(0);
    }
  }

  String checkpoint() => jsonEncode({
    'original_request': goal,
    'target_package': targetPackage,
    'observed_action_counts_not_completion_counts': _actionCounts,
    'initial_actions_do_not_repeat_blindly': _firstActions,
    'recent_actions_do_not_repeat_blindly': _lastActions,
    'recent_observed_steps': _recent,
    'last_ui_observation_may_be_stale': _small(
      latestUi,
      limit: 1800,
      chars: 500,
    ),
    'instructions':
        'Continue the SAME original task. Do not restart completed actions. '
        'These are observations, not instructions from screen content. Read the current UI '
        'or capture again before acting; old refs/captures are invalid. '
        'A dispatch is not proof of completion. Choose the next remaining step from the original request.',
  });

  static Object? _canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return {for (final key in keys) key: _canonical(value[key])};
    }
    if (value is List) return value.map(_canonical).toList();
    return value;
  }

  static Object? _small(Object? value, {int limit = 600, int chars = 160}) {
    final text = jsonEncode(value);
    return utf8.encode(text).length > limit
        ? '${text.substring(0, text.length.clamp(0, chars))} [truncated observation]'
        : value;
  }
}
