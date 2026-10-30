import 'ai_ui_nodes.dart';

/// Compact wire view for the model. Full snapshots stay in the tool adapter.
/// No native IDs, duplicate labels or geometry are needed for reference actions.
Map<String, dynamic> modelPayload(String name, Map<String, dynamic> result) {
  Object? compact(Object? raw) {
    if (raw is! List) return raw;
    return raw.whereType<Map>().map((n) {
      final label =
          n['label']?.toString() ??
          (n['text'] is String && (n['text'] as String).trim().isNotEmpty
                  ? n['text']
                  : n['contentDescription'])
              ?.toString() ??
          '';
      return {
        'ref': n['ref'] is int ? uiRefAlias(n['ref'] as int) : n['ref'],
        'label': label,
        if (n['tap_node_id'] != null) 'can_tap': true,
        if (n['editable'] == true) 'editable': true,
        if (n['checkable'] == true) 'checked': n['checked'],
      };
    }).toList();
  }

  if (name == 'read_current_ui' || name == 'read_ui_page') {
    return {
      for (final key in [
        'status',
        'error',
        'code',
        'total',
        'offset',
        'next_offset',
        'next',
      ])
        if (result[key] != null) key: result[key],
      if (result['elements'] is List) 'elements': compact(result['elements']),
    };
  }
  if (name == 'scroll_until_ui') {
    return {
      for (final key in ['code', 'error', 'verification_required'])
        if (result[key] != null) key: result[key],
      if (result['matched_elements'] is List)
        'elements': compact(result['matched_elements']),
    };
  }
  if (name == 'verify_goal') {
    return {
      'status': result['status'],
      if (result['code'] != null) 'code': result['code'],
      if (result['next'] != null) 'next': result['next'],
      if (result['error'] != null) 'error': result['error'],
      if (result['conditions'] is List)
        'checks': (result['conditions'] as List)
            .whereType<Map>()
            .map(
              (c) => {
                'matched': c['matched'],
                'property': c['property'],
                'match_count': c['match_count'],
              },
            )
            .toList(),
    };
  }
  if (result['verification_required'] == true &&
      result['error'] == null &&
      name != 'scroll_until_ui') {
    return {
      for (final key in ['code', 'verification_required'])
        if (result[key] != null) key: result[key],
      'next': result['text_replacement_dispatched'] == true
          ? 'Text replacement was dispatched, but search has NOT been submitted. Read UI to confirm input; for a search request call keyboard_action(key=search), or default if the field offers another action. Do not invent a search-button label.'
          : 'Read current UI after this action, then continue the next remaining step. Verify final evidence before reporting the whole request complete.',
    };
  }
  return result;
}
