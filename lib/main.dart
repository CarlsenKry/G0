import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'services/audio_handler.dart';
import 'state/player_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[DeviceOrientation.portraitUp]);

  final PlayerController controller = PlayerController();
  final AetherAudioHandler handler = await AudioService.init<AetherAudioHandler>(
    builder: () => AetherAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.aether.music.channel.audio',
      androidNotificationChannelName: 'Krypton m.Player Playback',
      androidNotificationIcon: 'drawable/ic_notification',
      // Stay in foreground mode while paused. If the service left foreground mode on
      // pause, every automatic resume (next song after the screen turned off, audio
      // focus returning after a call) would have to enter it again from the
      // background, which Android 12+ forbids and answers by killing the app. The
      // notification therefore stays visible, with working controls, while paused.
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: false,
    ),
  );

  runApp(AetherApp(controller: controller));
  await controller.init(handler);
}
