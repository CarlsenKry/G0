import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../models/app_settings.dart';

/// Canvas port of AudioVisualizer.tsx (radial / waveform / bars).
class AudioVisualizer extends StatefulWidget {
  const AudioVisualizer({
    super.key,
    required this.style,
    required this.accentColor,
    required this.secondaryColor,
    required this.isPlaying,
    required this.width,
    required this.height,
  });

  final VisualizerStyle style;
  final Color accentColor;
  final Color secondaryColor;
  final bool isPlaying;
  final double width;
  final double height;

  @override
  State<AudioVisualizer> createState() => _AudioVisualizerState();
}

class _AudioVisualizerState extends State<AudioVisualizer> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  Duration _elapsed = Duration.zero;
  Duration _lastPaint = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((Duration d) {
      _elapsed = d;
      // 30 fps is enough for these procedural shapes and roughly halves UI work.
      if (d - _lastPaint >= const Duration(milliseconds: 33)) {
        _lastPaint = d;
        _frame.value = _frame.value + 1;
      }
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size(widget.width, widget.height),
        painter: _VisualizerPainter(
          repaint: _frame,
          owner: this,
        ),
      ),
    );
  }
}

class _VisualizerPainter extends CustomPainter {
  _VisualizerPainter({required Listenable repaint, required this.owner}) : super(repaint: repaint);

  final _AudioVisualizerState owner;

  final Uint8List _idleFreq = Uint8List(128);
  final Uint8List _idleWave = Uint8List(128);

  @override
  void paint(Canvas canvas, Size size) {
    final AudioVisualizer w = owner.widget;
    // Procedural-only animation: no microphone or output-audio capture is used.
    // Two blended oscillators create varied movement without allocating frames.
    final double elapsed = owner._elapsed.inMicroseconds / 1000000.0;
    final double energy = w.isPlaying ? 1.0 : 0.42;
    for (int i = 0; i < 128; i++) {
      final double phase = i * 0.15;
      final double a = math.sin(elapsed * 1.8 + phase);
      final double b = math.sin(elapsed * 0.73 - phase * 1.7);
      _idleFreq[i] = _toByte(22 + energy * (math.max(0.0, a * 0.65 + b * 0.35) * 130));
      _idleWave[i] = _toByte(128 + energy * (math.sin(elapsed * 2.1 + i * 0.11) * 32 + math.sin(elapsed * 0.9 + i * 0.035) * 12));
    }
    final Uint8List freq = _idleFreq;
    final Uint8List wave = _idleWave;

    switch (w.style) {
      case VisualizerStyle.radial:
        _radial(canvas, size, freq, w.accentColor, w.secondaryColor, w.isPlaying);
        break;
      case VisualizerStyle.waveform:
        _waveform(canvas, size, wave, w.accentColor, w.secondaryColor);
        break;
      case VisualizerStyle.bars:
        _bars(canvas, size, freq, w.accentColor, w.secondaryColor);
        break;
    }
  }

  static int _toByte(double v) {
    final int r = v.round();
    if (r < 0) return 0;
    if (r > 255) return 255;
    return r;
  }

  void _radial(Canvas canvas, Size size, Uint8List data, Color accent, Color secondary, bool isPlaying) {
    final double width = size.width;
    final double cx = width / 2;
    final double cy = size.height / 2;
    final double innerRadius = width * 0.38;
    const int barCount = 48;
    const double angleStep = math.pi * 2 / barCount;

    final Paint ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = accent.withValues(alpha: 0.4);
    canvas.drawCircle(Offset(cx, cy), innerRadius - 2, ring);

    for (int i = 0; i < barCount; i++) {
      final double angle = i * angleStep - math.pi / 2;
      final int dataIndex = ((i / barCount) * (data.length * 0.65)).floor();
      final double rawVal = dataIndex < data.length ? data[dataIndex].toDouble() : 0;
      final double value = rawVal / 255;
      final double barLength = math.max(4.0, value * (width * 0.14) + (isPlaying ? 4 : 2));
      final double alpha = 0.35 + value * 0.65;

      final Offset p1 = Offset(cx + math.cos(angle) * innerRadius, cy + math.sin(angle) * innerRadius);
      final Offset p2 = Offset(
        cx + math.cos(angle) * (innerRadius + barLength),
        cy + math.sin(angle) * (innerRadius + barLength),
      );

      // A per-spoke radial shader is visually redundant and expensive to allocate
      // 48 times per frame. Interpolate the two accent colours directly instead.
      final Paint p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = Color.lerp(accent, secondary, i / (barCount - 1))!
            .withValues(alpha: alpha);
      canvas.drawLine(p1, p2, p);
    }
  }

  void _waveform(Canvas canvas, Size size, Uint8List data, Color accent, Color secondary) {
    final double width = size.width;
    final double height = size.height;
    final double centerY = height / 2;
    final double sliceWidth = width / (data.length * 0.8);
    final double limit = data.length * 0.8;

    final Path main = Path();
    final Path mirror = Path();
    double x = 0;
    for (int i = 0; i < limit; i++) {
      final double v = data[i] / 128.0;
      final double y1 = centerY + (v - 1) * (height * 0.42);
      final double y2 = centerY - (v - 1) * (height * 0.22);
      if (i == 0) {
        main.moveTo(x, y1);
        mirror.moveTo(x, y2);
      } else {
        main.lineTo(x, y1);
        mirror.lineTo(x, y2);
      }
      x += sliceWidth;
    }

    // canvas shadowBlur 12 == gaussian sigma 6
    final Paint glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = accent
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawPath(main, glow);

    final Paint line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(width, 0),
        <Color>[accent, secondary, accent],
        <double>[0.0, 0.5, 1.0],
      );
    canvas.drawPath(main, line);

    final Paint mirrorGlow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = accent.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawPath(mirror, mirrorGlow);
    final Paint mirrorLine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = secondary.withValues(alpha: 0.3);
    canvas.drawPath(mirror, mirrorLine);
  }

  void _bars(Canvas canvas, Size size, Uint8List data, Color accent, Color secondary) {
    final double width = size.width;
    final double height = size.height;
    const int barCount = 32;
    final double barWidth = (width / barCount) * 0.68;
    final double gap = (width / barCount) * 0.32;

    final ui.Shader shader = ui.Gradient.linear(
      Offset(0, height),
      const Offset(0, 0),
      <Color>[accent, secondary],
    );

    final Paint barPaint = Paint()..shader = shader;
    final Paint capPaint = Paint()..color = const Color.fromRGBO(255, 255, 255, 0.9);
    for (int i = 0; i < barCount; i++) {
      final int dataIndex = ((i / barCount) * (data.length * 0.6)).floor();
      final double value = (dataIndex < data.length ? data[dataIndex] : 0) / 255;
      final double barHeight = math.max(4.0, value * (height * 0.85));
      final double x = i * (barWidth + gap) + gap / 2;
      final double y = height - barHeight;

      // Draw directly instead of allocating a GPU saveLayer for every bar.
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(x, y, barWidth, barHeight),
          topLeft: const Radius.circular(4),
          topRight: const Radius.circular(4),
        ),
        barPaint,
      );

      canvas.drawRect(Rect.fromLTWH(x, math.max(0.0, y - 4), barWidth, 2), capPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _VisualizerPainter oldDelegate) => true;
}
