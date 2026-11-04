import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../../core/theme/app_colors.dart';

/// Full-width sidebar. Conversation data and navigation belong to its parent.
class HomeMenuPanel extends StatelessWidget {
  const HomeMenuPanel({
    super.key,
    required this.onClose,
    this.onNewChat,
    this.onSearch,
    this.onSettings,
  });

  final VoidCallback onClose;
  final VoidCallback? onNewChat;
  final VoidCallback? onSearch;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: colors.voidBase,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'MobilePilot',
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: context.tr('sidebar.search'),
                    onPressed: onSearch,
                    icon: Icon(
                      TablerIcons.search,
                      color: scheme.onSurface,
                      size: 24,
                    ),
                  ),
                  IconButton(
                    tooltip: context.tr('sidebar.close'),
                    onPressed: onClose,
                    icon: Icon(
                      TablerIcons.x,
                      color: scheme.onSurface,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: SizedBox(
                // Keep the reference's 41px pill inside a 48px touch target.
                height: 48,
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () {
                      onNewChat?.call();
                      onClose();
                    },
                    child: Center(
                      child: Ink(
                        height: 48,
                        decoration: BoxDecoration(
                          color: scheme.outlineVariant.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(20.5),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 15),
                        child: Row(
                          children: [
                            Icon(
                              TablerIcons.edit_circle,
                              color: scheme.onSurface,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              context.tr('sidebar.new_chat'),
                              style: TextStyle(
                                color: scheme.onSurface,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                context.tr('sidebar.recent'),
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      context.tr('sidebar.empty'),
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              thickness: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.3),
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              minLeadingWidth: 24,
              horizontalTitleGap: 12,
              leading: Icon(
                TablerIcons.settings,
                color: scheme.onSurface,
                size: 24,
              ),
              title: Text(
                context.tr('settings.title'),
                style: TextStyle(color: scheme.onSurface, fontSize: 12),
              ),
              onTap: onSettings,
            ),
          ],
        ),
      ),
    );
  }
}
