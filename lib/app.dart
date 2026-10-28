import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/equalizer_screen.dart';
import 'screens/library_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/stats_screen.dart';
import 'state/player_controller.dart';
import 'theme/app_theme.dart';
import 'theme/lucide.dart';
import 'widgets/dynamic_background.dart';
import 'widgets/lockscreen_player.dart';
import 'widgets/mini_player.dart';
import 'widgets/krypton_splash.dart';
import 'widgets/navigation_bottom_bar.dart';
import 'widgets/pressable.dart';
import 'widgets/queue_sheet.dart';

class AetherApp extends StatefulWidget {
  const AetherApp({super.key, required this.controller});

  final PlayerController controller;

  @override
  State<AetherApp> createState() => _AetherAppState();
}

class _AetherAppState extends State<AetherApp> {
  bool _lightMode = false;
  bool? _lastSystemUiLightMode;

  PlayerController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _lightMode = controller.settings.lightMode;
    controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant AetherApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      _lightMode = controller.settings.lightMode;
      controller.addListener(_handleControllerChanged);
    }
  }

  @override
  void dispose() {
    controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    final bool next = controller.settings.lightMode;
    // Position/progress notifications are frequent; rebuild MaterialApp only when
    // its actual appearance mode changes, not on every playback tick.
    if (next != _lightMode && mounted) setState(() => _lightMode = next);
  }

  ThemeData _themeFor(Brightness brightness) {
    final bool light = brightness == Brightness.light;
    return ThemeData(
      brightness: brightness,
      scaffoldBackgroundColor: light ? const Color(0xFFF7F8FC) : Colors.black,
      canvasColor: light ? const Color(0xFFF7F8FC) : const Color(0xFF09090B),
      cardColor: light ? Colors.white : const Color(0xFF18181B),
      dialogTheme: DialogThemeData(
        backgroundColor: light ? Colors.white : const Color(0xFF18181B),
      ),
      useMaterial3: true,
      fontFamily: AppText.inter,
      colorScheme: ColorScheme.fromSeed(
        seedColor: controller.accentColor,
        brightness: brightness,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    AppColors.configure(light: _lightMode);
    if (_lastSystemUiLightMode != _lightMode) {
      _lastSystemUiLightMode = _lightMode;
      SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
        statusBarIconBrightness: _lightMode ? Brightness.dark : Brightness.light,
        systemNavigationBarIconBrightness: _lightMode ? Brightness.dark : Brightness.light,
      ));
    }
    return MaterialApp(
      title: 'Krypton m.Player',
      debugShowCheckedModeBanner: false,
      theme: _themeFor(Brightness.light),
      darkTheme: _themeFor(Brightness.dark),
      themeMode: _lightMode ? ThemeMode.light : ThemeMode.dark,
      // Bottom sheets and dialogs live in Navigator overlays, so apply the app's
      // font scaling at the MaterialApp boundary as well as in the main shell.
      builder: (BuildContext context, Widget? child) => ListenableBuilder(
        listenable: controller,
        builder: (BuildContext context, Widget? _) => ValueListenableBuilder<bool>(
          valueListenable: controller.uiForeground,
          builder: (BuildContext context, bool uiForeground, Widget? __) => TickerMode(
            // Mute every Flutter ticker while backgrounded, without touching audio.
            enabled: uiForeground,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(controller.settings.fontScale),
              ),
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
      ),
      home: AppShell(controller: controller),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller});

  final PlayerController controller;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  MainNavView _view = MainNavView.player;
  MainNavView _previousView = MainNavView.player;
  bool _showSplash = true;
  Timer? _splashTimer;

  PlayerController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _splashTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showSplash = false);
    });
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    super.dispose();
  }

  void _navigateTo(MainNavView view) {
    if (view == _view) return;
    setState(() {
      _previousView = _view;
      _view = view;
    });
  }

  void _goBack() {
    final MainNavView target = _previousView == _view ? MainNavView.player : _previousView;
    setState(() {
      _previousView = _view;
      _view = target;
    });
  }

  void _openEqualizer() => _navigateTo(MainNavView.equalizer);

  void _openQueue() {
    unawaited(showQueueSheet(context, c));
  }

  void _openSettings() => _navigateTo(MainNavView.settings);

  void _openStats() => _navigateTo(MainNavView.stats);


  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (BuildContext context, Widget? _) {
        final bool needsPermission = c.permissionsChecked && !c.mediaGranted;
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(c.settings.fontScale)),
          child: _showSplash
              ? KryptonSplashScreen(lightMode: c.settings.lightMode)
              : Scaffold(
                  backgroundColor: AppColors.pageBackground,
                  body: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      ValueListenableBuilder<bool>(
                        valueListenable: c.uiForeground,
                        builder: (BuildContext context, bool uiForeground, Widget? _) {
                          // Dispose the blurred album-art image and GPU blur layers while
                          // hidden; they are presentation-only and rebuild on resume.
                          if (!uiForeground) {
                            return ColoredBox(
                              color: c.settings.lightMode ? const Color(0xFFF7F8FC) : Colors.black,
                            );
                          }
                          return DynamicBackground(
                            coverPath: c.currentCoverPath,
                            accentColor: c.accentColor,
                            theme: c.settings.theme,
                            lightMode: c.settings.lightMode,
                          );
                        },
                      ),
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 512),
                          child: needsPermission
                              ? _PermissionGate(controller: c)
                              : Column(
                                  children: <Widget>[
                                    Expanded(
                                      child: AnimatedSwitcher(
                                        duration: const Duration(milliseconds: 220),
                                        switchInCurve: Curves.easeOutCubic,
                                        switchOutCurve: Curves.easeInCubic,
                                        transitionBuilder: (Widget child, Animation<double> anim) {
                                          return FadeTransition(
                                            opacity: anim,
                                            child: ScaleTransition(scale: Tween<double>(begin: 0.975, end: 1.0).animate(anim), child: child),
                                          );
                                        },
                                        child: _buildView(),
                                      ),
                                    ),
                                    if (_view != MainNavView.player)
                                      MiniPlayer(controller: c, onOpenPlayer: () => _navigateTo(MainNavView.player)),
                                    NavigationBottomBar(
                                      currentView: _view,
                                      accentColor: c.accentColor,
                                      onNavigate: _navigateTo,
                                      onOpenEqualizer: _openEqualizer,
                                      onOpenQueue: _openQueue,
                                      onOpenSettings: _openSettings,
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }

  Widget _buildView() {
    switch (_view) {
      case MainNavView.player:
        return SizedBox.expand(
          key: const ValueKey<String>('player-view'),
          child: LockscreenPlayer(
            controller: c,
            onMinimize: () => _navigateTo(MainNavView.library),
            onOpenQueue: _openQueue,
            onOpenEqualizer: _openEqualizer,
            onOpenSettings: _openSettings,
          ),
        );
      case MainNavView.library:
        return SizedBox.expand(
          key: const ValueKey<String>('library-view'),
          child: LibraryScreen(controller: c, onOpenStats: _openStats, onOpenQueue: _openQueue),
        );
      case MainNavView.equalizer:
        return SizedBox.expand(key: const ValueKey<String>('equalizer-view'), child: EqualizerScreen(controller: c, onBack: _goBack));
      case MainNavView.stats:
        return SizedBox.expand(key: const ValueKey<String>('stats-view'), child: StatsScreen(controller: c, onBack: _goBack));
      case MainNavView.settings:
        return SizedBox.expand(
          key: const ValueKey<String>('settings-view'),
          child: SettingsScreen(controller: c, onBack: _goBack, onOpenEqualizer: _openEqualizer, onOpenStats: _openStats),
        );
    }
  }
}

class _PermissionGate extends StatelessWidget {
  const _PermissionGate({required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final Color accent = AppColors.cyan;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          LIcon(LucideIcons.sparkles, size: 40, color: AppColors.cyan400),
          const SizedBox(height: 16),
          Text('AUDIO ACCESS REQUIRED', textAlign: TextAlign.center, style: AppText.display(18, 700, Colors.white, lineHeight: 28, tracking: 0.05)),
          const SizedBox(height: 8),
          Text('Krypton m.Player needs permission to read the music on this device.', textAlign: TextAlign.center, style: AppText.body(14, 400, AppColors.zinc400, lineHeight: 20)),
          const SizedBox(height: 24),
          Pressable(
            scale: 0.95,
            onTap: controller.requestMediaPermission,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(999), boxShadow: <BoxShadow>[BoxShadow(color: accent.withValues(alpha: 0.45), blurRadius: 24, spreadRadius: 2)]),
              child: Text('GRANT ACCESS', style: AppText.mono(12, 700, Colors.black, tracking: 0.1)),
            ),
          ),
          const SizedBox(height: 12),
          Pressable(
            scale: 0.95,
            onTap: controller.openSystemSettings,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), border: Border.all(color: AppColors.white(0.2))),
              child: Text('OPEN SETTINGS', style: AppText.mono(12, 400, AppColors.zinc300, tracking: 0.1)),
            ),
          ),
        ],
      ),
    );
  }
}
