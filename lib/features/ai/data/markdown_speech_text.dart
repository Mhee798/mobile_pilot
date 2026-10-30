import 'package:markdown/markdown.dart' as md;

/// Extracts readable content without markup or link destinations.
String markdownSpeechText(String source) {
  final nodes = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored)
      .parseLines(source.split('\n'));
  String read(md.Node node) {
    if (node is md.Element) {
      if (node.tag == 'img') return node.attributes['alt'] ?? '';
      if (node.tag == 'pre') return 'มีบล็อกโค้ด';
      final separator =
          {
            'table',
            'thead',
            'tbody',
            'tr',
            'ul',
            'ol',
            'li',
            'blockquote',
          }.contains(node.tag)
          ? '\n'
          : '';
      return (node.children ?? []).map(read).join(separator);
    }
    return node.textContent;
  }

  return nodes.map(read).where((s) => s.trim().isNotEmpty).join('\n').trim();
}
