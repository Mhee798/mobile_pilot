import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_pilot/features/ai/data/ai_model_payload.dart';

void main() {
  test('verification instructions survive compacting tool results', () {
    for (final name in ['read_current_ui', 'verify_goal']) {
      expect(
        modelPayload(name, {
          'status': 'ok',
          'next': 'verify the latest ref',
        })['next'],
        'verify the latest ref',
      );
    }
  });
  test(
    'wire payload retains refs but strips native IDs and duplicate metadata',
    () {
      final raw = <String, dynamic>{
        'status': 'ok',
        'snapshot_id': 'ui123',
        'total': 1,
        'elements': [
          {
            'nodeId': 'node-0.1.2',
            'node_id': 'node-0.1.2',
            'snapshot_id': 'ui123',
            'ref': 9,
            'text': 'ข้อความไทย' * 40,
            'resourceId': 'native-id',
            'tap_node_id': 'node-0.1',
            'bounds': {'x': 100},
          },
        ],
      };
      final compact = modelPayload('read_current_ui', raw);
      final element = (compact['elements'] as List).single;
      expect(element['ref'], 'I');
      expect(element['can_tap'], isTrue);
      expect(element['label'], 'ข้อความไทย' * 40);
      expect(jsonEncode(compact), isNot(contains('node-0')));
      expect((raw['elements'] as List).single['resourceId'], 'native-id');
      expect(
        utf8.encode(jsonEncode(compact)).length,
        lessThan(utf8.encode(jsonEncode(raw)).length),
      );
    },
  );
}
