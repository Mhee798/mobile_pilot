import '../model_selection_scope.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../ai/data/model_download.dart';
import '../../../../core/widgets/settings_value_menu.dart';
import '../../domain/model_entry.dart';
import '../widgets/model_widgets.dart';

class ModelDownloadsPage extends StatefulWidget {
  const ModelDownloadsPage({super.key});
  @override
  State<ModelDownloadsPage> createState() => _ModelDownloadsPageState();
}

class _ModelDownloadsPageState extends State<ModelDownloadsPage> {
  final _url = TextEditingController();
  final _form = GlobalKey<FormState>();
  ModelType _type = ModelType.gemma4;
  bool _vision = true;
  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ModelSelectionScope.of(context);
    final colors = context.appColors;
    return Scaffold(
      backgroundColor: colors.voidBase,
      appBar: AppBar(title: Text(context.tr('models.download'))),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              context.tr('models.download_hint'),
              style: Theme.of(context).textTheme.bodyMedium!
                  .copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: 16),
            if (controller.busy || controller.phase == 'cancelled')
              ModelOperationPanel(controller: controller),
            if (controller.errorKey != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  '${context.tr(controller.errorKey!)}\n${controller.error ?? ''}',
                  style: Theme.of(context).textTheme.bodyMedium!
                      .copyWith(color: Theme.of(context).colorScheme.error),
                ),
              ),
            for (final model in downloadableModels)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ModelPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        model.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '≈ ${formatDownloadSize(model.estimatedBytes)} · ${context.tr('models.vision')}',
                      ),
                      const SizedBox(height: 8),
                      FilledButton.tonal(
                        onPressed: controller.busy
                            ? null
                            : () => controller.download(model),
                        child: Text(context.tr('models.download')),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            ModelPanel(
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('models.custom_url'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _url,
                      enabled: !controller.busy,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: context.tr('models.url'),
                        hintText: 'https://…/model.litertlm',
                      ),
                      validator: (value) {
                        return parseModelDownloadUri(value ?? '') != null
                            ? null
                            : context.tr('models.url_error');
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(context.tr('models.family')),
                      trailing: SettingsValueMenu<ModelType>(
                        value: _type,
                        tooltip: context.tr('models.family'),
                        options: modelFamilyLabels,
                        onSelected: controller.busy
                            ? null
                            : (value) => setState(() => _type = value),
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(context.tr('models.vision')),
                      value: _vision,
                      onChanged: controller.busy
                          ? null
                          : (value) => setState(() => _vision = value),
                    ),
                    FilledButton(
                      onPressed: controller.busy
                          ? null
                          : () {
                              if (!_form.currentState!.validate()) return;
                              final uri = Uri.parse(_url.text.trim());
                              controller.download(
                                DownloadableModel(
                                  uri.pathSegments.last,
                                  uri.toString(),
                                  0,
                                  _type,
                                  _vision,
                                ),
                              );
                            },
                      child: Text(context.tr('models.download')),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
