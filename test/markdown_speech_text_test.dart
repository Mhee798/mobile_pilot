import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_pilot/features/ai/data/markdown_speech_text.dart';

void main() {
  test('reads markdown content without formatting or link targets', () {
    final text = markdownSpeechText(
      '# หัวข้อ\n\n**เปิด** *Wi-Fi* [ตั้งค่า](https://example.com)\n\n- หนึ่ง\n- สอง\n\nคูณ 2 * 3',
    );
    expect(text, contains('หัวข้อ'));
    expect(text, contains('เปิด Wi-Fi ตั้งค่า'));
    expect(text, contains('หนึ่ง'));
    expect(text, contains('สอง'));
    expect(text, contains('2 * 3'));
    expect(text, isNot(contains('**')));
    expect(text, isNot(contains('https://')));
  });
  test('keeps image descriptions and skips fenced code', () {
    final text = markdownSpeechText(
      '![แมว](https://example.com/a.png)\n\n```dart\nprint(1);\n```',
    );
    expect(text, contains('แมว'));
    expect(text, contains('มีบล็อกโค้ด'));
    expect(text, isNot(contains('print')));
  });
}
