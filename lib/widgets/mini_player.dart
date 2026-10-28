import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../state/player_controller.dart';
import '../theme/app_theme.dart';
import 'cover_image.dart';

/// Compact transport surface shown on library, EQ, stats and settings routes.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, required this.controller, required this.onOpenPlayer});

  final PlayerController controller;
  final VoidCallback onOpenPlayer;

  @override
  Widget build(BuildContext context) {
    final track = controller.currentTrack;
    if (track == null) return const SizedBox.shrink();
    return Material(
      color: const Color(0xCC111118),
      child: InkWell(
        onTap: onOpenPlayer,
        child: Container(
          height: 68,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: controller.accentColor.withValues(alpha: 0.4))),
            boxShadow: <BoxShadow>[BoxShadow(color: controller.accentColor.withValues(alpha: 0.08), blurRadius: 18)],
          ),
          child: Row(
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: SizedBox(width: 48, height: 48, child: CoverImage(controller: controller, track: track, cacheWidth: 128)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(13, 600, Colors.white)),
                    const SizedBox(height: 2),
                    Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(11, 400, AppColors.zinc400)),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: controller.isPlaying ? 'Pause' : 'Play',
                onPressed: controller.togglePlayPause,
                icon: Icon(controller.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: controller.accentColor, size: 28),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Next track',
                onPressed: controller.next,
                icon: Icon(Icons.skip_next_rounded, color: AppColors.zinc300, size: 26),
              ),
              SizedBox(
                width: 2,
                height: 42,
                child: ValueListenableBuilder<double>(
                  valueListenable: controller.position,
                  builder: (BuildContext context, double pos, Widget? _) {
                    final double ratio = controller.duration <= 0 ? 0 : (pos / controller.duration).clamp(0.0, 1.0).toDouble();
                    return Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: math.max(0.02, ratio).toDouble(),
                        child: DecoratedBox(decoration: BoxDecoration(color: controller.accentColor, borderRadius: BorderRadius.circular(2))),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
