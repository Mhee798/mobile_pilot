import 'dart:convert';

import 'package:flutter/material.dart';

import '../../data/ai_run_history.dart';

class AiHistoryPage extends StatefulWidget {
  const AiHistoryPage({super.key, required this.history});
  final AiRunHistory history;

  @override
  State<AiHistoryPage> createState() => _AiHistoryPageState();
}

class _AiHistoryPageState extends State<AiHistoryPage> {
  @override
  void initState() {
    super.initState();
    widget.history.load();
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ล้างประวัติทั้งหมด?'),
        content: const Text(
          'ลบเฉพาะประวัติการทำงาน ไม่ลบโมเดลหรือบทสนทนาที่เปิดอยู่',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ล้างประวัติ'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.history.clear();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.history,
    builder: (context, _) {
      final runs = widget.history.runs;
      return Scaffold(
        appBar: AppBar(
          title: const Text('ประวัติการทำงาน AI'),
          actions: [
            IconButton(
              tooltip: 'ล้างประวัติ',
              onPressed:
                  runs.isEmpty || runs.any((r) => r['state'] == 'running')
                  ? null
                  : _clear,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        body: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'เก็บล่าสุด 30 งานในแอป ไม่มีภาพหน้าจอ รายละเอียดข้อความอาจมีข้อมูลส่วนตัว และอาจถูกตัดเมื่อยาวเกินกำหนด',
              ),
            ),
            if (widget.history.error case final error?)
              Padding(padding: const EdgeInsets.all(16), child: Text(error)),
            if (runs.isEmpty)
              const Expanded(
                child: Center(child: Text('ยังไม่มีประวัติการทำงาน')),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: runs.length,
                  itemBuilder: (context, index) => _RunTile(run: runs[index]),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _RunTile extends StatelessWidget {
  const _RunTile({required this.run});
  final Map<String, dynamic> run;
  @override
  Widget build(BuildContext context) {
    final steps = (run['steps'] as List).whereType<Map>().toList();
    final started = DateTime.tryParse('${run['started_at']}')?.toLocal();
    return ExpansionTile(
      title: Text('${run['request']}'),
      subtitle: Text(
        '${_state('${run['state']}')} · ${started ?? ''}\n${run['model']}',
      ),
      childrenPadding: const EdgeInsets.symmetric(horizontal: 16),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'เวลา: ${_duration(run['elapsed_ms'])} · เครื่องมือ ${run['tools'] == true ? 'เปิด' : 'ปิด'} · แนบภาพ ${run['image_attached'] == true ? 'ใช่' : 'ไม่'}',
        ),
        if (run['reason'] != null && run['reason'] != '')
          SelectableText('เหตุผลที่จบ: ${run['reason']}'),
        for (var i = 0; i < steps.length; i++)
          ExpansionTile(
            title: Text('${i + 1}. ${steps[i]['tool']}'),
            subtitle: Text(
              '${_state('${steps[i]['state']}')} · ${_duration(steps[i]['elapsed_ms'])}',
            ),
            children: [
              _details('ค่าที่ส่ง', steps[i]['arguments']),
              _details('ผลลัพธ์', steps[i]['result']),
            ],
          ),
        if (run['answer'] != null)
          _details('คำตอบ / รายงานที่แสดง', run['answer']),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _details(String label, Object? value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Align(
      alignment: Alignment.centerLeft,
      child: SelectableText(
        '$label\n${value is String ? value : const JsonEncoder.withIndent('  ').convert(value)}',
      ),
    ),
  );

  String _duration(Object? ms) =>
      ms is num ? '${(ms / 1000).toStringAsFixed(1)} วินาที' : 'ยังไม่ทราบ';
  String _state(String state) => switch (state) {
    'running' => 'กำลังทำงาน',
    'responded' => 'ตอบแล้ว (ไม่ได้ยืนยันผล)',
    'verified' => 'ตรงเงื่อนไขตรวจผล',
    'stopped' => 'หยุดก่อนจบ',
    'failed' => 'เกิดข้อผิดพลาด',
    'cancelled' => 'ผู้ใช้หยุด',
    'interrupted' => 'งานขาดตอน',
    'returned' => 'ได้รับผลเครื่องมือ',
    'unknown' => 'ไม่ทราบผล',
    _ => state,
  };
}
