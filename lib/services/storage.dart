import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import '../models/playlist.dart';

/// Local persistence (settings, favorites, play counts, session/queue, listening stats).
class Storage {
  static late SharedPreferences _p;
  static int _totalListenMsCache = 0;
  static final Map<String, int> _trackListenMsCache = <String, int>{};
  static final Map<String, int> _dailyListenMsCache = <String, int>{};
  static bool _statsDirty = false;
  static int _statsRevision = 0;
  static Future<void> _statsWriteTail = Future<void>.value();

  static Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    _trackListenMsCache.clear();
    _dailyListenMsCache.clear();

    // Prefer the single-key bundle. Older releases stored these three values as
    // separate keys, which are read once here and migrated on the next flush.
    final String? bundleRaw = _p.getString('stats.bundle');
    bool loadedBundle = false;
    if (bundleRaw != null) {
      try {
        final dynamic decoded = jsonDecode(bundleRaw);
        if (decoded is Map) {
          _totalListenMsCache = (decoded['totalMs'] as num?)?.toInt() ?? (_p.getInt('stats.totalMs') ?? 0);
          _trackListenMsCache.addAll(decoded['perTrack'] is Map
              ? _intMapFromValue(decoded['perTrack'])
              : _loadIntMap('stats.perTrack'));
          _dailyListenMsCache.addAll(decoded['daily'] is Map
              ? _intMapFromValue(decoded['daily'])
              : _loadIntMap('stats.daily'));
          loadedBundle = true;
        }
      } catch (_) {
        // Fall back to the legacy keys if the bundle is damaged.
      }
    }
    if (!loadedBundle) {
      _totalListenMsCache = _p.getInt('stats.totalMs') ?? 0;
      _trackListenMsCache.addAll(_loadIntMap('stats.perTrack'));
      _dailyListenMsCache.addAll(_loadIntMap('stats.daily'));
    }
    _statsDirty = false;
    _statsRevision = 0;
    _statsWriteTail = Future<void>.value();
  }

  // ---- settings
  static AppSettings loadSettings() {
    final String? raw = _p.getString('settings');
    if (raw == null) return AppSettings.defaults();
    try {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return AppSettings.defaults();
    }
  }

  static Future<void> saveSettings(AppSettings s) async {
    await _p.setString('settings', jsonEncode(s.toJson()));
  }

  // ---- favorites
  static Set<String> loadFavorites() {
    return (_p.getStringList('favorites') ?? <String>[]).toSet();
  }

  static Future<void> saveFavorites(Set<String> ids) async {
    await _p.setStringList('favorites', ids.toList());
  }

  // ---- playlists
  static List<Playlist> loadPlaylists() {
    final String? raw = _p.getString('playlists');
    if (raw == null) return <Playlist>[];
    try {
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.whereType<Map<String, dynamic>>().map(Playlist.fromJson).toList();
    } catch (_) {
      return <Playlist>[];
    }
  }

  static Future<void> savePlaylists(List<Playlist> lists) async {
    await _p.setString('playlists', jsonEncode(lists.map((Playlist p) => p.toJson()).toList()));
  }

  // ---- play counts
  static Map<String, int> loadPlayCounts() {
    final String? raw = _p.getString('playCounts');
    if (raw == null) return <String, int>{};
    try {
      final Map<String, dynamic> decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((String k, dynamic v) => MapEntry<String, int>(k, (v as num).toInt()));
    } catch (_) {
      return <String, int>{};
    }
  }

  static Future<void> savePlayCounts(Map<String, int> counts) async {
    final bool saved = await _p.setString('playCounts', jsonEncode(counts));
    if (!saved) throw StateError('Failed to persist play counts');
  }

  // ---- per-track ReplayGain/loudness analysis (persistent, not disposable cache)
  static String _replayGainAnalysisKey(String trackId) => 'replayGain.analysis.$trackId';

  /// Returns a saved analysis only when it still matches this file version.
  static Map<String, dynamic>? loadReplayGainAnalysis({
    required String trackId,
    required int? sizeBytes,
    required int dateModifiedSec,
  }) {
    final String? raw = _p.getString(_replayGainAnalysisKey(trackId));
    if (raw == null) return null;
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final int? storedSize = (decoded['sizeBytes'] as num?)?.toInt();
      final int storedModified = (decoded['dateModifiedSec'] as num?)?.toInt() ?? 0;
      if (storedSize != sizeBytes || storedModified != dateModifiedSec) return null;
      if (decoded['attempted'] != true) return null;
      return decoded;
    } catch (_) {
      return null;
    }
  }

  /// Stores successful results and completed unsupported/failed attempts. A cancelled
  /// scan is deliberately not stored, so playback can try again if re-enabled.
  static Future<void> saveReplayGainAnalysis({
    required String trackId,
    required int? sizeBytes,
    required int dateModifiedSec,
    required bool success,
    double? gainDb,
    double? peak,
    double? integratedLufs,
  }) async {
    final Map<String, dynamic> record = <String, dynamic>{
      'version': 1,
      'attempted': true,
      'success': success,
      'sizeBytes': sizeBytes,
      'dateModifiedSec': dateModifiedSec,
      'gainDb': gainDb,
      'peak': peak,
      'integratedLufs': integratedLufs,
      'savedAtMs': DateTime.now().millisecondsSinceEpoch,
    };
    final bool saved = await _p.setString(_replayGainAnalysisKey(trackId), jsonEncode(record));
    if (!saved) throw StateError('Failed to persist ReplayGain analysis for $trackId');
  }

  // ---- session (current track, position, queue, history, modes)
  static Map<String, dynamic> loadSession() {
    final String? raw = _p.getString('session');
    if (raw == null) return <String, dynamic>{};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static Future<void> saveSession(Map<String, dynamic> session) async {
    await _p.setString('session', jsonEncode(session));
  }

  // ---- permission prompts counter (avoid nagging)
  static int get permissionAskCount => _p.getInt('permAsk') ?? 0;

  static Future<void> setPermissionAskCount(int value) async {
    await _p.setInt('permAsk', value);
  }

  // ---- listening stats (real, persisted)
  static int get totalListenMs => _totalListenMsCache;

  static Map<String, int> loadTrackListenMs() => Map<String, int>.of(_trackListenMsCache);

  static Map<String, int> loadDailyListenMs() => Map<String, int>.of(_dailyListenMsCache);

  static Map<String, int> _loadIntMap(String key) {
    final String? raw = _p.getString(key);
    if (raw == null) return <String, int>{};
    try {
      return _intMapFromValue(jsonDecode(raw));
    } catch (_) {
      return <String, int>{};
    }
  }

  static Map<String, int> _intMapFromValue(dynamic value) {
    if (value is! Map) return <String, int>{};
    final Map<String, int> out = <String, int>{};
    value.forEach((dynamic key, dynamic item) {
      if (item is num) out['$key'] = item.toInt();
    });
    return out;
  }

  /// Adds a qualified listening delta to memory. No disk write happens here.
  /// The controller serializes one statistics snapshot at checkpoints, on pause,
  /// and when changing tracks.
  static void addListening(String trackId, String dayKey, int ms) {
    if (ms <= 0) return;
    _totalListenMsCache += ms;
    _trackListenMsCache[trackId] = (_trackListenMsCache[trackId] ?? 0) + ms;
    _dailyListenMsCache[dayKey] = (_dailyListenMsCache[dayKey] ?? 0) + ms;
    _statsDirty = true;
    _statsRevision++;
  }

  static Future<void> flushListeningStats() {
    // Serialize flushes so a slower earlier write cannot overwrite a newer snapshot.
    final Future<void> next = _statsWriteTail
        .catchError((Object _) {})
        .then((_) async {
          if (!_statsDirty) return;
          final int revision = _statsRevision;
          final int total = _totalListenMsCache;
          final Map<String, int> perTrack = Map<String, int>.of(_trackListenMsCache);
          final Map<String, int> daily = Map<String, int>.of(_dailyListenMsCache);
          final bool saved = await _p.setString('stats.bundle', jsonEncode(<String, dynamic>{
            'totalMs': total,
            'perTrack': perTrack,
            'daily': daily,
          }));
          if (!saved) throw StateError('Failed to persist listening statistics');
          if (_statsRevision == revision) _statsDirty = false;
        })
        .catchError((Object _) {
          // Leave the dirty flag set so the next checkpoint retries the snapshot.
          _statsDirty = true;
        });
    _statsWriteTail = next;
    return next;
  }
}
