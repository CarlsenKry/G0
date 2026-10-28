import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../models/track.dart';
import '../state/player_controller.dart';
import '../theme/app_theme.dart';
import '../theme/lucide.dart';
import 'audio_visualizer.dart';
import 'cover_image.dart';
import 'pressable.dart';
import 'synced_lyrics_view.dart';
import 'waveform_seekbar.dart';

class LockscreenPlayer extends StatefulWidget {
  const LockscreenPlayer({
    super.key,
    required this.controller,
    required this.onMinimize,
    required this.onOpenQueue,
    required this.onOpenEqualizer,
    required this.onOpenSettings,
  });

  final PlayerController controller;
  final VoidCallback onMinimize;
  final VoidCallback onOpenQueue;
  final VoidCallback onOpenEqualizer;
  final VoidCallback onOpenSettings;

  @override
  State<LockscreenPlayer> createState() => _LockscreenPlayerState();
}

class _LockscreenPlayerState extends State<LockscreenPlayer> with TickerProviderStateMixin {
  bool _showLyrics = false;
  String _timeStr = '';
  String _dateStr = '';
  Timer? _clock;
  Timer? _visualizerSwitchTimer;
  late final math.Random _visualizerRandom;
  late VisualizerStyle _activeVisualizerStyle;

  Offset _tilt = Offset.zero; // x = rotateY deg, y = rotateX deg
  Offset _dragTotal = Offset.zero;
  bool _dragging = false;
  bool _isForeground = true;
  final GlobalKey _cardKey = GlobalKey();

  late final AnimationController _ping;
  late final Animation<double> _pingCurve;
  late final AnimationController _pulse;
  late final Animation<double> _pulseCurve;

  static const List<String> _weekdays = <String>['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
  static const List<String> _months = <String>[
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];

  PlayerController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _isForeground = c.uiForeground.value;
    c.uiForeground.addListener(_handleForegroundChanged);
    _ping = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();
    _pingCurve = CurvedAnimation(parent: _ping, curve: const Cubic(0, 0, 0.2, 1));
    _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
    _pulseCurve = CurvedAnimation(parent: _pulse, curve: const Cubic(0.4, 0, 0.6, 1));
    _visualizerRandom = math.Random();
    _activeVisualizerStyle = c.settings.visualizerStyle;
    _updateClock();
    if (_isForeground) {
      _clock = Timer.periodic(const Duration(seconds: 1), (Timer _) => _updateClock());
      _scheduleVisualizerSwitch();
    }
  }

  @override
  void dispose() {
    c.uiForeground.removeListener(_handleForegroundChanged);
    _clock?.cancel();
    _visualizerSwitchTimer?.cancel();
    _ping.dispose();
    _pulse.dispose();
    super.dispose();
  }

  void _handleForegroundChanged() {
    final bool foreground = c.uiForeground.value;
    if (!mounted || foreground == _isForeground) return;
    setState(() => _isForeground = foreground);
    if (foreground) {
      _updateClock();
      _clock ??= Timer.periodic(const Duration(seconds: 1), (Timer _) => _updateClock());
      _scheduleVisualizerSwitch();
    } else {
      _clock?.cancel();
      _clock = null;
      _visualizerSwitchTimer?.cancel();
      _visualizerSwitchTimer = null;
    }
  }

  void _updateClock() {
    final DateTime now = DateTime.now();
    final String t = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final String d = '${_weekdays[now.weekday - 1]}, ${_months[now.month - 1]} ${now.day}';
    if (t != _timeStr || d != _dateStr) {
      if (mounted) {
        setState(() {
          _timeStr = t;
          _dateStr = d;
        });
      }
    }
  }

  // ------------------------------------------------------------------ gestures

  void _onPanStart(DragStartDetails d) {
    _dragging = true;
    _dragTotal = Offset.zero;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final RenderObject? ro = _cardKey.currentContext?.findRenderObject();
    Offset tilt = _tilt;
    if (ro is RenderBox && ro.hasSize) {
      final Offset local = ro.globalToLocal(d.globalPosition);
      final double px = local.dx / ro.size.width - 0.5;
      final double py = local.dy / ro.size.height - 0.5;
      tilt = Offset(px * 18, -py * 18);
    }
    setState(() {
      _dragTotal += d.delta;
      _tilt = tilt;
    });
  }

  void _onPanEnd(DragEndDetails d) {
    const double threshold = 50;
    final Offset o = _dragTotal;
    setState(() {
      _dragging = false;
      _dragTotal = Offset.zero;
      _tilt = Offset.zero;
    });
    if (o.dy > threshold * 1.5) {
      widget.onMinimize();
    } else if (o.dy < -threshold * 1.5) {
      widget.onOpenQueue();
    } else if (o.dx < -threshold) {
      c.next();
    } else if (o.dx > threshold) {
      c.prev();
    }
  }

  void _onPanCancel() {
    setState(() {
      _dragging = false;
      _dragTotal = Offset.zero;
      _tilt = Offset.zero;
    });
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final Track? track = c.currentTrack;
    if (track == null) {
      return Center(
        child: Text(
          c.scanning ? 'Scanning library...' : 'No track loaded',
          style: AppText.body(14, 400, AppColors.zinc500, lineHeight: 20),
        ),
      );
    }

    final double topInset = MediaQuery.paddingOf(context).top;
    final double topPad = math.max(32.0, topInset + 8);
    final Color accent = c.accentColor;
    final Color glow = c.glowColor;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, topPad, 20, 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          _buildHeader(accent),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (Widget child, Animation<double> anim) {
                  return FadeTransition(
                    opacity: anim,
                    child: ScaleTransition(scale: Tween<double>(begin: 0.95, end: 1.0).animate(anim), child: child),
                  );
                },
                child: _showLyrics
                    ? _buildLyrics(track, accent)
                    : _buildArt(track, accent, glow),
              ),
            ),
          ),
          _buildControls(track, accent, glow),
        ],
      ),
    );
  }

  Widget _buildHeader(Color accent) {
    final int? sleep = c.sleepTimeRemaining;
    Widget center;
    if (sleep != null) {
      center = AnimatedBuilder(
        animation: _pulseCurve,
        builder: (BuildContext context, Widget? child) {
          return Opacity(opacity: 1.0 - 0.5 * _pulseCurve.value, child: child);
        },
        child: Pressable(
          scale: 1.0,
          onTap: widget.onOpenSettings,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.cyan950.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.cyan500.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                LIcon(LucideIcons.moon, size: 12, color: AppColors.cyan400),
                const SizedBox(width: 4),
                Text(
                  '${(sleep / 60).ceil()}m left',
                  style: AppText.mono(11, 400, AppColors.cyan300, lineHeight: 16.5, tabular: true),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      center = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.white(0.05),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.white(0.05)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: 6,
              height: 6,
              child: AnimatedBuilder(
                animation: _pingCurve,
                builder: (BuildContext context, Widget? child) {
                  final double t = _pingCurve.value;
                  return Opacity(
                    opacity: 1.0 - t,
                    child: Transform.scale(scale: 1.0 + t, child: child),
                  );
                },
                child: const DecoratedBox(
                  decoration: BoxDecoration(color: AppColors.cyan400, shape: BoxShape.circle),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'KRY m.Player',
              style: AppText.mono(10, 400, AppColors.zinc400, lineHeight: 15, tabular: true),
            ),
          ],
        ),
      );
    }

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Pressable(
                onTap: widget.onMinimize,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      LIcon(LucideIcons.chevronDown, size: 20, color: AppColors.cyan400),
                      const SizedBox(width: 6),
                      Text(
                        'LIBRARY',
                        style: AppText.display(11, 600, AppColors.zinc300, lineHeight: 16.5, tracking: 0.05),
                      ),
                    ],
                  ),
                ),
              ),
              center,
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Pressable(
                    onTap: widget.onOpenEqualizer,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: LIcon(LucideIcons.slidersVertical, size: 16, color: AppColors.cyan400),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Pressable(
                    onTap: widget.onOpenQueue,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: LIcon(LucideIcons.listMusic, size: 16, color: AppColors.fuchsia400),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: <Widget>[
              Text(
                _timeStr.isEmpty ? '12:00' : _timeStr,
                style: AppText.display(
                  36,
                  700,
                  Colors.white,
                  lineHeight: 40,
                  tracking: -0.025,
                  shadows: <Shadow>[
                    Shadow(color: AppColors.black(0.8), blurRadius: 12, offset: const Offset(0, 2)),
                  ],
                ),
              ),
              Text(
                _dateStr.isEmpty ? 'ACTIVE' : _dateStr,
                style: AppText.mono(11, 500, AppColors.zinc400, lineHeight: 16.5, tracking: 0.1, tabular: true),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _scheduleVisualizerSwitch() {
    _visualizerSwitchTimer?.cancel();
    _visualizerSwitchTimer = null;
    if (!_isForeground) return;
    _visualizerSwitchTimer = Timer(Duration(seconds: 8 + _visualizerRandom.nextInt(11)), () {
      if (!mounted || !_isForeground) return;
      final List<VisualizerStyle> alternatives = VisualizerStyle.values
          .where((VisualizerStyle style) => style != _activeVisualizerStyle)
          .toList(growable: false);
      setState(() {
        _activeVisualizerStyle = alternatives[_visualizerRandom.nextInt(alternatives.length)];
      });
      _scheduleVisualizerSwitch();
    });
  }

  void _cycleVisualizerNow() {
    final List<VisualizerStyle> styles = VisualizerStyle.values;
    final int next = (styles.indexOf(_activeVisualizerStyle) + 1) % styles.length;
    setState(() => _activeVisualizerStyle = styles[next]);
    unawaited(c.updateSettings(c.settings.copyWith(visualizerStyle: _activeVisualizerStyle)));
    _scheduleVisualizerSwitch();
  }

  Widget _buildArt(Track track, Color accent, Color glow) {
    final VisualizerStyle style = _activeVisualizerStyle;
    final Matrix4 tiltMatrix = Matrix4.identity()
      ..setEntry(3, 2, -1 / 800)
      ..rotateY(_tilt.dx * math.pi / 180)
      ..rotateX(_tilt.dy * math.pi / 180);

    final Widget stack = SizedBox(
      width: 310,
      height: 310,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: <Widget>[
          if (_isForeground && style == VisualizerStyle.radial)
            IgnorePointer(
              child: SizedBox(
                width: 340,
                height: 340,
                child: AudioVisualizer(
                  style: VisualizerStyle.radial,
                  accentColor: accent,
                  secondaryColor: c.secondaryColor,
                  isPlaying: c.isPlaying,
                  width: 340,
                  height: 340,
                ),
              ),
            ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            transform: tiltMatrix,
            transformAlignment: Alignment.center,
            child: GestureDetector(
              onTap: _cycleVisualizerNow,
              child: Container(
                key: _cardKey,
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.white(0.2)),
                  boxShadow: <BoxShadow>[
                    BoxShadow(color: glow, blurRadius: 50, spreadRadius: -10, offset: const Offset(0, 20)),
                    BoxShadow(color: glow, blurRadius: 35, spreadRadius: 2),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(23),
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      if (_isForeground)
                        CoverImage(controller: c, track: track)
                      else
                        ColoredBox(color: AppColors.black(0.85)),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: <Color>[
                              Color.fromRGBO(0, 0, 0, 0.6),
                              Color.fromRGBO(0, 0, 0, 0.0),
                              Color.fromRGBO(0, 0, 0, 0.2),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        top: 12,
                        left: 12,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: BackdropFilter(
                            filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.black(0.6),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: AppColors.white(0.1)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  LIcon(LucideIcons.sparkles, size: 10, color: AppColors.cyan400),
                                  const SizedBox(width: 4),
                                  Text(
                                    'VISUALIZER: ${style.name.toUpperCase()}',
                                    style: AppText.mono(9, 400, AppColors.zinc300, lineHeight: 13.5, tabular: true),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_isForeground && style != VisualizerStyle.radial)
            Positioned(
              left: 0,
              right: 0,
              bottom: -28,
              height: 56,
              child: IgnorePointer(
                child: Center(
                  child: AudioVisualizer(
                    style: style,
                    accentColor: accent,
                    secondaryColor: c.secondaryColor,
                    isPlaying: c.isPlaying,
                    width: 280,
                    height: 50,
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    return GestureDetector(
      key: const ValueKey<String>('art-view'),
      behavior: HitTestBehavior.translucent,
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      onPanCancel: _onPanCancel,
      child: Center(
        child: AnimatedContainer(
          duration: _dragging ? Duration.zero : const Duration(milliseconds: 350),
          curve: Curves.easeOutBack,
          transform: Matrix4.translationValues(_dragTotal.dx * 0.4, _dragTotal.dy * 0.4, 0),
          child: FittedBox(fit: BoxFit.scaleDown, child: stack),
        ),
      ),
    );
  }

  Widget _buildLyrics(Track track, Color accent) {
    return Center(
      key: const ValueKey<String>('lyrics-view'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 360),
        child: SizedBox.expand(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.zinc950.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.white(0.1)),
                ),
                child: SyncedLyricsView(
                  lyrics: track.parsedLyrics,
                  position: c.position,
                  accentColor: accent,
                  onSeek: c.seekTo,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _circleButton({
    required double padding,
    required VoidCallback onTap,
    required Widget icon,
    Color? background,
    Color? borderColor,
    List<BoxShadow>? shadows,
    bool bordered = true,
  }) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(padding),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: background,
          border: bordered ? Border.all(color: borderColor ?? AppColors.white(0.1)) : null,
          boxShadow: shadows,
        ),
        child: icon,
      ),
    );
  }

  Widget _buildControls(Track track, Color accent, Color glow) {
    const Color cyanGlow = Color.fromRGBO(0, 240, 255, 0.4);
    final bool fav = track.favorite;

    final Widget lyricsButton = _circleButton(
      padding: 10,
      onTap: () => setState(() => _showLyrics = !_showLyrics),
      background: _showLyrics ? accent.withValues(alpha: 0x25 / 255) : AppColors.white(0.05),
      borderColor: _showLyrics ? accent.withValues(alpha: 0x60 / 255) : AppColors.white(0.1),
      shadows: _showLyrics
          ? const <BoxShadow>[BoxShadow(color: cyanGlow, blurRadius: 12)]
          : null,
      icon: LIcon(LucideIcons.quote, size: 16, color: _showLyrics ? accent : AppColors.zinc400),
    );

    final Widget heartButton = _circleButton(
      padding: 10,
      onTap: () => c.toggleFavorite(track),
      background: AppColors.white(0.05),
      icon: LIcon(
        LucideIcons.heart,
        size: 16,
        color: fav ? AppColors.rose500 : AppColors.zinc400,
        fill: fav ? AppColors.rose500 : null,
      ),
    );

    final Widget titleRow = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.display(20, 700, Colors.white, lineHeight: 28, tracking: -0.025),
                ),
                const SizedBox(height: 2),
                Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body(14, 500, AppColors.zinc400, lineHeight: 20),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          lyricsButton,
          const SizedBox(width: 4),
          heartButton,
        ],
      ),
    );

    final bool shuffleOn = c.isShuffle;
    final bool repeatOn = c.repeatMode != AetherRepeatMode.off;

    final Widget shuffle = _circleButton(
      padding: 10,
      bordered: false,
      onTap: c.toggleShuffle,
      shadows: shuffleOn ? const <BoxShadow>[BoxShadow(color: cyanGlow, blurRadius: 10)] : null,
      icon: LIcon(LucideIcons.shuffle, size: 20, color: shuffleOn ? AppColors.cyan400 : AppColors.zinc500),
    );
    final Widget prev = _circleButton(
      padding: 12,
      bordered: false,
      onTap: c.prev,
      icon: LIcon(LucideIcons.skipBack, size: 24, color: AppColors.zinc300, fill: AppColors.zinc300),
    );
    final Widget next = _circleButton(
      padding: 12,
      bordered: false,
      onTap: c.next,
      icon: LIcon(LucideIcons.skipForward, size: 24, color: AppColors.zinc300, fill: AppColors.zinc300),
    );
    final Widget repeat = _circleButton(
      padding: 10,
      bordered: false,
      onTap: c.toggleRepeat,
      shadows: repeatOn ? const <BoxShadow>[BoxShadow(color: cyanGlow, blurRadius: 10)] : null,
      icon: LIcon(
        c.repeatMode == AetherRepeatMode.one ? LucideIcons.repeat1 : LucideIcons.repeat,
        size: 20,
        color: repeatOn ? AppColors.cyan400 : AppColors.zinc500,
      ),
    );

    final Widget playButton = Pressable(
      scale: 0.95,
      onTap: () {
        c.togglePlayPause();
      },
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: accent,
          shape: BoxShape.circle,
          boxShadow: <BoxShadow>[
            BoxShadow(color: glow, blurRadius: 24, spreadRadius: 4),
            BoxShadow(color: AppColors.black(0.6), blurRadius: 20, offset: const Offset(0, 4)),
          ],
        ),
        child: Center(
          child: c.isPlaying
              ? LIcon(LucideIcons.pause, size: 28, color: Colors.black, fill: Colors.black)
              : Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: LIcon(LucideIcons.play, size: 28, color: Colors.black, fill: Colors.black),
                ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          titleRow,
          const SizedBox(height: 12),
          WaveformSeekbar(
            position: c.position,
            duration: c.duration,
            waveform: track.waveform,
            accentColor: accent,
            onSeek: c.seekTo,
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[shuffle, prev, playButton, next, repeat],
            ),
          ),
        ],
      ),
    );
  }
}
