import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../ai/data/model_download.dart';
import '../../application/model_selection_controller.dart';

class ModelPanel extends StatelessWidget {
  const ModelPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
    borderRadius: BorderRadius.circular(24),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

class ModelOperationPanel extends StatelessWidget {
  const ModelOperationPanel({super.key, required this.controller});
  final ModelSelectionController controller;
  @override
  Widget build(BuildContext context) {
    final progress = controller.progress;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ModelPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('models.phase_${controller.phase}')),
            if (controller.busy) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: progress?.total != null && progress!.total! > 0
                    ? (progress.received / progress.total!).clamp(0.0, 1.0)
                    : controller.nanoProgress != null
                    ? controller.nanoProgress! / 100
                    : null,
              ),
              if (progress != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${formatDownloadSize(progress.received)} / ${progress.total == null ? '—' : formatDownloadSize(progress.total!)}',
                  ),
                ),
              if (controller.nanoProgress != null)
                Text('${controller.nanoProgress}%'),
              if (controller.canCancel)
                TextButton(
                  onPressed: controller.cancelDownload,
                  child: Text(context.tr('models.cancel')),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
