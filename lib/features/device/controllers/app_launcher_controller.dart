import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'device_controller.dart';

class AppLauncherController extends DeviceController {
  AppLauncherController(super.feedback);

  final searchController = TextEditingController();
  bool isSearching = false;
  bool isLaunching = false;
  List<Map<String, String>> apps = [];
  String? selectedPackage;
  String? selectedLabel;
  String targetStatus = 'ยังไม่ได้เลือกแอปเป้าหมาย';

  bool isSelecting = false;

  Future<void> select(Map<String, String> app) async {
    if (isLaunching || isSelecting) return;
    final packageName = app['packageName'];
    if (packageName == null || packageName.isEmpty) return;
    update(() => isSelecting = true);
    try {
      await platform.setTargetApp(packageName);
      if (!mounted) return;
      update(() {
        selectedPackage = packageName;
        selectedLabel = app['label'];
        feedback.targetPackage = packageName;
        targetStatus = 'เป้าหมาย: $selectedLabel · ยังไม่ได้ตรวจสถานะ';
        feedback.message =
            'เลือก $selectedLabel แล้ว ยกเลิกคำสั่งเก่าที่รออยู่';
      });
    } on PlatformException catch (error) {
      if (mounted) update(() => feedback.message = error.message ?? error.code);
    } on MissingPluginException {
      if (mounted) {
        update(
          () =>
              feedback.message = 'ต้อง build Android ใหม่ก่อนเลือกแอปเป้าหมาย',
        );
      }
    } finally {
      if (mounted) update(() => isSelecting = false);
    }
  }

  Future<void> findApps() async {
    final query = searchController.text.trim();
    if (query.isEmpty) {
      update(() {
        apps = [];
        feedback.message = 'พิมพ์ชื่อแอป เช่น Shopee ก่อนค้นหา';
      });
      return;
    }
    update(() {
      isSearching = true;
    });
    try {
      final foundApps = await platform.findLaunchableApps(query);
      if (!mounted) return;
      update(() {
        apps = foundApps;
        feedback.message = foundApps.isEmpty
            ? 'ไม่พบแอปที่เปิดได้ชื่อตรงกับ “$query”'
            : 'พบ ${foundApps.length} แอป เลือกแอปที่ต้องการเปิด';
      });
    } on PlatformException catch (error) {
      if (mounted) {
        update(() {
          feedback.message = error.message ?? error.code;
          targetStatus = 'ยังยืนยันแอปเป้าหมายไม่ได้: ${error.code}';
        });
      }
    } on MissingPluginException {
      if (mounted) {
        update(
          () => feedback.message =
              'ไม่พบ app launcher channel; ต้อง build Android ใหม่',
        );
      }
    } finally {
      if (mounted) update(() => isSearching = false);
    }
  }

  Future<void> launchSelected() async {
    final packageName = selectedPackage;
    if (packageName == null) {
      update(() => feedback.message = 'เลือกแอปจากผลค้นหาก่อน');
      return;
    }
    if (isLaunching) return;
    final label = selectedLabel;
    update(() {
      isLaunching = true;
      targetStatus = 'กำลังเปิด $label และรอแอปพร้อม…';
    });
    try {
      await platform.launchApp(packageName);
      if (mounted && selectedPackage == packageName) {
        update(() {
          targetStatus = 'ยืนยันว่า $label อยู่ด้านหน้าแล้ว (ตอนเปิดแอป)';
          feedback.message = targetStatus;
        });
      }
    } on PlatformException catch (error) {
      if (mounted) {
        update(() {
          feedback.message = error.message ?? error.code;
          targetStatus = 'ยังยืนยันแอปเป้าหมายไม่ได้: ${error.code}';
        });
      }
    } on MissingPluginException {
      if (mounted) {
        update(
          () => feedback.message =
              'ไม่พบ app launcher channel; ต้อง build Android ใหม่',
        );
      }
    } finally {
      if (mounted) update(() => isLaunching = false);
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }
}
