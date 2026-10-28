import 'package:flutter/material.dart';

import '../models/playlist.dart';
import '../models/track.dart';
import '../state/player_controller.dart';
import '../theme/app_theme.dart';
import 'cover_image.dart';

const String _newPlaylistKey = '__new_playlist__';

/// Asks for a playlist name. Resolves to the trimmed name, or null when cancelled.
Future<String?> showPlaylistNameDialog(
  BuildContext context, {
  required Color accent,
  String title = 'New playlist',
  String initial = '',
  String confirmLabel = 'CREATE',
}) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) => _NameDialog(accent: accent, title: title, initial: initial, confirmLabel: confirmLabel),
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.accent, required this.title, required this.initial, required this.confirmLabel});

  final Color accent;
  final String title;
  final String initial;
  final String confirmLabel;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final String name = _text.text.trim();
    Navigator.pop(context, name.isEmpty ? null : name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.panelBackground,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: AppColors.white(0.1))),
      title: Text(widget.title, style: AppText.display(18, 700, Colors.white)),
      content: TextField(
        controller: _text,
        autofocus: true,
        maxLength: 60,
        textCapitalization: TextCapitalization.sentences,
        style: AppText.body(14, 500, Colors.white),
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          hintText: 'Playlist name',
          hintStyle: AppText.body(13, 400, AppColors.zinc600),
          counterStyle: AppText.mono(9, 400, AppColors.zinc600),
          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.white(0.2))),
          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: widget.accent)),
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(context), child: Text('CANCEL', style: AppText.mono(10, 700, AppColors.zinc400))),
        TextButton(onPressed: _submit, child: Text(widget.confirmLabel, style: AppText.mono(10, 700, widget.accent))),
      ],
    );
  }
}

/// "Add to playlist": pick an existing playlist or create a new one for [tracks].
Future<void> showAddToPlaylistSheet(BuildContext context, PlayerController controller, List<Track> tracks) async {
  if (tracks.isEmpty) return;
  final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
  final Color accent = controller.accentColor;
  final String? picked = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext sheetContext) => ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) {
        final List<Playlist> lists = controller.playlists;
        return SafeArea(
          top: false,
          child: Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
            decoration: BoxDecoration(
              color: AppColors.panelBackground,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              border: Border(top: BorderSide(color: Color(0x553DDAE8))),
            ),
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(color: AppColors.zinc600, borderRadius: BorderRadius.circular(99)))),
              const SizedBox(height: 16),
              Text('ADD TO PLAYLIST', style: AppText.mono(10, 700, accent, tracking: 0.14)),
              const SizedBox(height: 4),
              Text(tracks.length == 1 ? tracks.first.title : '${tracks.length} songs selected', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(12, 400, AppColors.zinc400)),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(width: 44, height: 44, decoration: BoxDecoration(color: accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)), child: Icon(Icons.add_rounded, color: accent)),
                title: Text('New playlist', style: AppText.body(14, 600, Colors.white)),
                onTap: () => Navigator.pop(sheetContext, _newPlaylistKey),
              ),
              Flexible(
                child: ListView(shrinkWrap: true, children: <Widget>[
                  for (final Playlist p in lists)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(width: 44, height: 44, decoration: BoxDecoration(color: AppColors.white(0.06), borderRadius: BorderRadius.circular(12)), child: Icon(Icons.queue_music_rounded, color: AppColors.zinc400)),
                      title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(14, 600, Colors.white)),
                      subtitle: Text('${p.trackIds.length} ${p.trackIds.length == 1 ? 'song' : 'songs'}', style: AppText.body(11, 400, AppColors.zinc500)),
                      onTap: () => Navigator.pop(sheetContext, p.id),
                    ),
                ]),
              ),
            ]),
          ),
        );
      },
    ),
  );
  if (picked == null) return;
  String playlistId = picked;
  if (picked == _newPlaylistKey) {
    if (!context.mounted) return;
    final String? newName = await showPlaylistNameDialog(context, accent: accent);
    if (newName == null) return;
    final Playlist created = await controller.createPlaylist(newName);
    playlistId = created.id;
  }
  final int added = await controller.addTracksToPlaylist(playlistId, tracks.map((Track t) => t.id));
  final String listName = controller.playlistById(playlistId)?.name ?? 'playlist';
  messenger?.showSnackBar(SnackBar(
    behavior: SnackBarBehavior.floating,
    content: Text(added == 0 ? 'Already in "$listName"' : 'Added $added ${added == 1 ? 'song' : 'songs'} to "$listName"'),
  ));
}

/// Full-height multi-select list of the library. [onConfirm] receives the chosen track ids.
Future<void> showSongPickerSheet(
  BuildContext context,
  PlayerController controller, {
  required String title,
  required String confirmLabel,
  required Future<void> Function(List<String> ids) onConfirm,
  Set<String> alreadyIn = const <String>{},
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext sheetContext) => _SongPicker(controller: controller, title: title, confirmLabel: confirmLabel, onConfirm: onConfirm, alreadyIn: alreadyIn),
  );
}

class _SongPicker extends StatefulWidget {
  const _SongPicker({required this.controller, required this.title, required this.confirmLabel, required this.onConfirm, required this.alreadyIn});

  final PlayerController controller;
  final String title;
  final String confirmLabel;
  final Future<void> Function(List<String> ids) onConfirm;
  final Set<String> alreadyIn;

  @override
  State<_SongPicker> createState() => _SongPickerState();
}

class _SongPickerState extends State<_SongPicker> {
  final TextEditingController _search = TextEditingController();
  final Set<String> _selected = <String>{};
  bool _busy = false;

  PlayerController get c => widget.controller;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Track> _filtered() {
    final String q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return c.tracks;
    return c.tracks.where((Track t) => '${t.title} ${t.artist} ${t.album}'.toLowerCase().contains(q)).toList();
  }

  Future<void> _confirm() async {
    if (_selected.isEmpty || _busy) return;
    setState(() => _busy = true);
    // Keep the library order, not the order in which the songs were ticked.
    final List<String> ids = <String>[
      for (final Track t in c.tracks)
        if (_selected.contains(t.id)) t.id,
    ];
    await widget.onConfirm(ids);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = c.accentColor;
    final List<Track> list = _filtered();
    final List<Track> selectable = list.where((Track t) => !widget.alreadyIn.contains(t.id)).toList();
    final bool allSelected = selectable.isNotEmpty && selectable.every((Track t) => _selected.contains(t.id));
    return FractionallySizedBox(
      heightFactor: 0.92,
      child: SafeArea(
        top: false,
        child: Container(
        decoration: BoxDecoration(
          color: AppColors.panelBackground,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(top: BorderSide(color: Color(0x553DDAE8))),
        ),
        padding: EdgeInsets.fromLTRB(16, 10, 16, 12 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(children: <Widget>[
          Container(width: 42, height: 4, decoration: BoxDecoration(color: AppColors.zinc600, borderRadius: BorderRadius.circular(99))),
          const SizedBox(height: 14),
          Row(children: <Widget>[
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text('SELECT SONGS', style: AppText.mono(10, 700, accent, tracking: 0.14)),
              const SizedBox(height: 3),
              Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.display(18, 700, Colors.white)),
            ])),
            IconButton(onPressed: () => Navigator.pop(context), icon: Icon(Icons.close_rounded, color: AppColors.zinc400)),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            style: AppText.body(13, 400, Colors.white),
            decoration: InputDecoration(
              hintText: 'Search title, artist, album…',
              hintStyle: AppText.body(12, 400, AppColors.zinc600),
              prefixIcon: Icon(Icons.search_rounded, color: AppColors.zinc500, size: 20),
              filled: true,
              fillColor: AppColors.white(0.045),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppColors.white(0.08))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: accent.withValues(alpha: 0.75))),
            ),
          ),
          const SizedBox(height: 6),
          Row(children: <Widget>[
            TextButton.icon(
              onPressed: selectable.isEmpty
                  ? null
                  : () => setState(() {
                        if (allSelected) {
                          _selected.removeAll(selectable.map((Track t) => t.id));
                        } else {
                          _selected.addAll(selectable.map((Track t) => t.id));
                        }
                      }),
              icon: Icon(allSelected ? Icons.deselect_rounded : Icons.select_all_rounded, size: 18, color: accent),
              label: Text(allSelected ? 'CLEAR' : 'SELECT ALL', style: AppText.mono(9, 700, accent)),
            ),
            const Spacer(),
            Text('${_selected.length} SELECTED', style: AppText.mono(9, 600, AppColors.zinc500, tracking: 0.08)),
          ]),
          Expanded(
            child: list.isEmpty
                ? Center(child: Text('NO MATCHES', style: AppText.mono(10, 700, AppColors.zinc600)))
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (BuildContext context, int i) {
                      final Track t = list[i];
                      final bool already = widget.alreadyIn.contains(t.id);
                      final bool on = _selected.contains(t.id);
                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: already ? null : () => setState(() => on ? _selected.remove(t.id) : _selected.add(t.id)),
                        child: Opacity(
                          opacity: already ? 0.45 : 1,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(children: <Widget>[
                              Checkbox(
                                value: already ? true : on,
                                activeColor: accent,
                                checkColor: Colors.black,
                                side: BorderSide(color: AppColors.white(0.3), width: 1.4),
                                onChanged: already ? null : (bool? v) => setState(() => v == true ? _selected.add(t.id) : _selected.remove(t.id)),
                              ),
                              ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 44, height: 44, child: CoverImage(controller: c, track: t, cacheWidth: 112))),
                              const SizedBox(width: 12),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                                Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(13, 500, Colors.white)),
                                const SizedBox(height: 2),
                                Text(already ? 'ALREADY IN PLAYLIST' : t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: already ? AppText.mono(8, 600, AppColors.zinc500) : AppText.body(10, 400, AppColors.zinc500)),
                              ])),
                            ]),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: _selected.isEmpty || _busy ? null : _confirm,
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                disabledBackgroundColor: AppColors.white(0.08),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(
                _selected.isEmpty ? widget.confirmLabel : '${widget.confirmLabel} (${_selected.length})',
                style: AppText.mono(11, 700, _selected.isEmpty ? AppColors.zinc600 : Colors.black, tracking: 0.08),
              ),
            ),
          ),
        ]),
      ),
      ),
    );
  }
}
