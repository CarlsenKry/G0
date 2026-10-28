import 'package:flutter/services.dart';

/// Thin wrapper around the Kotlin side (MainActivity.kt).
class NativeBridge {
  static const MethodChannel _channel = MethodChannel('com.aether.music/native');

  static Future<Map<String, bool>> checkPermissions() async {
    try {
      final Map<dynamic, dynamic>? raw = await _channel.invokeMapMethod<dynamic, dynamic>('checkPermissions');
      return _toBoolMap(raw);
    } catch (_) {
      return <String, bool>{'media': false, 'notifications': false};
    }
  }

  static Future<Map<String, bool>> requestPermissions() async {
    try {
      final Map<dynamic, dynamic>? raw = await _channel.invokeMapMethod<dynamic, dynamic>('requestPermissions');
      return _toBoolMap(raw);
    } catch (_) {
      return checkPermissions();
    }
  }

  /// Requests Android 13+ notification permission independently from media access.
  /// Android can defer/suppress the notification prompt when several permission
  /// groups are requested together during first launch.
  static Future<Map<String, bool>> requestNotificationPermission() async {
    try {
      final Map<dynamic, dynamic>? raw = await _channel.invokeMapMethod<dynamic, dynamic>('requestNotificationPermission');
      return _toBoolMap(raw);
    } catch (_) {
      return checkPermissions();
    }
  }

  static Map<String, bool> _toBoolMap(Map<dynamic, dynamic>? raw) {
    final Map<String, bool> out = <String, bool>{'media': false, 'notifications': false};
    if (raw != null) {
      raw.forEach((dynamic key, dynamic value) {
        out['$key'] = value == true;
      });
    }
    return out;
  }

  static Future<void> openAppSettings() async {
    try {
      await _channel.invokeMethod<bool>('openAppSettings');
    } catch (_) {}
  }

  /// Opens Android's document picker and returns the selected M3U text.
  static Future<String?> importM3u() async {
    return _channel.invokeMethod<String>('importM3u');
  }

  /// Opens Android's Save As dialog and writes an M3U playlist to the chosen URI.
  static Future<bool> exportM3u(String filename, String content) async {
    return (await _channel.invokeMethod<bool>('exportM3u', <String, dynamic>{
      'filename': filename,
      'content': content,
    })) == true;
  }

  /// Returns the persisted folder label used to locate external sibling .lrc files.
  static Future<String?> getLyricsFolder() async {
    try {
      return await _channel.invokeMethod<String>('getLyricsFolder');
    } catch (_) {
      return null;
    }
  }

  /// Change token incremented by Android when the selected tree or MediaStore
  /// reports a possible sidecar lyrics change.
  static Future<int> getExternalLyricsChangeToken() async {
    try {
      return await _channel.invokeMethod<int>('getExternalLyricsChangeToken') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Opens Android's folder picker. The selected folder grant is persisted by native code.
  static Future<String?> selectLyricsFolder() async {
    try {
      return await _channel.invokeMethod<String>('selectLyricsFolder');
    } catch (_) {
      return null;
    }
  }

  /// Reads a .lrc sidecar matching the audio filename in the same folder, if accessible.
  static Future<String?> readExternalLyrics(String id) async {
    try {
      return await _channel.invokeMethod<String>(
        'readExternalLyrics',
        <String, dynamic>{'id': id},
      );
    } catch (_) {
      return null;
    }
  }

  static Future<List<Map<dynamic, dynamic>>> scanTracks() async {
    final List<dynamic>? raw = await _channel.invokeListMethod<dynamic>('scanTracks');
    final List<Map<dynamic, dynamic>> out = <Map<dynamic, dynamic>>[];
    if (raw != null) {
      for (final dynamic item in raw) {
        if (item is Map) {
          out.add(item);
        }
      }
    }
    return out;
  }

  static Future<String?> loadCover(String id, {int size = 512}) async {
    try {
      return await _channel.invokeMethod<String>('loadCover', <String, dynamic>{'id': id, 'size': size});
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> readHead(String id, {int maxBytes = 524288}) async {
    try {
      return await _channel.invokeMethod<Uint8List>(
        'readHead',
        <String, dynamic>{'id': id, 'maxBytes': maxBytes},
      );
    } catch (_) {
      return null;
    }
  }

  /// Reads standard ReplayGain track/album gain and peak tags from the audio file.
  /// An empty result means no supported tag was found or the file could not be read.
  static Future<Map<String, double?>> readReplayGain(String id) async {
    try {
      final Map<dynamic, dynamic>? raw = await _channel.invokeMapMethod<dynamic, dynamic>(
        'readReplayGain',
        <String, dynamic>{'id': id},
      );
      final Map<String, double?> out = <String, double?>{};
      if (raw != null) {
        for (final String key in <String>['trackGainDb', 'albumGainDb', 'trackPeak', 'albumPeak']) {
          final dynamic value = raw[key];
          if (value is num && value.isFinite) out[key] = value.toDouble();
        }
      }
      return out;
    } catch (_) {
      return <String, double?>{};
    }
  }

  /// Decodes the song in the background and estimates integrated loudness and sample peak.
  /// A null result means the scan was cancelled (for example, the stabilizer was disabled).
  static Future<Map<String, dynamic>?> analyzeLoudness(
    String id, {
    double targetLufs = -14.0,
  }) async {
    try {
      final Map<dynamic, dynamic>? raw = await _channel.invokeMapMethod<dynamic, dynamic>(
        'analyzeLoudness',
        <String, dynamic>{'id': id, 'targetLufs': targetLufs},
      );
      if (raw == null) return null;
      final Map<String, dynamic> out = <String, dynamic>{};
      for (final String key in <String>['success', 'gainDb', 'peak', 'integratedLufs']) {
        final dynamic value = raw[key];
        if (key == 'success') {
          out[key] = value == true;
        } else if (value is num && value.isFinite) {
          out[key] = value.toDouble();
        }
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  /// Immediately invalidates the current native decoder scan.
  static Future<void> cancelLoudnessScan() async {
    try {
      await _channel.invokeMethod<bool>('cancelLoudnessScan');
    } catch (_) {}
  }

  /// Applies native Android audio effects to the current just_audio session.
  /// The ten UI bands are mapped to however many bands the device exposes.
  static Future<bool> applyAudioEffects({
    required int sessionId,
    required List<double> bandsDb,
    required double preampDb,
    required int bassBoost,
    required bool enabled,
    required bool volumeStabilizer,
    double? replayGainDb,
    double? replayGainPeak,
  }) async {
    try {
      final bool? result = await _channel.invokeMethod<bool>(
        'applyAudioEffects',
        <String, dynamic>{
          'sessionId': sessionId,
          'bandsDb': bandsDb,
          'preampDb': preampDb,
          'bassBoost': bassBoost,
          'enabled': enabled,
          'volumeStabilizer': volumeStabilizer,
          'replayGainDb': replayGainDb,
          'replayGainPeak': replayGainPeak,
        },
      );
      return result == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> releaseAudioEffects() async {
    try {
      await _channel.invokeMethod<bool>('releaseAudioEffects');
    } catch (_) {}
  }

  // ---- Screenlock KRY player (custom lock screen, LockScreenActivity.kt)

  /// Receives transport commands ("lockCommand") sent by the native lock screen.
  static void setCommandHandler(Future<dynamic> Function(MethodCall call) handler) {
    _channel.setMethodCallHandler(handler);
  }

  static Future<void> syncLockscreen(Map<String, dynamic> state) async {
    try {
      await _channel.invokeMethod<bool>('lockscreenSync', state);
    } catch (_) {}
  }

  /// "Display over other apps" - lets Android start the lock screen from the background.
  static Future<bool> canDrawOverlays() async {
    try {
      return (await _channel.invokeMethod<bool>('canDrawOverlays')) == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openOverlaySettings() async {
    try {
      await _channel.invokeMethod<bool>('openOverlaySettings');
    } catch (_) {}
  }

  static Future<void> previewLockscreen() async {
    try {
      await _channel.invokeMethod<bool>('previewLockscreen');
    } catch (_) {}
  }

}
