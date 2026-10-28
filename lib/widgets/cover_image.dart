import 'dart:io';

import 'package:flutter/material.dart';

import '../models/track.dart';
import '../state/player_controller.dart';
import '../theme/app_theme.dart';

/// Album cover from the platform thumbnail API, with a letter fallback.
class CoverImage extends StatelessWidget {
  const CoverImage({
    super.key,
    required this.controller,
    required this.track,
    this.cacheWidth = 600,
  });

  final PlayerController controller;
  final Track track;
  final int cacheWidth;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: controller.coverFor(track),
      builder: (BuildContext context, AsyncSnapshot<String?> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return ColoredBox(color: AppColors.zinc900);
        }
        final String? path = snapshot.data;
        if (path == null) {
          return LetterCover(letter: track.letter);
        }
        return Image.file(
          File(path),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          cacheWidth: cacheWidth,
          gaplessPlayback: true,
          errorBuilder: (BuildContext c, Object e, StackTrace? s) => LetterCover(letter: track.letter),
        );
      },
    );
  }
}

class LetterCover extends StatelessWidget {
  const LetterCover({super.key, required this.letter});

  final String letter;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double side = constraints.hasBoundedWidth && constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 100;
        return DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomLeft,
              end: Alignment.topRight,
              colors: <Color>[AppColors.cyan500, AppColors.indigo600],
            ),
          ),
          child: Center(
            child: Text(
              letter,
              style: AppText.display(side * 0.4, 700, Colors.white, lineHeight: side * 0.5),
            ),
          ),
        );
      },
    );
  }
}
