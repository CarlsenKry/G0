import 'package:flutter/material.dart';

import '../models/playlist.dart';
import '../models/track.dart';
import '../state/player_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/cover_image.dart';
import '../widgets/playlist_sheets.dart';
import '../services/native_bridge.dart';

/// Library > PLAYLISTS: list of playlists, and inside one: play, reorder, add and remove songs.
class PlaylistsView extends StatefulWidget {
  const PlaylistsView({super.key, required this.controller});

  final PlayerController controller;

  @override
  State<PlaylistsView> createState() => _PlaylistsViewState();
}

class _PlaylistsViewState extends State<PlaylistsView> {
  String? _openId;
  final Set<String> _selected = <String>{};

  PlayerController get c => widget.controller;

  Future<void> _create() async {
    final String? name = await showPlaylistNameDialog(context, accent: c.accentColor);
    if (name == null || !mounted) return;
    final Playlist p = await c.createPlaylist(name);
    if (!mounted) return;
    setState(() => _openId = p.id);
    // A new playlist is empty, so go straight to choosing its songs.
    await _addSongs(p);
  }

  Future<void> _addSongs(Playlist p) {
    return showSongPickerSheet(
      context,
      c,
      title: p.name,
      confirmLabel: 'ADD TO PLAYLIST',
      alreadyIn: p.trackIds.toSet(),
      onConfirm: (List<String> ids) => c.addTracksToPlaylist(p.id, ids),
    );
  }

  Future<void> _exportM3u(Playlist p) async {
    final List<Track> tracks = c.tracksOf(p);
    if (tracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This playlist has no available songs to export.')));
      return;
    }
    final StringBuffer out = StringBuffer('#EXTM3U\n#PLAYLIST:${p.name}\n');
    for (final Track t in tracks) {
      out.writeln('#KRYPTON-ID:${t.id}');
      out.writeln('#EXTINF:${t.duration.round()},${t.title} - ${t.artist}');
      out.writeln(t.uri);
    }
    try {
      final bool saved = await NativeBridge.exportM3u(p.name, out.toString());
      if (!mounted) return;
      if (saved) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Exported "${p.name}" as M3U.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not export playlist: $e')));
    }
  }

  Future<void> _importM3u() async {
    try {
      final String? content = await NativeBridge.importM3u();
      if (content == null || !mounted) return;
      final Map<String, Track> byId = <String, Track>{for (final Track t in c.tracks) t.id: t};
      final Map<String, Track> byUri = <String, Track>{for (final Track t in c.tracks) t.uri: t};
      final Map<String, Track> byName = <String, Track>{};
      String normalize(String value) => value.trim().replaceAll('\\', '/').split('/').last.replaceAll(RegExp(r'\.[^.]+$'), '').toLowerCase();
      for (final Track t in c.tracks) {
        byName.putIfAbsent(normalize(t.title), () => t);
        byName.putIfAbsent(normalize(t.uri), () => t);
      }
      final List<String> ids = <String>[];
      String? pendingId;
      String? playlistName;
      for (final String raw in content.split(RegExp(r'\r?\n'))) {
        final String line = raw.trim();
        if (line.isEmpty) continue;
        if (line.startsWith('#PLAYLIST:')) {
          playlistName = line.substring('#PLAYLIST:'.length).trim();
        } else if (line.startsWith('#KRYPTON-ID:')) {
          pendingId = line.substring('#KRYPTON-ID:'.length).trim();
        } else if (!line.startsWith('#')) {
          Track? track;
          if (pendingId != null) track = byId[pendingId];
          track ??= byUri[line];
          track ??= byName[normalize(line)];
          if (track != null && !ids.contains(track.id)) ids.add(track.id);
          pendingId = null;
        }
      }
      if (ids.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No songs from this M3U were found in your library.')));
        return;
      }
      String name = playlistName?.trim() ?? '';
      if (name.isEmpty) name = 'Imported playlist';
      final Playlist imported = await c.createPlaylist(name, trackIds: ids);
      if (!mounted) return;
      setState(() => _openId = imported.id);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Imported ${ids.length} songs into "${imported.name}".')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not import M3U: $e')));
    }
  }

  Future<void> _rename(Playlist p) async {
    final String? name = await showPlaylistNameDialog(context, accent: c.accentColor, title: 'Rename playlist', initial: p.name, confirmLabel: 'SAVE');
    if (name != null) await c.renamePlaylist(p.id, name);
  }

  Future<void> _delete(Playlist p) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: AppColors.panelBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: AppColors.white(0.1))),
        title: Text('Delete playlist?', style: AppText.display(18, 700, Colors.white)),
        content: Text('"${p.name}" will be removed. Your songs stay on the device.', style: AppText.body(12, 400, AppColors.zinc400, lineHeight: 18)),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text('CANCEL', style: AppText.mono(10, 700, AppColors.zinc400))),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text('DELETE', style: AppText.mono(10, 700, AppColors.rose500))),
        ],
      ),
    );
    if (ok != true) return;
    if (_openId == p.id) setState(() => _openId = null);
    await c.deletePlaylist(p.id);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (BuildContext context, Widget? _) {
        final Playlist? open = _openId == null ? null : c.playlistById(_openId!);
        if (open == null) return _overview();
        return _detail(open);
      },
    );
  }

  // ------------------------------------------------------------------ overview

  Widget _overview() {
    final Color accent = c.accentColor;
    final List<Playlist> lists = c.playlists;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Row(children: <Widget>[
        Expanded(child: Text('${lists.length} PLAYLIST${lists.length == 1 ? '' : 'S'}', style: AppText.mono(10, 600, AppColors.zinc500, tracking: 0.1))),
        TextButton.icon(
          onPressed: _importM3u,
          icon: Icon(Icons.file_open_rounded, size: 16, color: accent),
          label: Text('IMPORT M3U', style: AppText.mono(8, 700, accent)),
        ),
        TextButton.icon(
          onPressed: _create,
          icon: Icon(Icons.add_rounded, size: 17, color: accent),
          label: Text('NEW', style: AppText.mono(8, 700, accent)),
        ),
      ]),
      Expanded(
        child: lists.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                    Icon(Icons.queue_music_rounded, size: 40, color: AppColors.zinc600),
                    const SizedBox(height: 12),
                    Text('NO PLAYLISTS YET', style: AppText.mono(11, 700, AppColors.zinc400, tracking: 0.08)),
                    const SizedBox(height: 6),
                    Text('Create a playlist, then tick as many songs as you like to add them at once.', textAlign: TextAlign.center, style: AppText.body(11, 400, AppColors.zinc600, lineHeight: 17)),
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: _create,
                      style: FilledButton.styleFrom(backgroundColor: accent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      child: Text('CREATE PLAYLIST', style: AppText.mono(10, 700, Colors.black)),
                    ),
                  ]),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.only(bottom: 10),
                itemCount: lists.length,
                separatorBuilder: (BuildContext context, int index) => Divider(height: 1, color: AppColors.white(0.045), indent: 68),
                itemBuilder: (BuildContext context, int i) => _playlistRow(lists[i]),
              ),
      ),
    ]);
  }

  Widget _playlistRow(Playlist p) {
    final Color accent = c.accentColor;
    final List<Track> list = c.tracksOf(p);
    final double total = list.fold<double>(0, (double sum, Track t) => sum + (t.duration.isFinite ? t.duration : 0));
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() {
        _openId = p.id;
        _selected.clear();
      }),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
        child: Row(children: <Widget>[
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: <Color>[accent.withValues(alpha: 0.35), AppColors.white(0.05)]),
              border: Border.all(color: AppColors.white(0.08)),
            ),
            child: Icon(Icons.queue_music_rounded, color: accent, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(13, 600, Colors.white)),
            const SizedBox(height: 4),
            Text('${list.length} ${list.length == 1 ? 'song' : 'songs'}${list.isEmpty ? '' : '  ·  ${_formatTotal(total)}'}', style: AppText.mono(9, 400, AppColors.zinc500)),
          ])),
          IconButton(
            tooltip: 'Play playlist',
            visualDensity: VisualDensity.compact,
            onPressed: list.isEmpty ? null : () => c.playPlaylist(p),
            icon: Icon(Icons.play_circle_fill_rounded, color: list.isEmpty ? AppColors.zinc600 : accent, size: 30),
          ),
          PopupMenuButton<String>(
            tooltip: 'Playlist options',
            color: AppColors.zinc900,
            icon: Icon(Icons.more_vert_rounded, color: AppColors.zinc500, size: 22),
            onSelected: (String v) {
              if (v == 'shuffle') c.playPlaylist(p, shuffle: true);
              if (v == 'add') _addSongs(p);
              if (v == 'rename') _rename(p);
              if (v == 'export') _exportM3u(p);
              if (v == 'delete') _delete(p);
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              _menuItem('add', 'Add songs', Icons.playlist_add_rounded),
              if (list.isNotEmpty) _menuItem('shuffle', 'Shuffle play', Icons.shuffle_rounded),
              if (list.isNotEmpty) _menuItem('export', 'Export M3U', Icons.file_download_outlined),
              _menuItem('rename', 'Rename', Icons.edit_rounded),
              _menuItem('delete', 'Delete', Icons.delete_outline_rounded),
            ],
          ),
        ]),
      ),
    );
  }

  PopupMenuItem<String> _menuItem(String value, String label, IconData icon) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(children: <Widget>[
        Icon(icon, size: 18, color: AppColors.zinc300),
        const SizedBox(width: 10),
        Text(label, style: AppText.body(12, 500, Colors.white)),
      ]),
    );
  }

  // ------------------------------------------------------------------ one playlist

  Widget _detail(Playlist p) {
    final Color accent = c.accentColor;
    final List<Track> list = c.tracksOf(p);
    final bool selecting = _selected.isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Row(children: <Widget>[
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => setState(() {
            _openId = null;
            _selected.clear();
          }),
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.zinc300),
        ),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.display(18, 700, Colors.white, lineHeight: 24)),
          Text('${list.length} ${list.length == 1 ? 'SONG' : 'SONGS'}', style: AppText.mono(9, 600, AppColors.zinc500, tracking: 0.1)),
        ])),
        PopupMenuButton<String>(
          color: AppColors.zinc900,
          icon: Icon(Icons.more_vert_rounded, color: AppColors.zinc400, size: 22),
          onSelected: (String v) {
            if (v == 'rename') _rename(p);
            if (v == 'delete') _delete(p);
          },
          itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
            _menuItem('rename', 'Rename', Icons.edit_rounded),
            _menuItem('delete', 'Delete playlist', Icons.delete_outline_rounded),
          ],
        ),
      ]),
      const SizedBox(height: 6),
      if (selecting)
        Row(children: <Widget>[
          Expanded(child: Text('${_selected.length} SELECTED', style: AppText.mono(10, 700, accent, tracking: 0.08))),
          TextButton(
            onPressed: () => setState(() => _selected
              ..clear()
              ..addAll(list.map((Track t) => t.id))),
            child: Text('ALL', style: AppText.mono(9, 700, accent)),
          ),
          IconButton(
            tooltip: 'Add selected to queue',
            visualDensity: VisualDensity.compact,
            onPressed: () {
              c.addTracksToQueue(list.where((Track t) => _selected.contains(t.id)));
              setState(_selected.clear);
            },
            icon: Icon(Icons.queue_music_rounded, color: accent, size: 22),
          ),
          IconButton(
            tooltip: 'Remove selected from playlist',
            visualDensity: VisualDensity.compact,
            onPressed: () async {
              final Set<String> ids = Set<String>.of(_selected);
              setState(_selected.clear);
              await c.removeTracksFromPlaylist(p.id, ids);
            },
            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.rose500, size: 22),
          ),
          IconButton(
            tooltip: 'Cancel selection',
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(_selected.clear),
            icon: Icon(Icons.close_rounded, color: AppColors.zinc400, size: 22),
          ),
        ])
      else
        Row(children: <Widget>[
          Expanded(
            child: FilledButton.icon(
              onPressed: list.isEmpty ? null : () => c.playPlaylist(p),
              icon: const Icon(Icons.play_arrow_rounded, size: 20),
              label: Text('PLAY', style: AppText.mono(10, 700, Colors.black)),
              style: FilledButton.styleFrom(backgroundColor: accent, disabledBackgroundColor: AppColors.white(0.08), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: list.isEmpty ? null : () => c.playPlaylist(p, shuffle: true),
              icon: Icon(Icons.shuffle_rounded, size: 18, color: accent),
              label: Text('SHUFFLE', style: AppText.mono(10, 700, accent)),
              style: OutlinedButton.styleFrom(side: BorderSide(color: accent.withValues(alpha: 0.5)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.outlined(
            tooltip: 'Add songs',
            onPressed: () => _addSongs(p),
            icon: Icon(Icons.playlist_add_rounded, color: accent),
            style: IconButton.styleFrom(side: BorderSide(color: AppColors.white(0.15)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          ),
        ]),
      const SizedBox(height: 6),
      Expanded(
        child: list.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                    Icon(Icons.library_add_rounded, size: 38, color: AppColors.zinc600),
                    const SizedBox(height: 12),
                    Text('THIS PLAYLIST IS EMPTY', style: AppText.mono(11, 700, AppColors.zinc400, tracking: 0.08)),
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: () => _addSongs(p),
                      style: FilledButton.styleFrom(backgroundColor: accent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      child: Text('ADD SONGS', style: AppText.mono(10, 700, Colors.black)),
                    ),
                  ]),
                ),
              )
            : selecting
                ? ListView.builder(
                    padding: const EdgeInsets.only(bottom: 10),
                    itemCount: list.length,
                    itemBuilder: (BuildContext context, int i) => _trackRow(p, list, i, selecting: true),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.only(bottom: 10),
                    buildDefaultDragHandles: false,
                    itemCount: list.length,
                    onReorder: (int oldIndex, int newIndex) {
                      if (newIndex > oldIndex) newIndex -= 1;
                      final List<String> ids = list.map((Track t) => t.id).toList();
                      final String moved = ids.removeAt(oldIndex);
                      ids.insert(newIndex, moved);
                      c.setPlaylistOrder(p.id, ids);
                    },
                    itemBuilder: (BuildContext context, int i) => KeyedSubtree(key: ValueKey<String>('pl-${p.id}-${list[i].id}'), child: _trackRow(p, list, i, selecting: false)),
                  ),
      ),
    ]);
  }

  Widget _trackRow(Playlist p, List<Track> list, int index, {required bool selecting}) {
    final Track t = list[index];
    final Color accent = c.accentColor;
    final bool active = c.currentTrack?.id == t.id;
    final bool picked = _selected.contains(t.id);
    void toggle() => setState(() => picked ? _selected.remove(t.id) : _selected.add(t.id));
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: selecting ? toggle : () => c.playPlaylist(p, startWith: t),
      onLongPress: toggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(children: <Widget>[
          if (selecting)
            Checkbox(
              value: picked,
              activeColor: accent,
              checkColor: Colors.black,
              side: BorderSide(color: AppColors.white(0.3), width: 1.4),
              onChanged: (bool? _) => toggle(),
            ),
          ClipRRect(borderRadius: BorderRadius.circular(10), child: SizedBox(width: 48, height: 48, child: CoverImage(controller: c, track: t, cacheWidth: 128))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(13, active ? 700 : 500, active ? accent : Colors.white)),
            const SizedBox(height: 3),
            Text('${t.artist} · ${t.album}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(10, 400, AppColors.zinc500)),
          ])),
          if (!selecting) ...<Widget>[
            PopupMenuButton<String>(
              color: AppColors.zinc900,
              icon: Icon(Icons.more_vert_rounded, color: AppColors.zinc500, size: 20),
              onSelected: (String v) {
                if (v == 'next') c.playNext(t);
                if (v == 'queue') c.addToQueue(t);
                if (v == 'remove') c.removeTracksFromPlaylist(p.id, <String>[t.id]);
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                _menuItem('next', 'Play next', Icons.play_arrow_rounded),
                _menuItem('queue', 'Add to queue', Icons.queue_music_rounded),
                _menuItem('remove', 'Remove from playlist', Icons.remove_circle_outline_rounded),
              ],
            ),
            ReorderableDragStartListener(
              index: index,
              child: Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.drag_handle_rounded, color: AppColors.zinc600, size: 22)),
            ),
          ],
        ]),
      ),
    );
  }
}

String _formatTotal(double seconds) {
  final int s = seconds.isFinite ? seconds.round() : 0;
  final int h = s ~/ 3600;
  final int m = (s % 3600) ~/ 60;
  if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
  return '$m min';
}
