import 'dart:convert';

/// LiteRT can expose an unparsed tool marker as text. Only this complete wire
/// form is accepted, never prose, code fences, screen text or unknown tools.
({String name, Map<String, dynamic> args})? parseLocalToolCall(
  String text,
  Set<String> allowedTools,
) {
  if (text.length > 12000 || allowedTools.isEmpty) return null;
  final match = RegExp(
    r'^call:([a-z_][a-z0-9_]*)\s*(\{[\s\S]*\})<tool_call\|>$',
  ).firstMatch(text.trim());
  if (match == null || !allowedTools.contains(match[1])) return null;
  try {
    final args = jsonDecode(match[2]!);
    if (args is! Map<String, dynamic>) return null;
    return (name: match[1]!, args: args);
  } on FormatException {
    return null;
  }
}
