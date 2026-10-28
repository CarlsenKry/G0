import 'package:flutter/material.dart';

import '../state/player_controller.dart';
import '../theme/app_theme.dart';

const List<String> _eqLabels = <String>['31', '62', '125', '250', '500', '1k', '2k', '4k', '8k', '16k'];

class EqualizerScreen extends StatelessWidget {
  const EqualizerScreen({super.key, required this.controller, required this.onBack});

  final PlayerController controller;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: true,
      bottom: false,
      child: ListenableBuilder(
        listenable: controller,
        builder: (BuildContext context, Widget? _) {
          final settings = controller.settings;
          final Color accent = controller.accentColor;
          final List<double> bands = List<double>.generate(10, (int i) => i < settings.eqBandsDb.length ? settings.eqBandsDb[i] : 0);
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
            children: <Widget>[
              Row(children: <Widget>[
                IconButton(onPressed: onBack, icon: Icon(Icons.arrow_back_rounded, color: AppColors.zinc300)),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text('SIGNAL PROCESSING', style: AppText.mono(9, 700, accent, tracking: 0.15)),
                  Text('EQ Lab', style: AppText.display(26, 700, Colors.white, lineHeight: 31)),
                ])),
                Switch(value: settings.eqEnabled, activeThumbColor: accent, onChanged: controller.setEqualizerEnabled),
              ]),
              const SizedBox(height: 12),
              _panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Row(children: <Widget>[
                    Expanded(child: Text('10-BAND EQUALIZER', style: AppText.mono(10, 700, AppColors.zinc300, tracking: 0.09))),
                    Text(settings.eqEnabled ? 'ACTIVE' : 'BYPASSED', style: AppText.mono(9, 700, settings.eqEnabled ? accent : AppColors.zinc600)),
                  ]),
                  const SizedBox(height: 4),
                  Text('±12 dB per band', style: AppText.body(11, 400, AppColors.zinc500)),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 230,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: List<Widget>.generate(10, (int index) {
                          return SizedBox(
                            width: 46,
                            child: Column(children: <Widget>[
                              Text('${bands[index].toStringAsFixed(0)}', style: AppText.mono(9, 600, bands[index] == 0 ? AppColors.zinc500 : accent, tabular: true)),
                              const SizedBox(height: 4),
                              Expanded(
                                child: Center(
                                  child: RotatedBox(
                                    quarterTurns: 3,
                                    child: SizedBox(
                                      width: 174,
                                      height: 28,
                                      child: SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          trackHeight: 2,
                                          activeTrackColor: accent,
                                          inactiveTrackColor: AppColors.zinc800,
                                          thumbColor: accent,
                                          overlayColor: accent.withValues(alpha: 0.12),
                                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                                        ),
                                        child: Slider(
                                          min: -12,
                                          max: 12,
                                          divisions: 24,
                                          value: bands[index].clamp(-12.0, 12.0).toDouble(),
                                          onChanged: settings.eqEnabled ? (double value) => controller.setEqualizerBand(index, value) : null,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(_eqLabels[index], style: AppText.mono(9, 500, AppColors.zinc400, tabular: true)),
                            ]),
                          );
                        }),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(children: <Widget>[
                    Expanded(child: Text('−12 dB', style: AppText.mono(9, 400, AppColors.zinc600))),
                    Expanded(child: Text('0 dB', textAlign: TextAlign.center, style: AppText.mono(9, 400, AppColors.zinc600))),
                    Expanded(child: Text('+12 dB', textAlign: TextAlign.end, style: AppText.mono(9, 400, AppColors.zinc600))),
                  ]),
                ]),
              ),
              const SizedBox(height: 14),
              _panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text('PREAMP', style: AppText.mono(10, 700, AppColors.zinc300, tracking: 0.09)),
                  Row(children: <Widget>[
                    Expanded(child: Slider(min: -12, max: 12, divisions: 48, activeColor: accent, inactiveColor: AppColors.zinc800, value: settings.preampDb.clamp(-12.0, 12.0).toDouble(), onChanged: settings.eqEnabled ? controller.setPreamp : null)),
                    SizedBox(width: 54, child: Text('${settings.preampDb >= 0 ? '+' : ''}${settings.preampDb.toStringAsFixed(1)} dB', textAlign: TextAlign.end, style: AppText.mono(10, 600, accent, tabular: true))),
                  ]),
                  const SizedBox(height: 8),
                  Text('BASS BOOST', style: AppText.mono(10, 700, AppColors.zinc300, tracking: 0.09)),
                  Row(children: <Widget>[
                    Expanded(child: Slider(min: 0, max: 100, divisions: 20, activeColor: accent, inactiveColor: AppColors.zinc800, value: settings.bassBoost.toDouble(), onChanged: settings.eqEnabled ? (double v) => controller.setBassBoost(v.round()) : null)),
                    SizedBox(width: 54, child: Text('${settings.bassBoost}%', textAlign: TextAlign.end, style: AppText.mono(10, 600, accent, tabular: true))),
                  ]),
                ]),
              ),
              const SizedBox(height: 14),
              _panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text('PRESETS', style: AppText.mono(10, 700, AppColors.zinc300, tracking: 0.09)),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
                    for (final String preset in <String>['Flat', 'Bass', 'Vocal', 'Rock', 'Treble'])
                      OutlinedButton(
                        onPressed: () => controller.applyEqualizerPreset(preset),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: preset == 'Flat' && bands.every((double v) => v == 0) ? Colors.black : AppColors.zinc300,
                          backgroundColor: preset == 'Flat' && bands.every((double v) => v == 0) ? accent : AppColors.white(0.025),
                          side: BorderSide(color: AppColors.white(0.12)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(preset.toUpperCase(), style: AppText.mono(9, 700, preset == 'Flat' && bands.every((double v) => v == 0) ? Colors.black : AppColors.zinc300)),
                      ),
                  ]),
                ]),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.white(0.025), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.white(0.07))),
                child: Text(
                  'Android audio effects are device-dependent. The ten controls are mapped to the nearest native Equalizer bands (many devices expose five, not ten). Preamp uses LoudnessEnhancer and bass boost uses BassBoost where supported; unsupported effects safely fall back without stopping playback.',
                  style: AppText.body(10, 400, AppColors.zinc500, lineHeight: 16),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

Widget _panel({required Widget child}) => Container(
  padding: const EdgeInsets.all(15),
  decoration: BoxDecoration(
    color: AppColors.panelBackground,
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: AppColors.white(0.09)),
    boxShadow: <BoxShadow>[BoxShadow(color: AppColors.cyan.withValues(alpha: 0.035), blurRadius: 24, spreadRadius: 1)],
  ),
  child: child,
);
