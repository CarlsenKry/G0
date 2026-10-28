import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

class ExtractedPalette {
  const ExtractedPalette({
    required this.dominant,
    required this.glow,
    required this.secondary,
    required this.isDark,
  });

  final Color dominant;
  final Color glow;
  final Color secondary;
  final bool isDark;

  static const ExtractedPalette defaults = ExtractedPalette(
    dominant: Color(0xFF00F0FF),
    glow: Color.fromRGBO(0, 240, 255, 0.45),
    secondary: Color(0xFF8A2BE2),
    isDark: true,
  );
}

/// Exact port of the web paletteExtractor: scales the cover to 40x40 and picks the
/// most saturated pixel (reading every 4th pixel, skipping near-black/near-white).
Future<ExtractedPalette> extractPaletteFromFile(String path) async {
  try {
    final Uint8List bytes = await File(path).readAsBytes();
    final ui.Codec codec = await ui.instantiateImageCodec(bytes, targetWidth: 40, targetHeight: 40);
    final ui.FrameInfo frame = await codec.getNextFrame();
    final ByteData? data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    frame.image.dispose();
    codec.dispose();
    if (data == null) return ExtractedPalette.defaults;

    int count = 0;
    double maxSaturation = 0;
    int vibrantR = 0;
    int vibrantG = 240;
    int vibrantB = 255;

    for (int i = 0; i + 3 < data.lengthInBytes; i += 16) {
      final int r = data.getUint8(i);
      final int g = data.getUint8(i + 1);
      final int b = data.getUint8(i + 2);
      final int a = data.getUint8(i + 3);
      if (a < 128) continue;

      final int maxC = r > g ? (r > b ? r : b) : (g > b ? g : b);
      final int minC = r < g ? (r < b ? r : b) : (g < b ? g : b);
      final int delta = maxC - minC;
      final double lum = (maxC + minC) / 2;
      if (lum < 20 || lum > 240) continue;

      count++;
      final double saturation = maxC == 0 ? 0 : delta / maxC;
      if (saturation > maxSaturation) {
        maxSaturation = saturation;
        vibrantR = r;
        vibrantG = g;
        vibrantB = b;
      }
    }

    if (count > 0 && maxSaturation > 0.25) {
      return ExtractedPalette(
        dominant: Color.fromARGB(255, vibrantR, vibrantG, vibrantB),
        glow: Color.fromRGBO(vibrantR, vibrantG, vibrantB, 0.5),
        secondary: maxSaturation > 0.5 ? const Color(0xFF8A2BE2) : const Color(0xFFFF2E93),
        isDark: true,
      );
    }
    return ExtractedPalette.defaults;
  } catch (_) {
    return ExtractedPalette.defaults;
  }
}
