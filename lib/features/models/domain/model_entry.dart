import 'package:flutter_edge_ai/flutter_edge_ai.dart';

export '../../../core/ai/model_catalog.dart';

class LocalModelEntry {
  const LocalModelEntry({
    required this.id,
    required this.name,
    required this.path,
    required this.type,
    required this.bytes,
    required this.vision,
    this.managed = true,
  });
  final String id, name, path;
  final ModelType type;
  final int bytes;
  final bool vision, managed;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'path': path,
    'type': type.name,
    'bytes': bytes,
    'vision': vision,
    'managed': managed,
  };
  factory LocalModelEntry.fromJson(Map<dynamic, dynamic> data) =>
      LocalModelEntry(
        id: data['id'] as String,
        name: data['name'] as String,
        path: data['path'] as String,
        type: ModelType.values.byName(data['type'] as String),
        bytes: data['bytes'] as int,
        vision: data['vision'] as bool,
        managed: data['managed'] as bool? ?? true,
      );
}

enum ModelLocation { file, nano, cloud }

class ModelSelection {
  const ModelSelection(this.location, this.id, this.label);
  final ModelLocation location;
  final String id, label;
  Map<String, String> toJson() => {
    'location': location.name,
    'id': id,
    'label': label,
  };
  factory ModelSelection.fromJson(Map<dynamic, dynamic> data) => ModelSelection(
    ModelLocation.values.byName(data['location'] as String),
    data['id'] as String,
    data['label'] as String,
  );
}
