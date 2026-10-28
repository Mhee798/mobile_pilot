import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_pilot/features/ai/data/ai_goal_check.dart';

void main() {
  test(
    'requires all conditions and reads checked state rather than a label',
    () {
      final conditions = [
        {
          'selector': 'text',
          'value': 'Wi-Fi',
          'property': 'present',
          'expected': 'true',
        },
        {
          'selector': 'resourceId',
          'value': 'switch',
          'property': 'checked',
          'expected': 'true',
        },
      ];
      final nodes = <Map<String, dynamic>>[
        {'text': 'Wi-Fi'},
        {'resourceId': 'switch', 'checkable': true, 'checked': false},
      ];
      expect(checkUiGoal(conditions, nodes)['status'], 'not_matched');
      nodes.last['checked'] = true;
      expect(checkUiGoal(conditions, nodes)['status'], 'matched');
    },
  );
  test('ambiguous or password field cannot verify a value', () {
    final conditions = [
      {
        'selector': 'resourceId',
        'value': 'field',
        'property': 'text',
        'expected': 'ok',
      },
    ];
    expect(
      checkUiGoal(conditions, [
        {'resourceId': 'field', 'text': 'ok', 'password': true},
      ])['status'],
      'not_matched',
    );
    expect(
      checkUiGoal(conditions, [
        {'resourceId': 'field', 'text': 'ok'},
        {'resourceId': 'field', 'text': 'ok'},
      ])['status'],
      'not_matched',
    );
  });
  test('rejects malformed model arguments', () {
    expect(() => checkUiGoal([], []), throwsFormatException);
    expect(
      () => checkUiGoal([
        {
          'selector': 'text',
          'value': 'x',
          'property': 'checked',
          'expected': 'maybe',
        },
      ], []),
      throwsFormatException,
    );
  });
}
