import 'package:flutter/material.dart';

import '../controllers/app_launcher_controller.dart';

class AppLauncherSection extends StatelessWidget {
  const AppLauncherSection({super.key, required this.launcher});

  final AppLauncherController launcher;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      leading: const Icon(Icons.apps_outlined),
      title: const Text('เปิดแอปจากชื่อ'),
      subtitle: const Text('เช่น Shopee — เลือกผลลัพธ์เมื่อชื่อซ้ำ'),
      children: [
        TextField(
          controller: launcher.searchController,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => launcher.findApps(),
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: 'ชื่อแอป',
            hintText: 'Shopee',
            suffixIcon: IconButton(
              tooltip: 'ค้นหาแอป',
              onPressed: launcher.isSearching ? null : launcher.findApps,
              icon: launcher.isSearching
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
            ),
          ),
        ),
        if (launcher.apps.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final app in launcher.apps)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              selected: app['packageName'] == launcher.selectedPackage,
              title: Text(app['label']!),
              subtitle: Text(app['packageName']!),
              trailing: app['packageName'] == launcher.selectedPackage
                  ? const Icon(Icons.check_circle_outline)
                  : null,
              onTap: () => launcher.select(app),
            ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: launcher.isLaunching || launcher.selectedPackage == null
                ? null
                : launcher.launchSelected,
            icon: launcher.isLaunching
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.open_in_new),
            label: Text(
              launcher.selectedLabel == null
                  ? 'เลือกแอปที่จะเปิด'
                  : 'เปิด ${launcher.selectedLabel!}',
            ),
          ),
        ],
      ],
    );
  }
}
