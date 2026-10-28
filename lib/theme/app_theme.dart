import 'package:flutter/material.dart';

/// Colors mirror the Tailwind v4 palette used by the web version.
class AppColors {
  /// Updated from the persisted app setting before the widget tree is built.
  /// This keeps the existing custom visual system usable in both appearances.
  static bool lightMode = false;

  static void configure({required bool light}) => lightMode = light;
  static bool get isLight => lightMode;

  static const Color cyan = Color(0xFF00F0FF);
  static const Color violet = Color(0xFF8A2BE2);
  static const Color magenta = Color(0xFFFF2E93);
  static const Color emerald = Color(0xFF00FF9D);

  static const Color cyan300 = Color(0xFF53EAFD);
  static const Color cyan400 = Color(0xFF00D3F3);
  static const Color cyan500 = Color(0xFF00B8DB);
  static const Color cyan950 = Color(0xFF053345);
  static const Color fuchsia400 = Color(0xFFED6AFF);
  static const Color rose500 = Color(0xFFFF2056);
  static const Color indigo600 = Color(0xFF4F39F6);

  static Color get zinc300 => lightMode ? const Color(0xFF3F3F46) : const Color(0xFFD4D4D8);
  static Color get zinc400 => lightMode ? const Color(0xFF52525B) : const Color(0xFF9F9FA9);
  static Color get zinc500 => lightMode ? const Color(0xFF71717A) : const Color(0xFF71717B);
  static Color get zinc600 => lightMode ? const Color(0xFF71717A) : const Color(0xFF52525C);
  static Color get zinc800 => lightMode ? const Color(0xFFE4E4E7) : const Color(0xFF27272A);
  static Color get zinc900 => lightMode ? const Color(0xFFF4F4F5) : const Color(0xFF18181B);
  static Color get zinc950 => lightMode ? const Color(0xFFFFFFFF) : const Color(0xFF09090B);

  static Color get pageBackground => lightMode ? const Color(0xFFF7F8FC) : Colors.black;
  static Color get panelBackground => lightMode ? const Color(0xFFF7F8FC) : const Color(0xFF111118);
  static Color get primaryText => lightMode ? const Color(0xFF18181B) : Colors.white;

  /// Resolve old design-token text colors for contrast in light mode.
  static Color resolveTextColor(Color color) {
    if (!lightMode) return color;
    if (color == Colors.white) return const Color(0xFF18181B);
    if (color == const Color(0xFFD4D4D8)) return const Color(0xFF3F3F46);
    if (color == const Color(0xFF9F9FA9)) return const Color(0xFF52525B);
    if (color == const Color(0xFF52525C)) return const Color(0xFF71717A);
    return color;
  }

  static Color white(double alpha) => lightMode
      ? Color.fromRGBO(0, 0, 0, alpha)
      : Color.fromRGBO(255, 255, 255, alpha);
  static Color black(double alpha) => Color.fromRGBO(0, 0, 0, alpha);

  static Color fromHex(String hex) {
    String h = hex.replaceAll('#', '');
    if (h.length == 3) {
      h = '${h[0]}${h[0]}${h[1]}${h[1]}${h[2]}${h[2]}';
    }
    final int v = int.tryParse(h, radix: 16) ?? 0x00F0FF;
    return Color(0xFF000000 | v);
  }
}

class AppText {
  static const String inter = 'Inter';
  static const String displayFamily = 'SpaceGrotesk';
  static const String monoFamily = 'JetBrainsMono';

  static TextStyle _style(
    String family,
    double size,
    int weight,
    Color color,
    double? lineHeightPx,
    double letterSpacingEm,
    List<Shadow>? shadows,
    bool tabular,
  ) {
    final int idx = (weight ~/ 100) - 1;
    return TextStyle(
      fontFamily: family,
      fontSize: size,
      fontWeight: FontWeight.values[idx < 0 ? 0 : (idx > 8 ? 8 : idx)],
      fontVariations: <FontVariation>[FontVariation('wght', weight.toDouble())],
      color: AppColors.resolveTextColor(color),
      height: lineHeightPx == null ? null : lineHeightPx / size,
      leadingDistribution: TextLeadingDistribution.even,
      letterSpacing: letterSpacingEm * size,
      decoration: TextDecoration.none,
      shadows: shadows,
      fontFeatures: tabular ? const <FontFeature>[FontFeature.tabularFigures()] : null,
    );
  }

  /// Inter (font-sans)
  static TextStyle body(double size, int weight, Color color,
      {double? lineHeight, double tracking = 0, List<Shadow>? shadows}) {
    return _style(inter, size, weight, color, lineHeight ?? size * 1.5, tracking, shadows, false);
  }

  /// Space Grotesk (font-display)
  static TextStyle display(double size, int weight, Color color,
      {double? lineHeight, double tracking = 0, List<Shadow>? shadows}) {
    return _style(displayFamily, size, weight, color, lineHeight ?? size * 1.5, tracking, shadows, false);
  }

  /// JetBrains Mono (font-mono)
  static TextStyle mono(double size, int weight, Color color,
      {double? lineHeight, double tracking = 0, List<Shadow>? shadows, bool tabular = false}) {
    return _style(monoFamily, size, weight, color, lineHeight ?? size * 1.5, tracking, shadows, tabular);
  }
}
