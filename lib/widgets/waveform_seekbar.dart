import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/audio_math.dart';

class WaveformSeekbar extends StatefulWidget {
  const WaveformSeekbar({
    super.key,
    required this.position,
    required this.duration,
    required this.waveform,
    required this.accentColor,
    required this.onSeek,
  });

  final ValueListenable<double> position;
  final double duration;
  final List<double> waveform;
  final Color accentColor;
  final ValueChanged<double> onSeek;

  @override
  State<WaveformSeekbar> createState() => _WaveformSeekbarState();
}

class _WaveformSeekbarState extends State<WaveformSeekbar> {
  bool _dragging = false;
  double? _dragSeconds;

  double _timeFromDx(double dx, double width) {
    if (widget.duration <= 0 || width <= 0) return 0;
    final double x = math.max(0.0, math.min(width, dx));
    return (x / width) * widget.duration;
  }

  @override
  Widget build(BuildContext context) {
    final List<double> bars = widget.waveform.isNotEmpty
        ? widget.waveform
        : List<double>.generate(
            50,
            (int i) => 0.2 + 0.6 * math.sin((i / 50) * math.pi * 3).abs(),
          );
    final Color accent = widget.accentColor;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        return ValueListenableBuilder<double>(
          valueListenable: widget.position,
          builder: (BuildContext context, double pos, Widget? _) {
            final double shown = _dragSeconds ?? pos;
            final double progress =
                widget.duration > 0 ? clampDouble(shown / widget.duration, 0, 1) : 0;
            final double remaining = math.max(0, widget.duration - shown);

            return SizedBox(
              height: 60,
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  // Interactive bar container (h-12)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: 48,
                    child: Listener(
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (PointerDownEvent e) {
                        setState(() {
                          _dragging = true;
                          _dragSeconds = _timeFromDx(e.localPosition.dx, width);
                        });
                      },
                      onPointerMove: (PointerMoveEvent e) {
                        if (_dragging) {
                          setState(() {
                            _dragSeconds = _timeFromDx(e.localPosition.dx, width);
                          });
                        }
                      },
                      onPointerUp: (PointerUpEvent e) {
                        if (_dragging) {
                          final double finalTime = _timeFromDx(e.localPosition.dx, width);
                          widget.onSeek(finalTime);
                          setState(() {
                            _dragging = false;
                            _dragSeconds = null;
                          });
                        }
                      },
                      onPointerCancel: (PointerCancelEvent e) {
                        if (_dragging) {
                          setState(() {
                            _dragging = false;
                            _dragSeconds = null;
                          });
                        }
                      },
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: <Widget>[
                          Positioned(
                            left: 0,
                            right: 0,
                            top: 8,
                            height: 32,
                            child: CustomPaint(
                              painter: _BarsPainter(bars: bars, progress: progress, accent: accent),
                            ),
                          ),
                          // Glowing draggable thumb
                          Positioned(
                            left: progress * width - 8,
                            top: 16,
                            child: AnimatedScale(
                              scale: _dragging ? 1.35 : 1.0,
                              duration: const Duration(milliseconds: 150),
                              child: Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: <BoxShadow>[
                                    BoxShadow(color: accent, blurRadius: 14, spreadRadius: 2),
                                    BoxShadow(
                                      color: accent.withValues(alpha: 0.4),
                                      blurRadius: 28,
                                      spreadRadius: 4,
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // Scrub time tooltip
                          if (_dragging)
                            Positioned(
                              left: progress * width,
                              top: -28,
                              child: FractionalTranslation(
                                translation: const Offset(-0.5, 0),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.zinc900,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: AppColors.white(0.2)),
                                    boxShadow: <BoxShadow>[
                                      BoxShadow(
                                        color: AppColors.black(0.5),
                                        blurRadius: 16,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    formatTime(_dragSeconds ?? 0),
                                    style: AppText.mono(10, 400, Colors.white, tabular: true),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  // Time readout (-mt-1, px-1)
                  Positioned(
                    left: 4,
                    right: 4,
                    top: 44,
                    height: 16,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text(
                          formatTime(shown),
                          style: AppText.mono(12, 500, AppColors.zinc300, lineHeight: 16, tabular: true),
                        ),
                        Text(
                          '-${formatTime(remaining)}',
                          style: AppText.mono(12, 400, AppColors.zinc500, lineHeight: 16, tabular: true),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({required this.bars, required this.progress, required this.accent});

  final List<double> bars;
  final double progress;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final int n = bars.length;
    if (n == 0) return;
    const double gap = 2;
    final double bw = (size.width - gap * (n - 1)) / n;
    final Paint playedPaint = Paint()..color = accent;
    final Paint idlePaint = Paint()..color = const Color.fromRGBO(255, 255, 255, 0.16);
    final Paint glowPaint = Paint()
      ..color = accent.withValues(alpha: 0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    for (int i = 0; i < n; i++) {
      final double pct = math.max(12.0, bars[i] * 100) / 100;
      final double h = pct * size.height;
      final double x = i * (bw + gap);
      final double y = (size.height - h) / 2;
      final double radius = math.min(bw, h) / 2;
      final RRect r = RRect.fromRectAndRadius(Rect.fromLTWH(x, y, bw, h), Radius.circular(radius));
      final bool played = (i / n) <= progress;
      if (played) {
        canvas.drawRRect(r, glowPaint);
        canvas.drawRRect(r, playedPaint);
      } else {
        canvas.drawRRect(r, idlePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BarsPainter old) {
    return old.progress != progress || old.accent != accent || !identical(old.bars, bars);
  }
}
