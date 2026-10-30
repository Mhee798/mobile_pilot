import 'package:flutter/material.dart';

/// Separate entry point for the production interface, still under development.
class MobilePilotHomePage extends StatelessWidget {
  const MobilePilotHomePage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('MobilePilot')),
    body: const SafeArea(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'หน้าหลักกำลังพัฒนา\nเปิดโหมดทดสอบใน main.dart เพื่อใช้เครื่องมือเดิม',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
  );
}
