import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/lucide.dart';
import 'pressable.dart';

enum MainNavView { player, library, equalizer, stats, settings }

class NavigationBottomBar extends StatefulWidget {
  const NavigationBottomBar({
    super.key,
    required this.currentView,
    required this.accentColor,
    required this.onNavigate,
    required this.onOpenEqualizer,
    required this.onOpenQueue,
    required this.onOpenSettings,
  });

  final MainNavView currentView;
  final Color accentColor;
  final ValueChanged<MainNavView> onNavigate;
  final VoidCallback onOpenEqualizer;
  final VoidCallback onOpenQueue;
  final VoidCallback onOpenSettings;

  @override
  State<NavigationBottomBar> createState() => _NavigationBottomBarState();
}

class _NavigationBottomBarState extends State<NavigationBottomBar> with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  Widget _item({
    required String body,
    required String label,
    required bool active,
    required VoidCallback onTap,
    bool spin = false,
  }) {
    final Color iconColor = active ? widget.accentColor : AppColors.zinc500;
    Widget icon = LIcon(body, size: 20, color: iconColor);
    if (spin && active) {
      icon = RotationTransition(turns: _spin, child: icon);
    }
    return Pressable(
      scale: 0.95,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            icon,
            const SizedBox(height: 4),
            Text(
              label.toUpperCase(),
              style: AppText.mono(
                10,
                active ? 700 : 400,
                active ? Colors.white : AppColors.zinc500,
                tracking: 0.05,
                tabular: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double bottomInset = MediaQuery.paddingOf(context).bottom;
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 8 + bottomInset),
          decoration: BoxDecoration(
            color: const Color.fromRGBO(18, 18, 26, 0.65),
            border: Border(
              top: BorderSide(color: AppColors.white(0.10)),
              left: BorderSide(color: AppColors.white(0.08)),
              right: BorderSide(color: AppColors.white(0.08)),
              bottom: BorderSide(color: AppColors.white(0.08)),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: <Widget>[
              _item(
                body: LucideIcons.disc,
                label: 'Player',
                active: widget.currentView == MainNavView.player,
                spin: true,
                onTap: () => widget.onNavigate(MainNavView.player),
              ),
              _item(
                body: LucideIcons.library,
                label: 'Library',
                active: widget.currentView == MainNavView.library || widget.currentView == MainNavView.stats,
                onTap: () => widget.onNavigate(MainNavView.library),
              ),
              _item(
                body: LucideIcons.slidersVertical,
                label: 'EQ Lab',
                active: widget.currentView == MainNavView.equalizer,
                onTap: widget.onOpenEqualizer,
              ),
              _item(
                body: LucideIcons.listMusic,
                label: 'Queue',
                active: false,
                onTap: widget.onOpenQueue,
              ),
              _item(
                body: LucideIcons.settings,
                label: 'Settings',
                active: widget.currentView == MainNavView.settings,
                onTap: widget.onOpenSettings,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
