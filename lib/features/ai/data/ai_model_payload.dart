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
        'ref': n['ref'],
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
      'next': 'read_current_ui then verify_goal(label copied from that read) before another action',
    };
  }
  return result;
}
