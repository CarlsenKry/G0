/// Options for the custom "Screenlock KRY player" (Settings > Screenlock KRY player).
///
/// Stored as a flat key/value map so new toggles never need a schema migration:
/// a key that was never saved simply falls back to [defaults]. The very same map
/// is handed to the native lock screen (LockScreenActivity.kt), which reads the
/// keys listed below.
class LockscreenSettings {
  const LockscreenSettings([this._values = const <String, dynamic>{}]);

  final Map<String, dynamic> _values;

  static const Map<String, dynamic> defaults = <String, dynamic>{
    // master + behaviour
    'enabled': false,
    'onlyWhilePlaying': true,
    // clock
    'showClock': true,
    'showDate': true,
    'clockFormat': 'system', // system | 12h | 24h
    // cover + background
    'showCover': true,
    'coverShape': 'rounded', // rounded | square | circle
    'coverSpin': false,
    'coverSize': 72, // percent of screen width
    'blurBackground': true,
    'dim': 62, // percent of black laid over the blurred cover
    'accentTint': true,
    // track info
    'showTitle': true,
    'showArtist': true,
    'showAlbum': true,
    // controls
    'showSeekbar': true,
    'remainingTime': true,
    'showSeekButtons': true,
    'showPrevNext': true,
    'transportButtonScale': 100, // percent size for previous / play-pause / next
    'showFavorite': true,
    'showShuffle': false,
    'showRepeat': true,
    'showQueueButton': true,
    'showLyricsButton': true,
  };

  static const List<String> coverShapes = <String>['rounded', 'square', 'circle'];
  static const List<String> clockFormats = <String>['system', '12h', '24h'];

  bool flag(String key) {
    final dynamic v = _values[key];
    if (v is bool) return v;
    return (defaults[key] as bool?) ?? false;
  }

  int number(String key) {
    final dynamic v = _values[key];
    if (v is num) return v.toInt();
    return (defaults[key] as int?) ?? 0;
  }

  String text(String key) {
    final dynamic v = _values[key];
    if (v is String) return v;
    return (defaults[key] as String?) ?? '';
  }

  bool get enabled => flag('enabled');

  /// Returns a copy with [key] set to [value].
  LockscreenSettings set(String key, Object value) {
    return LockscreenSettings(<String, dynamic>{..._values, key: value});
  }

  /// Complete option map (defaults filled in) for the native side.
  Map<String, dynamic> toNative() => <String, dynamic>{...defaults, ..._values};

  Map<String, dynamic> toJson() => <String, dynamic>{..._values};

  factory LockscreenSettings.fromJson(dynamic json) {
    if (json is! Map) return const LockscreenSettings();
    final Map<String, dynamic> clean = <String, dynamic>{};
    json.forEach((dynamic k, dynamic v) {
      final Object? fallback = defaults['$k'];
      if (fallback == null) return;
      if (fallback is bool && v is bool) clean['$k'] = v;
      if (fallback is int && v is num) clean['$k'] = v.toInt();
      if (fallback is String && v is String) clean['$k'] = v;
    });
    return LockscreenSettings(clean);
  }
}
