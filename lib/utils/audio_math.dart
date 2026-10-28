import 'dart:math' as math;

/// Formats seconds as m:ss or h:mm:ss (same output as the web formatTime).
String formatTime(double seconds) {
  if (seconds.isNaN || seconds < 0) return '0:00';
  final int totalSecs = seconds.isInfinite ? 0 : seconds.floor();
  final int hrs = totalSecs ~/ 3600;
  final int mins = (totalSecs % 3600) ~/ 60;
  final int secs = totalSecs % 60;
  final String paddedSecs = secs < 10 ? '0$secs' : '$secs';
  if (hrs > 0) {
    final String paddedMins = mins < 10 ? '0$mins' : '$mins';
    return '$hrs:$paddedMins:$paddedSecs';
  }
  return '$mins:$paddedSecs';
}

double clampDouble(double value, double min, double max) {
  return math.min(math.max(value, min), max);
}

/// Deterministic pseudo-random waveform, identical algorithm to the web version.
List<double> generateSyntheticWaveform({int count = 60, double seed = 42}) {
  final List<double> out = <double>[];
  double current = math.sin(seed).abs();
  for (int i = 0; i < count; i++) {
    current = (current * 9301 + 49297) % 233280;
    final double rnd = current / 233280;
    final double envelope = math.sin((i / (count - 1)) * math.pi);
    final double value = 0.15 + (0.35 * rnd + 0.5 * envelope);
    final double clamped = clampDouble(value, 0.08, 1.0);
    out.add(double.parse(clamped.toStringAsFixed(2)));
  }
  return out;
}

/// Simple fast fuzzy matcher for search queries (port of the web fuzzyMatch).
bool fuzzyMatch(String pattern, String text) {
  if (pattern.isEmpty) return true;
  if (text.isEmpty) return false;
  final String p = pattern.toLowerCase().trim();
  final String t = text.toLowerCase();
  if (t.contains(p)) return true;
  int patternIdx = 0;
  for (int i = 0; i < t.length && patternIdx < p.length; i++) {
    if (t[i] == p[patternIdx]) {
      patternIdx++;
    }
  }
  return patternIdx == p.length;
}
