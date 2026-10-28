import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/storage.dart';
import '../state/player_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/cover_image.dart';

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key, required this.controller, required this.onBack});

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
          final int totalMs = Storage.totalListenMs;
          final Map<String, int> byTrack = Storage.loadTrackListenMs();
          final Map<String, int> byDay = Storage.loadDailyListenMs();
          final List<MapEntry<String, int>> ranked = byTrack.entries.toList()..sort((MapEntry<String, int> a, MapEntry<String, int> b) => b.value.compareTo(a.value));
          final DateTime today = DateTime.now();
          final List<MapEntry<String, int>> lastSeven = List<MapEntry<String, int>>.generate(7, (int i) {
            final DateTime day = DateTime(today.year, today.month, today.day).subtract(Duration(days: 6 - i));
            final String key = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
            return MapEntry<String, int>(key, byDay[key] ?? 0);
          });
          final int maxDay = lastSeven.fold<int>(0, (int maxValue, MapEntry<String, int> e) => e.value > maxValue ? e.value : maxValue);
          final Map<String, Track> tracksById = <String, Track>{for (final Track t in controller.tracks) t.id: t};
          final Color accent = controller.accentColor;
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
            children: <Widget>[
              Row(children: <Widget>[
                IconButton(onPressed: onBack, icon: Icon(Icons.arrow_back_rounded, color: AppColors.zinc300)),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text('REAL PLAYBACK DATA', style: AppText.mono(9, 700, accent, tracking: 0.15)),
                  Text('Listening stats', style: AppText.display(24, 700, Colors.white, lineHeight: 30)),
                ])),
              ]),
              const SizedBox(height: 14),
              Row(children: <Widget>[
                Expanded(child: _metric('TOTAL LISTENED', _formatMs(totalMs), Icons.headphones_rounded, accent)),
                const SizedBox(width: 10),
                Expanded(child: _metric('TRACKS PLAYED', '${controller.tracks.where((Track t) => t.playCount > 0).length}', Icons.audiotrack_rounded, AppColors.violet)),
              ]),
              const SizedBox(height: 10),
              Row(children: <Widget>[
                Expanded(child: _metric('FAVORITES', '${controller.tracks.where((Track t) => t.favorite).length}', Icons.favorite_rounded, AppColors.magenta)),
                const SizedBox(width: 10),
                Expanded(child: _metric('LIBRARY SIZE', '${controller.tracks.length}', Icons.library_music_rounded, AppColors.cyan)),
              ]),
              const SizedBox(height: 16),
              _panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text('LAST 7 DAYS', style: AppText.mono(10, 700, AppColors.zinc300, tracking: 0.1)),
                  const SizedBox(height: 5),
                  Text('Listening time recorded by Krypton m.Player', style: AppText.body(11, 400, AppColors.zinc500)),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 118,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        for (final MapEntry<String, int> entry in lastSeven)
                          Expanded(child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Column(mainAxisAlignment: MainAxisAlignment.end, children: <Widget>[
                              Text(entry.value > 0 ? _compactMs(entry.value) : '—', style: AppText.mono(8, 500, AppColors.zinc600, tabular: true)),
                              const SizedBox(height: 5),
                              Expanded(child: LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
                                final double ratio = maxDay <= 0 ? 0 : entry.value / maxDay;
                                final double height = constraints.maxHeight * ratio;
                                return Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Container(
                                    height: height.clamp(entry.value > 0 ? 4.0 : 0.0, constraints.maxHeight).toDouble(),
                                    decoration: BoxDecoration(
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                                      gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: <Color>[accent.withValues(alpha: 0.4), accent]),
                                      boxShadow: entry.value > 0 ? <BoxShadow>[BoxShadow(color: accent.withValues(alpha: 0.15), blurRadius: 8)] : null,
                                    ),
                                  ),
                                );
                              })),
                              const SizedBox(height: 6),
                              Text(entry.key.substring(5).replaceAll('-', '/'), style: AppText.mono(8, 400, AppColors.zinc600, tabular: true)),
                            ]),
                          )),
                      ],
                    ),
                  ),
                  if (totalMs == 0) Padding(padding: const EdgeInsets.only(top: 12), child: Text('No listening time has been recorded yet. Start playback to build your history.', style: AppText.body(11, 400, AppColors.zinc600, lineHeight: 16))),
                ]),
              ),
              const SizedBox(height: 14),
              _panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text('MOST LISTENED', style: AppText.mono(10, 700, AppColors.zinc300, tracking: 0.1)),
                  const SizedBox(height: 10),
                  if (ranked.isEmpty)
                    Text('Per-track listening data will appear here after audio has played.', style: AppText.body(11, 400, AppColors.zinc600, lineHeight: 16))
                  else
                    for (final MapEntry<String, int> entry in ranked.take(5))
                      if (tracksById[entry.key] != null)
                        _topTrack(tracksById[entry.key]!, entry.value, accent),
                ]),
              ),
              const SizedBox(height: 14),
              _panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text('DATA SOURCE', style: AppText.mono(10, 700, AppColors.zinc300, tracking: 0.1)),
                  const SizedBox(height: 7),
                  Text('These values are read from locally persisted playback events and library metadata. A fresh install starts at zero; Krypton m.Player does not invent historical listens.', style: AppText.body(10, 400, AppColors.zinc500, lineHeight: 16)),
                ]),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _metric(String label, String value, IconData icon, Color color) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(color: AppColors.panelBackground, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.white(0.08))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Icon(icon, color: color, size: 18),
      const SizedBox(height: 10),
      Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.display(20, 700, Colors.white, lineHeight: 24)),
      const SizedBox(height: 2),
      Text(label, style: AppText.mono(8, 600, AppColors.zinc500, tracking: 0.04)),
    ]),
  );

  Widget _topTrack(Track track, int ms, Color accent) => Padding(
    padding: const EdgeInsets.only(bottom: 11),
    child: Row(children: <Widget>[
      ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 42, height: 42, child: CoverImage(controller: controller, track: track, cacheWidth: 112))),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(12, 600, Colors.white)),
        Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(10, 400, AppColors.zinc500)),
      ])),
      const SizedBox(width: 8),
      Text(_formatMs(ms), style: AppText.mono(9, 600, accent, tabular: true)),
    ]),
  );
}

Widget _panel({required Widget child}) => Container(
  padding: const EdgeInsets.all(15),
  decoration: BoxDecoration(color: AppColors.panelBackground, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.white(0.08))),
  child: child,
);

String _formatMs(int value) {
  final int minutes = (value / 60000).floor();
  final int hours = minutes ~/ 60;
  final int remMinutes = minutes % 60;
  if (hours > 0) return '${hours}h ${remMinutes}m';
  return '${minutes}m';
}

String _compactMs(int value) {
  final int minutes = value ~/ 60000;
  if (minutes < 60) return '${minutes}m';
  return '${minutes ~/ 60}h';
}
