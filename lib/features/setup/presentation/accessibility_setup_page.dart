import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/platform/mobile_pilot_platform.dart';
import '../../device/presentation/command_page.dart';

class AccessibilitySetupPage extends StatefulWidget {
  const AccessibilitySetupPage({super.key});

  @override
  State<AccessibilitySetupPage> createState() => _AccessibilitySetupPageState();
}

class _AccessibilitySetupPageState extends State<AccessibilitySetupPage>
    with WidgetsBindingObserver {
  static const _platform = MobilePilotPlatform();

  bool _isOpeningSettings = false;
  bool _isCheckingStatus = true;
  bool? _isAccessibilityEnabled;
  bool _hasOpenedCommandPage = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshAccessibilityStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshAccessibilityStatus();
    }
  }

  Future<void> _refreshAccessibilityStatus() async {
    if (mounted) setState(() => _isCheckingStatus = true);
    try {
      final isEnabled = await _platform.isAccessibilityServiceEnabled();
      if (!mounted) return;
      setState(() {
        _isAccessibilityEnabled = isEnabled;
        _isCheckingStatus = false;
      });
      if (isEnabled == true) _openCommandPage();
    } on PlatformException {
      _setStatusUnknown();
    } on MissingPluginException {
      _setStatusUnknown();
    }
  }

  void _setStatusUnknown() {
    if (!mounted) return;
    setState(() {
      _isAccessibilityEnabled = null;
      _isCheckingStatus = false;
    });
  }

  void _openCommandPage() {
    if (_hasOpenedCommandPage || !mounted) return;
    _hasOpenedCommandPage = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const CommandPage()),
      );
    });
  }

  Future<void> _openAccessibilitySettings() async {
    setState(() => _isOpeningSettings = true);
    try {
      await _platform.openAccessibilitySettings();
    } on PlatformException {
      _showSettingsError();
    } on MissingPluginException {
      _showSettingsError();
    } finally {
      if (mounted) setState(() => _isOpeningSettings = false);
    }
  }

  void _showSettingsError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('เปิดหน้าตั้งค่า Accessibility ไม่สำเร็จ')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('MobilePilot')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.smartphone, size: 56, color: colors.primary),
                  const SizedBox(height: 20),
                  Text(
                    'ตั้งค่า MobilePilot',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'เปิด Accessibility Service เพื่อให้ MobilePilot อ่านโครงสร้างหน้าจอและแตะองค์ประกอบที่คุณสั่งได้',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 24),
                  _AccessibilityStatusCard(
                    isEnabled: _isAccessibilityEnabled,
                    isChecking: _isCheckingStatus,
                    onRefresh: _refreshAccessibilityStatus,
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'วิธีเปิดใช้งาน',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            '1. แตะปุ่มด้านล่างเพื่อเปิดการตั้งค่า Android\n'
                            '2. เลือก MobilePilot ในรายการบริการ\n'
                            '3. เปิดใช้บริการด้วยตัวเอง',
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Android จะแสดงคำเตือนเกี่ยวกับสิทธิ์นี้ โปรดตรวจสอบและยืนยันบนอุปกรณ์ของคุณ',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _isOpeningSettings
                        ? null
                        : _openAccessibilitySettings,
                    icon: _isOpeningSettings
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.settings_accessibility),
                    label: const Text('เปิดการตั้งค่า Accessibility'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AccessibilityStatusCard extends StatelessWidget {
  const _AccessibilityStatusCard({
    required this.isEnabled,
    required this.isChecking,
    required this.onRefresh,
  });

  final bool? isEnabled;
  final bool isChecking;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final statusColor = isEnabled == true
        ? colors.primary
        : isEnabled == false
        ? colors.error
        : colors.onSurfaceVariant;
    final statusIcon = isEnabled == true
        ? Icons.check_circle
        : isEnabled == false
        ? Icons.error_outline
        : Icons.help_outline;
    final statusText = isChecking
        ? 'กำลังตรวจสอบสถานะ…'
        : isEnabled == true
        ? 'เปิดใช้งานแล้ว'
        : isEnabled == false
        ? 'ยังไม่ได้เปิดใช้งาน'
        : 'ตรวจสอบสถานะไม่ได้';

    return Card(
      child: ListTile(
        leading: isChecking
            ? SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.primary,
                ),
              )
            : Icon(statusIcon, color: statusColor),
        title: const Text('สถานะ Accessibility'),
        subtitle: Text(statusText),
        trailing: IconButton(
          onPressed: isChecking ? null : onRefresh,
          tooltip: 'ตรวจสอบอีกครั้ง',
          icon: const Icon(Icons.refresh),
        ),
      ),
    );
  }
}
