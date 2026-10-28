import 'dart:async';

import 'package:flutter/services.dart';

import '../models/lockscreen_settings.dart';
import '../models/track.dart';
import '../state/player_controller.dart';
import '../utils/lrc_parser.dart';
import 'native_bridge.dart';

/// Keeps the native Screenlock KRY player (LockScreenActivity.kt) in sync with the
/// Dart player, and executes the transport commands it sends back.
///
/// State only goes native when something it displays changes; the playback
/// position travels as a snapshot and is extrapolated natively, so no per-tick
/// traffic is needed. A slow timer re-syncs any drift.
class LockscreenService {
  LockscreenService(this._c);

  final PlayerController _c;
  Timer? _timer;
  String _signature = '';

  void attach() {
    NativeBridge.setCommandHandler(_onCall);
    _c.addListener(_onChanged);
    _timer = Timer.periodic(const Duration(seconds: 10), (Timer _) {
      if (_c.settings.lockscreen.enabled) push(force: true);
    });
    push(force: true);
  }

  void dispose() {
    _timer?.cancel();
    _c.removeListener(_onChanged);
  }

  void _onChanged() => push();

  void push({bool force = false}) {
    final LockscreenSettings ls = _c.settings.lockscreen;
    final Track? t = _c.currentTrack;
    final List<LyricLine> lyricLines = t?.parsedLyrics ?? const <LyricLine>[];
    final List<String> queueTitles = _c.queue.take(6).map((Track q) => q.title).toList();
    final String repeat = _c.repeatMode.name;
    final int accent = _c.accentColor.toARGB32();

    final String signature = !ls.enabled
        ? 'off'
        : '${t?.id}|${_c.isPlaying}|${_c.duration}|${t?.favorite}|${_c.isShuffle}|$repeat|'
            '${_c.currentCoverPath}|$accent|${lyricLines.length}|${queueTitles.join('\u0001')}|${ls.toNative()}';
    if (!force && signature == _signature) return;
    _signature = signature;

    if (!ls.enabled) {
      unawaited(NativeBridge.syncLockscreen(<String, dynamic>{'enabled': false, 'hasTrack': false}));
      return;
    }

    final double durationSec = _c.duration > 0 ? _c.duration : (t?.duration ?? 0);
    unawaited(NativeBridge.syncLockscreen(<String, dynamic>{
      'enabled': true,
      'opts': ls.toNative(),
      'hasTrack': t != null,
      'playing': _c.isPlaying,
      'title': t?.title ?? '',
      'artist': t?.artist ?? '',
      'album': t?.album ?? '',
      'coverPath': _c.currentCoverPath,
      'accent': accent,
      'favorite': t?.favorite ?? false,
      'shuffle': _c.isShuffle,
      'repeat': repeat,
      'positionMs': (_c.position.value * 1000).round(),
      'durationMs': (durationSec * 1000).round(),
      'lyrics': <List<Object>>[
        for (final LyricLine l in lyricLines.take(600)) <Object>[l.time, l.text],
      ],
      'queue': queueTitles,
    }));
  }

  Future<dynamic> _onCall(MethodCall call) async {
    if (call.method != 'lockCommand') return null;
    final dynamic raw = call.arguments;
    final Map<dynamic, dynamic> args = raw is Map ? raw : const <dynamic, dynamic>{};
    final String name = '${args['name']}';
    final dynamic value = args['value'];
    final Track? t = _c.currentTrack;
    switch (name) {
      case 'playPause':
        await _c.togglePlayPause();
      case 'next':
        await _c.next();
      case 'prev':
        await _c.prev();
      case 'seek':
        if (value is num) _c.seekTo(value.toDouble());
      case 'seekBy':
        if (value is num) {
          final double limit = _c.duration > 0 ? _c.duration : double.infinity;
          final double target = (_c.position.value + value.toDouble()).clamp(0.0, limit).toDouble();
          _c.seekTo(target);
        }
      case 'favorite':
        if (t != null) _c.toggleFavorite(t);
      case 'shuffle':
        _c.toggleShuffle();
      case 'repeat':
        _c.toggleRepeat();
    }
    push(force: true);
    return true;
  }
}
