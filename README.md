# Krypton Player

A native Android offline music-player starter built with Kotlin, Jetpack Compose and AndroidX Media3.

## Included

- Dark premium-minimalist player UI with library, now-playing, queue, and settings surfaces.
- Device audio discovery through Android's MediaStore (audio permission required).
- Background playback service using Media3 ExoPlayer and MediaSession.
- Android media notification, headset/media-button handling, and lock-screen transport controls through the media session.
- Metadata lyric lookup for common embedded lyric tags exposed by Media3 metadata, plus sidecar `.lrc` and `.txt` lookup.
- Timestamped LRC line highlighting.
- Playback queue, shuffle, repeat, playback speed, sleep timer UI, and equalizer entry point.
- GitHub Actions workflow to build a debug APK on pushes/PRs and publish an APK artifact; tagged builds create a GitHub Release.

## Build

1. Install Android Studio (current stable) and Android SDK Platform 35.
2. Open this folder in Android Studio.
3. Let Gradle sync, then run the `app` configuration on an Android 8.0+ device.
4. Grant music/audio permission when prompted.

Command line:

```bash
./gradlew assembleDebug
```

The APK is written to `app/build/outputs/apk/debug/app-debug.apk`.

## GitHub automatic builds

Push this project to a GitHub repository. The workflow at `.github/workflows/android.yml` builds on every push and pull request. Download `KryptonPlayer-debug-apk` from the Actions run's Artifacts section. Push a tag such as `v0.1.0` to publish a GitHub Release with the APK attached.

## Notes / next implementation steps

- The equalizer screen is a UI entry point; wire the platform `android.media.audiofx.Equalizer`, `BassBoost`, and `Virtualizer` to the active audio session before shipping.
- Embedded lyric formats vary by codec/container. The app checks common metadata keys when available and falls back to matching sidecar files. For broader format coverage, add a dedicated tag-reading library and test against your target formats.
- Android's system lock screen is driven by the Media3 media session/notification. The in-app full-screen player is a separate custom UI; Android does not allow an app to replace the system lock screen.
- Add a production signing configuration through GitHub Secrets before distributing a signed release APK. Never commit keystore files or passwords.
- This is a starter implementation, not a tested release build. Build and test on a physical device, especially background playback, scoped storage, and audio-effect behavior.
