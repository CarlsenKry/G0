import 'package:flutter/material.dart';

import '../models/track.dart';
import '../state/player_controller.dart';
import '../theme/app_theme.dart';
import 'cover_image.dart';
import 'playlist_sheets.dart';

Future<void> showTrackOptionsSheet(BuildContext context, PlayerController controller, Track track) {
  final BuildContext hostContext = context;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext sheetContext) {
      bool details = false;
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setSheetState) {
          Widget action({required String label, required String subtitle, required IconData icon, required VoidCallback onTap}) {
            return ListTile(
              leading: Icon(icon, color: controller.accentColor),
              title: Text(label, style: AppText.body(14, 600, Colors.white)),
              subtitle: Text(subtitle, style: AppText.body(11, 400, AppColors.zinc500)),
              onTap: onTap,
            );
          }

          return SafeArea(
            top: false,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.panelBackground,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                border: Border(top: BorderSide(color: Color(0x553DDAE8))),
              ),
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(width: 42, height: 4, decoration: BoxDecoration(color: AppColors.zinc600, borderRadius: BorderRadius.circular(99))),
                    const SizedBox(height: 18),
                    Row(
                      children: <Widget>[
                        ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(width: 62, height: 62, child: CoverImage(controller: controller, track: track, cacheWidth: 160))),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                            Text(track.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.display(17, 700, Colors.white)),
                            const SizedBox(height: 3),
                            Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(12, 400, AppColors.zinc400)),
                          ]),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    action(label: 'Play next', subtitle: 'Move this track to the front of the queue', icon: Icons.play_arrow_rounded, onTap: () { controller.playNext(track); Navigator.pop(sheetContext); }),
                    action(label: 'Add to queue', subtitle: 'Append after the current queue', icon: Icons.queue_music_rounded, onTap: () { controller.addToQueue(track); Navigator.pop(sheetContext); }),
                    action(label: 'Add to playlist', subtitle: 'Pick a playlist or create a new one', icon: Icons.playlist_add_rounded, onTap: () { Navigator.pop(sheetContext); showAddToPlaylistSheet(hostContext, controller, <Track>[track]); }),
                    action(label: track.favorite ? 'Remove from favorites' : 'Add to favorites', subtitle: 'Saved on this device', icon: track.favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded, onTap: () { controller.toggleFavorite(track); setSheetState(() {}); }),
                    action(label: details ? 'Hide track details' : 'Track details', subtitle: 'Album, format and file location', icon: Icons.info_outline_rounded, onTap: () => setSheetState(() => details = !details)),
                    if (details)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(left: 12, right: 12, bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: AppColors.white(0.035), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.white(0.08))),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                          _detail('ALBUM', track.album),
                          _detail('DURATION', _duration(track.duration)),
                          _detail('YEAR', track.year?.toString() ?? 'Unknown'),
                          _detail('GENRE', track.genre ?? 'Unknown'),
                          _detail('FORMAT', track.mimeType ?? 'Unknown'),
                          _detail('FOLDER', track.folder ?? 'Not reported by media provider'),
                          _detail('PLAY COUNT', '${track.playCount}'),
                        ]),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

Widget _detail(String label, String value) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 4),
  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
    SizedBox(width: 82, child: Text(label, style: AppText.mono(9, 600, AppColors.zinc500))),
    Expanded(child: Text(value, style: AppText.body(11, 400, AppColors.zinc300))),
  ]),
);

String _duration(double seconds) {
  final int s = seconds.isFinite ? seconds.round().clamp(0, 1 << 30).toInt() : 0;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}
