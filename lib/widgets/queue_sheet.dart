import 'package:flutter/material.dart';

import '../models/track.dart';
import '../state/player_controller.dart';
import '../theme/app_theme.dart';
import 'cover_image.dart';
import 'track_options_sheet.dart';

Future<void> showQueueSheet(BuildContext context, PlayerController controller) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext sheetContext) => DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.36,
      maxChildSize: 0.94,
      expand: false,
      builder: (BuildContext context, ScrollController scrollController) {
        return ListenableBuilder(
          listenable: controller,
          builder: (BuildContext context, Widget? _) {
            final Track? current = controller.currentTrack;
            final List<Track> queue = controller.queue;
            return Container(
              decoration: BoxDecoration(
                color: AppColors.panelBackground,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                border: Border(top: BorderSide(color: Color(0x553DDAE8))),
              ),
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
              child: Column(
                children: <Widget>[
                  Container(width: 42, height: 4, decoration: BoxDecoration(color: AppColors.zinc600, borderRadius: BorderRadius.circular(99))),
                  const SizedBox(height: 14),
                  Row(children: <Widget>[
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                      Text('PLAYBACK QUEUE', style: AppText.mono(11, 700, controller.accentColor, tracking: 0.12)),
                      const SizedBox(height: 4),
                      Text('${queue.length} upcoming ${queue.length == 1 ? 'track' : 'tracks'}', style: AppText.body(12, 400, AppColors.zinc400)),
                    ])),
                    TextButton(onPressed: queue.isEmpty ? null : controller.clearQueue, child: Text('CLEAR', style: AppText.mono(10, 600, queue.isEmpty ? AppColors.zinc600 : AppColors.zinc300))),
                    IconButton(onPressed: () => Navigator.pop(sheetContext), icon: Icon(Icons.close_rounded, color: AppColors.zinc300)),
                  ]),
                  if (current != null)
                    Container(
                      margin: const EdgeInsets.only(top: 4, bottom: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: controller.accentColor.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: controller.accentColor.withValues(alpha: 0.35))),
                      child: Row(children: <Widget>[
                        ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 42, height: 42, child: CoverImage(controller: controller, track: current, cacheWidth: 128))),
                        const SizedBox(width: 10),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                          Text('NOW PLAYING', style: AppText.mono(9, 700, controller.accentColor, tracking: 0.1)),
                          Text(current.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(12, 600, Colors.white)),
                          Text(current.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(10, 400, AppColors.zinc400)),
                        ])),
                      ]),
                    ),
                  Expanded(
                    child: queue.isEmpty
                        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                            Icon(Icons.queue_music_rounded, size: 36, color: AppColors.zinc600),
                            const SizedBox(height: 10),
                            Text('QUEUE IS EMPTY', style: AppText.mono(11, 600, AppColors.zinc400)),
                            const SizedBox(height: 4),
                            Text('Add tracks from the Library menu.', style: AppText.body(11, 400, AppColors.zinc600)),
                          ]))
                        : ReorderableListView.builder(
                            scrollController: scrollController,
                            itemCount: queue.length,
                            onReorder: controller.reorderQueue,
                            itemBuilder: (BuildContext context, int index) {
                              final Track track = queue[index];
                              return ListTile(
                                key: ValueKey<String>('queue-${track.id}'),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                                leading: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                                  ReorderableDragStartListener(index: index, child: Icon(Icons.drag_handle_rounded, color: AppColors.zinc600, size: 20)),
                                  const SizedBox(width: 4),
                                  ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 44, height: 44, child: CoverImage(controller: controller, track: track, cacheWidth: 120))),
                                ]),
                                title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(12, 600, Colors.white)),
                                subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(10, 400, AppColors.zinc500)),
                                onTap: () { controller.playQueuedTrack(track); Navigator.pop(sheetContext); },
                                trailing: PopupMenuButton<String>(
                                  color: AppColors.zinc900,
                                  icon: Icon(Icons.more_horiz_rounded, color: AppColors.zinc400),
                                  onSelected: (String value) {
                                    if (value == 'remove') controller.removeQueuedTrack(track.id);
                                    if (value == 'options') showTrackOptionsSheet(context, controller, track);
                                  },
                                  itemBuilder: (BuildContext context) => const <PopupMenuEntry<String>>[
                                    PopupMenuItem<String>(value: 'remove', child: Text('Remove from queue')),
                                    PopupMenuItem<String>(value: 'options', child: Text('Track options')),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    ),
  );
}
