import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../settings/presentation/screen/settings_page.dart';
import '../../../models/presentation/model_selection_scope.dart';
import '../../../models/presentation/screen/model_selection_page.dart';
import '../widgets/bottom_glow_widget.dart';
import '../widgets/chat_bar.dart';
import '../widgets/figma_background_widget.dart';
import '../widgets/full_screen_swipe_menu.dart';
import '../widgets/home_menu_panel.dart';

export '../widgets/bottom_glow_widget.dart' show BottomGlowWidget;
export '../widgets/chat_bar.dart' show ChatBar, AudioWaveWidget;
export '../widgets/figma_background_widget.dart' show FigmaBackgroundWidget;

/// Separate entry point for the production interface, still under development.
class MobilePilotHomePage extends StatefulWidget {
  const MobilePilotHomePage({super.key});

  @override
  State<MobilePilotHomePage> createState() => _MobilePilotHomePageState();
}

class _MobilePilotHomePageState extends State<MobilePilotHomePage> {
  void _handleSend(String text) {
    if (text.trim().isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.tr('home.sent', namedArgs: {'text': text})),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final models = ModelSelectionScope.maybeOf(context);

    return FullScreenSwipeMenu(
      bodyBuilder: (context, openMenu) => Scaffold(
        backgroundColor: colors.voidBase,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            onPressed: openMenu,
            icon: Icon(TablerIcons.menu_2, color: colors.textPrimary),
          ),
          title: TextButton(
            onPressed: models == null
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const ModelSelectionPage(),
                    ),
                  ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    models?.selection?.label ?? 'MobilePilot',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.textPrimary, fontSize: 16),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  TablerIcons.chevron_down,
                  color: colors.textSecondary,
                  size: 16,
                ),
              ],
            ),
          ),
          actions: [
            IconButton(
              onPressed: () {},
              icon: Icon(TablerIcons.automation, color: colors.textPrimary),
            ),
          ],
        ),
        body: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            const Positioned.fill(child: FigmaBackgroundWidget()),
            Positioned(
              left: -(MediaQuery.sizeOf(context).width) / 6,
              right: -(MediaQuery.sizeOf(context).width) / 6,
              bottom: -350 / 2,
              child: BottomGlowWidget(),
            ),
            SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          context.tr('home.placeholder'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ),
                  ChatBar(onSend: _handleSend, onPhoto: () {}, onFile: () {}),
                ],
              ),
            ),
          ],
        ),
      ),
      menuBuilder: (context, closeMenu) => HomeMenuPanel(
        onClose: closeMenu,
        onSettings: () {
          closeMenu();
          Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const SettingsPage()));
        },
      ),
    );
  }
}
