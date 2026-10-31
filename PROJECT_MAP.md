# Project map

- `app/src/main/java/com/krypton/player/MainActivity.kt` — Compose UI and MediaController connection
- `MusicLibrary.kt` — MediaStore-based offline library scan
- `PlaybackService.kt` — Media3 background playback + MediaSession
- `LyricsReader.kt` — LRC/TXT parsing and embedded metadata lyric helper
- `PlaybackOptions.kt` — shuffle, repeat, playback speed helpers
- `.github/workflows/android.yml` — automated APK build and tagged release
