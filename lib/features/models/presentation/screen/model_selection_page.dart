import '../model_selection_scope.dart';

import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../ai/data/model_download.dart';
import '../../../../core/widgets/settings_value_menu.dart';
import '../../application/model_selection_controller.dart';
import '../../domain/model_entry.dart';
import 'model_downloads_page.dart';
import '../widgets/model_widgets.dart';

class ModelSelectionPage extends StatefulWidget {
  const ModelSelectionPage({super.key});
  @override
  State<ModelSelectionPage> createState() => _ModelSelectionPageState();
}

class _ModelSelectionPageState extends State<ModelSelectionPage> {
  bool _cloud = false;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final controller = ModelSelectionScope.of(context);
    _cloud = controller.selection?.location == ModelLocation.cloud;
    // Native probing is read-only; visiting this page never starts a download.
    unawaited(controller.initialize().then((_) => controller.probeNano()));
  }

  Future<void> _import(ModelSelectionController controller) async {
    final options = await showModalBottomSheet<({ModelType type, bool vision})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const ImportModelSheet(),
    );
    if (options != null) {
      unawaited(controller.importFile(options.type, options.vision));
    }
  }

  Future<void> _delete(
    ModelSelectionController controller,
    LocalModelEntry entry,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('models.delete_title')),
        content: Text(
          context.tr('models.delete_confirm', namedArgs: {'name': entry.name}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('models.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('models.delete')),
          ),
        ],
      ),
    );
    if (confirmed == true) unawaited(controller.delete(entry));
  }

  @override
  Widget build(BuildContext context) {
    final controller = ModelSelectionScope.of(context);
    final colors = context.appColors;
    final selection = controller.selection;
    var readinessKey = 'models.reload';
    if (controller.ready) {
      readinessKey = selection?.location == ModelLocation.cloud
          ? 'models.cloud_checked'
          : 'models.ready';
    }
    final nanoCanLoad = [
      'available',
      'downloadable',
      'downloading',
    ].contains(controller.nanoStatus);
    return Scaffold(
      backgroundColor: colors.voidBase,
      appBar: AppBar(
        title: Text(context.tr('models.title')),
        centerTitle: true,
        leading: IconButton(
          tooltip: context.tr('common.back'),
          icon: const Icon(TablerIcons.chevron_left),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            ModelPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr(
                      controller.ready ? 'models.current' : 'models.selected',
                    ),
                    style: Theme.of(context).textTheme.bodyMedium!
                        .copyWith(color: colors.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        selection?.location == ModelLocation.cloud
                            ? TablerIcons.cloud
                            : TablerIcons.cpu,
                        color: colors.primaryCyan,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          selection?.label ?? context.tr('models.none'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (selection != null)
                        TextButton(
                          onPressed: controller.busy ? null : controller.unload,
                          child: Text(context.tr('models.unload')),
                        ),
                    ],
                  ),
                  if (selection != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        context.tr(readinessKey),
                        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                          color: colors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: false,
                  icon: const Icon(TablerIcons.device_mobile),
                  label: Text(context.tr('models.local')),
                ),
                ButtonSegment(
                  value: true,
                  icon: const Icon(TablerIcons.cloud),
                  label: Text(context.tr('models.cloud')),
                ),
              ],
              selected: {_cloud},
              onSelectionChanged: (value) =>
                  setState(() => _cloud = value.single),
            ),
            const SizedBox(height: 16),
            if (controller.busy || controller.phase == 'cancelled')
              ModelOperationPanel(controller: controller),
            if (controller.errorKey case final key?)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: ModelPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr(key),
                        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      if (controller.error != null)
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: Text(context.tr('models.error_details')),
                          children: [SelectableText(controller.error!)],
                        ),
                      if (!controller.loaded)
                        TextButton(
                          onPressed: controller.initialize,
                          child: Text(context.tr('models.retry')),
                        ),
                    ],
                  ),
                ),
              ),
            if (!controller.loaded && controller.errorKey == null)
              const Center(child: CircularProgressIndicator()),
            if (_cloud) ...[
              Text(
                context.tr('models.cloud_description'),
                style: Theme.of(context).textTheme.bodyMedium!
                    .copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: 12),
              for (final entry in cloudModels.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ModelPanel(
                    padding: EdgeInsets.zero,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: const Icon(TablerIcons.cloud),
                      title: Text(entry.value),
                      subtitle: Text(
                        'Google · Firebase AI Logic\n${entry.key}',
                      ),
                      isThreeLine: true,
                      trailing: Icon(
                        selection?.location == ModelLocation.cloud &&
                                selection?.id == entry.key &&
                                controller.ready
                            ? TablerIcons.circle_check
                            : TablerIcons.chevron_right,
                        color: selection?.id == entry.key && controller.ready
                            ? colors.primaryCyan
                            : colors.textSecondary,
                      ),
                      onTap: controller.busy || !controller.loaded
                          ? null
                          : () =>
                                controller.selectCloud(entry.key, entry.value),
                    ),
                  ),
                ),
              Text(
                context.tr('models.cloud_check_hint'),
                style: Theme.of(context).textTheme.bodyMedium!
                    .copyWith(color: colors.textSecondary, fontSize: 12),
              ),
            ] else ...[
              _heading(context.tr('models.my_models')),
              if (controller.loaded && controller.models.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: ModelPanel(
                    child: Text(
                      context.tr('models.empty'),
                      style: Theme.of(context).textTheme.bodyMedium!
                          .copyWith(color: colors.textSecondary),
                    ),
                  ),
                ),
              for (final entry in controller.models)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ModelPanel(
                    padding: EdgeInsets.zero,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: Icon(
                        selection?.location == ModelLocation.file &&
                                selection?.id == entry.id &&
                                controller.ready
                            ? TablerIcons.circle_check
                            : TablerIcons.file,
                        color: colors.textSecondary,
                      ),
                      title: Text(
                        entry.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${formatDownloadSize(entry.bytes)} · ${entry.type.name}\n'
                        '${context.tr(entry.vision ? 'models.vision' : 'models.text_only')}',
                      ),
                      isThreeLine: true,
                      trailing: PopupMenuButton<String>(
                        tooltip: context.tr('models.more'),
                        onSelected: (value) => value == 'delete'
                            ? _delete(controller, entry)
                            : _details(entry),
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'details',
                            child: Text(context.tr('models.details')),
                          ),
                          if (entry.managed)
                            PopupMenuItem(
                              value: 'delete',
                              enabled:
                                  !controller.busy &&
                                  !(selection?.location == ModelLocation.file &&
                                      selection?.id == entry.id),
                              child: Text(context.tr('models.delete')),
                            ),
                        ],
                      ),
                      onTap: controller.busy
                          ? null
                          : () => controller.selectFile(entry),
                    ),
                  ),
                ),
              _heading('Gemini Nano'),
              ModelPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr('models.nano_description')),
                    const SizedBox(height: 8),
                    Text(
                      context.tr('models.nano_${controller.nanoStatus}'),
                      style: Theme.of(context).textTheme.bodyMedium!
                          .copyWith(color: colors.textSecondary, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton.tonal(
                          onPressed:
                              controller.busy ||
                                  !controller.loaded ||
                                  !nanoCanLoad
                              ? null
                              : controller.selectNano,
                          child: Text(
                            context.tr(
                              controller.nanoStatus == 'available'
                                  ? 'models.use'
                                  : 'models.prepare',
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed:
                              controller.busy ||
                                  controller.nanoStatus == 'checking'
                              ? null
                              : controller.probeNano,
                          child: Text(context.tr('models.check_again')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _heading(context.tr('models.add')),
              ModelPanel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(TablerIcons.download),
                      title: Text(context.tr('models.download')),
                      trailing: const Icon(TablerIcons.chevron_right),
                      onTap: !controller.loaded || controller.busy
                          ? null
                          : () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => const ModelDownloadsPage(),
                              ),
                            ),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(
                      leading: const Icon(TablerIcons.file_import),
                      title: Text(context.tr('models.import')),
                      subtitle: const Text('.litertlm'),
                      trailing: const Icon(TablerIcons.chevron_right),
                      onTap: !controller.loaded || controller.busy
                          ? null
                          : () => _import(controller),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              context.tr('models.switch_hint'),
              style: Theme.of(context).textTheme.bodyMedium!
                  .copyWith(color: colors.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium!
          .copyWith(color: context.appColors.textSecondary, fontSize: 12),
    ),
  );

  void _details(LocalModelEntry entry) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(entry.name),
      content: SelectableText(
        '${entry.type.name} · ${formatDownloadSize(entry.bytes)}\n${entry.path}',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('models.close')),
        ),
      ],
    ),
  );
}

/// The file's family is explicit because a filename cannot reliably identify its chat template.
class ImportModelSheet extends StatefulWidget {
  const ImportModelSheet({super.key});
  @override
  State<ImportModelSheet> createState() => _ImportModelSheetState();
}

class _ImportModelSheetState extends State<ImportModelSheet> {
  ModelType _type = ModelType.gemma4;
  bool _vision = true;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.tr('models.import'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Text(context.tr('models.family_hint')),
          ListTile(
            title: Text(context.tr('models.family')),
            trailing: SettingsValueMenu<ModelType>(
              value: _type,
              tooltip: context.tr('models.family'),
              options: modelFamilyLabels,
              onSelected: (value) => setState(() => _type = value),
            ),
          ),
          SwitchListTile(
            title: Text(context.tr('models.vision')),
            value: _vision,
            onChanged: (value) => setState(() => _vision = value),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, (type: _type, vision: _vision)),
            child: Text(context.tr('models.choose_file')),
          ),
        ],
      ),
    ),
  );
}
