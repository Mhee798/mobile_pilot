import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Compact value picker with the same trigger and popup style across settings.
class SettingsValueMenu<T> extends StatelessWidget {
  SettingsValueMenu({
    super.key,
    required this.value,
    required this.options,
    required this.tooltip,
    required this.onSelected,
  }) : assert(options.isNotEmpty),
       assert(options.containsKey(value));

  final T value;
  final Map<T, String> options;
  final String tooltip;
  final ValueChanged<T>? onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final borderRadius = BorderRadius.circular(10);

    return PopupMenuButton<T>(
      tooltip: tooltip,
      enabled: onSelected != null,
      initialValue: value,
      menuPadding: EdgeInsets.zero,
      borderRadius: borderRadius,
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      clipBehavior: Clip.antiAlias,
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final option in options.entries)
          PopupMenuItem<T>(value: option.key, child: Text(option.value)),
      ],
      child: Container(
        padding: const EdgeInsets.only(left: 8),
        decoration: BoxDecoration(borderRadius: borderRadius),
        constraints: const BoxConstraints(minHeight: 40),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              options[value]!,
              style: Theme.of(context).textTheme.bodyMedium!
                  .copyWith(color: colors.textSecondary, fontSize: 14),
            ),
            Icon(Icons.arrow_drop_down, color: colors.textSecondary),
          ],
        ),
      ),
    );
  }
}
