import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';

/// Home sits on top and slides away. The menu stays put underneath, with a
/// small gap so the two pages are separate sheets — not one continuous strip.
class FullScreenSwipeMenu extends StatefulWidget {
  const FullScreenSwipeMenu({
    super.key,
    required this.bodyBuilder,
    required this.menuBuilder,
    this.duration = const Duration(milliseconds: 280),
  });

  final Widget Function(BuildContext context, VoidCallback openMenu)
  bodyBuilder;
  final Widget Function(BuildContext context, VoidCallback closeMenu)
  menuBuilder;
  final Duration duration;

  @override
  State<FullScreenSwipeMenu> createState() => _FullScreenSwipeMenuState();
}

class _FullScreenSwipeMenuState extends State<FullScreenSwipeMenu>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress;

  static const _flingVelocity = 350.0;

  /// How far the menu sits to the left while hidden, then eases into the front.
  static const _menuGapFactor = 0.12;

  FocusNode? _foldedFocus;
  bool _keyboardFolded = false;

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(vsync: this, duration: widget.duration)
      ..addListener(_syncKeyboard);
  }

  @override
  void dispose() {
    _progress.removeListener(_syncKeyboard);
    _progress.dispose();
    super.dispose();
  }

  bool get _isOpen => _progress.value > 0.5;

  void openMenu() => _progress.animateTo(1, curve: Curves.easeOutCubic);

  void closeMenu() => _progress.animateTo(0, curve: Curves.easeOutCubic);

  void _syncKeyboard() {
    if (_progress.value > 0) {
      if (_keyboardFolded) return;
      _keyboardFolded = true;
      final focus = FocusManager.instance.primaryFocus;
      if (focus != null && focus.hasFocus) {
        _foldedFocus = focus;
        focus.unfocus();
      }
      SystemChannels.textInput.invokeMethod('TextInput.hide');
      return;
    }

    if (!_keyboardFolded) return;
    _keyboardFolded = false;
    final saved = _foldedFocus;
    _foldedFocus = null;
    if (saved == null || !saved.canRequestFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          ModalRoute.of(context)?.isCurrent != false &&
          saved.context != null &&
          saved.canRequestFocus) {
        saved.requestFocus();
      }
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final width = MediaQuery.sizeOf(context).width;
    if (width <= 0) return;
    _progress.value = (_progress.value + details.primaryDelta! / width).clamp(
      0.0,
      1.0,
    );
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() > _flingVelocity) {
      velocity > 0 ? openMenu() : closeMenu();
      return;
    }
    _isOpen ? openMenu() : closeMenu();
  }

  Widget _sheet({required Widget child}) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = widget.bodyBuilder(context, openMenu);
    final menu = widget.menuBuilder(context, closeMenu);
    return AnimatedBuilder(
      animation: _progress,
      builder: (context, _) {
        final width = MediaQuery.sizeOf(context).width;
        final t = _progress.value;

        return PopScope(
          canPop: t == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && t > 0) closeMenu();
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              IgnorePointer(
                ignoring: t == 0,
                child: Transform.translate(
                  offset: Offset((t - 1) * width * _menuGapFactor, 0),
                  child: _sheet(child: menu),
                ),
              ),
              IgnorePointer(
                ignoring: t == 1,
                child: Transform.translate(
                  offset: Offset(t * width, 0),
                  child: _sheet(
                    child: ClipRect(
                      child: PhysicalModel(
                        color: context.appColors.voidBase,
                        elevation: t == 0 ? 0 : 24,
                        shadowColor: Colors.black,
                        child: body,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
