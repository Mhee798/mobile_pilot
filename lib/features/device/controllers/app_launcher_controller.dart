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

  void select(Map<String, String> app) => update(() {
    selectedPackage = app['packageName'];
    selectedLabel = app['label'];
  });

  Future<void> findApps() async {
    final query = searchController.text.trim();
    if (query.isEmpty) {
      update(() {
        apps = [];
        selectedPackage = null;
        selectedLabel = null;
        feedback.message = 'พิมพ์ชื่อแอป เช่น Shopee ก่อนค้นหา';
      });
      return;
    }
    update(() {
      isSearching = true;
      selectedPackage = null;
      selectedLabel = null;
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
      if (mounted) update(() => feedback.message = error.message ?? error.code);
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
    update(() => isLaunching = true);
    try {
      final response = await platform.launchApp(packageName);
      if (mounted) {
        update(
          () => feedback.message =
              'เปิด ${response?['label'] as String? ?? selectedLabel} แล้ว',
        );
      }
    } on PlatformException catch (error) {
      if (mounted) update(() => feedback.message = error.message ?? error.code);
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
