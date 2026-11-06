import 'package:hive_ce/hive_ce.dart';

class MemoryChatBox implements Box<dynamic> {
  final data = <dynamic, dynamic>{};
  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => data[key] ?? defaultValue;
  @override
  Future<void> put(dynamic key, dynamic value) async {
    data[key] = value;
  }

  @override
  Future<void> delete(dynamic key) async {
    data.remove(key);
  }

  @override
  bool containsKey(dynamic key) => data.containsKey(key);
  @override
  Iterable<dynamic> get values => data.values;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
