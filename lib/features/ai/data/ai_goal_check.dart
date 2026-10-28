/// Evaluate explicit observations, not the model's claim that a task succeeded.
Map<String, dynamic> checkUiGoal(
  Object? raw,
  List<Map<String, dynamic>> nodes,
) {
  if (raw is! List || raw.isEmpty || raw.length > 5) {
    throw const FormatException('Provide 1..5 conditions');
  }
  final checks = <Map<String, dynamic>>[];
  for (final item in raw) {
    if (item is! Map ||
        !{
          'text',
          'contentDescription',
          'resourceId',
        }.contains(item['selector']) ||
        item['value'] is! String ||
        (item['value'] as String).isEmpty ||
        (item['value'] as String).length > 2000 ||
        !{'present', 'checked', 'enabled', 'text'}.contains(item['property'])) {
      throw const FormatException('Invalid UI condition');
    }
    final property = item['property'] as String;
    final rawExpected = item['expected'];
    final expected = property != 'text' && rawExpected == 'true'
        ? true
        : property != 'text' && rawExpected == 'false'
        ? false
        : rawExpected;
    if (property == 'text' ? expected is! String : expected is! bool) {
      throw const FormatException('Expected value has wrong type');
    }
    final matches = nodes
        .where(
          (n) =>
              n['password'] != true &&
              n['visible'] != false &&
              n[item['selector']] == item['value'],
        )
        .toList();
    final matched = property == 'present'
        ? matches.isNotEmpty == expected
        : matches.length == 1 &&
              (property != 'checked' || matches.single['checkable'] == true) &&
              matches.single[property] == expected;
    checks.add({
      'selector': item['selector'],
      'value': item['value'],
      'property': property,
      'expected': expected,
      'matched': matched,
      'match_count': matches.length,
    });
  }
  final matched = checks.every((c) => c['matched'] == true);
  return {
    'status': matched ? 'matched' : 'not_matched',
    'conditions': checks,
    'note': 'Only these observable conditions were checked. This does not independently prove the model interpreted the user goal correctly.',
  };
}
