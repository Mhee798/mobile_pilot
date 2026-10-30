import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

class AnswerMarkdown extends StatelessWidget {
  const AnswerMarkdown(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => SelectionArea(
    child: GptMarkdown(
      text,
      // Model-provided image URLs should not cause unsolicited network access.
      imageBuilder: (context, url, width, height) => const Text('[รูปภาพ]'),
    ),
  );
}
