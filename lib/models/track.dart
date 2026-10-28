import '../utils/audio_math.dart';
import '../utils/lrc_parser.dart';

class Track {
  Track({
    required this.id,
    required this.uri,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.addedAt,
    this.genre,
    this.year,
    this.bitrateBps,
    this.sizeBytes,
    this.dateModifiedSec = 0,
    this.mimeType,
    this.folder,
    this.playCount = 0,
    this.favorite = false,
    this.replayGainDb,
    this.replayGainPeak,
    this.replayGainResolved = false,
    this.replayGainScanAttempted = false,
  });

  final String id;
  final String uri;
  final String title;
  final String artist;
  final String album;

  /// Duration in seconds.
  final double duration;
  final int addedAt;
  final String? genre;
  final int? year;
  final int? bitrateBps;
  final int? sizeBytes;
  final int dateModifiedSec;
  final String? mimeType;
  final String? folder;

  int playCount;
  bool favorite;

  /// ReplayGain correction in dB, read lazily from file tags. Track gain is preferred;
  /// album gain is used only when track gain is absent.
  double? replayGainDb;
  double? replayGainPeak;
  bool replayGainResolved;

  /// True after a persistent analysis attempt was already made for this file version.
  bool replayGainScanAttempted;

  List<LyricLine>? parsedLyrics;
  List<double>? _waveform;

  /// Same synthetic, seeded waveform the web version generates for imported tracks.
  List<double> get waveform {
    final List<double>? existing = _waveform;
    if (existing != null) return existing;
    int hash = 0;
    for (final int unit in id.codeUnits) {
      hash = (hash * 31 + unit) & 0x7FFFFFFF;
    }
    final List<double> generated =
        generateSyntheticWaveform(count: 64, seed: ((hash % 997) + 50).toDouble());
    _waveform = generated;
    return generated;
  }

  String get letter {
    final String t = title.trim();
    return t.isEmpty ? '?' : t.substring(0, 1).toUpperCase();
  }

  factory Track.fromMap(Map<dynamic, dynamic> m) {
    final int durMs = (m['durationMs'] as num?)?.toInt() ?? 0;
    final int yearValue = (m['year'] as num?)?.toInt() ?? 0;
    final int bitrate = (m['bitrate'] as num?)?.toInt() ?? 0;
    final int size = (m['size'] as num?)?.toInt() ?? 0;
    final String genreValue = ((m['genre'] as String?) ?? '').trim();
    return Track(
      id: '${m['id']}',
      uri: '${m['uri']}',
      title: '${m['title']}',
      artist: '${m['artist']}',
      album: '${m['album']}',
      duration: durMs / 1000.0,
      addedAt: ((m['dateAddedSec'] as num?)?.toInt() ?? 0) * 1000,
      genre: genreValue.isEmpty ? null : genreValue,
      year: yearValue > 0 ? yearValue : null,
      bitrateBps: bitrate > 0 ? bitrate : null,
      sizeBytes: size > 0 ? size : null,
      dateModifiedSec: (m['dateModifiedSec'] as num?)?.toInt() ?? 0,
      mimeType: m['mime'] as String?,
      folder: m['folder'] as String?,
    );
  }
}
