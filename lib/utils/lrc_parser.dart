class LyricLine {
  const LyricLine(this.time, this.text);
  final double time;
  final String text;
}

final RegExp _timeRegex = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');

/// Parses LRC text into time-sorted lines (port of the web lrcParser).
List<LyricLine> parseLRC(String lrc) {
  final List<LyricLine> lines = <LyricLine>[];
  for (final String raw in lrc.split(RegExp(r'\r?\n'))) {
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) continue;
    final List<RegExpMatch> matches = _timeRegex.allMatches(trimmed).toList();
    if (matches.isEmpty) continue;
    final String text = trimmed.replaceAll(_timeRegex, '').trim();
    for (final RegExpMatch m in matches) {
      final int minutes = int.parse(m.group(1)!);
      final int seconds = int.parse(m.group(2)!);
      final String? msRaw = m.group(3);
      int ms = 0;
      if (msRaw != null) {
        final String padded = msRaw.padRight(3, '0').substring(0, 3);
        ms = int.parse(padded);
      }
      lines.add(LyricLine(minutes * 60 + seconds + ms / 1000.0, text));
    }
  }
  lines.sort((LyricLine a, LyricLine b) => a.time.compareTo(b.time));
  return lines;
}

bool looksLikeLrc(String text) => _timeRegex.hasMatch(text);

/// Binary search for the active lyric line (-1 if before the first line).
int findActiveLyricIndex(List<LyricLine> lyrics, double currentTime) {
  if (lyrics.isEmpty) return -1;
  int low = 0;
  int high = lyrics.length - 1;
  int result = -1;
  while (low <= high) {
    final int mid = (low + high) >> 1;
    if (lyrics[mid].time <= currentTime) {
      result = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return result;
}
