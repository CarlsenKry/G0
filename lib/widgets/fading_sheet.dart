import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../state/player_controller.dart';
import '../theme/app_theme.dart';

/// Settings > Playback > Fading: crossfade length (0-30 s) and related switches.
Future<void> showFadingSheet(BuildContext context, PlayerController controller) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext sheetContext) => ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) {
        final AppSettings s = controller.settings;
        final Color accent = controller.accentColor;
        final int secs = s.crossfadeDuration.clamp(0, 30).toInt();
        return SafeArea(
          top: false,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.panelBackground,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              border: Border(top: BorderSide(color: Color(0x553DDAE8))),
            ),
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(color: AppColors.zinc600, borderRadius: BorderRadius.circular(99)))),
                  const SizedBox(height: 18),
                  Text('FADING', style: AppText.mono(10, 700, accent, tracking: 0.15)),
                  const SizedBox(height: 4),
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: <Widget>[
                    Expanded(child: Text('Fade between songs', style: AppText.display(20, 700, Colors.white, lineHeight: 26))),
                    Text(secs == 0 ? 'OFF' : '$secs s', style: AppText.mono(22, 700, secs == 0 ? AppColors.zinc500 : accent, tabular: true)),
                  ]),
                  const SizedBox(height: 14),
                  Container(
                    height: 118,
                    width: double.infinity,
                    decoration: BoxDecoration(color: AppColors.white(0.03), borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.white(0.08))),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: CustomPaint(painter: _FadeCurvePainter(seconds: secs, accent: accent, other: AppColors.zinc300)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Slider(
                    value: secs.toDouble(),
                    min: 0,
                    max: 30,
                    divisions: 30,
                    label: secs == 0 ? 'Off' : '$secs s',
                    activeColor: accent,
                    inactiveColor: AppColors.white(0.12),
                    onChanged: (double v) => controller.updateSettings(s.copyWith(crossfadeDuration: v.round())),
                  ),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: <Widget>[
                    Text('0 S', style: AppText.mono(8, 600, AppColors.zinc500)),
                    Text('15 S', style: AppText.mono(8, 600, AppColors.zinc500)),
                    Text('30 S', style: AppText.mono(8, 600, AppColors.zinc500)),
                  ]),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 4, children: <Widget>[
                    for (final int preset in const <int>[0, 2, 5, 8, 12, 20, 30])
                      ChoiceChip(
                        label: Text(preset == 0 ? 'OFF' : '$preset S', style: AppText.mono(9, 700, secs == preset ? Colors.black : AppColors.zinc400)),
                        selected: secs == preset,
                        selectedColor: accent,
                        backgroundColor: AppColors.white(0.035),
                        side: BorderSide(color: AppColors.white(0.1)),
                        showCheckmark: false,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => controller.updateSettings(s.copyWith(crossfadeDuration: preset)),
                      ),
                  ]),
                  const SizedBox(height: 8),
                  _switchRow(
                    title: 'Fade on manual skip',
                    subtitle: 'Also fade when you tap Next, Previous or pick a song (at most 5 s)',
                    value: s.fadeOnManualSkip,
                    enabled: secs > 0,
                    accent: accent,
                    onChanged: (bool v) => controller.updateSettings(s.copyWith(fadeOnManualSkip: v)),
                  ),
                  Divider(height: 1, color: AppColors.white(0.07)),
                  _switchRow(
                    title: 'Skip fade within an album',
                    subtitle: 'Songs of the same album play straight through, ideal for live albums and mixes',
                    value: s.albumAwareFading,
                    enabled: secs > 0,
                    accent: accent,
                    onChanged: (bool v) => controller.updateSettings(s.copyWith(albumAwareFading: v)),
                  ),
                  Divider(height: 1, color: AppColors.white(0.07)),
                  _switchRow(
                    title: 'Fade on pause / resume',
                    subtitle: 'Half a second of fade-out when you pause and fade-in when you resume',
                    value: s.fadeOnPause,
                    enabled: true,
                    accent: accent,
                    onChanged: (bool v) => controller.updateSettings(s.copyWith(fadeOnPause: v)),
                  ),
                  Divider(height: 1, color: AppColors.white(0.07)),
                  _switchRow(
                    title: 'Gapless playback',
                    subtitle: 'Pre-loads the next song so it starts the moment the current one ends',
                    value: s.gapless,
                    enabled: true,
                    accent: accent,
                    onChanged: (bool v) => controller.updateSettings(s.copyWith(gapless: v)),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    secs == 0
                        ? 'Fading is off. With gapless playback on, songs follow each other without a pause.'
                        : 'The ending song fades out while the next song fades in at the same time, so the two overlap for $secs seconds. Songs shorter than ${secs * 2} s use a shorter fade.',
                    style: AppText.body(10, 400, AppColors.zinc500, lineHeight: 16),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

Widget _switchRow({
  required String title,
  required String subtitle,
  required bool value,
  required bool enabled,
  required Color accent,
  required ValueChanged<bool> onChanged,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(children: <Widget>[
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(title, style: AppText.body(12, 600, enabled ? Colors.white : AppColors.zinc600)),
          const SizedBox(height: 3),
          Text(subtitle, style: AppText.body(10, 400, AppColors.zinc500, lineHeight: 15)),
        ]),
      ),
      const SizedBox(width: 8),
      Switch(value: value, activeThumbColor: accent, onChanged: enabled ? onChanged : null),
    ]),
  );
}

/// Draws the two volume curves: song A going down, song B coming up, overlapping.
class _FadeCurvePainter extends CustomPainter {
  _FadeCurvePainter({required this.seconds, required this.accent, required this.other});

  final int seconds;
  final Color accent;
  final Color other;

  @override
  void paint(Canvas canvas, Size size) {
    const double padX = 14;
    const double padY = 16;
    final double w = size.width - padX * 2;
    final double top = padY;
    final double bottom = size.height - padY;
    // The overlap grows with the setting; "off" is a hard cut in the middle.
    final double frac = seconds == 0 ? 0.0 : (0.12 + 0.76 * seconds / 30.0);
    final double xs = padX + w * (0.5 - frac / 2);
    final double xe = padX + w * (0.5 + frac / 2);

    final Paint grid = Paint()
      ..color = const Color(0x14FFFFFF)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(padX, top), Offset(padX + w, top), grid);
    canvas.drawLine(Offset(padX, bottom), Offset(padX + w, bottom), grid);

    final Path outgoing = Path()..moveTo(padX, top);
    final Path incoming = Path()..moveTo(padX, bottom);
    if (seconds == 0) {
      final double mid = padX + w / 2;
      outgoing
        ..lineTo(mid, top)
        ..lineTo(mid, bottom)
        ..lineTo(padX + w, bottom);
      incoming
        ..lineTo(mid, bottom)
        ..lineTo(mid, top)
        ..lineTo(padX + w, top);
    } else {
      outgoing.lineTo(xs, top);
      incoming.lineTo(xs, bottom);
      const int steps = 28;
      for (int i = 1; i <= steps; i++) {
        final double t = i / steps;
        final double x = xs + (xe - xs) * t;
        outgoing.lineTo(x, bottom - (bottom - top) * math.cos(t * math.pi / 2));
        incoming.lineTo(x, bottom - (bottom - top) * math.sin(t * math.pi / 2));
      }
      outgoing.lineTo(padX + w, bottom);
      incoming.lineTo(padX + w, top);

      canvas.drawRect(
        Rect.fromLTRB(xs, top, xe, bottom),
        Paint()..color = accent.withValues(alpha: 0.07),
      );
    }

    canvas.drawPath(
      outgoing,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round
        ..color = other.withValues(alpha: 0.75),
    );
    canvas.drawPath(
      incoming,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round
        ..color = accent,
    );

    _label(canvas, 'SONG A', Offset(padX + 2, size.height - 13), other.withValues(alpha: 0.75));
    _label(canvas, 'SONG B', Offset(padX + w - 44, size.height - 13), accent);
  }

  void _label(Canvas canvas, String text, Offset at, Color color) {
    final TextPainter tp = TextPainter(
      text: TextSpan(text: text, style: AppText.mono(8, 700, color)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_FadeCurvePainter old) => old.seconds != seconds || old.accent != accent;
}
