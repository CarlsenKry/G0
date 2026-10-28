import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/lucide.dart';
import '../utils/lrc_parser.dart';

class SyncedLyricsView extends StatefulWidget {
  const SyncedLyricsView({
    super.key,
    required this.lyrics,
    required this.position,
    required this.accentColor,
    required this.onSeek,
  });

  final List<LyricLine>? lyrics;
  final ValueListenable<double> position;
  final Color accentColor;
  final ValueChanged<double> onSeek;

  @override
  State<SyncedLyricsView> createState() => _SyncedLyricsViewState();
}

class _SyncedLyricsViewState extends State<SyncedLyricsView> with SingleTickerProviderStateMixin {
  List<GlobalKey> _keys = <GlobalKey>[];
  int _lastActive = -2;
  late final AnimationController _pulse;
  late final Animation<double> _pulseCurve;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
    _pulseCurve = CurvedAnimation(parent: _pulse, curve: const Cubic(0.4, 0, 0.6, 1));
    _rebuildKeys();
  }

  @override
  void didUpdateWidget(covariant SyncedLyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.lyrics, widget.lyrics)) {
      _rebuildKeys();
      _lastActive = -2;
    }
  }

  void _rebuildKeys() {
    final int n = widget.lyrics?.length ?? 0;
    _keys = List<GlobalKey>.generate(n, (int i) => GlobalKey());
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _scrollTo(int index) {
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted || index < 0 || index >= _keys.length) return;
      final BuildContext? ctx = _keys[index].currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.5,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<LyricLine> lyrics = widget.lyrics ?? <LyricLine>[];
    if (lyrics.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Opacity(
                opacity: 0.3,
                child: LIcon(LucideIcons.sparkles, size: 40, color: AppColors.cyan400),
              ),
              const SizedBox(height: 12),
              Text(
                'TELEMETRY DATA UNAVAILABLE',
                textAlign: TextAlign.center,
                style: AppText.display(14, 400, AppColors.zinc400, lineHeight: 20, tracking: 0.05),
              ),
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text(
                  'No synchronized LRC stream encoded for this track.',
                  textAlign: TextAlign.center,
                  style: AppText.body(12, 400, AppColors.zinc600, lineHeight: 16),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final Color accent = widget.accentColor;
    return ValueListenableBuilder<double>(
      valueListenable: widget.position,
      builder: (BuildContext context, double pos, Widget? _) {
        final int active = findActiveLyricIndex(lyrics, pos);
        if (active != _lastActive) {
          _lastActive = active;
          _scrollTo(active);
        }
        final List<Widget> children = <Widget>[const SizedBox(height: 40)];
        for (int idx = 0; idx < lyrics.length; idx++) {
          final bool isActive = idx == active;
          final bool isPast = idx < active;
          final LyricLine line = lyrics[idx];
          children.add(
            GestureDetector(
              key: _keys[idx],
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.onSeek(line.time),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: isActive ? 1.0 : (isPast ? 0.4 : 0.25),
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 300),
                  scale: isActive ? 1.05 : 0.95,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        line.text.isEmpty ? '♪ ♪ ♪' : line.text,
                        textAlign: TextAlign.center,
                        style: AppText.display(
                          18,
                          isActive ? 700 : (isPast ? 500 : 400),
                          isActive ? Colors.white : AppColors.zinc400,
                          lineHeight: 29.25,
                          shadows: isActive
                              ? <Shadow>[
                                  Shadow(color: accent, blurRadius: 16),
                                  Shadow(color: accent.withValues(alpha: 0.5), blurRadius: 32),
                                ]
                              : null,
                        ),
                      ),
                      if (isActive)
                        AnimatedBuilder(
                          animation: _pulseCurve,
                          builder: (BuildContext context, Widget? child) {
                            return Opacity(opacity: 1.0 - 0.5 * _pulseCurve.value, child: child);
                          },
                          child: Container(
                            margin: const EdgeInsets.only(top: 8),
                            width: 32,
                            height: 4,
                            decoration: BoxDecoration(
                              color: accent,
                              borderRadius: BorderRadius.circular(2),
                              boxShadow: <BoxShadow>[BoxShadow(color: accent, blurRadius: 8)],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
          if (idx != lyrics.length - 1) {
            children.add(const SizedBox(height: 28));
          }
        }
        children.add(const SizedBox(height: 64));
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
          child: Column(children: children),
        );
      },
    );
  }
}
