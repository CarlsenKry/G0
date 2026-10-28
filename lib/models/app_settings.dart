import 'lockscreen_settings.dart';

enum AetherRepeatMode { off, all, one }

enum VisualizerStyle { radial, waveform, bars }

VisualizerStyle visualizerStyleFromName(String? name) {
  for (final VisualizerStyle v in VisualizerStyle.values) {
    if (v.name == name) return v;
  }
  return VisualizerStyle.radial;
}

AetherRepeatMode repeatModeFromName(String? name) {
  for (final AetherRepeatMode m in AetherRepeatMode.values) {
    if (m.name == name) return m;
  }
  return AetherRepeatMode.all;
}

class AppSettings {
  const AppSettings({
    required this.theme,
    required this.accentMode,
    required this.visualizerStyle,
    required this.crossfadeDuration,
    required this.gapless,
    this.fadeOnManualSkip = true,
    this.fadeOnPause = true,
    this.albumAwareFading = true,
    this.sleepTimerMinutes,
    this.sleepTimerEndTime,
    this.eqEnabled = true,
    this.eqBandsDb = const <double>[0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    this.preampDb = 0,
    this.bassBoost = 0,
    this.hiddenFolders = const <String>[],
    this.lockscreenPlayerEnabled = true,
    this.lockscreenShowPrevious = true,
    this.lockscreenShowNext = true,
    this.fontScale = 1.0,
    this.volumeStabilizerEnabled = false,
    this.lightMode = false,
    this.lockscreen = const LockscreenSettings(),
  });

  /// 'amoled' | 'cyberpunk' | 'aurora' | 'holo' (stored only, like the web version)
  final String theme;

  /// 'auto' (from artwork) or a hex color such as '#00F0FF'
  final String accentMode;
  final VisualizerStyle visualizerStyle;
  /// Fading length in seconds (0 = off, up to 30). Stored under the old key name.
  final int crossfadeDuration;

  /// Pre-loads the next track so a track change without fading has no audible gap.
  final bool gapless;

  /// Also fade when the user taps Next/Previous or picks a song (capped to a few seconds).
  final bool fadeOnManualSkip;

  /// Short fade-out when pausing and fade-in when resuming.
  final bool fadeOnPause;

  /// No crossfade between consecutive tracks of the same album (live albums, mixes).
  final bool albumAwareFading;
  final int? sleepTimerMinutes;
  final int? sleepTimerEndTime;
  final bool eqEnabled;
  final List<double> eqBandsDb;
  final double preampDb;
  final int bassBoost;
  final List<String> hiddenFolders;
  final bool lockscreenPlayerEnabled;
  final bool lockscreenShowPrevious;
  final bool lockscreenShowNext;
  final double fontScale;
  final bool volumeStabilizerEnabled;

  /// True for the light appearance; false preserves the original AMOLED dark look.
  final bool lightMode;

  /// Custom slide-to-unlock lock screen (Settings > Screenlock KRY player).
  final LockscreenSettings lockscreen;

  factory AppSettings.defaults() {
    return const AppSettings(
      theme: 'amoled',
      accentMode: 'auto',
      visualizerStyle: VisualizerStyle.radial,
      crossfadeDuration: 2,
      gapless: true,
    );
  }

  AppSettings copyWith({
    String? theme,
    String? accentMode,
    VisualizerStyle? visualizerStyle,
    int? crossfadeDuration,
    bool? gapless,
    bool? fadeOnManualSkip,
    bool? fadeOnPause,
    bool? albumAwareFading,
    int? sleepTimerMinutes,
    int? sleepTimerEndTime,
    bool clearSleep = false,
    bool? eqEnabled,
    List<double>? eqBandsDb,
    double? preampDb,
    int? bassBoost,
    List<String>? hiddenFolders,
    bool? lockscreenPlayerEnabled,
    bool? lockscreenShowPrevious,
    bool? lockscreenShowNext,
    double? fontScale,
    bool? volumeStabilizerEnabled,
    bool? lightMode,
    LockscreenSettings? lockscreen,
  }) {
    return AppSettings(
      theme: theme ?? this.theme,
      accentMode: accentMode ?? this.accentMode,
      visualizerStyle: visualizerStyle ?? this.visualizerStyle,
      crossfadeDuration: crossfadeDuration ?? this.crossfadeDuration,
      gapless: gapless ?? this.gapless,
      fadeOnManualSkip: fadeOnManualSkip ?? this.fadeOnManualSkip,
      fadeOnPause: fadeOnPause ?? this.fadeOnPause,
      albumAwareFading: albumAwareFading ?? this.albumAwareFading,
      sleepTimerMinutes: clearSleep ? null : (sleepTimerMinutes ?? this.sleepTimerMinutes),
      sleepTimerEndTime: clearSleep ? null : (sleepTimerEndTime ?? this.sleepTimerEndTime),
      eqEnabled: eqEnabled ?? this.eqEnabled,
      eqBandsDb: eqBandsDb ?? this.eqBandsDb,
      preampDb: preampDb ?? this.preampDb,
      bassBoost: bassBoost ?? this.bassBoost,
      hiddenFolders: hiddenFolders ?? this.hiddenFolders,
      lockscreenPlayerEnabled: lockscreenPlayerEnabled ?? this.lockscreenPlayerEnabled,
      lockscreenShowPrevious: lockscreenShowPrevious ?? this.lockscreenShowPrevious,
      lockscreenShowNext: lockscreenShowNext ?? this.lockscreenShowNext,
      fontScale: fontScale ?? this.fontScale,
      volumeStabilizerEnabled: volumeStabilizerEnabled ?? this.volumeStabilizerEnabled,
      lightMode: lightMode ?? this.lightMode,
      lockscreen: lockscreen ?? this.lockscreen,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'theme': theme,
      'accentMode': accentMode,
      'visualizerStyle': visualizerStyle.name,
      'crossfadeDuration': crossfadeDuration,
      'gapless': gapless,
      'fadeOnManualSkip': fadeOnManualSkip,
      'fadeOnPause': fadeOnPause,
      'albumAwareFading': albumAwareFading,
      'sleepTimerMinutes': sleepTimerMinutes,
      'sleepTimerEndTime': sleepTimerEndTime,
      'eqEnabled': eqEnabled,
      'eqBandsDb': eqBandsDb,
      'preampDb': preampDb,
      'bassBoost': bassBoost,
      'hiddenFolders': hiddenFolders,
      'lockscreenPlayerEnabled': lockscreenPlayerEnabled,
      'lockscreenShowPrevious': lockscreenShowPrevious,
      'lockscreenShowNext': lockscreenShowNext,
      'fontScale': fontScale,
      'volumeStabilizerEnabled': volumeStabilizerEnabled,
      'lightMode': lightMode,
      'lockscreen': lockscreen.toJson(),
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final AppSettings d = AppSettings.defaults();
    final dynamic rawBands = json['eqBandsDb'];
    final List<double> bands = List<double>.generate(10, (int i) {
      if (rawBands is List && i < rawBands.length && rawBands[i] is num) {
        return (rawBands[i] as num).toDouble().clamp(-12.0, 12.0).toDouble();
      }
      return 0.0;
    });
    final String theme = (json['theme'] as String?) ?? d.theme;
    final String accentMode = (json['accentMode'] as String?) ?? d.accentMode;
    final double preamp = ((json['preampDb'] as num?)?.toDouble() ?? d.preampDb).clamp(-12.0, 12.0).toDouble();
    final int bass = ((json['bassBoost'] as num?)?.toInt() ?? d.bassBoost).clamp(0, 100).toInt();
    return AppSettings(
      theme: theme,
      accentMode: accentMode,
      visualizerStyle: visualizerStyleFromName(json['visualizerStyle'] as String?),
      crossfadeDuration: ((json['crossfadeDuration'] as num?)?.toInt() ?? d.crossfadeDuration).clamp(0, 30).toInt(),
      gapless: (json['gapless'] as bool?) ?? d.gapless,
      fadeOnManualSkip: (json['fadeOnManualSkip'] as bool?) ?? d.fadeOnManualSkip,
      fadeOnPause: (json['fadeOnPause'] as bool?) ?? d.fadeOnPause,
      albumAwareFading: (json['albumAwareFading'] as bool?) ?? d.albumAwareFading,
      sleepTimerMinutes: (json['sleepTimerMinutes'] as num?)?.toInt(),
      sleepTimerEndTime: (json['sleepTimerEndTime'] as num?)?.toInt(),
      eqEnabled: (json['eqEnabled'] as bool?) ?? d.eqEnabled,
      eqBandsDb: bands,
      preampDb: preamp,
      bassBoost: bass,
      hiddenFolders: (json['hiddenFolders'] as List<dynamic>?)?.whereType<String>().toSet().toList() ?? const <String>[],
      lockscreenPlayerEnabled: (json['lockscreenPlayerEnabled'] as bool?) ?? d.lockscreenPlayerEnabled,
      lockscreenShowPrevious: (json['lockscreenShowPrevious'] as bool?) ?? d.lockscreenShowPrevious,
      lockscreenShowNext: (json['lockscreenShowNext'] as bool?) ?? d.lockscreenShowNext,
      fontScale: ((json['fontScale'] as num?)?.toDouble() ?? d.fontScale).clamp(0.8, 1.4).toDouble(),
      volumeStabilizerEnabled: (json['volumeStabilizerEnabled'] as bool?) ?? d.volumeStabilizerEnabled,
      lightMode: (json['lightMode'] as bool?) ?? d.lightMode,
      lockscreen: LockscreenSettings.fromJson(json['lockscreen']),
    );
  }
}
