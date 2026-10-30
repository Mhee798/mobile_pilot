import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../../data/ai_run_history.dart';

class AiHistoryPage extends StatefulWidget {
  const AiHistoryPage({super.key, required this.history});
  final AiRunHistory history;

  @override
  State<AiHistoryPage> createState() => _AiHistoryPageState();
}

class _AiHistoryPageState extends State<AiHistoryPage> {
  bool _exporting = false;

  Future<void> _export({String? runId}) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final json = await widget.history.exportJson(runId: runId);
      if (!mounted) return;
      final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(
        RegExp(r'[:.]'),
        '-',
      );
      final saved = await FilePicker.saveFile(
        fileName:
            'mobilepilot-${runId == null ? 'history' : 'run'}-$stamp.json',
        mimeType: 'application/json',
        bytes: Uint8List.fromList(utf8.encode(json)),
        dialogTitle: 'บันทึกประวัติการทำงาน AI',
      );
      if (mounted && saved != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ส่งออกประวัติแล้ว แนบไฟล์ JSON เพื่อตรวจสอบได้'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ส่งออกประวัติไม่สำเร็จ: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

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
              tooltip: 'ส่งออกประวัติทั้งหมด',
              onPressed: runs.isEmpty || _exporting ? null : () => _export(),
              icon: const Icon(Icons.file_download_outlined),
            ),
            IconButton(
              tooltip: 'ล้างประวัติ',
              onPressed:
                  _exporting ||
                      runs.isEmpty ||
                      runs.any((r) => r['state'] == 'running')
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
                  itemBuilder: (context, index) => _RunTile(
                    run: runs[index],
                    onExport: _exporting
                        ? null
                        : () => _export(runId: runs[index]['id'] as String),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _RunTile extends StatelessWidget {
  const _RunTile({required this.run, this.onExport});
  final Map<String, dynamic> run;
  final VoidCallback? onExport;
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
        if ((run['older_steps_omitted'] as int? ?? 0) > 0)
          Text(
            'แสดงขั้นล่าสุด ตัดรายละเอียดก่อนหน้า ${run['older_steps_omitted']} ขั้น',
          ),
        TextButton.icon(
          onPressed: onExport,
          icon: const Icon(Icons.file_download_outlined),
          label: const Text('ส่งออกงานนี้'),
        ),
        Text(
          'เวลา: ${_duration(run['elapsed_ms'])} · เครื่องมือ ${run['tools'] == true ? 'เปิด' : 'ปิด'} · แนบภาพ ${run['image_attached'] == true ? 'ใช่' : 'ไม่'}',
        ),
        if (run['vision_enabled'] is bool)
          Text('Vision: ${run['vision_enabled'] == true ? 'เปิด' : 'ปิด'}'),
        if (run['reason'] != null && run['reason'] != '')
          SelectableText('เหตุผลที่จบ: ${run['reason']}'),
        for (var i = 0; i < steps.length; i++)
          ExpansionTile(
            title: Text(
              '${(run['older_steps_omitted'] as int? ?? 0) + i + 1}. ${steps[i]['tool']}',
            ),
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
    'unverified' => 'ส่งคำสั่งแล้ว (ยังไม่ยืนยันผล)',
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
