import 'dart:io';

import 'package:hive_ce/hive_ce.dart';
import 'package:path_provider/path_provider.dart';

/// App-owned storage. A record is written as one value so messages and metadata
/// cannot disagree after a partial update.
class ConversationStore {
  ConversationStore(this._box);
  final Box<dynamic> _box;
  static const boxName = 'conversations_v1';

  static Future<ConversationStore> open() async {
    final directory = await getApplicationSupportDirectory();
    final location = Directory('${directory.path}/conversations');
    await location.create(recursive: true);
    final box = await Hive.openBox<dynamic>(boxName, path: location.path);
    return ConversationStore(box);
  }

  Future<void> save(Map<String, dynamic> conversation) async {
    final id = conversation['id'];
    if (id is! String || id.isEmpty) {
      throw ArgumentError('Missing conversation id');
    }
    await _box.put(id, conversation);
  }

  Map<String, dynamic>? read(String id) {
    final value = _box.get(id);
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  List<Map<String, dynamic>> list() {
    final records = _box.values
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .toList();
    records.sort(
      (a, b) => (b['updatedAt'] as String? ?? '').compareTo(
        a['updatedAt'] as String? ?? '',
      ),
    );
    return records;
  }

  Future<void> delete(String id) => _box.delete(id);
}
