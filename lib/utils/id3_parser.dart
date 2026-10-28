import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

class ParsedAudioMetadata {
  String title = '';
  String artist = '';
  String album = '';
  String genre = '';
  String year = '';
  String? lyrics;
}

int _syncsafe(Uint8List b, int o) {
  return ((b[o] & 0x7F) << 21) | ((b[o + 1] & 0x7F) << 14) | ((b[o + 2] & 0x7F) << 7) | (b[o + 3] & 0x7F);
}

String _decodeUtf16(Uint8List b, bool? littleEndianHint) {
  if (b.length < 2) return '';
  int start = 0;
  bool little = littleEndianHint ?? true;
  if (b[0] == 0xFF && b[1] == 0xFE) {
    little = true;
    start = 2;
  } else if (b[0] == 0xFE && b[1] == 0xFF) {
    little = false;
    start = 2;
  }
  final List<int> units = <int>[];
  for (int i = start; i + 1 < b.length; i += 2) {
    units.add(little ? (b[i] | (b[i + 1] << 8)) : ((b[i] << 8) | b[i + 1]));
  }
  return String.fromCharCodes(units);
}

String _decodeText(Uint8List data, int encoding) {
  switch (encoding) {
    case 0:
      return latin1.decode(data, allowInvalid: true);
    case 1:
      return _decodeUtf16(data, null);
    case 2:
      return _decodeUtf16(data, false);
    default:
      return utf8.decode(data, allowMalformed: true);
  }
}

String _cleanText(Uint8List frameBody) {
  if (frameBody.isEmpty) return '';
  final int enc = frameBody[0];
  final String text = _decodeText(Uint8List.sublistView(frameBody, 1), enc);
  final int nul = text.indexOf('\u0000');
  return (nul >= 0 ? text.substring(0, nul) : text).trim();
}

String? _decodeUslt(Uint8List frame) {
  if (frame.length < 5) return null;
  final int enc = frame[0];
  int idx = 4; // encoding(1) + language(3)
  if (enc == 1 || enc == 2) {
    while (idx + 1 < frame.length && !(frame[idx] == 0 && frame[idx + 1] == 0)) {
      idx += 2;
    }
    idx += 2;
  } else {
    while (idx < frame.length && frame[idx] != 0) {
      idx += 1;
    }
    idx += 1;
  }
  if (idx >= frame.length) return null;
  final String text = _decodeText(Uint8List.sublistView(frame, idx), enc);
  return text.replaceAll('\u0000', '').trim();
}

/// Parses ID3v2.3 / v2.4 text frames (TIT2, TPE1, TALB, TCON, TYER/TDRC) and USLT lyrics.
ParsedAudioMetadata parseId3(Uint8List bytes) {
  final ParsedAudioMetadata meta = ParsedAudioMetadata();
  if (bytes.length > 10 && bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) {
    final int version = bytes[3];
    final int tagSize = _syncsafe(bytes, 6);
    final int maxOffset = math.min(tagSize + 10, bytes.length);
    int offset = 10;
    final RegExp idPattern = RegExp(r'^[A-Z0-9]{4}$');
    while (offset + 10 < maxOffset) {
      final String frameId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      if (!idPattern.hasMatch(frameId)) break;
      final int frameSize = version == 4
          ? _syncsafe(bytes, offset + 4)
          : ((bytes[offset + 4] << 24) | (bytes[offset + 5] << 16) | (bytes[offset + 6] << 8) | bytes[offset + 7]);
      if (frameSize <= 0 || offset + 10 + frameSize > bytes.length) break;
      final Uint8List body = Uint8List.sublistView(bytes, offset + 10, offset + 10 + frameSize);
      if (frameId == 'TIT2') {
        meta.title = _cleanText(body);
      } else if (frameId == 'TPE1') {
        meta.artist = _cleanText(body);
      } else if (frameId == 'TALB') {
        meta.album = _cleanText(body);
      } else if (frameId == 'TCON') {
        meta.genre = _cleanText(body);
      } else if (frameId == 'TYER' || frameId == 'TDRC') {
        final String y = _cleanText(body);
        meta.year = y.length >= 4 ? y.substring(0, 4) : y;
      } else if (frameId == 'USLT' && meta.lyrics == null) {
        meta.lyrics = _decodeUslt(body);
      }
      offset += 10 + frameSize;
    }
  }
  return meta;
}
