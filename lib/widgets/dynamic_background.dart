import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';


/// Port of DynamicBackground.tsx: blurred cover mesh, three neon orbs, vignette,
/// scanlines and HUD grid.
class DynamicBackground extends StatefulWidget {
  const DynamicBackground({super.key, required this.coverPath, required this.accentColor, this.theme = 'amoled', this.lightMode = false});

  final String? coverPath;
  final Color accentColor;
  final String theme;
  final bool lightMode;

  @override
  State<DynamicBackground> createState() => _DynamicBackgroundState();
}

class _DynamicBackgroundState extends State<DynamicBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _pulseCurve;

  @override
  void initState() {
    super.initState();
    // animate-pulse: 2s cubic-bezier(0.4, 0, 0.6, 1) infinite, opacity 1 -> .5 -> 1
    _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
    _pulseCurve = CurvedAnimation(parent: _pulse, curve: const Cubic(0.4, 0, 0.6, 1));
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  static List<double> _satBrightnessMatrix(double s, double b) {
    const double lr = 0.2126;
    const double lg = 0.7152;
    const double lb = 0.0722;
    return <double>[
      (lr + (1 - lr) * s) * b, (lg - lg * s) * b, (lb - lb * s) * b, 0, 0,
      (lr - lr * s) * b, (lg + (1 - lg) * s) * b, (lb - lb * s) * b, 0, 0,
      (lr - lr * s) * b, (lg - lg * s) * b, (lb + (1 - lb) * s) * b, 0, 0,
      0, 0, 0, 1, 0,
    ];
  }

  Widget _orb(Color color, double size, double opacity) {
    // radial-gradient(circle, color 0%, transparent 70%) on a square: farthest-corner radius.
    return Opacity(
      opacity: opacity,
      child: ClipOval(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              radius: 0.495,
              colors: <Color>[color, color.withValues(alpha: 0)],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    final String? cover = widget.coverPath;
    final List<Color> ambientColors = switch (widget.theme) {
      'aurora' => <Color>[const Color(0xFF00FF9D), const Color(0xFF00A8FF), const Color(0xFF7E57C2)],
      'holo' => <Color>[const Color(0xFF8A2BE2), const Color(0xFF00F0FF), const Color(0xFFED6AFF)],
      'cyberpunk' => <Color>[const Color(0xFF00F0FF), const Color(0xFF8A2BE2), const Color(0xFFFF2E93)],
      _ => <Color>[widget.accentColor, const Color(0xFF8A2BE2), const Color(0xFFFF2E93)],
    };
    return IgnorePointer(
      child: RepaintBoundary(
        child: ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              ColoredBox(color: widget.lightMode ? const Color(0xFFF7F8FC) : Colors.black),
              if (cover != null)
                AnimatedBuilder(
                  animation: _pulseCurve,
                  builder: (BuildContext context, Widget? child) {
                    return Opacity(opacity: 1.0 - 0.5 * _pulseCurve.value, child: child);
                  },
                  child: Transform.scale(
                    scale: 1.35,
                    child: ColorFiltered(
                      colorFilter: ColorFilter.matrix(_satBrightnessMatrix(1.8, 0.35)),
                      child: ImageFiltered(
                        imageFilter: ui.ImageFilter.blur(sigmaX: 70, sigmaY: 70),
                        child: Image.file(
                          File(cover),
                          fit: BoxFit.cover,
                          width: size.width,
                          height: size.height,
                          cacheWidth: 256,
                          gaplessPlayback: true,
                          errorBuilder: (BuildContext c, Object e, StackTrace? s) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                ),
              ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 64, sigmaY: 64),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Positioned(left: -96, top: -96, child: _orb(ambientColors[0], 384, widget.theme == 'amoled' ? 0.16 : 0.25)),
                    Positioned(right: -128, top: size.height / 2, child: _orb(ambientColors[1], 384, 0.20)),
                    Positioned(left: size.width / 3, bottom: -96, child: _orb(ambientColors[2], 320, 0.15)),
                  ],
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: widget.lightMode
                        ? const <Color>[
                            Color.fromRGBO(247, 248, 252, 0.64),
                            Color.fromRGBO(247, 248, 252, 0.48),
                            Color.fromRGBO(247, 248, 252, 0.82),
                          ]
                        : const <Color>[
                            Color.fromRGBO(0, 0, 0, 0.6),
                            Color.fromRGBO(0, 0, 0, 0.4),
                            Color.fromRGBO(0, 0, 0, 0.9),
                          ],
                  ),
                ),
              ),
              Opacity(opacity: 0.3, child: CustomPaint(painter: _ScanlinePainter())),
              Opacity(opacity: 0.2, child: CustomPaint(painter: _GridPainter())),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint dark = Paint()..color = const Color.fromRGBO(0, 0, 0, 0.25);
    for (double y = 1.5; y < size.height; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1.5), dark);
    }
    final Paint rgb = Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        const Offset(6, 0),
        const <Color>[
          Color.fromRGBO(255, 0, 0, 0.03),
          Color.fromRGBO(0, 255, 0, 0.01),
          Color.fromRGBO(0, 0, 255, 0.03),
        ],
        const <double>[0.0, 0.5, 1.0],
        TileMode.repeated,
      );
    canvas.drawRect(Offset.zero & size, rgb);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint line = Paint()
      ..color = const Color.fromRGBO(255, 255, 255, 0.03)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 24) {
      canvas.drawLine(Offset(x + 0.5, 0), Offset(x + 0.5, size.height), line);
    }
    for (double y = 0; y < size.height; y += 24) {
      canvas.drawLine(Offset(0, y + 0.5), Offset(size.width, y + 0.5), line);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
