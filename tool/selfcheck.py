#!/usr/bin/env python3
"""Static self-check (no Flutter SDK needed): imports, assets, manifest refs, bracket balance."""
import os, re, sys

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
errors = []

# pubspec dependencies
pub = open(os.path.join(root, 'pubspec.yaml')).read()
deps = set(re.findall(r'^  ([a-z_]+):', pub.split('dependencies:')[1].split('flutter:\n  uses')[0], re.M))
deps.add('flutter')
sdk_libs = {'dart:async','dart:io','dart:math','dart:typed_data','dart:ui','dart:convert'}

# Dart imports
for dp, _, fs in os.walk(os.path.join(root, 'lib')):
    for f in fs:
        if not f.endswith('.dart'): continue
        path = os.path.join(dp, f)
        src = open(path).read()
        for m in re.finditer(r"^import '([^']+)'", src, re.M):
            imp = m.group(1)
            if imp.startswith('dart:'):
                if imp not in sdk_libs: errors.append(f'{path}: unknown sdk lib {imp}')
            elif imp.startswith('package:'):
                pkg = imp[8:].split('/')[0]
                if pkg == 'aether_music':
                    errors.append(f'{path}: use relative imports {imp}')
                elif pkg not in deps:
                    errors.append(f'{path}: package {pkg} not in pubspec')
            else:
                target = os.path.normpath(os.path.join(dp, imp))
                if not os.path.exists(target): errors.append(f'{path}: missing {imp}')
        # bracket balance (strip strings/comments crudely)
        s = re.sub(r"'(?:\\.|[^'\\\n])*'", "''", src)
        s = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', s)
        s = re.sub(r'//.*', '', s)
        for a, b in ('()', '[]', '{}'):
            if s.count(a) != s.count(b):
                errors.append(f'{path}: unbalanced {a}{b} ({s.count(a)} vs {s.count(b)})')

# declared assets (fonts are downloaded by CI before build)
for a in re.findall(r'asset: (\S+)', pub):
    if not os.path.exists(os.path.join(root, a)) and not a.startswith('assets/fonts/'):
        errors.append(f'pubspec asset missing: {a}')
if 'tool/fetch_fonts.sh' not in open(os.path.join(root, '.github/workflows/build.yml')).read():
    errors.append('workflow does not fetch fonts')
if 'chmod +x android/gradlew' not in open(os.path.join(root, '.github/workflows/build.yml')).read():
    errors.append('workflow does not make Gradle wrapper executable')
for a in re.findall(r'asset: assets/fonts/(\S+)', pub):
    if a not in open(os.path.join(root, 'tool/fetch_fonts.sh')).read():
        errors.append(f'font {a} not produced by fetch_fonts.sh')

# Android manifest + resources
res = os.path.join(root, 'android/app/src/main/res')
man = open(os.path.join(root, 'android/app/src/main/AndroidManifest.xml')).read()
def res_exists(kind, name):
    for d in os.listdir(res):
        if d.split('-')[0] == kind:
            for f in os.listdir(os.path.join(res, d)):
                if f.rsplit('.', 1)[0] == name: return True
    return False
allxml = man
for dp, _, fs in os.walk(res):
    for f in fs:
        if f.endswith('.xml'): allxml += open(os.path.join(dp, f)).read()
for kind, name in set(re.findall(r'@(drawable|mipmap|style|color|string)/([A-Za-z0-9_]+)', allxml)):
    if kind in ('drawable', 'mipmap'):
        ok = res_exists(kind, name)
    else:
        ok = False
        for f in os.listdir(os.path.join(res, 'values')):
            if re.search(r'name="%s"' % name, open(os.path.join(res, 'values', f)).read()): ok = True
    if not ok: errors.append(f'manifest/resource ref missing: @{kind}/{name}')
if 'drawable/ic_notification' not in open(os.path.join(root, 'lib/main.dart')).read():
    errors.append('notification icon not wired')
k = os.path.join(root, 'android/app/src/main/kotlin/com/aether/music/MainActivity.kt')
if not os.path.exists(k): errors.append('MainActivity.kt missing')
ks = open(k).read()
for a, b in ('()', '[]', '{}'):
    if ks.count(a) != ks.count(b): errors.append(f'MainActivity.kt unbalanced {a}{b}')
# every MethodChannel method Dart calls exists in Kotlin
for m in set(re.findall(r"invoke(?:Map|List)?Method(?:<[^>]*>)?\('(\w+)'", open(os.path.join(root, 'lib/services/native_bridge.dart')).read())):
    if f'"{m}"' not in ks: errors.append(f'Kotlin does not handle method {m}')
for cls in ('applicationId = "com.aether.music"', 'minSdk = 26', 'targetSdk = 35'):
    if cls not in open(os.path.join(root, 'android/app/build.gradle.kts')).read(): errors.append(f'gradle missing {cls}')
if '-Xmx4096m' not in open(os.path.join(root, 'android/gradle.properties')).read(): errors.append('jvmargs missing')
for p in ('READ_MEDIA_AUDIO', 'READ_EXTERNAL_STORAGE', 'POST_NOTIFICATIONS', 'FOREGROUND_SERVICE_MEDIA_PLAYBACK'):
    if p not in man: errors.append(f'manifest permission missing {p}')
if 'RECORD_AUDIO' in man: errors.append('recording permission must not be declared for procedural visualizers')
if 'foregroundServiceType="mediaPlayback"' not in man: errors.append('service type missing')

# Build delivery checks: required wrapper is tracked and CI must build release, not debug.
workflow = open(os.path.join(root, '.github/workflows/build.yml')).read()
if 'flutter build apk --release' not in workflow: errors.append('workflow does not build a release APK')
if 'flutter build apk --debug' in workflow: errors.append('workflow still builds a debug APK')
if 'aether-release-apk' not in workflow: errors.append('workflow release artifact name missing')
if 'if-no-files-found: error' not in workflow: errors.append('workflow can silently upload no APK')
wrapper = os.path.join(root, 'android/gradlew')
if not os.path.isfile(wrapper): errors.append('android/gradlew missing; Flutter cannot invoke the Gradle build')
if os.path.isfile(wrapper) and not os.access(wrapper, os.X_OK): errors.append('android/gradlew is not executable')
if not os.path.isfile(os.path.join(root, 'android/gradlew.bat')): errors.append('android/gradlew.bat missing')
gitignore = open(os.path.join(root, '.gitignore')).read()
for required_path in ('android/gradlew', 'android/gradlew.bat'):
    if required_path in gitignore: errors.append(f'required build wrapper is ignored: {required_path}')
if 'applyAudioEffects' not in open(os.path.join(root, 'android/app/src/main/kotlin/com/aether/music/MainActivity.kt')).read():
    errors.append('native EQ method handler missing')
for required in ('lib/screens/library_screen.dart', 'lib/screens/equalizer_screen.dart', 'lib/screens/stats_screen.dart', 'lib/screens/settings_screen.dart', 'lib/widgets/queue_sheet.dart', 'lib/widgets/mini_player.dart', 'lib/widgets/track_options_sheet.dart'):
    if not os.path.isfile(os.path.join(root, required)): errors.append(f'missing Step 2/3 module: {required}')


# Brand assets and new requested settings
for asset in ('assets/images/guy_donn_splash.jpg', 'assets/images/krypton_app_icon.jpg'):
    if not os.path.isfile(os.path.join(root, asset)):
        errors.append(f'missing requested image asset: {asset}')
for density in ('mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi'):
    for icon in ('ic_launcher.png', 'ic_launcher_round.png'):
        path = os.path.join(res, f'mipmap-{density}', icon)
        if not os.path.isfile(path): errors.append(f'missing launcher icon: {path}')
if not os.path.isfile(os.path.join(res, 'drawable-nodpi', 'ic_launcher_foreground.png')):
    errors.append('adaptive launcher foreground bitmap missing')
if 'Krypton m.Player' not in open(os.path.join(root, 'android/app/src/main/res/values/strings.xml')).read():
    errors.append('Android app display name was not changed to Krypton m.Player')
model = open(os.path.join(root, 'lib/models/app_settings.dart')).read()
for field in ('hiddenFolders', 'lockscreenPlayerEnabled', 'lockscreenShowPrevious', 'lockscreenShowNext', 'fontScale'):
    if field not in model: errors.append(f'AppSettings missing requested field {field}')
if 'assets/images/' not in pub: errors.append('image asset directory is not declared in pubspec')
if 'KryptonSplashScreen' not in open(os.path.join(root, 'lib/app.dart')).read():
    errors.append('animated splash screen is not wired into the app shell')
settings_ui = open(os.path.join(root, 'lib/screens/settings_screen.dart')).read()
lockscreen_settings = open(os.path.join(root, 'lib/models/lockscreen_settings.dart')).read()
lockscreen_panel = open(os.path.join(root, 'lib/widgets/lockscreen_settings_panel.dart')).read()
lockscreen_activity = open(os.path.join(root, 'android/app/src/main/kotlin/com/aether/music/LockScreenActivity.kt')).read()
if 'initiallyExpanded: false' not in settings_ui or 'screenlock-kry-player-settings' not in settings_ui:
    errors.append('Screenlock KRY Player settings should be collapsed by default')
if "'transportButtonScale': 100" not in lockscreen_settings or "'Transport button size'" not in lockscreen_panel:
    errors.append('custom lock-screen transport button size setting is missing')
if 'LockState.number("transportButtonScale", 100)' not in lockscreen_activity:
    errors.append('native lock-screen transport buttons do not use the saved size setting')
if '0xFFFFF08A' in lockscreen_activity:
    errors.append('custom lock-screen play/previous/next buttons should use white, not the old yellow tint')
for required_ui in ('App font size', 'System lock-screen player', 'Previous button', 'Next button', 'Hide folders from library scan'):
    if required_ui not in settings_ui: errors.append(f'settings UI missing {required_ui}')
main_source = open(os.path.join(root, 'lib/main.dart')).read()
if 'androidNotificationOngoing: false' not in main_source or 'androidStopForegroundOnPause: false' not in main_source:
    errors.append('media service must stay in foreground mode while paused (Android 12+ blocks re-entering it from the background)')
keep_xml = os.path.join(res, 'raw', 'keep.xml')
if not os.path.isfile(keep_xml) or '@drawable/ic_notification' not in open(keep_xml).read():
    errors.append('res/raw/keep.xml must keep drawable/ic_notification from the release resource shrinker')
gradle_app = open(os.path.join(root, 'android/app/build.gradle.kts')).read()
if 'isShrinkResources = false' not in gradle_app:
    errors.append('release build must not shrink resources (notification icon is looked up by name)')
handler_source = open(os.path.join(root, 'lib/services/audio_handler.dart')).read()
if '.pause();' in handler_source.split('Future<bool> _loadTrackImpl')[1].split('setAudioSource(')[0]:
    errors.append('track loading must not pause the player before replacing the source (it drops the foreground service)')
if '_artCache' not in handler_source:
    errors.append('artwork is not cached per track, it can be lost when the media item is replaced')
if "id: track.uri" not in handler_source:
    errors.append('media item id is not a playable URI for Android MediaSession')
if 'p.playerStateStream.listen(' not in handler_source or 'identical(p, _active)' not in handler_source:
    errors.append('media notification does not mirror player play/pause state transitions')
if 'await sub.cancel();' not in handler_source:
    errors.append('player-state stream subscription is not disposed')
if 'Future<void> next({' not in open(os.path.join(root, 'lib/state/player_controller.dart')).read() or 'String? expectedTrackId' not in open(os.path.join(root, 'lib/state/player_controller.dart')).read():
    errors.append('player next handler is not awaitable from media controls')
controller_source = open(os.path.join(root, 'lib/state/player_controller.dart')).read()
if 'unawaited(incoming.play()' not in handler_source or handler_source.index('unawaited(incoming.play()') > handler_source.index('_activate(incoming);'):
    errors.append('incoming player must start playing before it is published as active (keeps the foreground service alive)')
if 'handler.positionStream.listen' not in controller_source:
    errors.append('controller must listen to the handler streams, not to a single player (players swap during fades)')
if 'clamp(0, 30)' not in open(os.path.join(root, 'lib/models/app_settings.dart')).read():
    errors.append('fade length must allow up to 30 seconds')
if 'handler.onSkipNext = () => next();' not in controller_source or 'handler.onSkipPrevious = () => prev();' not in controller_source:
    errors.append('media notification skip callbacks are not wired to the controller')
if 'await _loadAuxiliarySafely(t)' not in controller_source and 'unawaited(_loadAuxiliarySafely(t))' not in controller_source:
    errors.append('track artwork and metadata work is not isolated from playback errors')
if 'Future<void> prev() => _serializeTrackTransition<void>(_prevImpl);' not in controller_source or 'tracks[(activeIndex - 1 - offset + tracks.length) % tracks.length]' not in controller_source:
    errors.append('previous-track fallback for empty history is missing')

# Queue-transition regression checks: changes should serialize, commit only after a
# successful source load, and keep a failed queue item instead of silently consuming it.
if '_serializeTrackTransition<T>' not in controller_source or 'Future<void> _trackTransitionTail' not in controller_source:
    errors.append('track transitions are not serialized')
if 'Future<void> playQueuedTrack(Track track)' not in controller_source or 'controller.playQueuedTrack(track)' not in open(os.path.join(root, 'lib/widgets/queue_sheet.dart')).read():
    errors.append('playing a queue item does not preserve the custom queue path')
if 'void _moveQueuedTrackToEnd(String id)' not in controller_source or 'if (!loaded) {\n        if (fromQueue && !queueChangedDuringTransition) {' not in controller_source:
    errors.append('failed queue items are not retained and moved out of the immediate way')
if 'if (!loaded) {\n        // A failed/superseded load must not change currentTrack or clear queue state.\n        return false;\n      }\n\n      currentTrack = t;' not in controller_source:
    errors.append('track controller state is committed before a successful load')
if 'if (generation != _loadGeneration) return false;' not in handler_source:
    errors.append('superseded native loads can still report success')
if 'if (expectedTrackId != null && currentTrack?.id != expectedTrackId) return;' not in controller_source:
    errors.append('stale automatic advances are not rejected after a manual transition')

# Latest performance/privacy regression checks.
controller_source = open(os.path.join(root, 'lib/state/player_controller.dart')).read()
storage_source = open(os.path.join(root, 'lib/services/storage.dart')).read()
visualizer_source = open(os.path.join(root, 'lib/widgets/audio_visualizer.dart')).read()
bridge_source = open(os.path.join(root, 'lib/services/native_bridge.dart')).read()
activity_source = open(os.path.join(root, 'android/app/src/main/kotlin/com/aether/music/MainActivity.kt')).read()
effect_manager_path = os.path.join(root, 'android/app/src/main/kotlin/com/aether/music/AudioEffectManager.kt')
effect_manager_source = open(effect_manager_path).read() if os.path.isfile(effect_manager_path) else activity_source
if '_currentTrackPlayedMs >= thresholdMs' not in controller_source:
    errors.append('play counts are not qualified by actual half-track listening time')
if 'stats.bundle' not in storage_source or 'flushListeningStats' not in controller_source:
    errors.append('listening statistics are not batched into one persisted bundle')
if 'com.aether.music/visualizer' in bridge_source or 'startVisualizer' in bridge_source:
    errors.append('Dart bridge still exposes native audio-capture visualizer calls')
if 'android.media.audiofx.Visualizer' in activity_source or 'startVisualizer' in activity_source:
    errors.append('native audio-capture visualizer code remains in MainActivity')
if 'canvas.saveLayer(' in visualizer_source:
    errors.append('procedural visualizer allocates a GPU layer per painted bar')


# ReplayGain correctness checks.
handler_source = open(os.path.join(root, 'lib/services/audio_handler.dart')).read()
if "'readReplayGain'" not in bridge_source or '"readReplayGain"' not in activity_source:
    errors.append('ReplayGain tag reader is not wired through the native bridge')
if 'replaygain_track_gain' not in activity_source.lower() or 'replaygain_album_gain' not in activity_source.lower():
    errors.append('ReplayGain parser must support track and album gain tags')
if 'replaygain_track_peak' not in activity_source.lower() or 'maximumSafeGainDb' not in effect_manager_source:
    errors.append('ReplayGain peak protection is missing')
if 'stabilizerGainMb = if (volumeStabilizer) 500 else 0' in activity_source:
    errors.append('volume stabilizer still applies a fixed +5 dB boost instead of ReplayGain')
if 'prepareSessionEffects: prepareSessionEffects' not in handler_source or 'await prepareSessionEffects?.call(sessionId, track)' not in handler_source:
    errors.append('ReplayGain/EQ effects are not prepared per track before playback/crossfade')
if '_trackVolumeMultiplier' not in controller_source or '_volumeFor(_active)' not in handler_source:
    errors.append('negative ReplayGain attenuation is not applied per audio player')
if 'coerceIn(0, 1200)' not in effect_manager_source:
    errors.append('native LoudnessEnhancer target gain is not clamped to non-negative boost values')
if 'ReplayGain tags' not in settings_ui:
    errors.append('volume stabilizer description does not explain ReplayGain tags')

# Regressions for this change: screen timeout, sidecar monitor, and process-owned audio effects.
app_source = open(os.path.join(root, 'android/app/src/main/kotlin/com/aether/music/KryptonApplication.kt')).read()
lock_activity_source = open(os.path.join(root, 'android/app/src/main/kotlin/com/aether/music/LockScreenActivity.kt')).read()
lyrics_monitor_source = open(os.path.join(root, 'android/app/src/main/kotlin/com/aether/music/LyricsFileMonitor.kt')).read()
if 'LockLauncher.launchIfNeeded(context.applicationContext, false)' in app_source:
    errors.append('screen-off receiver still launches the custom lock screen while Android is turning the display off')
if 'launchAfterScreenOn' not in app_source or 'FLAG_KEEP_SCREEN_ON' not in lock_activity_source:
    errors.append('custom lock screen must explicitly obey Android screen-off behavior')
if 'ContentObserver' not in lyrics_monitor_source or 'CHANGE_TOKEN_KEY' not in lyrics_monitor_source:
    errors.append('automatic .lrc change monitor is missing')
if 'getExternalLyricsChangeToken' not in bridge_source or '_lyricsMonitorTimer' not in controller_source:
    errors.append('Dart lyrics controller is not polling native lyrics change notifications')
if 'object AudioEffectManager' not in effect_manager_source or 'effectsBySession' not in effect_manager_source:
    errors.append('native audio effects are not owned by a process-level session manager')
if 'releaseAudioEffects()' in activity_source.split('override fun onDestroy()')[1]:
    errors.append('MainActivity destroys audio effects along with the UI Activity')
if 'unawaited(NativeBridge.releaseAudioEffects())' in controller_source:
    errors.append('PlayerController dispose still releases effects while background audio can continue')


# Analyzer regression guards for APIs deprecated in the pinned Flutter 3.41 line.
# Keep these narrow to avoid flagging valid properties such as Slider.activeColor.
all_dart = '\n'.join(
    open(os.path.join(dp, f), encoding='utf-8').read()
    for dp, _, fs in os.walk(os.path.join(root, 'lib'))
    for f in fs if f.endswith('.dart')
)

# Background UI resource-saving regression guards.
app_ui_source = open(os.path.join(root, 'lib/app.dart'), encoding='utf-8').read()
lockscreen_ui_source = open(os.path.join(root, 'lib/widgets/lockscreen_player.dart'), encoding='utf-8').read()
if 'TickerMode(' not in app_ui_source or 'enabled: uiForeground' not in app_ui_source:
    errors.append('Flutter animations are not muted while the UI is backgrounded')
if 'return DynamicBackground(' not in app_ui_source or 'if (!uiForeground)' not in app_ui_source:
    errors.append('expensive blurred background is not removed while the UI is hidden')
if 'if (_isForeground && style == VisualizerStyle.radial)' not in lockscreen_ui_source or 'if (_isForeground && style != VisualizerStyle.radial)' not in lockscreen_ui_source:
    errors.append('procedural visualizer widgets are not removed while the UI is hidden')
if '_clock?.cancel();' not in lockscreen_ui_source or '_visualizerSwitchTimer?.cancel();' not in lockscreen_ui_source:
    errors.append('lockscreen UI timers are not suspended in background')
if '_stopLyricsMonitor();' not in open(os.path.join(root, 'lib/state/player_controller.dart'), encoding='utf-8').read():
    errors.append('external lyrics polling is not stopped while the UI is hidden')

bridge_source = open(os.path.join(root, 'lib/services/native_bridge.dart'), encoding='utf-8').read()
if re.search(r'\bdialogBackgroundColor\s*:', all_dart):
    errors.append('deprecated ThemeData.dialogBackgroundColor found; use DialogThemeData.backgroundColor')
if re.search(r'\.withOpacity\s*\(', all_dart):
    errors.append('deprecated Color.withOpacity found; use Color.withValues(alpha: ...)')
if re.search(r'\btextScaleFactor\s*:', all_dart) or 'textScaleFactorOf(' in all_dart:
    errors.append('deprecated textScaleFactor API found; use TextScaler APIs')
if re.search(r'\bcacheExtent(?:Style)?\s*:', all_dart):
    errors.append('deprecated cacheExtent API found; use the current scrolling/cache API')
if "import 'dart:typed_data';" in bridge_source:
    errors.append('native_bridge.dart has an unnecessary dart:typed_data import (services.dart exports Uint8List)')
if "import 'dart:async';" in bridge_source:
    errors.append('native_bridge.dart has an unnecessary dart:async import')
if 'MaterialStateProperty' in all_dart or re.search(r'\bMaterialState\.', all_dart):
    errors.append('deprecated MaterialState API found; use WidgetState APIs')


def constructor_bodies(source, names):
    """Return argument text for matching Dart constructors, respecting nested calls."""
    bodies = []
    for name in names:
        pattern = re.compile(r'(?<![A-Za-z0-9_$])' + re.escape(name) + r'\s*\(')
        for match in pattern.finditer(source):
            i = match.end()
            start = i
            depth = 1
            quote = None
            triple = False
            escaped = False
            while i < len(source) and depth:
                ch = source[i]
                if quote is not None:
                    if escaped:
                        escaped = False
                    elif ch == '\\':
                        escaped = True
                    elif triple and source.startswith(quote * 3, i):
                        quote = None
                        triple = False
                        i += 2
                    elif not triple and ch == quote:
                        quote = None
                else:
                    if source.startswith('//', i):
                        newline = source.find('\n', i + 2)
                        i = len(source) if newline < 0 else newline
                        continue
                    if source.startswith('/*', i):
                        close = source.find('*/', i + 2)
                        i = len(source) if close < 0 else close + 2
                        continue
                    if ch in ('\\\'', '"'):
                        # Raw strings are handled by entering at their quote character too.
                        quote = ch
                        triple = source.startswith(ch * 3, i)
                        if triple:
                            i += 2
                    elif ch == '(':
                        depth += 1
                    elif ch == ')':
                        depth -= 1
                        if depth == 0:
                            bodies.append((name, source[start:i]))
                            break
                i += 1
    return bodies


for widget_name, body in constructor_bodies(all_dart, ('Switch', 'SwitchListTile')):
    if re.search(r'\bactiveColor\s*:', body):
        errors.append(f'deprecated {widget_name}.activeColor found; use activeThumbColor/activeTrackColor')
for widget_name, body in constructor_bodies(all_dart, ('DropdownButtonFormField',)):
    if re.search(r'\bvalue\s*:', body):
        errors.append('deprecated DropdownButtonFormField.value found; use initialValue')
for widget_name, body in constructor_bodies(all_dart, ('Radio', 'RadioListTile')):
    if re.search(r'\b(groupValue|onChanged)\s*:', body):
        errors.append(f'deprecated {widget_name} radio-group properties found; use RadioGroup')

# This project should check analysis during pull requests too, not just after merge.
# External sibling LRC support must be reachable from settings, Dart and Android SAF.
activity_source = open(os.path.join(root, 'android/app/src/main/kotlin/com/aether/music/MainActivity.kt'), encoding='utf-8').read()
if 'readExternalLyrics' not in bridge_source or "'readExternalLyrics'" not in bridge_source:
    errors.append('external LRC reader is not wired through NativeBridge')
if 'readLrcFromGrantedTree' not in activity_source or 'takePersistableUriPermission' not in activity_source:
    errors.append('external LRC lookup must support a persisted Android folder grant')
if 'chooseExternalLyricsFolder' not in controller_source or 'External synced lyrics (.lrc)' not in settings_ui:
    errors.append('external LRC folder selection is not wired through settings')
readme_text = open(os.path.join(root, 'README.md'), encoding='utf-8').read()
if 'Track.mp3' not in readme_text or 'Track.lrc' not in readme_text:
    errors.append('README does not explain external LRC filename matching')

if 'pull_request:' not in workflow:
    errors.append('workflow should run its checks for pull requests before merge')

# pubspec.lock is intentionally checked as a notice rather than a failure so this
# source package remains buildable; committing it makes dependency resolution reproducible.
if not os.path.isfile(os.path.join(root, 'pubspec.lock')):
    print('NOTICE: pubspec.lock is absent; CI will resolve compatible dependency versions on each run.')

print('SELF-CHECK FAILED' if errors else 'SELF-CHECK PASSED')
for e in errors: print(' -', e)
sys.exit(1 if errors else 0)
