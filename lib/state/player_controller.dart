import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../models/app_settings.dart';
import '../models/lockscreen_settings.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../services/audio_handler.dart';
import '../services/lockscreen_service.dart';
import '../services/native_bridge.dart';
import '../services/storage.dart';
import '../theme/app_theme.dart';
import '../utils/id3_parser.dart';
import '../utils/lrc_parser.dart';
import '../utils/palette_extractor.dart';

class PlayerController extends ChangeNotifier with WidgetsBindingObserver {
  PlayerController();

  AetherAudioHandler? _handler;
  final List<StreamSubscription<dynamic>> _subs = <StreamSubscription<dynamic>>[];
  late final LockscreenService _lockscreen = LockscreenService(this);

  /// Playback position in seconds (separate notifier so the whole UI does not rebuild 5x/second).
  final ValueNotifier<double> position = ValueNotifier<double>(0);

  /// False while the app UI is hidden. Audio service/state deliberately stay alive.
  final ValueNotifier<bool> uiForeground = ValueNotifier<bool>(true);

  List<Track> tracks = <Track>[];
  List<Track> _scannedTracks = <Track>[];
  List<String> availableFolders = <String>[];
  Track? currentTrack;
  bool isPlaying = false;
  double duration = 0;
  List<Track> queue = <Track>[];
  List<Track> history = <Track>[];
  int _queueRevision = 0;

  // A single ordered lane owns all track changes. Media-session commands, UI taps,
  // and end-of-track callbacks can arrive almost simultaneously; without this lane
  // their queue mutations can overtake the audio load they requested.
  Future<void> _trackTransitionTail = Future<void>.value();
  bool _trackTransitionLoading = false;
  bool isShuffle = false;
  AetherRepeatMode repeatMode = AetherRepeatMode.all;
  AppSettings settings = AppSettings.defaults();
  ExtractedPalette palette = ExtractedPalette.defaults;
  int? sleepTimeRemaining;
  String? currentCoverPath;

  bool permissionsChecked = false;
  bool mediaGranted = false;
  bool notificationsGranted = false;
  bool overlayGranted = false;
  bool scanning = false;
  String? externalLyricsFolder;

  final Map<String, Future<String?>> _coverFutures = <String, Future<String?>>{};
  final Map<String, Future<void>> _replayGainReads = <String, Future<void>>{};
  String? _loudnessScanTrackId;
  int _loudnessScanEpoch = 0;
  final Set<String> _lyricsTried = <String>{};
  Timer? _lyricsMonitorTimer;
  int? _lyricsChangeToken;
  int _lyricsCacheEpoch = 0;
  bool _checkingLyricsChangeToken = false;
  Map<String, int> _playCounts = <String, int>{};
  Set<String> _favorites = <String>{};
  List<Playlist> playlists = <Playlist>[];

  Timer? _advanceTimer;
  bool _advancing = false;
  String? _preloadRequestedId;

  bool _endedHandled = false;
  bool _notificationPrompted = false;
  int _lastTickMs = 0;
  int _pendingListenMs = 0;
  int _currentTrackPlayedMs = 0;
  bool _currentTrackQualified = false;
  bool _playCountsDirty = false;
  int? _audioSessionId;
  Timer? _persistTimer;
  Timer? _sleepTimer;

  Future<T> _serializeTrackTransition<T>(Future<T> Function() action) {
    final Completer<T> result = Completer<T>();
    _trackTransitionTail = _trackTransitionTail.then<void>((_) async {
      try {
        result.complete(await action());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  void _replaceQueue(List<Track> nextQueue) {
    queue = nextQueue;
    _queueRevision++;
  }

  // ------------------------------------------------------------------ derived colors

  Color get accentColor {
    if (settings.accentMode == 'auto') return palette.dominant;
    return AppColors.fromHex(settings.accentMode);
  }

  Color get glowColor {
    if (settings.accentMode == 'auto') return palette.glow;
    return accentColor.withValues(alpha: 0.45);
  }

  Color get secondaryColor => const Color(0xFFFF2E93);

  // ------------------------------------------------------------------ lifecycle

  Future<void> init(AetherAudioHandler handler) async {
    _handler = handler;
    await Storage.init();
    settings = Storage.loadSettings();
    externalLyricsFolder = await NativeBridge.getLyricsFolder();
    _lyricsChangeToken = await NativeBridge.getExternalLyricsChangeToken();
    _startLyricsMonitor();
    _favorites = Storage.loadFavorites();
    _playCounts = Storage.loadPlayCounts();
    playlists = Storage.loadPlaylists();
    final Map<String, dynamic> session = Storage.loadSession();
    isShuffle = session['shuffle'] == true;
    repeatMode = repeatModeFromName(session['repeat'] as String?);

    WidgetsBinding.instance.addObserver(this);
    handler.onSkipNext = () => next();
    handler.onSkipPrevious = () => prev();
    handler.updateLockscreenOptions(
      enabled: settings.lockscreenPlayerEnabled,
      showPrevious: settings.lockscreenShowPrevious,
      showNext: settings.lockscreenShowNext,
    );
    handler.pauseFade = _pauseFadeDuration();

    _lockscreen.attach();
    unawaited(_refreshOverlay());

    // The handler forwards the streams of whichever player is active, so these
    // subscriptions stay valid when a fade hands playback over to the other player.
    _subs.add(handler.positionStream.listen(_onPosition));
    _subs.add(handler.playerStateStream.listen(_onPlayerState));
    _subs.add(handler.durationStream.listen(_onDuration));
    _subs.add(handler.androidAudioSessionIdStream.listen(_onSessionId));

    // Keep session checkpoints and statistics writes infrequent. Listening statistics
    // remain in memory until a track qualifies and this checkpoint flushes the batch.
    _persistTimer = Timer.periodic(const Duration(seconds: 60), (Timer _) {
      // Session position only changes during playback. Avoid disk writes every minute
      // while paused; pause/track/queue transitions persist their own latest state.
      if (isPlaying) _persistSession();
      unawaited(_flushPlayCounts());
      unawaited(Storage.flushListeningStats());
    });
    _syncSleepTimer();

    await _bootstrapPermissionsAndScan();
  }

  void _startLyricsMonitor() {
    if (_lyricsMonitorTimer != null) return;
    _lyricsMonitorTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      unawaited(_pollExternalLyricsChanges());
    });
  }

  void _stopLyricsMonitor() {
    _lyricsMonitorTimer?.cancel();
    _lyricsMonitorTimer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      uiForeground.value = true;
      _startLyricsMonitor();
      refreshPermissions();
      // Catch .lrc changes that happened while the UI was suspended.
      unawaited(_pollExternalLyricsChanges());
    } else if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      uiForeground.value = false;
      // This is UI-side change detection, not a playback requirement. Resume with
      // one immediate poll instead of waking Dart every four seconds in background.
      _stopLyricsMonitor();
      if (state == AppLifecycleState.paused) {
        _persistSession();
        unawaited(_flushPlayCounts());
        unawaited(Storage.flushListeningStats());
      }
    }
  }

  // ------------------------------------------------------------------ permissions & scan

  void _applyPermissions(Map<String, bool> state) {
    mediaGranted = state['media'] == true;
    notificationsGranted = state['notifications'] == true;
  }

  Future<void> _bootstrapPermissionsAndScan() async {
    Map<String, bool> state = await NativeBridge.checkPermissions();
    final bool anyMissing = !(state['media'] == true) || !(state['notifications'] == true);
    final int asked = Storage.permissionAskCount;
    if (anyMissing && (state['media'] != true || asked < 2)) {
      state = await NativeBridge.requestPermissions();
      await Storage.setPermissionAskCount(asked + 1);
    }
    // Request POST_NOTIFICATIONS separately on Android 13+ after media access.
    // This app no longer requests any recording or microphone permission.
    if (state['notifications'] != true && asked < 2) {
      state = await NativeBridge.requestNotificationPermission();
    }
    _applyPermissions(state);
    permissionsChecked = true;
    notifyListeners();
    if (mediaGranted) {
      await scan();
    }
  }

  /// Called by the permission gate button.
  Future<void> requestMediaPermission() async {
    final Map<String, bool> state = await NativeBridge.requestPermissions();
    _applyPermissions(state);
    notifyListeners();
    if (mediaGranted) {
      await scan();
    }
  }

  Future<void> requestNotificationPermission() async {
    final Map<String, bool> state = await NativeBridge.requestNotificationPermission();
    _applyPermissions(state);
    notifyListeners();
    if (!notificationsGranted) {
      // If Android has permanently denied the prompt or the app/channel is
      // disabled, the user must enable it in system app settings.
      await NativeBridge.openAppSettings();
    }
  }

  Future<void> openSystemSettings() => NativeBridge.openAppSettings();

  /// Re-checks permissions (e.g. after returning from system settings).
  Future<void> refreshPermissions() async {
    final bool hadMedia = mediaGranted;
    final Map<String, bool> state = await NativeBridge.checkPermissions();
    _applyPermissions(state);
    overlayGranted = await NativeBridge.canDrawOverlays();
    notifyListeners();
    if (mediaGranted && (!hadMedia || tracks.isEmpty)) {
      await scan();
    }
    // Visualizers are procedural; no microphone/audio-capture permission is needed.
  }

  Future<void> _refreshOverlay() async {
    overlayGranted = await NativeBridge.canDrawOverlays();
    notifyListeners();
  }

  // ------------------------------------------------------------------ Screenlock KRY player

  Future<void> updateLockscreen(LockscreenSettings value) => updateSettings(settings.copyWith(lockscreen: value));

  /// Opens Android's "Display over other apps" page for this app.
  Future<void> openOverlaySettings() => NativeBridge.openOverlaySettings();

  /// Shows the Screenlock KRY player right now, so it can be styled without locking the phone.
  Future<void> previewLockscreen() async {
    _lockscreen.push(force: true);
    await NativeBridge.previewLockscreen();
  }

  Future<void> scan() async {
    if (scanning) return;
    scanning = true;
    notifyListeners();
    try {
      final List<Map<dynamic, dynamic>> raw = await NativeBridge.scanTracks();
      final List<Track> list = <Track>[];
      for (final Map<dynamic, dynamic> m in raw) {
        final Track t = Track.fromMap(m);
        t.favorite = _favorites.contains(t.id);
        t.playCount = _playCounts[t.id] ?? 0;
        list.add(t);
      }
      list.sort((Track a, Track b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      _scannedTracks = list;
      availableFolders = list
          .map((Track t) => t.folder?.trim() ?? '')
          .where((String folder) => folder.isNotEmpty)
          .toSet()
          .toList()
        ..sort((String a, String b) => a.toLowerCase().compareTo(b.toLowerCase()));
      _applyFolderVisibility();
      if (currentTrack == null && tracks.isNotEmpty) {
        await _restoreSession();
      }
    } catch (_) {
      // Keep whatever we had; the UI shows the empty state.
    }
    scanning = false;
    notifyListeners();
  }

  Track? _byId(String? id) {
    if (id == null) return null;
    for (final Track t in tracks) {
      if (t.id == id) return t;
    }
    return null;
  }

  List<Track> _sequentialQueueAfter(Track track) {
    final int idx = tracks.indexWhere((Track t) => t.id == track.id);
    if (idx == -1) return <Track>[];
    return <Track>[...tracks.sublist(idx + 1), ...tracks.sublist(0, idx)];
  }

  Future<void> _restoreSession() async {
    final Map<String, dynamic> session = Storage.loadSession();
    final Track? saved = _byId(session['trackId'] as String?);
    final Track current = saved ?? tracks.first;

    List<Track> restoredQueue = <Track>[];
    final dynamic qIds = session['queue'];
    if (saved != null && qIds is List) {
      for (final dynamic id in qIds) {
        final Track? t = _byId('$id');
        if (t != null && t.id != current.id) restoredQueue.add(t);
      }
    }
    if (restoredQueue.isEmpty) {
      restoredQueue = _sequentialQueueAfter(current);
    }
    final List<Track> restoredHistory = <Track>[];
    final dynamic hIds = session['history'];
    if (hIds is List) {
      for (final dynamic id in hIds) {
        final Track? t = _byId('$id');
        if (t != null) restoredHistory.add(t);
      }
    }
    _replaceQueue(restoredQueue);
    history = restoredHistory;
    final double startAt = saved != null ? (((session['positionMs'] as num?)?.toDouble() ?? 0) / 1000.0) : 0;
    await _startTrack(current, autoPlay: false, startAt: startAt);
  }

  // ------------------------------------------------------------------ engine streams

  void _onPosition(Duration d) {
    // Position events from the outgoing source may continue while the next source
    // is loading. Do not attribute that time to either track or arm another advance.
    if (_trackTransitionLoading) {
      _lastTickMs = 0;
      return;
    }
    position.value = d.inMilliseconds / 1000.0;
    final int now = DateTime.now().millisecondsSinceEpoch;
    if (isPlaying && _lastTickMs != 0) {
      final int delta = now - _lastTickMs;
      if (delta > 0 && delta < 2000) {
        _currentTrackPlayedMs += delta;
        _pendingListenMs += delta;
        final int thresholdMs = duration > 0 ? (duration * 500).round() : 0;
        if (!_currentTrackQualified && thresholdMs > 0 && _currentTrackPlayedMs >= thresholdMs) {
          _currentTrackQualified = true;
          final Track? track = currentTrack;
          if (track != null) {
            track.playCount += 1;
            _playCounts[track.id] = track.playCount;
            _playCountsDirty = true;

            // The song has now crossed the 50% listened-time threshold. Commit the
            // accumulated eligible time immediately so a force-stop right after this
            // point does not lose the first qualified listening batch.
            if (_pendingListenMs > 0) {
              final int qualifiedMs = _pendingListenMs;
              _pendingListenMs = 0;
              Storage.addListening(track.id, _dayKey(), qualifiedMs);
              unawaited(Storage.flushListeningStats());
            }
            unawaited(_flushPlayCounts());
            notifyListeners();
          }
        }
      }
    }
    _lastTickMs = now;
    _scheduleAutoAdvance(d);
  }

  void _onPlayerState(PlayerState state) {
    final bool completed = state.processingState == ProcessingState.completed;
    final bool playing = state.playing && !completed;
    if (playing != isPlaying) {
      isPlaying = playing;
      if (playing && !_trackTransitionLoading && settings.volumeStabilizerEnabled && currentTrack != null) {
        _maybeAnalyzeReplayGain(currentTrack!);
      }
      if (!playing) {
        _lastTickMs = 0;
        _advanceTimer?.cancel();
        _advanceTimer = null;
        _persistSession();
        // A pause is a natural checkpoint. Persist eligible stats and play counts
        // here so a later force-stop does not lose a completed listening session.
        unawaited(_flushPlayCounts());
        unawaited(Storage.flushListeningStats());
      }
      notifyListeners();
    }
    if (!completed) {
      // The flag is only re-armed once the engine has really left the completed
      // state (new source loading, or a seek back into the track). Re-arming it
      // earlier made the end-of-track handler fire twice and skip a song.
      _endedHandled = false;
    } else if (!_endedHandled) {
      _endedHandled = true;
      // A source switch can report completion for the outgoing player. That event
      // must not enqueue a second Next while the requested transition is underway.
      if (!_trackTransitionLoading) _onEnded();
    }
  }

  void _onDuration(Duration? d) {
    if (!_trackTransitionLoading && d != null && d.inMilliseconds > 0) {
      duration = d.inMilliseconds / 1000.0;
      notifyListeners();
    }
  }

  void _onSessionId(int? id) {
    if (id == _audioSessionId) return;
    _audioSessionId = id;
    unawaited(_applyAudioEffects());
  }

  // ------------------------------------------------------------------ fading / gapless

  int get _fadeSeconds => settings.crossfadeDuration.clamp(0, 30).toInt();

  /// Fade length for the track that is playing now. Short tracks never fade longer
  /// than the middle of the song, so the next one cannot start before this one.
  double _effectiveFade() {
    final int s = _fadeSeconds;
    if (s == 0 || duration <= 0) return 0;
    return math.min(s.toDouble(), duration / 2 - 0.5).clamp(0.0, 30.0).toDouble();
  }

  Duration _pauseFadeDuration() => settings.fadeOnPause ? const Duration(milliseconds: 500) : Duration.zero;

  /// True when both tracks carry the same real album tag. Untagged files usually get the
  /// folder name as album, so an album equal to the folder name does not count.
  bool _isSameAlbum(Track? a, Track b) {
    if (a == null) return false;
    final String x = a.album.trim().toLowerCase();
    if (x.isEmpty || x != b.album.trim().toLowerCase()) return false;
    if (x == 'unknown' || x == '<unknown>' || x == 'unknown album') return false;
    for (final Track t in <Track>[a, b]) {
      final List<String> parts = (t.folder ?? '')
          .replaceAll('\\', '/')
          .split('/')
          .where((String part) => part.trim().isNotEmpty)
          .toList();
      if (parts.isNotEmpty && parts.last.trim().toLowerCase() == x) return false;
    }
    return true;
  }

  /// Fade length for the change from the current track to [upcoming].
  double _fadeTo(Track upcoming) {
    if (settings.albumAwareFading && _isSameAlbum(currentTrack, upcoming)) return 0;
    return _effectiveFade();
  }

  /// Fade used when the user changes track by hand. Capped so Next never waits half a minute.
  Duration _manualTransition() {
    final int s = _fadeSeconds;
    if (s == 0 || !settings.fadeOnManualSkip) return Duration.zero;
    return Duration(milliseconds: (math.min(s.toDouble(), 5.0) * 1000).round());
  }

  /// The track Next would play, without touching the queue. Null when playback
  /// should simply end after the current track.
  Track? _peekNext() {
    if (queue.isNotEmpty) return queue.first;
    if (tracks.isNotEmpty && repeatMode != AetherRepeatMode.off) return tracks.first;
    return null;
  }

  void _invalidatePreload() {
    _preloadRequestedId = null;
  }

  void _cancelAutoAdvance() {
    _advanceTimer?.cancel();
    _advanceTimer = null;
  }

  /// Runs on every position tick. Pre-loads the next track shortly before it is needed
  /// and arms a timer for the exact moment the next track has to start: `fade` seconds
  /// before the end (overlap), or at the end (gapless).
  void _scheduleAutoAdvance(Duration position) {
    final AetherAudioHandler? h = _handler;
    final bool useFade = _fadeSeconds > 0;
    if (h == null || !isPlaying || duration <= 0 || repeatMode == AetherRepeatMode.one || !(useFade || settings.gapless)) {
      _cancelAutoAdvance();
      return;
    }
    final Track? upcoming = _peekNext();
    if (upcoming == null) {
      _cancelAutoAdvance();
      return;
    }
    final double remaining = duration - position.inMilliseconds / 1000.0;
    final double fade = _fadeTo(upcoming);
    // Same-album change with gapless off: let the track end on its own.
    if (fade == 0 && !settings.gapless) {
      _cancelAutoAdvance();
      return;
    }
    if (remaining <= fade + 12 && _preloadRequestedId != upcoming.id) {
      _preloadRequestedId = upcoming.id;
      unawaited(() async {
        if (settings.volumeStabilizerEnabled) await _ensureReplayGain(upcoming);
        if (_preloadRequestedId != upcoming.id) return;
        await h.preload(
          upcoming,
          replayGainMultiplier: _trackVolumeMultiplier(upcoming),
          prepareSessionEffects: _prepareAudioEffectsForTrack,
        );
      }());
    }
    if (remaining > fade + 1.0) {
      _cancelAutoAdvance();
      return;
    }
    // A small lead compensates for the platform-channel round trip of the switch.
    final int waitMs = math.max(0, ((remaining - fade) * 1000).round() - 60);
    _advanceTimer?.cancel();
    _advanceTimer = Timer(Duration(milliseconds: waitMs), () => unawaited(_autoAdvance()));
  }

  Future<void> _autoAdvance() async {
    _advanceTimer = null;
    if (_advancing || !isPlaying || repeatMode == AetherRepeatMode.one) return;
    final String? expectedTrackId = currentTrack?.id;
    final Track? upcoming = _peekNext();
    final double fade = upcoming == null ? 0 : _fadeTo(upcoming);
    final double remaining = duration - position.value;
    // The user seeked away after the timer was armed.
    if (remaining > fade + 1.5) return;
    _advancing = true;
    try {
      await next(
        fromEnd: true,
        autoFade: Duration(milliseconds: (fade * 1000).round()),
        expectedTrackId: expectedTrackId,
      );
    } finally {
      _advancing = false;
    }
  }

  void _onEnded() {
    final String? endedTrackId = currentTrack?.id;
    if (repeatMode == AetherRepeatMode.one) {
      unawaited(_restartCurrentTrack(expectedTrackId: endedTrackId));
      return;
    }
    unawaited(next(fromEnd: true, expectedTrackId: endedTrackId));
  }

  Future<void> _restartCurrentTrack({required String? expectedTrackId}) =>
      _serializeTrackTransition<void>(() => _restartCurrentTrackImpl(expectedTrackId));

  Future<void> _restartCurrentTrackImpl(String? expectedTrackId) async {
    if (expectedTrackId != null && currentTrack?.id != expectedTrackId) return;
    final AetherAudioHandler? h = _handler;
    if (h == null) return;
    // Repeat-one starts a new listening attempt without loading a new Track object.
    // Commit the completed attempt first, then re-arm the 50% play qualification.
    _persistSession();
    await _flushPlayCounts();
    await Storage.flushListeningStats();
    _currentTrackPlayedMs = 0;
    _currentTrackQualified = false;
    _pendingListenMs = 0;
    _lastTickMs = 0;
    try {
      await h.seek(Duration.zero);
      await h.play();
    } catch (_) {
      // A device/player may reject a restart while its decoder is being torn down.
    }
  }

  // ------------------------------------------------------------------ track loading

  Future<String?> coverFor(Track t) {
    return _coverFutures.putIfAbsent(t.id, () => NativeBridge.loadCover(t.id, size: 512));
  }

  /// Returns false if the engine could not load this track. Controller state is only
  /// committed after the audio handler confirms the source load, so queue callers can
  /// safely retain an item after a real failure or a superseded request.
  Future<bool> _startTrack(
    Track t, {
    required bool autoPlay,
    double startAt = 0,
    Duration? transition,
  }) async {
    try {
      // Resolve tags before switching IDs, but do not let outgoing-source position
      // events count toward either song while a transition is pending.
      if (settings.volumeStabilizerEnabled) await _ensureReplayGain(t);
      // Let the old source continue contributing listening time during tag lookup.
      // Freeze stats and end-of-track scheduling only for the actual source switch.
      _trackTransitionLoading = true;
      _lastTickMs = 0;
      _persistSession();
      await _flushPlayCounts();
      await Storage.flushListeningStats();
      _invalidatePreload();
      _cancelAutoAdvance();

      final AetherAudioHandler? h = _handler;
      bool loaded = true;
      if (h != null) {
        loaded = await h.loadTrack(
          t,
          autoPlay: autoPlay,
          start: Duration(milliseconds: (startAt * 1000).round()),
          transition: autoPlay ? (transition ?? _manualTransition()) : Duration.zero,
          replayGainMultiplier: _trackVolumeMultiplier(t),
          prepareSessionEffects: _prepareAudioEffectsForTrack,
        );
      }
      if (!loaded) {
        // A failed/superseded load must not change currentTrack or clear queue state.
        return false;
      }

      currentTrack = t;
      duration = t.duration;
      position.value = startAt;
      currentCoverPath = null;
      _currentTrackPlayedMs = 0;
      _currentTrackQualified = false;
      _pendingListenMs = 0;
      _lastTickMs = 0;
      // Play count is recorded only after at least half of the track's duration
      // has actually been listened to, not when playback merely starts.
      notifyListeners();
      unawaited(_loadAuxiliarySafely(t));

      if (h != null) {
        // Analysis starts only once the track is actually being played, never merely
        // because a paused/session-restored track was loaded.
        if (autoPlay && settings.volumeStabilizerEnabled) {
          _maybeAnalyzeReplayGain(t, playbackStarted: true);
        }
        // A player's audio session can persist when its source changes, so a session-ID
        // event alone is not enough to refresh ReplayGain for consecutive tracks.
        final int? activeSessionId = h.player.androidAudioSessionId;
        if (activeSessionId != null && activeSessionId != _audioSessionId) {
          _onSessionId(activeSessionId);
        } else {
          unawaited(_applyAudioEffects());
        }
      }
      _persistSession();
      return true;
    } finally {
      _trackTransitionLoading = false;
      _lastTickMs = 0;
    }
  }

  Future<void> _ensureReplayGain(Track track) {
    if (track.replayGainResolved) return Future<void>.value();
    return _replayGainReads.putIfAbsent(track.id, () async {
      try {
        // File tags remain authoritative. The decoded-audio result is consulted only
        // when neither track nor album ReplayGain gain is present.
        final Map<String, double?> tags = await NativeBridge.readReplayGain(track.id);
        final double? trackGain = tags['trackGainDb'];
        final double? albumGain = tags['albumGainDb'];
        final double? gain = trackGain ?? albumGain;
        if (gain != null) {
          track.replayGainDb = gain;
          track.replayGainPeak = trackGain != null
              ? (tags['trackPeak'] ?? tags['albumPeak'])
              : (tags['albumPeak'] ?? tags['trackPeak']);
          track.replayGainScanAttempted = true;
        } else {
          track.replayGainDb = null;
          track.replayGainPeak = null;
          final Map<String, dynamic>? cached = Storage.loadReplayGainAnalysis(
            trackId: track.id,
            sizeBytes: track.sizeBytes,
            dateModifiedSec: track.dateModifiedSec,
          );
          if (cached != null) {
            track.replayGainScanAttempted = true;
            if (cached['success'] == true) {
              final dynamic cachedGain = cached['gainDb'];
              final dynamic cachedPeak = cached['peak'];
              if (cachedGain is num && cachedGain.isFinite) {
                track.replayGainDb = cachedGain.toDouble();
                track.replayGainPeak = cachedPeak is num && cachedPeak.isFinite
                    ? cachedPeak.toDouble()
                    : null;
              }
            }
          } else {
            track.replayGainScanAttempted = false;
          }
        }
        track.replayGainResolved = true;
      } catch (_) {
        track.replayGainResolved = false;
      } finally {
        _replayGainReads.remove(track.id);
      }
    });
  }

  /// Starts at most one decoder scan at a time. Results are persisted and will be used
  /// on the next playback; the current track is not abruptly re-gained mid-song.
  void _maybeAnalyzeReplayGain(Track track, {bool playbackStarted = false}) {
    if (!settings.volumeStabilizerEnabled ||
        currentTrack?.id != track.id ||
        !track.replayGainResolved ||
        track.replayGainDb != null ||
        track.replayGainScanAttempted) {
      return;
    }
    final bool playingNow = isPlaying || (_handler?.player.playing ?? false);
    if (!playingNow && !playbackStarted) return;

    if (_loudnessScanTrackId != null) {
      return;
    }
    _loudnessScanTrackId = track.id;
    final int scanEpoch = _loudnessScanEpoch;
    unawaited(_runReplayGainAnalysis(track, scanEpoch));
  }

  Future<void> _runReplayGainAnalysis(Track track, int scanEpoch) async {
    try {
      final Map<String, dynamic>? result = await NativeBridge.analyzeLoudness(track.id);
      // A null result is an explicit native cancellation. Never persist that as a failed
      // attempt: enabling the setting later should allow the song to be analyzed.
      if (result == null ||
          scanEpoch != _loudnessScanEpoch ||
          !settings.volumeStabilizerEnabled) {
        track.replayGainScanAttempted = false;
        return;
      }
      final bool success = result['success'] == true;
      final double? gain = result['gainDb'] is num
          ? (result['gainDb'] as num).toDouble()
          : null;
      final double? peak = result['peak'] is num
          ? (result['peak'] as num).toDouble()
          : null;
      final double? integratedLufs = result['integratedLufs'] is num
          ? (result['integratedLufs'] as num).toDouble()
          : null;
      final bool usable = success && gain != null && gain.isFinite && peak != null && peak.isFinite;
      await Storage.saveReplayGainAnalysis(
        trackId: track.id,
        sizeBytes: track.sizeBytes,
        dateModifiedSec: track.dateModifiedSec,
        success: usable,
        gainDb: usable ? gain : null,
        peak: usable ? peak : null,
        integratedLufs: integratedLufs,
      );
      track.replayGainScanAttempted = true;
      if (usable) {
        track.replayGainDb = gain;
        track.replayGainPeak = peak;
        track.replayGainResolved = true;
      }
    } catch (_) {
      // Transient platform/storage errors are not memoized as a completed scan.
      track.replayGainScanAttempted = false;
    } finally {
      if (_loudnessScanTrackId == track.id) _loudnessScanTrackId = null;
      // Prefer the Track instance that is actually playing now. If the previous
      // scan was cancelled while the stabilizer was toggled off and then back on,
      // retry it here instead of waiting for another track change. Use currentTrack
      // directly so this also works if it has just been hidden from the library view.
      final Track? active = currentTrack;
      final bool playingNow = isPlaying || (_handler?.player.playing ?? false);
      if (settings.volumeStabilizerEnabled && playingNow && active != null) {
        _maybeAnalyzeReplayGain(active);
      }
    }
  }

  Future<void> _loadAuxiliarySafely(Track t) async {
    try {
      final String? path = await coverFor(t);
      if (currentTrack?.id != t.id) return;
      currentCoverPath = path;
      if (path != null) {
        _handler?.updateArt(t.id, Uri.file(path));
        palette = await extractPaletteFromFile(path);
      } else {
        palette = ExtractedPalette.defaults;
      }
      if (currentTrack?.id != t.id) return;
      notifyListeners();
      await _loadLyrics(t);
    } catch (_) {
      // Metadata and artwork are optional; failed artwork must never interrupt playback.
      if (currentTrack?.id == t.id) {
        currentCoverPath = null;
        palette = ExtractedPalette.defaults;
        notifyListeners();
      }
    }
  }

  Future<void> chooseExternalLyricsFolder() async {
    final String? selected = await NativeBridge.selectLyricsFolder();
    if (selected == null) return; // Picker was cancelled or Android rejected the grant.
    externalLyricsFolder = selected;
    _lyricsChangeToken = await NativeBridge.getExternalLyricsChangeToken();
    _invalidateLyricsCacheAndReloadActive();
  }

  Future<void> _pollExternalLyricsChanges() async {
    if (_checkingLyricsChangeToken) return;
    _checkingLyricsChangeToken = true;
    try {
      final int token = await NativeBridge.getExternalLyricsChangeToken();
      final int? previous = _lyricsChangeToken;
      _lyricsChangeToken = token;
      if (previous != null && token != previous) {
        _invalidateLyricsCacheAndReloadActive();
      }
    } catch (_) {
      // Monitoring is advisory; lyrics and playback must keep working if storage
      // temporarily denies the content observer or the platform channel is absent.
    } finally {
      _checkingLyricsChangeToken = false;
    }
  }

  void _invalidateLyricsCacheAndReloadActive() {
    _lyricsCacheEpoch++;
    _lyricsTried.clear();
    for (final Track track in _scannedTracks) {
      track.parsedLyrics = null;
    }
    final Track? active = currentTrack;
    active?.parsedLyrics = null;
    if (active != null) unawaited(_loadLyrics(active));
    notifyListeners();
  }

  Future<void> _loadLyrics(Track t) async {
    if (_lyricsTried.contains(t.id) || t.parsedLyrics != null) return;
    _lyricsTried.add(t.id);
    final int loadEpoch = _lyricsCacheEpoch;
    try {
      // An external sibling .lrc is preferred because users can edit it without
      // rewriting the audio file. Native code uses a persisted folder grant on
      // modern Android, where ordinary text files are protected by scoped storage.
      final String? externalText = await NativeBridge.readExternalLyrics(t.id);
      if (loadEpoch != _lyricsCacheEpoch) return;
      if (_applyLyricsText(t, externalText)) return;

      // Keep embedded USLT lyrics as a fallback for tracks without a usable sidecar.
      final bytes = await NativeBridge.readHead(t.id);
      if (loadEpoch != _lyricsCacheEpoch || bytes == null) return;
      final ParsedAudioMetadata meta = parseId3(bytes);
      _applyLyricsText(t, meta.lyrics);
    } catch (_) {
      // Lyrics are optional and must never interrupt playback.
    }
  }

  bool _applyLyricsText(Track track, String? text) {
    if (text == null || !looksLikeLrc(text)) return false;
    final List<LyricLine> parsed = parseLRC(text);
    if (parsed.isEmpty) return false;
    track.parsedLyrics = parsed;
    if (currentTrack?.id == track.id) notifyListeners();
    return true;
  }

  // ------------------------------------------------------------------ playback actions

  /// Android 13+ hides the media notification and lock-screen card until the user
  /// allows notifications, so ask once per session at the first real playback.
  Future<void> _ensureNotificationPermission() async {
    if (notificationsGranted || _notificationPrompted) return;
    _notificationPrompted = true;
    final Map<String, bool> state = await NativeBridge.requestNotificationPermission();
    _applyPermissions(state);
    notifyListeners();
  }

  Future<void> togglePlayPause() async {
    unawaited(_ensureNotificationPermission());
    if (currentTrack == null) {
      if (tracks.isNotEmpty) await selectTrack(tracks.first);
      return;
    }
    final AetherAudioHandler? h = _handler;
    if (h == null) return;
    if (isPlaying) {
      await h.pause();
    } else {
      unawaited(h.play());
    }
  }

  void seekTo(double seconds) {
    _cancelAutoAdvance();
    position.value = seconds;
    final AetherAudioHandler? h = _handler;
    if (h != null) {
      unawaited(h.seek(Duration(milliseconds: (seconds * 1000).round())));
    }
    if (settings.lockscreen.enabled) _lockscreen.push(force: true);
  }

  Future<void> selectTrack(Track track) =>
      _serializeTrackTransition<void>(() => _selectTrackImpl(track));

  Future<void> _selectTrackImpl(Track track) async {
    unawaited(_ensureNotificationPermission());
    final Track? previous = currentTrack;
    final bool loaded = await _startTrack(track, autoPlay: true);
    if (!loaded) return;
    if (previous != null && previous.id != track.id) {
      history = <Track>[previous, ...history.where((Track t) => t.id != previous.id).take(19)];
    }
    final int idx = _scannedTracks.indexWhere((Track t) => t.id == track.id);
    if (idx != -1) {
      final List<Track> following = <Track>[
        ..._scannedTracks.sublist(idx + 1),
        ..._scannedTracks.sublist(0, idx),
      ];
      _replaceQueue(following.where(_isVisibleTrack).toList());
    }
    _persistSession();
    notifyListeners();
  }

  /// Play an item from the visible queue without reconstructing that queue from the
  /// library scan order. If the queue was edited while loading, preserve those edits.
  Future<void> playQueuedTrack(Track track) =>
      _serializeTrackTransition<void>(() => _playQueuedTrackImpl(track));

  Future<void> _playQueuedTrackImpl(Track track) async {
    final List<Track> queuedAtStart = List<Track>.of(queue);
    final int selectedIndex = queuedAtStart.indexWhere((Track t) => t.id == track.id);
    if (selectedIndex < 0) return;
    final int revisionAtStart = _queueRevision;
    final Track? previous = currentTrack;
    final bool loaded = await _startTrack(track, autoPlay: true);
    if (!loaded) return;
    if (previous != null && previous.id != track.id) {
      history = <Track>[previous, ...history.where((Track t) => t.id != previous.id).take(19)];
    }
    if (_queueRevision == revisionAtStart) {
      _replaceQueue(queuedAtStart.skip(selectedIndex + 1).toList());
    } else {
      // A user queue edit made during loading wins over the original snapshot.
      final List<Track> updated = List<Track>.of(queue);
      final int currentIndex = updated.indexWhere((Track t) => t.id == track.id);
      if (currentIndex >= 0) updated.removeAt(currentIndex);
      _replaceQueue(updated);
    }
    _persistSession();
    notifyListeners();
  }

  Future<void> next({
    bool fromEnd = false,
    Duration? autoFade,
    String? expectedTrackId,
  }) => _serializeTrackTransition<void>(
        () => _nextImpl(fromEnd: fromEnd, autoFade: autoFade, expectedTrackId: expectedTrackId),
      );

  Future<void> _nextImpl({
    required bool fromEnd,
    required Duration? autoFade,
    required String? expectedTrackId,
  }) async {
    // Auto-advance callbacks can sit in the serialized lane while a user skips to a
    // different track. Drop the stale callback instead of skipping the new song too.
    if (expectedTrackId != null && currentTrack?.id != expectedTrackId) return;

    final bool fromQueue = queue.isNotEmpty;
    if (!fromQueue && tracks.isEmpty) return;
    if (!fromQueue && fromEnd && repeatMode == AetherRepeatMode.off) {
      _stopAtEnd();
      return;
    }

    final List<Track> candidates = List<Track>.of(fromQueue ? queue : tracks);
    final Track? previous = currentTrack;
    final int queueRevisionAtStart = _queueRevision;
    int observedQueueRevision = queueRevisionAtStart;
    bool queueChangedDuringTransition = false;
    final Set<String> failedIds = <String>{};
    int attempted = 0;
    for (final Track candidate in candidates) {
      if (attempted >= 5) break;
      if (!failedIds.add(candidate.id)) continue;
      attempted++;
      // If a queue item was removed before its turn, respect that user edit.
      if (fromQueue && !queue.any((Track t) => t.id == candidate.id)) continue;

      final bool loaded = await _startTrack(
        candidate,
        autoPlay: true,
        transition: attempted == 1 ? autoFade : null,
      );
      if (_queueRevision != observedQueueRevision) {
        // Once a real queue edit happens during a decoder load, leave the user's
        // chosen ordering alone for the remainder of this transition.
        queueChangedDuringTransition = true;
        observedQueueRevision = _queueRevision;
      }
      if (!loaded) {
        if (fromQueue && !queueChangedDuringTransition) {
          _moveQueuedTrackToEnd(candidate.id);
          observedQueueRevision = _queueRevision;
        }
        continue;
      }

      if (previous != null && previous.id != candidate.id) {
        history = <Track>[previous, ...history.where((Track t) => t.id != previous.id).take(19)];
      }
      if (fromQueue) {
        final List<Track> updated = List<Track>.of(queue);
        final int selectedIndex = updated.indexWhere((Track t) => t.id == candidate.id);
        if (selectedIndex >= 0) updated.removeAt(selectedIndex);
        _replaceQueue(updated);
      } else if (_queueRevision == queueRevisionAtStart && queue.isEmpty) {
        final int playedIndex = tracks.indexWhere((Track t) => t.id == candidate.id);
        if (playedIndex >= 0) _replaceQueue(tracks.skip(playedIndex + 1).toList());
      }
      _persistSession();
      notifyListeners();
      return;
    }

    // Keep unplayable queued items visible (rotated to the end) rather than silently
    // deleting them. If this was natural end-of-track handling, stop cleanly when no
    // candidate could be started; manual Next leaves the current source alone.
    if (fromEnd) {
      _stopAtEnd();
    }
  }

  void _moveQueuedTrackToEnd(String id) {
    final List<Track> updated = List<Track>.of(queue);
    final int index = updated.indexWhere((Track t) => t.id == id);
    if (index < 0 || index == updated.length - 1) return;
    final Track failed = updated.removeAt(index);
    updated.add(failed);
    _replaceQueue(updated);
    _persistSession();
    notifyListeners();
  }

  void _stopAtEnd() {
    final AetherAudioHandler? h = _handler;
    if (h != null) {
      unawaited(h.pause());
    }
    seekTo(0);
    isPlaying = false;
    notifyListeners();
  }

  Future<void> prev() => _serializeTrackTransition<void>(_prevImpl);

  Future<void> _prevImpl() async {
    if (position.value > 3) {
      seekTo(0);
      return;
    }

    final Track? active = currentTrack;
    final List<Track> historyCandidates = history.where(_isVisibleTrack).toList();
    final bool fromHistory = historyCandidates.isNotEmpty;
    List<Track> candidates = historyCandidates;
    if (!fromHistory) {
      // After a cold launch, history is empty. Try preceding visible library tracks
      // in order, so one missing file cannot make Previous appear broken.
      final int activeIndex = tracks.indexWhere((Track t) => t.id == active?.id);
      if (activeIndex >= 0 && tracks.length > 1) {
        candidates = List<Track>.generate(
          tracks.length - 1,
          (int offset) => tracks[(activeIndex - 1 - offset + tracks.length) % tracks.length],
        );
      }
    }

    final List<Track> failedHistory = <Track>[];
    int attempted = 0;
    for (final Track candidate in candidates) {
      if (attempted >= 5) break;
      attempted++;
      final bool loaded = await _startTrack(candidate, autoPlay: true);
      if (!loaded) {
        if (fromHistory) failedHistory.add(candidate);
        continue;
      }

      if (fromHistory) {
        final int selectedIndex = history.indexWhere((Track t) => t.id == candidate.id);
        if (selectedIndex >= 0) {
          final List<Track> remaining = history
              .skip(selectedIndex + 1)
              .where(_isVisibleTrack)
              .where((Track t) => !failedHistory.any((Track failed) => failed.id == t.id))
              .toList();
          history = <Track>[...remaining, ...failedHistory];
        }
      }
      if (active != null && active.id != candidate.id) {
        _replaceQueue(<Track>[active, ...queue.where((Track t) => t.id != active.id)]);
      }
      _persistSession();
      notifyListeners();
      return;
    }
    seekTo(0);
  }

  void toggleShuffle() {
    _invalidatePreload();
    isShuffle = !isShuffle;
    if (isShuffle) {
      final List<Track> shuffled = List<Track>.of(queue);
      shuffled.shuffle(math.Random());
      _replaceQueue(shuffled);
    } else {
      final Track? cur = currentTrack;
      if (cur != null) {
        final List<Track> sequential = _sequentialQueueAfter(cur);
        if (sequential.isNotEmpty) _replaceQueue(sequential);
      }
    }
    _persistSession();
    notifyListeners();
  }

  void toggleRepeat() {
    switch (repeatMode) {
      case AetherRepeatMode.off:
        repeatMode = AetherRepeatMode.all;
        break;
      case AetherRepeatMode.all:
        repeatMode = AetherRepeatMode.one;
        break;
      case AetherRepeatMode.one:
        repeatMode = AetherRepeatMode.off;
        break;
    }
    _persistSession();
    notifyListeners();
  }

  void toggleFavorite(Track track) {
    track.favorite = !track.favorite;
    if (track.favorite) {
      _favorites.add(track.id);
    } else {
      _favorites.remove(track.id);
    }
    Storage.saveFavorites(_favorites);
    notifyListeners();
  }

  // ------------------------------------------------------------------ settings

  Future<void> updateSettings(AppSettings updated) async {
    final AppSettings previous = settings;
    final bool foldersChanged = !_sameStringSet(previous.hiddenFolders, updated.hiddenFolders);
    final bool audioEffectsChanged = previous.eqEnabled != updated.eqEnabled ||
        previous.volumeStabilizerEnabled != updated.volumeStabilizerEnabled ||
        previous.preampDb != updated.preampDb ||
        previous.bassBoost != updated.bassBoost ||
        !_sameDoubleList(previous.eqBandsDb, updated.eqBandsDb);
    final List<double> bands = List<double>.generate(10, (int i) {
      final double v = i < updated.eqBandsDb.length ? updated.eqBandsDb[i] : 0.0;
      return v.clamp(-12.0, 12.0).toDouble();
    });
    settings = updated.copyWith(
      eqBandsDb: bands,
      preampDb: updated.preampDb.clamp(-12.0, 12.0).toDouble(),
      bassBoost: updated.bassBoost.clamp(0, 100).toInt(),
    );
    if (previous.volumeStabilizerEnabled && !settings.volumeStabilizerEnabled) {
      // Invalidate late Dart results first, then cooperatively stop the native decoder.
      _loudnessScanEpoch++;
      await NativeBridge.cancelLoudnessScan();
      final Track? active = currentTrack;
      if (active != null && active.id == _loudnessScanTrackId) {
        active.replayGainScanAttempted = false;
      }
    }
    await Storage.saveSettings(settings);
    if (foldersChanged) {
      _applyFolderVisibility();
    }
    _handler?.updateLockscreenOptions(
      enabled: settings.lockscreenPlayerEnabled,
      showPrevious: settings.lockscreenShowPrevious,
      showNext: settings.lockscreenShowNext,
    );
    _handler?.pauseFade = _pauseFadeDuration();
    notifyListeners();
    if (updated.volumeStabilizerEnabled && !previous.volumeStabilizerEnabled && currentTrack != null) {
      final Track active = currentTrack!;
      await _ensureReplayGain(active);
      if (isPlaying || (_handler?.player.playing ?? false)) {
        _maybeAnalyzeReplayGain(active);
      }
    }
    if (audioEffectsChanged) {
      await _applyAudioEffects();
      final Track? active = currentTrack;
      if (active != null) {
        await _handler?.setActiveTrackVolumeMultiplier(_trackVolumeMultiplier(active));
      }
    }
  }

  bool _sameDoubleList(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool _sameStringSet(List<String> a, List<String> b) {
    final Set<String> first = a.toSet();
    final Set<String> second = b.toSet();
    return first.length == second.length && first.containsAll(second);
  }

  String _normalizeFolder(String folder) => folder
      .replaceAll('\\', '/')
      .replaceAll(RegExp('/+'), '/')
      .replaceAll(RegExp(r'/$'), '')
      .toLowerCase();

  bool _isVisibleTrack(Track track) {
    final String? rawFolder = track.folder;
    if (rawFolder == null || rawFolder.trim().isEmpty) return true;
    final String folder = _normalizeFolder(rawFolder);
    for (final String hiddenPath in settings.hiddenFolders) {
      final String hidden = _normalizeFolder(hiddenPath);
      if (hidden.isNotEmpty && folder == hidden) {
        return false;
      }
    }
    return true;
  }

  void _applyFolderVisibility() {
    tracks = _scannedTracks.where(_isVisibleTrack).toList();
    _replaceQueue(queue.where(_isVisibleTrack).toList());
  }

  Future<void> setFolderHidden(String folder, bool hidden) async {
    final Set<String> folders = settings.hiddenFolders.toSet();
    if (hidden) {
      folders.add(folder);
    } else {
      folders.remove(folder);
    }
    final List<String> sorted = folders.toList()
      ..sort((String a, String b) => a.toLowerCase().compareTo(b.toLowerCase()));
    await updateSettings(settings.copyWith(hiddenFolders: sorted));
    _persistSession();
  }

  double _combinedGainDb(Track track) {
    final double replayGain = settings.volumeStabilizerEnabled ? (track.replayGainDb ?? 0.0) : 0.0;
    final double preamp = settings.eqEnabled ? settings.preampDb : 0.0;
    double total = (replayGain + preamp).clamp(-12.0, 12.0).toDouble();
    if (settings.volumeStabilizerEnabled && track.replayGainDb != null) {
      final double? peak = track.replayGainPeak;
      if (peak != null && peak > 0.0) {
        final double maxSafeDb = -20.0 * (math.log(peak) / math.ln10);
        total = math.min(total, maxSafeDb).toDouble();
      } else {
        // Do not boost above full scale if metadata does not include a usable peak.
        total = math.min(total, 0.0).toDouble();
      }
    }
    return total.clamp(-12.0, 12.0).toDouble();
  }

  double _trackVolumeMultiplier(Track track) {
    final double gainDb = _combinedGainDb(track);
    if (gainDb >= 0.0) return 1.0;
    return math.pow(10.0, gainDb / 20.0).clamp(0.0, 1.0).toDouble();
  }

  Future<void> _prepareAudioEffectsForTrack(int sessionId, Track track) async {
    await NativeBridge.applyAudioEffects(
      sessionId: sessionId,
      bandsDb: settings.eqBandsDb,
      preampDb: settings.preampDb,
      bassBoost: settings.bassBoost,
      enabled: settings.eqEnabled,
      volumeStabilizer: settings.volumeStabilizerEnabled,
      replayGainDb: settings.volumeStabilizerEnabled ? track.replayGainDb : null,
      replayGainPeak: settings.volumeStabilizerEnabled ? track.replayGainPeak : null,
    );
  }

  Future<void> _applyAudioEffects() async {
    final int? sessionId = _audioSessionId;
    if (sessionId == null || sessionId <= 0) return;
    await NativeBridge.applyAudioEffects(
      sessionId: sessionId,
      bandsDb: settings.eqBandsDb,
      preampDb: settings.preampDb,
      bassBoost: settings.bassBoost,
      enabled: settings.eqEnabled,
      volumeStabilizer: settings.volumeStabilizerEnabled,
      replayGainDb: settings.volumeStabilizerEnabled ? currentTrack?.replayGainDb : null,
      replayGainPeak: settings.volumeStabilizerEnabled ? currentTrack?.replayGainPeak : null,
    );
  }

  void setEqualizerBand(int index, double value) {
    if (index < 0 || index >= 10) return;
    final List<double> bands = List<double>.generate(10, (int i) =>
        (i < settings.eqBandsDb.length ? settings.eqBandsDb[i] : 0.0));
    bands[index] = value.clamp(-12.0, 12.0).toDouble();
    unawaited(updateSettings(settings.copyWith(eqBandsDb: bands)));
  }

  void setPreamp(double value) {
    unawaited(updateSettings(settings.copyWith(preampDb: value.clamp(-12.0, 12.0).toDouble())));
  }

  void setBassBoost(int value) {
    unawaited(updateSettings(settings.copyWith(bassBoost: value.clamp(0, 100).toInt())));
  }

  void setEqualizerEnabled(bool value) {
    unawaited(updateSettings(settings.copyWith(eqEnabled: value)));
  }

  void applyEqualizerPreset(String preset) {
    final List<double> bands = List<double>.filled(10, 0);
    switch (preset) {
      case 'Bass':
        bands[0] = 7; bands[1] = 6; bands[2] = 4; bands[7] = -1; bands[8] = 2; bands[9] = 3;
        break;
      case 'Vocal':
        bands[0] = -2; bands[1] = -1; bands[3] = 2; bands[4] = 4; bands[5] = 4; bands[6] = 2;
        break;
      case 'Treble':
        bands[0] = -3; bands[1] = -2; bands[5] = 2; bands[6] = 4; bands[7] = 5; bands[8] = 6; bands[9] = 6;
        break;
      case 'Rock':
        bands[0] = 5; bands[1] = 3; bands[3] = -2; bands[4] = -3; bands[5] = 1; bands[7] = 4; bands[8] = 5;
        break;
      default:
        break;
    }
    unawaited(updateSettings(settings.copyWith(eqBandsDb: bands)));
  }

  // Queue operations are centralized here so every edit is persisted.
  void addToQueue(Track track) {
    _invalidatePreload();
    _replaceQueue(<Track>[...queue.where((Track t) => t.id != track.id), track]);
    _persistSession();
    notifyListeners();
  }

  void playNext(Track track) {
    _invalidatePreload();
    _replaceQueue(<Track>[track, ...queue.where((Track t) => t.id != track.id)]);
    _persistSession();
    notifyListeners();
  }

  void removeQueuedTrack(String id) {
    _invalidatePreload();
    _replaceQueue(queue.where((Track t) => t.id != id).toList());
    _persistSession();
    notifyListeners();
  }

  void reorderQueue(int oldIndex, int newIndex) {
    _invalidatePreload();
    if (oldIndex < 0 || oldIndex >= queue.length || newIndex < 0 || newIndex > queue.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final List<Track> reordered = List<Track>.of(queue);
    final Track item = reordered.removeAt(oldIndex);
    reordered.insert(newIndex.clamp(0, reordered.length).toInt(), item);
    _replaceQueue(reordered);
    _persistSession();
    notifyListeners();
  }

  void clearQueue() {
    _invalidatePreload();
    _replaceQueue(<Track>[]);
    _persistSession();
    notifyListeners();
  }


  void cycleVisualizer() {
    const List<VisualizerStyle> styles = VisualizerStyle.values;
    final int nextIndex = (styles.indexOf(settings.visualizerStyle) + 1) % styles.length;
    updateSettings(settings.copyWith(visualizerStyle: styles[nextIndex]));
  }

  void addTracksToQueue(Iterable<Track> list) {
    _invalidatePreload();
    final Set<String> ids = list.map((Track t) => t.id).toSet();
    _replaceQueue(<Track>[...queue.where((Track t) => !ids.contains(t.id)), ...list]);
    _persistSession();
    notifyListeners();
  }

  // ------------------------------------------------------------------ playlists

  Playlist? playlistById(String id) {
    for (final Playlist p in playlists) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Playlist tracks that exist in the (visible) library, in playlist order.
  List<Track> tracksOf(Playlist playlist) {
    final Map<String, Track> byId = <String, Track>{for (final Track t in tracks) t.id: t};
    return <Track>[
      for (final String id in playlist.trackIds)
        if (byId[id] != null) byId[id]!,
    ];
  }

  Future<Playlist> createPlaylist(String name, {Iterable<String> trackIds = const <String>[]}) async {
    final String clean = name.trim().isEmpty ? 'New playlist' : name.trim();
    final Playlist p = Playlist(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: clean,
      trackIds: trackIds.toSet().toList(),
    );
    playlists = <Playlist>[...playlists, p];
    await Storage.savePlaylists(playlists);
    notifyListeners();
    return p;
  }

  Future<void> renamePlaylist(String id, String name) async {
    final Playlist? p = playlistById(id);
    final String clean = name.trim();
    if (p == null || clean.isEmpty) return;
    p.name = clean;
    await Storage.savePlaylists(playlists);
    notifyListeners();
  }

  Future<void> deletePlaylist(String id) async {
    playlists = playlists.where((Playlist p) => p.id != id).toList();
    await Storage.savePlaylists(playlists);
    notifyListeners();
  }

  /// Adds the tracks that are not in the playlist yet and returns how many were added.
  Future<int> addTracksToPlaylist(String id, Iterable<String> trackIds) async {
    final Playlist? p = playlistById(id);
    if (p == null) return 0;
    final Set<String> existing = p.trackIds.toSet();
    int added = 0;
    for (final String tid in trackIds) {
      if (existing.add(tid)) {
        p.trackIds.add(tid);
        added++;
      }
    }
    if (added > 0) {
      await Storage.savePlaylists(playlists);
      notifyListeners();
    }
    return added;
  }

  Future<void> removeTracksFromPlaylist(String id, Iterable<String> trackIds) async {
    final Playlist? p = playlistById(id);
    if (p == null) return;
    final Set<String> drop = trackIds.toSet();
    p.trackIds.removeWhere(drop.contains);
    await Storage.savePlaylists(playlists);
    notifyListeners();
  }

  /// Stores a new order for the visible tracks; ids of missing files stay at the end.
  Future<void> setPlaylistOrder(String id, List<String> orderedVisibleIds) async {
    final Playlist? p = playlistById(id);
    if (p == null) return;
    final Set<String> visible = orderedVisibleIds.toSet();
    final List<String> missing = p.trackIds.where((String t) => !visible.contains(t)).toList();
    p.trackIds
      ..clear()
      ..addAll(orderedVisibleIds)
      ..addAll(missing);
    await Storage.savePlaylists(playlists);
    notifyListeners();
  }

  /// Plays a playlist from [startWith] (or its first track). Following tracks go to the
  /// queue in playlist order, wrapping around, or in random order when [shuffle] is set.
  Future<void> playPlaylist(Playlist playlist, {bool shuffle = false, Track? startWith}) =>
      _serializeTrackTransition<void>(
        () => _playPlaylistImpl(playlist, shuffle: shuffle, startWith: startWith),
      );

  Future<void> _playPlaylistImpl(Playlist playlist, {required bool shuffle, required Track? startWith}) async {
    final List<Track> list = tracksOf(playlist);
    if (list.isEmpty) return;
    unawaited(_ensureNotificationPermission());
    final List<Track> order = List<Track>.of(list);
    if (shuffle) order.shuffle(math.Random());
    final Track first = startWith ?? order.first;
    final int idx = order.indexWhere((Track t) => t.id == first.id);
    final Track? previous = currentTrack;
    final bool loaded = await _startTrack(first, autoPlay: true);
    if (!loaded) return;
    if (previous != null && previous.id != first.id) {
      history = <Track>[previous, ...history.where((Track t) => t.id != previous.id).take(19)];
    }
    if (idx == -1) {
      _replaceQueue(order);
    } else {
      _replaceQueue(<Track>[...order.sublist(idx + 1), ...order.sublist(0, idx)]);
    }
    _persistSession();
    notifyListeners();
  }

  // ------------------------------------------------------------------ sleep timer

  void setSleepTimer(int? minutes) {
    if (minutes == null) {
      updateSettings(settings.copyWith(clearSleep: true));
    } else {
      final int end = DateTime.now().millisecondsSinceEpoch + minutes * 60 * 1000;
      updateSettings(settings.copyWith(sleepTimerMinutes: minutes, sleepTimerEndTime: end));
    }
    _syncSleepTimer();
  }

  void _syncSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    final int? end = settings.sleepTimerEndTime;
    if (end == null) {
      if (sleepTimeRemaining != null) {
        sleepTimeRemaining = null;
        notifyListeners();
      }
      return;
    }
    _tickSleep(end);
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (Timer _) {
      final int? e = settings.sleepTimerEndTime;
      if (e == null) {
        _sleepTimer?.cancel();
        return;
      }
      _tickSleep(e);
    });
  }

  void _tickSleep(int endMs) {
    final int remaining = math.max(0, ((endMs - DateTime.now().millisecondsSinceEpoch) / 1000).floor());
    sleepTimeRemaining = remaining;
    final AetherAudioHandler? h = _handler;
    if (remaining <= 20 && remaining > 0 && h != null) {
      unawaited(h.setPlayerVolume(remaining / 20));
    }
    if (remaining == 0) {
      _sleepTimer?.cancel();
      if (h != null) {
        unawaited(h.pause());
        unawaited(h.setPlayerVolume(1.0));
      }
      sleepTimeRemaining = null;
      updateSettings(settings.copyWith(clearSleep: true));
    }
    notifyListeners();
  }

  // ------------------------------------------------------------------ persistence

  String _dayKey() {
    final DateTime n = DateTime.now();
    final String m = n.month.toString().padLeft(2, '0');
    final String d = n.day.toString().padLeft(2, '0');
    return '${n.year}-$m-$d';
  }

  void _persistSession() {
    final Track? cur = currentTrack;
    if (cur != null) {
      Storage.saveSession(<String, dynamic>{
        'trackId': cur.id,
        'positionMs': (position.value * 1000).round(),
        'queue': queue.map((Track t) => t.id).toList(),
        'history': history.map((Track t) => t.id).toList(),
        'shuffle': isShuffle,
        'repeat': repeatMode.name,
      });
    }
    if (_pendingListenMs > 0 && cur != null && _currentTrackQualified) {
      final int ms = _pendingListenMs;
      _pendingListenMs = 0;
      // This updates the in-memory aggregate only; disk writes are batched.
      Storage.addListening(cur.id, _dayKey(), ms);
      notifyListeners();
    }
    // If the track is still unqualified, retain its pending listen time in memory.
    // When it reaches 50%, the whole listen becomes eligible; switching tracks
    // resets this value in _startTrack, so short skips never reach persistent stats.
  }

  Future<void> _flushPlayCounts() async {
    if (!_playCountsDirty) return;
    final Map<String, int> snapshot = Map<String, int>.of(_playCounts);
    _playCountsDirty = false;
    try {
      await Storage.savePlayCounts(snapshot);
    } catch (_) {
      // Retry at the next checkpoint if SharedPreferences reports a write failure.
      _playCountsDirty = true;
    }
  }

  @override
  void dispose() {
    for (final StreamSubscription<dynamic> s in _subs) {
      s.cancel();
    }
    _persistTimer?.cancel();
    _persistSession();
    unawaited(_flushPlayCounts());
    unawaited(Storage.flushListeningStats());
    _sleepTimer?.cancel();
    _advanceTimer?.cancel();
    _stopLyricsMonitor();
    _lockscreen.dispose();
    WidgetsBinding.instance.removeObserver(this);
    position.dispose();
    uiForeground.dispose();
    super.dispose();
  }
}
