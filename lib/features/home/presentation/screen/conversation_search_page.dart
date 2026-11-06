import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../../core/theme/app_colors.dart';

class ConversationSearchPage extends StatefulWidget {
  const ConversationSearchPage({super.key, required this.conversations});
  final List<Map<String, dynamic>> conversations;
  @override
  State<ConversationSearchPage> createState() => _ConversationSearchPageState();
}

class _ConversationSearchPageState extends State<ConversationSearchPage> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final results = widget.conversations
        .where(
          (conversation) =>
              '${conversation['title']} ${(conversation['messages'] as List).whereType<Map>().map((m) => m['text']).join(' ')}'
                  .toLowerCase()
                  .contains(_query.toLowerCase()),
        )
        .toList();
    final colors = context.appColors;
    final theme = Theme.of(context);
    final now = DateTime.now();
    return Scaffold(
      backgroundColor: colors.voidBase,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
              child: SizedBox(
                height: 56,
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        style: TextStyle(
                          fontSize: 15,
                          color: colors.textPrimary,
                        ),
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: context.tr('sidebar.search'),
                          prefixIcon: const Icon(TablerIcons.search, size: 24),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 44,
                          ),
                          isDense: true,
                          filled: true,
                          fillColor: theme.brightness == Brightness.dark
                              ? const Color(0xFF3E484F)
                              : theme.colorScheme.surfaceContainerHigh,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (value) =>
                            setState(() => _query = value.trim()),
                      ),
                    ),
                    IconButton(
                      tooltip: context.tr('sidebar.close'),
                      icon: const Icon(TablerIcons.x, size: 24),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    context.tr(
                      _query.isEmpty ? 'sidebar.recent' : 'chat.search_results',
                    ),
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textPrimary,
                      height: 25 / 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (results.isEmpty)
                    Text(
                      context.tr(
                        _query.isEmpty ? 'sidebar.empty' : 'chat.no_results',
                      ),
                    ),
                  for (final conversation in results)
                    InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () => Navigator.pop(context, conversation['id']),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 9,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${conversation['title']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15,
                                  color: colors.textPrimary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _age(context, now, conversation['updatedAt']),
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _age(BuildContext context, DateTime now, Object? timestamp) {
    final updated = timestamp is String ? DateTime.tryParse(timestamp) : null;
    if (updated == null) return '';
    final days = now.difference(updated).inDays;
    if (days < 1) return context.tr('chat.search_today');
    final (unit, count) = switch (days) {
      >= 365 => ('year', days ~/ 365),
      >= 30 => ('month', days ~/ 30),
      >= 7 => ('week', days ~/ 7),
      _ => ('day', days),
    };
    return context.plural('chat.search_age_$unit', count);
  }
}
