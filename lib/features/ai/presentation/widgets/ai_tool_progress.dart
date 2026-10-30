import 'package:flutter/material.dart';

/// Diagnostics must never take the vertical space reserved for conversation.
class AiToolProgress extends StatelessWidget {
  const AiToolProgress({super.key, required this.tools, required this.results});
  final List<String> tools;
  final List<String> results;

  @override
  Widget build(BuildContext context) => ExpansionTile(
    key: const ValueKey('ai-tool-progress'),
    title: const Text('รายละเอียดเครื่องมือ', maxLines: 1),
    subtitle: Text(
      tools.isEmpty ? 'ผลล่าสุด' : 'ล่าสุด: ${tools.last}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    children: [
      SizedBox(
        height: (MediaQuery.sizeOf(context).height * .15).clamp(60, 140),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            const Text('แสดงผลล่าสุดไม่เกิน 30 รายการ ดูย้อนหลังได้ในประวัติ'),
            for (final result in results.reversed.take(30))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  result,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    ],
  );
}
