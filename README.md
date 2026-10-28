# Krypton m.Player

Krypton m.Player is a dark, neon-accented Android music player built with Flutter. This project continues the supplied AETHER Music codebase while preserving the existing application id (`com.aether.music`) so an installed test build can be upgraded rather than treated as a different package.

## Included features

- **Player:** cover artwork and letter fallback, dynamic accent palette, seekbar, shuffle, previous/play/next/repeat controls, lyrics, visualizer, and queue access.
- **Library:** device MediaStore scan, search, Favorites/Recent/Most Played filters, sorting, artwork fallback, track options, and a folder exclusion list under Settings → Library & Data. Excluded folders no longer appear in the app's library or playback queue. A rescan discovers any newly added folders.
- **Queue and background playback:** persistent queue/session, auto-advance, safe serialized track loading, notification controls, and Android MediaSession metadata for the notification and lock screen.
- **Screenlock KRY player (Settings -> Screenlock KRY player):** a custom dark, slide-to-unlock music screen drawn over the lock screen (clock + date, cover art with blurred background, title/artist/album, seek bar with remaining time, +/-10 s, previous/play/next, favorite/shuffle/repeat, up-next panel, synced lyrics, slide-to-unlock pill). Every component has its own toggle; cover shape/size/spin, background dimming, accent tint and clock format are adjustable, and *Preview* shows it without locking the phone. When the master switch is **off**, Android's own music lock-screen card is used (controlled by the *System lock screen* section). It needs *Display over other apps*; on Android 10+ a full-screen-intent notification is used as a fallback if the direct launch is blocked. Native code: `KryptonApplication.kt` (screen-off receiver), `LockScreenActivity.kt`, `SlideToUnlockView.kt`, `LockState.kt`; Dart sync in `lib/services/lockscreen_service.dart`.
- **Lock-screen options:** enable or suppress the app's published system media controls, and independently show/hide the Previous and Next actions. These controls are shared with the media notification because Android presents both from the same media session. Android controls the card layout and artwork presentation, so the exact Musicolet lock-screen design cannot be recreated from an ordinary media session.
- **Splash screen and app icon:** a three-second animated opening screen using the supplied GUY DONN artwork and the supplied blue GUY app icon packaged into Android launcher resources.
- **Appearance:** persisted app font-size scale (80–140%), dynamic/manual accent, visual skin, and visualizer style. The three animated visualizer styles are procedural, switch periodically, and require no microphone/recording permission.
- **EQ Lab:** ten UI bands, Flat/Bass/Vocal/Rock/Treble presets, preamp, bass boost and bypass. Effects use Android audio APIs where available.
- **Stats:** locally persisted real listening time, day/track summaries, and play counts. A play qualifies only after at least half of the track duration has actually been listened to; eligible statistics are batched in memory and written at qualification/checkpoints instead of every few seconds. Fresh installs start with zero historical listening time.
- **Settings:** library rescanning, folder exclusion, lock-screen transport options, sleep timer, EQ access, visualizer style, and font sizing.

## Build locally

Use the Flutter version pinned in CI (`3.41.9`) and JDK 17. Font files are downloaded at build time, then bundled into the app; the app does not fetch fonts while running.

```bash
bash tool/fetch_fonts.sh
flutter pub get
python3 tool/selfcheck.py
dart analyze
flutter build apk --release
```

The APK is written to `build/app/outputs/flutter-apk/app-release.apk`.

## GitHub Actions

The existing **Android Release APK** workflow is preserved with the working release-build steps:

1. Check out the repository and install JDK 17.
2. Set up pinned Flutter 3.41.9.
3. Make `android/gradlew` executable and fetch bundled fonts.
4. Resolve pinned Dart dependencies, run the project self-check and `dart analyze`.
5. Run `flutter build apk --release` and upload `build/app/outputs/flutter-apk/*.apk` as the `aether-release-apk` artifact for 14 days.

The APK is currently signed using Gradle's debug signing configuration so GitHub Actions can compile it without storing a private keystore in the repository. For Play Store distribution, configure a private release keystore and GitHub Actions secrets; never commit signing credentials.

## Audio behavior and platform limits

- **Background UI resource saving:** when Android hides the app, Flutter tickers are muted, the procedural visualizer and blurred album-art background are removed, the player screen stops its display clock/automatic visualizer switching, and external LRC change polling pauses. They resume when the app returns; playback, notification/media-session controls, audio effects, and the sleep timer are left running.
- **Notification persistence:** the media service stays in foreground mode while playback is paused (`androidNotificationOngoing: false`, `androidStopForegroundOnPause: false`). Leaving foreground mode on pause forces Android 12+ to re-enter it from the background on every automatic resume, which it refuses. Track changes never flip the published playing state to paused for the same reason. The notification icon (`drawable/ic_notification`) is looked up by name from Dart, so `res/raw/keep.xml` protects it from the release resource shrinker and release shrinking is switched off in `android/app/build.gradle.kts`; without a valid small icon Android shows only a generic "app is running" notification. Android notification permission and OEM notification settings still apply.
- **Lock-screen control switch:** turning it off removes transport actions from the shared system media session, so it also affects notification buttons. The app keeps the real playback state so ongoing playback is not falsely reported as stopped. Some Android OEMs may still display an empty media card; only the system can decide its final lock-screen layout.
- **Fading (Settings > Playback > Fading):** a real overlapping crossfade of 0-30 seconds. The app owns two audio players: the ending song keeps playing on one while the next song starts on the other, and the two volumes are ramped in opposite directions with equal-power curves. Songs shorter than twice the fade use a shorter fade. Tapping Next/Previous or choosing a song can fade too (switch in the Fading sheet, capped at 5 s). Pausing in the middle of a fade drops the old song. While two songs overlap, only the new song is routed through the EQ/visualizer session; the outgoing song fades out unprocessed.
- **Album-aware fading:** consecutive tracks with the same album tag skip the crossfade and play straight through (switch in the Fading sheet). Untagged files, whose album is just the folder name, still fade.
- **Fade on pause/resume:** 0.5 s fade-out on pause and fade-in on resume, also for the notification and lock-screen buttons.
- **Gapless playback:** the next song is pre-loaded on the idle player shortly before the end of the current one and started by a timer at the exact remaining time (minus a small lead for the platform round trip). This avoids the load gap of the old single-player design, but it is timer-based, not sample-accurate like a single gapless decoder pipeline; a few milliseconds of difference between devices is possible.
- **Playlists:** Library > PLAYLISTS. Create, rename, delete, reorder (drag handle), play/shuffle, and add many songs at once with the multi-select picker. In the song list, long-press a song to select several and add them to a playlist or the queue. Playlists store MediaStore track ids locally on the device.
- **EQ:** Android devices commonly expose fewer native equalizer bands than the ten UI sliders. The app maps ten UI bands to the available native band centers and averages collisions. Preamp uses `LoudnessEnhancer`; bass boost uses `BassBoost`. Support and gain behavior vary by device/ROM; playback remains available if effects fail to initialize.
- **Artwork:** Android 10+ uses `ContentResolver.loadThumbnail`; older supported Android versions use embedded metadata fallback. Tracks without usable art display a letter cover.
- **Folder exclusions:** the app uses MediaStore to discover folders, then filters tracks in the app library and queue based on saved exclusions. The media index is still queried on rescan so folders remain discoverable and can be unhidden.
- **Splash duration:** the Flutter splash display lasts 3 seconds and animates the provided image. A short black native launch window may appear before Flutter renders, depending on device startup time.

## Push from Termux to a new GitHub repository

Extract the ZIP, enter the `aether_music` directory, and replace the example URL with your new empty repository:

```bash
git init -b main
git add .
git commit -m "Brand Krypton m.Player and improve Android playback controls"
git remote add origin https://github.com/YOUR-USERNAME/YOUR-REPO.git
git push -u origin main
```

Open the repository's **Actions** tab. After the workflow completes, open the **Android Release APK** run and download the `aether-release-apk` artifact.


### Volume stabilizer (ReplayGain)

The Android volume stabilizer reads ReplayGain metadata from each media file without decoding the song. It prefers `REPLAYGAIN_TRACK_GAIN` and `REPLAYGAIN_TRACK_PEAK`, falling back to the album values when track values are missing. It supports common ID3 TXXX, Vorbis-comment/APE-style key-value, and MP4/iTunes freeform tags. Peak data limits positive correction to reduce clipping risk. Positive corrections use Android's `LoudnessEnhancer`; negative corrections use per-player volume attenuation so the effect remains safe and each side of a crossfade keeps its own gain.

ReplayGain tags must already exist in the audio file for automatic track-to-track leveling. Files without ReplayGain tags play without a ReplayGain correction; the setting does not analyze the entire audio file or create tags. Android audio-effect support varies by device.

## External synced lyrics (.lrc)

The player looks for a timestamped LRC file with the same base filename as the current audio file, in that audio file's folder. For example, `Track.mp3` pairs with `Track.lrc`. The external sidecar is preferred; embedded ID3 USLT lyrics remain the fallback when the sidecar is absent or does not contain parseable timestamps.

On modern Android versions, go to **Settings → Library & Data → External synced lyrics (.lrc) → Choose**, then grant access to the highest common folder containing your music (for example, `Music`). This folder access is saved by Android so the player can look up sibling lyric files without asking every time. If your songs live in unrelated folders, choose a common parent if Android allows it, or change the granted folder to match the song location.
