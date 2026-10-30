import 'dart:convert';

/// Decides when to change observation strategy, never what to tap.
class AiVisualFallback {
  final _reads = <String, int>{};
  final _capturedViews = <String>{};
  String _view = 'unknown';
  int _uiFailures = 0;
  int _attemptsWithoutAction = 0;
  bool get canRecaptureAfterContextReset => _attemptsWithoutAction < 2;

  String? observe(String tool, Map<String, dynamic> result) {
    if (tool == 'capture_screen') {
      captureAttempted();
      return null;
    }
    final mutation = {
      'keyboard_action',
      'open_app',
      'ui_action',
      'screen_action',
      'navigate',
      'scroll_until_ui',
    }.contains(tool);
    if (mutation &&
        result['error'] == null &&
        (result['verification_required'] == true ||
            result['status'] == 'opened')) {
      // The read after an accepted action is normal, not a retry loop.
      _reads.clear();
      _capturedViews.clear();
      _uiFailures = 0;
      _attemptsWithoutAction = 0;
      return null;
    }
    if (tool == 'verify_goal' && result['status'] == 'matched') {
      _uiFailures = 0;
      _reads.clear();
      return null;
    }
    String? reason;
    if ({'read_current_ui', 'read_ui_page'}.contains(tool) &&
        result['status'] == 'ok') {
      final elements = result['elements'];
      _view = jsonEncode({
        'offset': result['offset'],
        'elements': elements is List
            ? elements
                  .whereType<Map>()
                  .map(
                    (node) => {
                      for (final key in [
                        'label',
                        'editable',
                        'checked',
                        'can_tap',
                      ])
                        if (node[key] != null) key: node[key],
                    },
                  )
                  .toList()
            : [],
      });
      final count = _reads.update(
        _view,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      if (_reads.length > 16) _reads.remove(_reads.keys.first);
      if (count >= 2) {
        reason = 'Repeated UI observation without an accepted action';
      }
    }
    if ({'ui_action', 'verify_goal'}.contains(tool) &&
        result['error'] != null &&
        {
          'STALE_SCREEN',
          'INVALID_ARGUMENT',
          'NODE_NOT_ACTIONABLE',
          'ACTION_REJECTED',
          'VERIFY_BEFORE_ACTION',
        }.contains(result['code'])) {
      if (++_uiFailures >= 2) {
        reason = 'Repeated UI targeting/verification failures';
      }
    }
    if (tool == 'screen_action' &&
        result['error'].toString().contains('Capture is missing/expired')) {
      reason = 'Screen action requires a real, fresh capture_id';
    }
    if (_attemptsWithoutAction >= 2 || _capturedViews.contains(_view)) {
      return null;
    }
    return reason;
  }

  void captureAttempted() {
    _attemptsWithoutAction++;
    _capturedViews.add(_view);
    _uiFailures = 0;
  }
}
