import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

class ChatExecutionCard extends StatelessWidget {
  const ChatExecutionCard({super.key, required this.steps, this.active = true});
  final List<Map> steps;
  final bool active;
  static const _tools = {
    'read_selected_file',
    'media_control',
    'open_map',
    'prepare_alarm',
    'open_link',
    'device_info',
    'media_volume',
    'report_observation',
    'verify_goal',
    'wait_for_ui',
    'read_current_ui',
    'read_ui_page',
    'open_app',
    'open_system_settings',
    'find_apps',
    'read_ui_snapshot',
    'ui_action',
  };
  static String toolLabel(BuildContext context, Object? tool) =>
      context.tr('chat.tools.${_tools.contains(tool) ? tool : 'other'}');

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: colors.glassFill,
        border: Border.all(color: colors.borderGlassSubtle),
        borderRadius: BorderRadius.circular(24),
      ),
      child: ExpansionTile(
        initiallyExpanded: false,
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(
          context.tr('chat.steps'),
          style: TextStyle(fontSize: 12, color: colors.primaryCyan),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: steps.map((step) {
          final interrupted =
              step['state'] != 'returned' &&
              !(step['state'] == 'running' && active);
          final running = step['state'] == 'running' && active;
          final result = step['result'];
          final failed =
              result is Map &&
              (result['error'] != null || result['success'] == false);
          return Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(18),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (context) => SafeArea(
                  child: SizedBox(
                    height: MediaQuery.sizeOf(context).height * .7,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.tr('chat.step_details'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: SingleChildScrollView(
                              child: SelectableText(
                                const JsonEncoder.withIndent('  ')
                                    .convert(step),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              child: Row(
                children: [
                  if (running)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      interrupted
                          ? Icons.help_outline
                          : failed
                          ? Icons.error_outline
                          : Icons.check_circle_outline,
                      size: 18,
                      color: failed
                          ? Theme.of(context).colorScheme.error
                          : colors.primaryCyan,
                    ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      toolLabel(context, step['tool']),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    context.tr(
                      running
                          ? 'chat.running'
                          : interrupted
                          ? 'chat.unknown'
                          : failed
                          ? 'chat.failed'
                          : 'chat.returned',
                    ),
                    style: TextStyle(fontSize: 10, color: colors.textSecondary),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
