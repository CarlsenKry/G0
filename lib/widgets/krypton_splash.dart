import 'package:flutter/material.dart';

/// Three-second branded opening screen using the artwork provided for Krypton.
class KryptonSplashScreen extends StatefulWidget {
  const KryptonSplashScreen({super.key, this.lightMode = false});

  final bool lightMode;

  @override
  State<KryptonSplashScreen> createState() => _KryptonSplashScreenState();
}

class _KryptonSplashScreenState extends State<KryptonSplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entry;
  late final AnimationController _pulse;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _entry = AnimationController(vsync: this, duration: const Duration(milliseconds: 1250));
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 950))
      ..repeat(reverse: true);
    _opacity = CurvedAnimation(parent: _entry, curve: Curves.easeOutCubic);
    _scale = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _entry, curve: Curves.easeOutBack),
    );
    _entry.forward();
  }

  @override
  void dispose() {
    _entry.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Size screen = MediaQuery.sizeOf(context);
    final double artworkWidth = (screen.width - 30).clamp(240.0, 460.0).toDouble();
    return Scaffold(
      backgroundColor: widget.lightMode ? const Color(0xFFF7F8FC) : const Color(0xFF050608),
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.14),
                radius: 0.9,
                colors: widget.lightMode
                    ? const <Color>[
                        Color(0xFFF7F8FC),
                        Color(0xFFEEF2F7),
                        Color(0xFFE4E8F0),
                      ]
                    : <Color>[
                        const Color(0xFF102026).withValues(alpha: 0.9),
                        const Color(0xFF080A0D),
                        const Color(0xFF020203),
                      ],
                stops: const <double>[0, 0.58, 1],
              ),
            ),
          ),
          Center(
            child: FadeTransition(
              opacity: _opacity,
              child: ScaleTransition(
                scale: _scale,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    AnimatedBuilder(
                      animation: _pulse,
                      builder: (BuildContext context, Widget? child) {
                        final double glow = 0.10 + (_pulse.value * 0.17);
                        return Container(
                          width: artworkWidth,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: const Color(0xFF82F5FF).withValues(alpha: glow),
                                blurRadius: 42 + (_pulse.value * 16),
                                spreadRadius: 1 + (_pulse.value * 3),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(22),
                            child: Image.asset(
                              'assets/images/guy_donn_splash.jpg',
                              width: artworkWidth,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'KRYPTON m.PLAYER',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: widget.lightMode ? const Color(0xFF18181B) : const Color(0xFFEAFDFF),
                        fontFamily: 'SpaceGrotesk',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2.1,
                      ),
                    ),
                    const SizedBox(height: 22),
                    AnimatedBuilder(
                      animation: _pulse,
                      builder: (BuildContext context, Widget? _) {
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List<Widget>.generate(21, (int index) {
                            final double distance = (index - 10).abs().toDouble();
                            final double height = 5 + ((1 - distance / 11) * (10 + _pulse.value * 18));
                            return Container(
                              width: 3,
                              height: height,
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              decoration: BoxDecoration(
                                color: Color.lerp(const Color(0xFF4C8190), const Color(0xFFB8FAFF), 1 - distance / 11),
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: <BoxShadow>[
                                  BoxShadow(
                                    color: const Color(0xFF73EFFF).withValues(alpha: 0.18 + _pulse.value * 0.18),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            );
                          }),
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'PREPARING YOUR MUSIC',
                      style: TextStyle(
                        color: Color(0xFF81939A),
                        fontFamily: 'JetBrainsMono',
                        fontSize: 9,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
