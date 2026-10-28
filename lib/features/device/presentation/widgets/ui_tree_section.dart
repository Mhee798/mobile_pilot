import 'package:flutter/material.dart';

import '../controllers/ui_tree_controller.dart';

class UiTreeSection extends StatelessWidget {
  const UiTreeSection({super.key, required this.tree});

  final UiTreeController tree;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: tree.inputTextController,
          maxLength: 2000,
          enabled: !tree.feedback.isTapping,
          decoration: const InputDecoration(
            labelText: 'ข้อความแทนที่ในช่องที่เลือกจากรายการ UI',
            helperText: 'อ่าน UI tree แล้วเลือกเมนูช่องพิมพ์ด้านล่าง · ล้างข้อความได้โดยไม่ต้องกรอก',
          ),
        ),

        Text(
          'รายการจากหน้าจอปัจจุบัน (${tree.elements.length})',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        SizedBox(
          child: tree.elements.isEmpty
              ? const Center(
                  child: Text(
                    'แตะ “อ่าน UI tree” เพื่อดู element ที่เข้าถึงได้',
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: tree.elements.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final element = tree.elements[index];
                    final text = element['text'] as String?;
                    final description =
                        element['contentDescription'] as String?;
                    final resourceId = element['resourceId'] as String?;
                    final title =
                        (text?.isNotEmpty == true
                            ? text
                            : description?.isNotEmpty == true
                            ? description
                            : resourceId) ??
                        '(ไม่มีข้อความ)';
                    final details = [
                      if (resourceId?.isNotEmpty == true) resourceId,
                      if (element['clickable'] == true) 'แตะได้',
                      if (element['editable'] == true) 'ช่องพิมพ์',
                    ].join(' · ');
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        element['clickable'] == true
                            ? Icons.touch_app_outlined
                            : Icons.text_fields,
                      ),
                      title: Semantics(
                        label: 'ผล UI รายการ ${index + 1}',
                        excludeSemantics: true,
                        child: Text(
                          'รายการ UI: $title',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      subtitle: details.isEmpty ? null : Text(details),
                      trailing: element['editable'] == true
                          ? PopupMenuButton<String>(
                              tooltip: 'จัดการช่องพิมพ์นี้',
                              enabled: tree.canEditReference(element),
                              onSelected: (action) =>
                                  tree.editReference(element, action),
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'focus',
                                  child: Text('โฟกัสช่องนี้'),
                                ),
                                PopupMenuItem(
                                  value: 'replace',
                                  child: Text('แทนที่ข้อความในช่องนี้'),
                                ),
                                PopupMenuItem(
                                  value: 'clear',
                                  child: Text('ล้างข้อความในช่องนี้'),
                                ),
                              ],
                            )
                          : element['nodeId'] is String
                          ? IconButton(
                              tooltip: 'แตะรายการนี้ในแอปเป้าหมาย',
                              icon: const Icon(Icons.ads_click),
                              onPressed: tree.canTapReference(element)
                                  ? () => tree.tapReference(element)
                                  : null,
                            )
                          : null,
                      onTap: () => tree.targetController.text = title,
                    );
                  },
                ),
        ),
      ],
    );
  }
}
