import 'dart:async';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/track.dart';

/// Background handler for Android MediaSession, notification and lock-screen controls.
/// Source changes are serialized so rapid library taps cannot race each other.
///
/// Two [AudioPlayer]s are used so that tracks can really overlap:
///  * the *active* player owns everything the rest of the app sees (position,
///    state, duration, audio session, media notification);
///  * the *idle* player pre-loads the next track (gapless) and, during a fade,
///    becomes the active one while the old active player keeps playing and fades out.
///
/// Important: a track change must never flip the published `playing` flag to false.
/// audio_service leaves foreground mode when `playing` turns false and has to call
/// startForeground again when it turns true. When the next song starts on its own
/// (screen off, app in background) Android 12+ refuses that second startForeground
/// call and kills the app. The incoming player therefore starts playing *before* it
/// is published as the active player, and events of the idle/outgoing player are
/// never forwarded.
class AetherAudioHandler extends BaseAudioHandler with SeekHandler {
  AetherAudioHandler() {
    _positionPublishTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (player.playing) _publishState();
    });
    for (final AudioPlayer p in <AudioPlayer>[_playerA, _playerB]) {
      _subs.add(p.playbackEventStream.listen(
        (PlaybackEvent event) {
          if (identical(p, _active)) playbackState.add(_transformEvent(event));
        },
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('Krypton playback stream error: $error');
        },
      ));
      // Some devices emit playing/paused transitions on playerStateStream before
      // a new detailed PlaybackEvent. Mirror those transitions so notification
      // Play/Pause controls stay in sync with the audio engine.
      _subs.add(p.playerStateStream.listen(
        (PlayerState state) {
          if (!identical(p, _active)) return;
          _publishState();
          _stateCtl.add(state);
        },
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('Krypton player-state stream error: $error');
        },
      ));
      _subs.add(p.positionStream.listen(
        (Duration d) {
          if (identical(p, _active)) _positionCtl.add(d);
        },
        onError: (Object error, StackTrace stackTrace) {},
      ));
      _subs.add(p.durationStream.listen(
        (Duration? d) {
          if (identical(p, _active)) _durationCtl.add(d);
        },
        onError: (Object error, StackTrace stackTrace) {},
      ));
      _subs.add(p.androidAudioSessionIdStream.listen(
        (int? id) {
          if (identical(p, _active)) _sessionCtl.add(id);
        },
        onError: (Object error, StackTrace stackTrace) {},
      ));
    }
  }

  final AudioPlayer _playerA = AudioPlayer();
  final AudioPlayer _playerB = AudioPlayer();
  late AudioPlayer _active = _playerA;
  final List<StreamSubscription<dynamic>> _subs = <StreamSubscription<dynamic>>[];
  late final Timer _positionPublishTimer;

  /// The player the rest of the app talks to. Changes when a fade or a gapless switch happens.
  AudioPlayer get player => _active;
  AudioPlayer get _idle => identical(_active, _playerA) ? _playerB : _playerA;

  // Streams of the *active* player only (a plain player getter would go stale on swap).
  final StreamController<Duration> _positionCtl = StreamController<Duration>.broadcast();
  final StreamController<PlayerState> _stateCtl = StreamController<PlayerState>.broadcast();
  final StreamController<Duration?> _durationCtl = StreamController<Duration?>.broadcast();
  final StreamController<int?> _sessionCtl = StreamController<int?>.broadcast();
  Stream<Duration> get positionStream => _positionCtl.stream;
  Stream<PlayerState> get playerStateStream => _stateCtl.stream;
  Stream<Duration?> get durationStream => _durationCtl.stream;
  Stream<int?> get androidAudioSessionIdStream => _sessionCtl.stream;

  Future<void> Function()? onSkipNext;
  Future<void> Function()? onSkipPrevious;

  bool _lockscreenEnabled = true;
  bool _showPrevious = true;
  bool _showNext = true;
  int _loadGeneration = 0;
  int _rampEpoch = 0;
  int _pauseEpoch = 0;

  /// Length of the fade when pausing/resuming; zero disables it.
  Duration pauseFade = Duration.zero;
  double _targetVolume = 1.0;
  final Map<AudioPlayer, double> _trackVolumeMultipliers = <AudioPlayer, double>{};
  Future<void> _loadTail = Future<void>.value();

  /// Outgoing player that is still audible while a fade is running.
  AudioPlayer? _lingering;

  /// Uri of the track the idle player has loaded and paused at 0:00, ready to start instantly.
  String? _preloadedUri;

  /// Artwork can arrive before or after the MediaItem of its track is published.
  /// Remember it per track so it is never lost when the MediaItem is replaced.
  final Map<String, Uri> _artCache = <String, Uri>{};

  void _publishState() {
    playbackState.add(_transformEvent(player.playbackEvent));
  }

  /// Controls the set of actions exposed to Android's system media controls.
  /// Android still decides the exact appearance and layout of the lock-screen card.
  void updateLockscreenOptions({
    required bool enabled,
    required bool showPrevious,
    required bool showNext,
  }) {
    _lockscreenEnabled = enabled;
    _showPrevious = showPrevious;
    _showNext = showNext;
    _publishState();
  }

  /// Resolves to true only when this request loaded its source. A superseded request
  /// returns false so the controller does not consume its queue entry as a success.
  ///
  /// [transition] is the fade length. With a fade (or a pre-loaded next track) the
  /// new track starts on the idle player while the current one keeps playing.
  Future<bool> loadTrack(
    Track track, {
    required bool autoPlay,
    Duration start = Duration.zero,
    Uri? artUri,
    Duration transition = Duration.zero,
    double replayGainMultiplier = 1.0,
    Future<void> Function(int sessionId, Track track)? prepareSessionEffects,
  }) {
    final int generation = ++_loadGeneration;
    final Future<bool> operation = _loadTail.then<bool>(
      (_) => _loadTrackImpl(
        generation,
        track,
        autoPlay: autoPlay,
        start: start,
        artUri: artUri,
        transition: transition,
        replayGainMultiplier: replayGainMultiplier,
        prepareSessionEffects: prepareSessionEffects,
      ),
    );
    _loadTail = operation.then<void>(
      (bool _) {},
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Krypton track-load queue error: $error');
      },
    );
    return operation;
  }

  /// Loads [track] on the idle player (paused) so the next switch has no loading gap.
  Future<void> preload(
    Track track, {
    double replayGainMultiplier = 1.0,
    Future<void> Function(int sessionId, Track track)? prepareSessionEffects,
  }) {
    final Future<void> operation = _loadTail.then<void>(
      (_) => _preloadImpl(
        track,
        replayGainMultiplier: replayGainMultiplier,
        prepareSessionEffects: prepareSessionEffects,
      ),
    );
    _loadTail = operation.then<void>((_) {}, onError: (Object error, StackTrace stackTrace) {});
    return operation;
  }

  Future<void> _preloadImpl(
    Track track, {
    double replayGainMultiplier = 1.0,
    Future<void> Function(int sessionId, Track track)? prepareSessionEffects,
  }) async {
    final Uri? uri = Uri.tryParse(track.uri);
    if (uri == null || uri.scheme.isEmpty) return;
    if (_preloadedUri == track.uri) return;
    // The idle player is still fading out the previous track.
    if (_lingering != null) return;
    final AudioPlayer target = _idle;
    try {
      _preloadedUri = null;
      await target.setAudioSource(AudioSource.uri(uri)).timeout(const Duration(seconds: 20));
      _trackVolumeMultipliers[target] = _safeVolumeMultiplier(replayGainMultiplier);
      final int? sessionId = target.androidAudioSessionId;
      if (sessionId != null) await prepareSessionEffects?.call(sessionId, track);
      await target.setVolume(0);
      _preloadedUri = track.uri;
    } catch (error) {
      _preloadedUri = null;
      debugPrint('Krypton could not pre-load ${track.uri}: $error');
    }
  }

  void _publishMediaItem(Track track, Uri? artUri) {
    final Uri? art = artUri ?? _artCache[track.id];
    mediaItem.add(
      MediaItem(
        id: track.uri,
        title: track.title.isNotEmpty ? track.title : 'Unknown track',
        artist: track.artist.isNotEmpty ? track.artist : 'Unknown artist',
        album: track.album.isNotEmpty ? track.album : 'Krypton m.Player',
        duration: Duration(milliseconds: (track.duration * 1000).round()),
        artUri: art,
        extras: <String, dynamic>{'trackId': track.id},
      ),
    );
  }

  Future<bool> _loadTrackImpl(
    int generation,
    Track track, {
    required bool autoPlay,
    required Duration start,
    required Uri? artUri,
    required Duration transition,
    required double replayGainMultiplier,
    Future<void> Function(int sessionId, Track track)? prepareSessionEffects,
  }) async {
    final Uri? sourceUri = Uri.tryParse(track.uri);
    if (sourceUri == null || sourceUri.scheme.isEmpty) {
      debugPrint('Krypton skipped invalid audio URI for ${track.id}');
      return false;
    }
    if (generation != _loadGeneration) return false;

    // A pause/resume fade that is still running must not touch the new track.
    _pauseEpoch++;
    // A previous fade is cut short: its outgoing track stops now, whatever level it had.
    _rampEpoch++;
    await _stopLingering();
    if (generation != _loadGeneration) return false;

    // Overlap only when something is audibly playing right now. After a natural end
    // the player is in the completed state and there is nothing left to fade out.
    final bool audible = _active.playing && _active.processingState == ProcessingState.ready;
    final bool preloaded = _preloadedUri == track.uri && start == Duration.zero;
    final bool overlap = autoPlay && audible && (transition.inMilliseconds > 0 || preloaded);
    try {
      if (overlap) {
        return await _overlapTo(
          generation,
          track,
          sourceUri,
          artUri: artUri,
          start: start,
          transition: transition,
          preloaded: preloaded,
          replayGainMultiplier: replayGainMultiplier,
          prepareSessionEffects: prepareSessionEffects,
        );
      }

      // Publish metadata before preparing the decoder so the media notification
      // and the lock-screen card can render the new track immediately.
      _publishMediaItem(track, artUri);

      // No pause() here on purpose: see the class comment. Do not replace the
      // player's previous gain until the new source has loaded successfully.
      await _active
          .setAudioSource(
            AudioSource.uri(sourceUri),
            initialPosition: start,
          )
          .timeout(const Duration(seconds: 20));
      if (generation != _loadGeneration) return false;
      _trackVolumeMultipliers[_active] = _safeVolumeMultiplier(replayGainMultiplier);
      final int? sessionId = _active.androidAudioSessionId;
      if (sessionId != null) await prepareSessionEffects?.call(sessionId, track);
      if (generation != _loadGeneration) return false;

      await _active.setVolume(_volumeFor(_active));
      if (autoPlay) {
        // Returns immediately when the player is already in the playing state.
        _playSafely();
      } else if (_active.playing) {
        // Restoring a saved session: keep the player paused.
        await _active.pause();
      }
      _publishState();
      return true;
    } catch (error, stackTrace) {
      debugPrint('Krypton could not load ${track.uri}: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (generation == _loadGeneration) {
        try {
          await _active.setVolume(_volumeFor(_active));
        } catch (_) {}
      }
      // Source failures are contained here so a bad or removed file cannot crash the app.
      // Do not report a request that was superseded mid-load as a success.
      return false;
    }
  }

  /// Starts [track] on the idle player and hands the active role over to it.
  /// With a fade the old track keeps playing underneath and fades out while the new
  /// one fades in; without one the pre-loaded track simply takes over (gapless).
  Future<bool> _overlapTo(
    int generation,
    Track track,
    Uri sourceUri, {
    required Uri? artUri,
    required Duration start,
    required Duration transition,
    required bool preloaded,
    required double replayGainMultiplier,
    Future<void> Function(int sessionId, Track track)? prepareSessionEffects,
  }) async {
    final AudioPlayer outgoing = _active;
    final AudioPlayer incoming = _idle;
    final int rampMs = transition.inMilliseconds;
    final bool ready = preloaded && incoming.processingState == ProcessingState.ready;
    if (!ready) {
      await incoming
          .setAudioSource(AudioSource.uri(sourceUri), initialPosition: start)
          .timeout(const Duration(seconds: 20));
    }
    _preloadedUri = null;
    if (generation != _loadGeneration) return false;
    _trackVolumeMultipliers[incoming] = _safeVolumeMultiplier(replayGainMultiplier);
    final int? sessionId = incoming.androidAudioSessionId;
    if (sessionId != null) await prepareSessionEffects?.call(sessionId, track);
    if (generation != _loadGeneration) return false;

    await incoming.setVolume(rampMs > 0 ? 0 : _volumeFor(incoming));
    final double outgoingStart = outgoing.volume;
    _publishMediaItem(track, artUri);

    // Start first, publish second: `playing` is set synchronously by play(), so the
    // published state never drops to false during the hand-over.
    unawaited(incoming.play().catchError((Object error, StackTrace stackTrace) {
      debugPrint('Krypton playback failed: $error');
    }));
    _lingering = outgoing;
    _activate(incoming);

    final int epoch = ++_rampEpoch;
    unawaited(_rampAndFinish(epoch, outgoing, incoming, outgoingStart, rampMs));
    return true;
  }

  void _activate(AudioPlayer p) {
    _active = p;
    _stateCtl.add(p.playerState);
    _durationCtl.add(p.duration);
    _sessionCtl.add(p.androidAudioSessionId);
    _positionCtl.add(p.position);
    _publishState();
  }

  Future<void> _rampAndFinish(int epoch, AudioPlayer outgoing, AudioPlayer incoming, double outgoingStart, int rampMs) async {
    try {
      if (rampMs > 0) {
        final Stopwatch watch = Stopwatch()..start();
        while (epoch == _rampEpoch) {
          final double t = (watch.elapsedMilliseconds / rampMs).clamp(0.0, 1.0).toDouble();
          // Equal-power curves keep the perceived loudness steady through the overlap.
          final double outVolume = (outgoingStart * math.cos(t * math.pi / 2)).clamp(0.0, 1.0).toDouble();
          final double inVolume = (_volumeFor(incoming) * math.sin(t * math.pi / 2)).clamp(0.0, 1.0).toDouble();
          await Future.wait(<Future<void>>[outgoing.setVolume(outVolume), incoming.setVolume(inVolume)]);
          if (t >= 1.0) break;
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
      }
      // A newer request or a pause took over and already cleaned up.
      if (epoch != _rampEpoch) return;
      await incoming.setVolume(_volumeFor(incoming));
      await _stopLingering();
    } catch (error) {
      debugPrint('Krypton fade failed: $error');
      if (epoch == _rampEpoch) {
        await _stopLingering();
      }
    }
  }

  Future<void> _stopLingering() async {
    final AudioPlayer? p = _lingering;
    _lingering = null;
    if (p == null) return;
    try {
      await p.stop();
    } catch (_) {}
    _trackVolumeMultipliers.remove(p);
  }

  void _playSafely() {
    unawaited(_active.play().catchError((Object error, StackTrace stackTrace) {
      debugPrint('Krypton playback failed: $error');
    }));
  }

  /// Attaches artwork to the track it belongs to, whether or not that track's
  /// MediaItem has been published yet.
  void updateArt(String trackId, Uri? art) {
    if (art == null) return;
    _artCache[trackId] = art;
    final MediaItem? current = mediaItem.value;
    if (current != null && current.extras?['trackId'] == trackId) {
      mediaItem.add(current.copyWith(artUri: art));
    }
  }

  Future<void> setPlayerVolume(double volume) async {
    _targetVolume = volume.clamp(0.0, 1.0).toDouble();
    // While a fade runs, its ramp follows _targetVolume itself.
    if (_lingering != null) return;
    try {
      await _active.setVolume(_volumeFor(_active));
    } catch (error) {
      debugPrint('Krypton could not set volume: $error');
    }
  }

  /// Recomputes negative-gain attenuation after ReplayGain, EQ preamp or settings change.
  Future<void> setActiveTrackVolumeMultiplier(double multiplier) async {
    _trackVolumeMultipliers[_active] = _safeVolumeMultiplier(multiplier);
    // During a crossfade the ramp applies the current multiplier on its next frame.
    if (_lingering != null) return;
    try {
      await _active.setVolume(_volumeFor(_active));
    } catch (error) {
      debugPrint('Krypton could not update track gain: $error');
    }
  }

  double _safeVolumeMultiplier(double value) => value.isFinite ? value.clamp(0.0, 1.0).toDouble() : 1.0;

  double _volumeFor(AudioPlayer player) =>
      (_targetVolume * (_trackVolumeMultipliers[player] ?? 1.0)).clamp(0.0, 1.0).toDouble();

  @override
  Future<void> play() async {
    try {
      final int epoch = ++_pauseEpoch;
      final int ms = pauseFade.inMilliseconds;
      if (ms > 0 && !_active.playing && _lingering == null) {
        // Start silent and fade in. `playing` flips to true right away, so the
        // notification state is not delayed by the fade.
        await _active.setVolume(0);
        _playSafely();
        _publishState();
        await _fadeVolume(_active, 0, ms, epoch);
        if (epoch == _pauseEpoch) await _active.setVolume(_volumeFor(_active));
        return;
      }
      _playSafely();
      _publishState();
    } catch (error) {
      debugPrint('Krypton play action failed: $error');
    }
  }

  @override
  Future<void> pause() async {
    try {
      final int epoch = ++_pauseEpoch;
      // Pausing in the middle of a fade ends the fade: the old track is dropped
      // and the new one continues at full level when playback resumes.
      if (_lingering != null) {
        _rampEpoch++;
        await _stopLingering();
        await _active.setVolume(_volumeFor(_active));
      }
      final int ms = pauseFade.inMilliseconds;
      if (ms > 0 && _active.playing && _active.processingState == ProcessingState.ready) {
        await _fadeVolume(_active, _targetVolume, ms, epoch, fadeOut: true);
        // Resumed or switched track while fading out: that request owns playback now.
        if (epoch != _pauseEpoch) return;
      }
      await _active.pause();
      // Back to full level so the next start (also from a notification) is not silent.
      await _active.setVolume(_volumeFor(_active));
      _publishState();
    } catch (error) {
      debugPrint('Krypton pause action failed: $error');
    }
  }

  /// Linear ramp between silence and the target volume. Fade-out starts from the
  /// current level, fade-in ends at the (live) target level.
  Future<void> _fadeVolume(AudioPlayer p, double from, int ms, int epoch, {bool fadeOut = false}) async {
    final Stopwatch watch = Stopwatch()..start();
    final double start = fadeOut ? p.volume : from;
    while (epoch == _pauseEpoch) {
      final double t = (watch.elapsedMilliseconds / ms).clamp(0.0, 1.0).toDouble();
      final double end = fadeOut ? 0.0 : _volumeFor(p);
      await p.setVolume((start + (end - start) * t).clamp(0.0, 1.0).toDouble());
      if (t >= 1.0) break;
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
  }

  @override
  Future<void> seek(Duration position) async {
    try {
      await _active.seek(position);
    } catch (error) {
      debugPrint('Krypton seek action failed: $error');
    }
  }

  @override
  Future<void> stop() async {
    _loadGeneration++;
    _rampEpoch++;
    _preloadedUri = null;
    await _stopLingering();
    try {
      await _active.stop();
    } catch (_) {}
    try {
      await _idle.stop();
    } catch (_) {}
    try {
      await _active.setVolume(_volumeFor(_active));
    } catch (_) {}
    _trackVolumeMultipliers.clear();
    await super.stop();
  }

  @override
  Future<void> skipToNext() async {
    final Future<void> Function()? callback = onSkipNext;
    if (callback == null) return;
    try {
      await callback();
    } catch (error) {
      debugPrint('Krypton skip-next action failed: $error');
    }
  }

  @override
  Future<void> skipToPrevious() async {
    final Future<void> Function()? callback = onSkipPrevious;
    if (callback == null) return;
    try {
      await callback();
    } catch (error) {
      debugPrint('Krypton skip-previous action failed: $error');
    }
  }

  PlaybackState _transformEvent(PlaybackEvent event) {
    AudioProcessingState processing;
    switch (event.processingState) {
      case ProcessingState.idle:
        processing = AudioProcessingState.idle;
        break;
      case ProcessingState.loading:
        processing = AudioProcessingState.loading;
        break;
      case ProcessingState.buffering:
        processing = AudioProcessingState.buffering;
        break;
      case ProcessingState.ready:
        processing = AudioProcessingState.ready;
        break;
      case ProcessingState.completed:
        processing = AudioProcessingState.completed;
        break;
    }

    if (!_lockscreenEnabled) {
      // Keep the real playing/processing state so Android never thinks the service
      // has stopped; only remove the transport actions from the lock-screen session.
      return PlaybackState(
        controls: const <MediaControl>[],
        systemActions: const <MediaAction>{},
        androidCompactActionIndices: const <int>[],
        processingState: processing,
        playing: player.playing,
        updatePosition: player.position,
        updateTime: DateTime.now(),
        bufferedPosition: player.bufferedPosition,
        speed: player.speed,
      );
    }

    final List<MediaControl> controls = <MediaControl>[];
    final List<int> compactIndices = <int>[];
    if (_showPrevious) {
      compactIndices.add(controls.length);
      controls.add(MediaControl.skipToPrevious);
    }
    compactIndices.add(controls.length);
    controls.add(player.playing ? MediaControl.pause : MediaControl.play);
    if (_showNext) {
      compactIndices.add(controls.length);
      controls.add(MediaControl.skipToNext);
    }

    return PlaybackState(
      controls: controls,
      systemActions: const <MediaAction>{
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: compactIndices.take(3).toList(),
      processingState: processing,
      playing: player.playing,
      updatePosition: player.position,
      updateTime: DateTime.now(),
      bufferedPosition: player.bufferedPosition,
      speed: player.speed,
    );
  }

  @override
  Future<void> onTaskRemoved() async {
    // Leave playback alive; Android media controls and the audio foreground service
    // own the background lifetime, not the Flutter activity.
    await super.onTaskRemoved();
  }

  Future<void> disposeHandler() async {
    _positionPublishTimer.cancel();
    for (final StreamSubscription<dynamic> sub in _subs) {
      await sub.cancel();
    }
    await _positionCtl.close();
    await _stateCtl.close();
    await _durationCtl.close();
    await _sessionCtl.close();
    await _playerA.dispose();
    await _playerB.dispose();
  }
}
