import 'package:flutter/material.dart';

import '../models/track.dart';
import '../state/player_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/cover_image.dart';
import '../widgets/playlist_sheets.dart';
import '../widgets/track_options_sheet.dart';
import 'playlists_view.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.controller, required this.onOpenStats, required this.onOpenQueue});

  final PlayerController controller;
  final VoidCallback onOpenStats;
  final VoidCallback onOpenQueue;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final TextEditingController _search = TextEditingController();
  String _filter = 'ALL';
  String _sort = 'TITLE';
  final Set<String> _selected = <String>{};

  PlayerController get c => widget.controller;
  bool get _selecting => _selected.isNotEmpty;

  void _toggleSelected(Track t) {
    setState(() {
      if (!_selected.remove(t.id)) _selected.add(t.id);
    });
  }

  List<Track> _selectedTracks() => c.tracks.where((Track t) => _selected.contains(t.id)).toList();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Track> _tracks() {
    final String q = _search.text.trim().toLowerCase();
    final List<Track> result = c.tracks.where((Track t) {
      final bool matchesSearch = q.isEmpty || '${t.title} ${t.artist} ${t.album} ${t.genre ?? ''}'.toLowerCase().contains(q);
      if (!matchesSearch) return false;
      if (_filter == 'FAVORITES') return t.favorite;
      if (_filter == 'RECENT') return true;
      if (_filter == 'MOST PLAYED') return true;
      return true;
    }).toList();
    switch (_filter == 'RECENT' ? 'RECENT' : _sort) {
      case 'ARTIST':
        result.sort((Track a, Track b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
        break;
      case 'RECENT':
        result.sort((Track a, Track b) => b.addedAt.compareTo(a.addedAt));
        break;
      case 'MOST PLAYED':
        result.sort((Track a, Track b) => b.playCount.compareTo(a.playCount));
        break;
      default:
        result.sort((Track a, Track b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: true,
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(children: <Widget>[
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text('YOUR LIBRARY', style: AppText.mono(10, 700, c.accentColor, tracking: 0.18)),
                const SizedBox(height: 4),
                Text('Local audio', style: AppText.display(26, 700, Colors.white, lineHeight: 31)),
              ])),
              IconButton(tooltip: 'Listening stats', onPressed: widget.onOpenStats, icon: Icon(Icons.insights_rounded, color: c.accentColor)),
              IconButton(tooltip: 'Playback queue', onPressed: widget.onOpenQueue, icon: Icon(Icons.queue_music_rounded, color: c.accentColor)),
              IconButton(tooltip: 'Scan library again', onPressed: c.scanning ? null : c.scan, icon: Icon(Icons.refresh_rounded, color: c.scanning ? AppColors.zinc600 : AppColors.zinc300)),
            ]),
            if (_filter != 'PLAYLISTS') ...<Widget>[
            const SizedBox(height: 12),
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              style: AppText.body(13, 400, Colors.white),
              decoration: InputDecoration(
                hintText: 'Search title, artist, album…',
                hintStyle: AppText.body(12, 400, AppColors.zinc600),
                prefixIcon: Icon(Icons.search_rounded, color: AppColors.zinc500, size: 20),
                suffixIcon: _search.text.isEmpty ? null : IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: () { _search.clear(); setState(() {}); }),
                filled: true,
                fillColor: AppColors.white(0.045),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: AppColors.white(0.08))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.accentColor.withValues(alpha: 0.75))),
              ),
            ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: <Widget>[
                  for (final String label in <String>['ALL', 'FAVORITES', 'RECENT', 'MOST PLAYED', 'PLAYLISTS'])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(label, style: AppText.mono(9, _filter == label ? 700 : 500, _filter == label ? Colors.black : AppColors.zinc400)),
                        selected: _filter == label,
                        onSelected: (_) => setState(() { _filter = label; _selected.clear(); if (label == 'MOST PLAYED') _sort = 'MOST PLAYED'; }),
                        selectedColor: c.accentColor,
                        backgroundColor: AppColors.white(0.04),
                        side: BorderSide(color: _filter == label ? c.accentColor : AppColors.white(0.10)),
                        showCheckmark: false,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_filter == 'PLAYLISTS')
              Expanded(child: PlaylistsView(controller: c))
            else
            ListenableBuilder(
              listenable: c,
              builder: (BuildContext context, Widget? _) {
                final List<Track> tracks = _tracks();
                return Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    if (_selecting)
                      Row(children: <Widget>[
                        Expanded(child: Text('${_selected.length} SELECTED', style: AppText.mono(10, 700, c.accentColor, tracking: 0.08))),
                        TextButton(
                          onPressed: () => setState(() => _selected.addAll(tracks.map((Track t) => t.id))),
                          child: Text('ALL', style: AppText.mono(9, 700, c.accentColor)),
                        ),
                        IconButton(
                          tooltip: 'Add selected to playlist',
                          visualDensity: VisualDensity.compact,
                          onPressed: () async {
                            final List<Track> picked = _selectedTracks();
                            await showAddToPlaylistSheet(context, c, picked);
                            if (mounted) setState(_selected.clear);
                          },
                          icon: Icon(Icons.playlist_add_rounded, color: c.accentColor, size: 24),
                        ),
                        IconButton(
                          tooltip: 'Add selected to queue',
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            c.addTracksToQueue(_selectedTracks());
                            setState(_selected.clear);
                          },
                          icon: Icon(Icons.queue_music_rounded, color: c.accentColor, size: 22),
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
                      Expanded(child: Text('${tracks.length} TRACK${tracks.length == 1 ? '' : 'S'}', style: AppText.mono(10, 600, AppColors.zinc500, tracking: 0.1))),
                      DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _filter == 'MOST PLAYED' ? 'MOST PLAYED' : _sort,
                          isDense: true,
                          dropdownColor: AppColors.zinc900,
                          style: AppText.mono(9, 500, AppColors.zinc300),
                          icon: Icon(Icons.unfold_more_rounded, size: 15, color: AppColors.zinc500),
                          items: const <DropdownMenuItem<String>>[
                            DropdownMenuItem<String>(value: 'TITLE', child: Text('TITLE')),
                            DropdownMenuItem<String>(value: 'ARTIST', child: Text('ARTIST')),
                            DropdownMenuItem<String>(value: 'RECENT', child: Text('RECENT')),
                            DropdownMenuItem<String>(value: 'MOST PLAYED', child: Text('MOST PLAYED')),
                          ],
                          onChanged: (String? v) { if (v != null) setState(() { _sort = v; if (v == 'MOST PLAYED') _filter = 'MOST PLAYED'; }); },
                        ),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    Expanded(
                      child: c.scanning && c.tracks.isEmpty
                          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[const CircularProgressIndicator(), const SizedBox(height: 14), Text('SCANNING DEVICE MUSIC', style: AppText.mono(10, 600, AppColors.zinc400))]))
                          : tracks.isEmpty
                              ? _emptyState()
                              : ListView.separated(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  itemCount: tracks.length,
                                  separatorBuilder: (BuildContext context, int index) => Divider(height: 1, color: AppColors.white(0.045), indent: 68),
                                  itemBuilder: (BuildContext context, int index) => _trackRow(tracks[index]),
                                ),
                    ),
                  ]),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _trackRow(Track track) {
    final bool active = c.currentTrack?.id == track.id;
    final bool picked = _selected.contains(track.id);
    return InkWell(
      onTap: _selecting ? () => _toggleSelected(track) : () => c.selectTrack(track),
      onLongPress: () => _toggleSelected(track),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
        child: Row(children: <Widget>[
          if (_selecting)
            Checkbox(
              value: picked,
              activeColor: c.accentColor,
              checkColor: Colors.black,
              side: BorderSide(color: AppColors.white(0.3), width: 1.4),
              onChanged: (bool? _) => _toggleSelected(track),
            ),
          Stack(children: <Widget>[
            ClipRRect(borderRadius: BorderRadius.circular(10), child: SizedBox(width: 54, height: 54, child: CoverImage(controller: c, track: track, cacheWidth: 144))),
            if (active && c.isPlaying)
              Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.38), borderRadius: BorderRadius.circular(10)), child: Icon(Icons.equalizer_rounded, color: c.accentColor, size: 24))),
          ]),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(13, active ? 700 : 500, active ? c.accentColor : Colors.white)),
            const SizedBox(height: 3),
            Text('${track.artist} · ${track.album}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.body(10, 400, AppColors.zinc500)),
            const SizedBox(height: 4),
            Row(children: <Widget>[
              if (track.favorite) Padding(padding: const EdgeInsets.only(right: 5), child: Icon(Icons.favorite_rounded, size: 10, color: c.accentColor)),
              Text(_formatDuration(track.duration), style: AppText.mono(9, 400, AppColors.zinc600, tabular: true)),
              if (track.playCount > 0) Text('  ·  ${track.playCount} plays', style: AppText.mono(9, 400, AppColors.zinc600)),
            ]),
          ])),
          IconButton(
            tooltip: 'Track options',
            visualDensity: VisualDensity.compact,
            onPressed: () => showTrackOptionsSheet(context, c, track),
            icon: Icon(Icons.more_vert_rounded, color: AppColors.zinc500, size: 22),
          ),
        ]),
      ),
    );
  }

  Widget _emptyState() {
    return Center(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Icon(_filter == 'FAVORITES' ? Icons.favorite_border_rounded : Icons.library_music_rounded, size: 40, color: AppColors.zinc600),
        const SizedBox(height: 12),
        Text(c.tracks.isEmpty ? 'NO LOCAL TRACKS FOUND' : 'NO MATCHES FOUND', textAlign: TextAlign.center, style: AppText.mono(11, 700, AppColors.zinc400, tracking: 0.08)),
        const SizedBox(height: 6),
        Text(c.tracks.isEmpty ? 'Grant audio access or add music files to the device, then scan again.' : 'Try another search or switch the filter.', textAlign: TextAlign.center, style: AppText.body(11, 400, AppColors.zinc600, lineHeight: 17)),
        if (c.tracks.isEmpty) TextButton(onPressed: c.scan, child: Text('SCAN AGAIN', style: AppText.mono(10, 700, c.accentColor))),
      ]),
    ));
  }
}

String _formatDuration(double duration) {
  final int seconds = (duration.isFinite ? duration : 0).round().clamp(0, 1 << 30).toInt();
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}
