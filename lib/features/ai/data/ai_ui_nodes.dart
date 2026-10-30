/// Native IDs encode ancestry as node-0.1.2. Labels may belong to a clickable
/// row above them. Resolve only against the same saved snapshot.
int? parseUiRef(Object? raw) {
  if (raw is String && RegExp(r'^[A-Z]{1,8}$').hasMatch(raw)) {
    var value = 0;
    for (final unit in raw.codeUnits) {
      value = value * 26 + unit - 64;
    }
    return value;
  }
  if (raw is int && raw > 0) return raw;
  if (raw is num && raw.isFinite && raw > 0 && raw == raw.toInt()) {
    return raw.toInt();
  }
  if (raw is String && RegExp(r'^[1-9][0-9]*$').hasMatch(raw)) {
    return int.tryParse(raw);
  }
  return null;
}

/// Compact, lossless aliases. Never reuse an alias after a fresh observation.
String uiRefAlias(int value) {
  if (value <= 0) throw ArgumentError.value(value);
  var result = '';
  while (value > 0) {
    value--;
    result = String.fromCharCode(65 + value % 26) + result;
    value ~/= 26;
  }
  return result;
}

String uiNodeLabel(Map node) {
  final text = node['text'];
  return text is String && text.trim().isNotEmpty
      ? text
      : node['contentDescription']?.toString() ?? '';
}

String? tapNodeId(Map<String, dynamic> node, List<Map<String, dynamic>> nodes) {
  bool tappable(Map<String, dynamic> n) =>
      n['clickable'] == true &&
      n['editable'] != true &&
      n['password'] != true &&
      n['enabled'] != false &&
      n['visible'] != false;
  final id = node['nodeId'];
  if (id is! String) return null;
  if (node['editable'] == true) return null;
  if (tappable(node)) return id;
  final parents =
      nodes
          .where(
            (n) =>
                n['nodeId'] is String &&
                id.startsWith('${n['nodeId']}.') &&
                tappable(n),
          )
          .toList()
        ..sort(
          (a, b) => (b['nodeId'] as String).length.compareTo(
            (a['nodeId'] as String).length,
          ),
        );
  return parents.isEmpty ? null : parents.first['nodeId'] as String;
}

Map<String, dynamic> modelUiNode(
  Map<String, dynamic> node,
  List<Map<String, dynamic>> nodes,
) => {
  'label': uiNodeLabel(node),
  for (final key in [
    'nodeId',
    'text',
    'contentDescription',
    'resourceId',
    'clickable',
    'editable',
    'enabled',
    'visible',
    'bounds',
    'checkable',
    'checked',
    'selected',
  ])
    if (node[key] != null)
      key:
          key != 'nodeId' &&
              node[key] is String &&
              (node[key] as String).length > 150
          ? (node[key] as String).substring(0, 150)
          : node[key],
  'tap_node_id': ?tapNodeId(node, nodes),
};
