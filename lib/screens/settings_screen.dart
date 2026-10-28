import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../state/player_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/fading_sheet.dart';
import '../widgets/lockscreen_settings_panel.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.controller, required this.onBack, required this.onOpenEqualizer, required this.onOpenStats});

  final PlayerController controller;
  final VoidCallback onBack;
  final VoidCallback onOpenEqualizer;
  final VoidCallback onOpenStats;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: true,
      bottom: false,
      child: ListenableBuilder(
        listenable: controller,
        builder: (BuildContext context, Widget? _) {
          final AppSettings s = controller.settings;
          final Color accent = controller.accentColor;
          final int timer = s.sleepTimerMinutes ?? 0;
          final String timerLabel = controller.sleepTimeRemaining == null
              ? (timer == 0 ? 'Off' : '$timer min')
              : '${(controller.sleepTimeRemaining! / 60).ceil()} min remaining';
          final String accentName = s.accentMode == 'auto' ? 'Artwork' : s.accentMode.toUpperCase();
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
            children: <Widget>[
              Row(children: <Widget>[
                IconButton(onPressed: onBack, icon: Icon(Icons.arrow_back_rounded, color: AppColors.zinc300)),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text('PREFERENCES', style: AppText.mono(9, 700, accent, tracking: 0.15)),
                  Text('Settings', style: AppText.display(26, 700, Colors.white, lineHeight: 31)),
                ])),
              ]),
              const SizedBox(height: 12),
              _section('APPEARANCE', accent),
              _panel(Column(children: <Widget>[
                _row(
                  icon: s.lightMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                  title: 'Light mode',
                  subtitle: s.lightMode
                      ? 'Light surfaces with dark text'
                      : 'Dark AMOLED surfaces with light text',
                  trailing: Switch(
                    value: s.lightMode,
                    activeThumbColor: accent,
                    onChanged: (bool value) => controller.updateSettings(
                      s.copyWith(lightMode: value),
                    ),
                  ),
                ),
                Divider(height: 1, color: AppColors.white(0.07)),
                _row(
                  icon: Icons.palette_outlined,
                  title: 'Visual skin',
                  subtitle: 'Change the ambient accent palette',
                  trailing: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: <String>['amoled', 'cyberpunk', 'aurora', 'holo'].contains(s.theme) ? s.theme : 'amoled',
                      dropdownColor: AppColors.zinc900,
                      style: AppText.mono(9, 600, AppColors.zinc300),
                      items: const <DropdownMenuItem<String>>[
                        DropdownMenuItem<String>(value: 'amoled', child: Text('AMOLED')),
                        DropdownMenuItem<String>(value: 'cyberpunk', child: Text('CYBERPUNK')),
                        DropdownMenuItem<String>(value: 'aurora', child: Text('AURORA')),
                        DropdownMenuItem<String>(value: 'holo', child: Text('HOLO')),
                      ],
                      onChanged: (String? v) { if (v != null) controller.updateSettings(s.copyWith(theme: v)); },
                    ),
                  ),
                ),
                Divider(height: 1, color: AppColors.white(0.07)),
                _row(
                  icon: Icons.color_lens_outlined,
                  title: 'Accent color',
                  subtitle: 'Current: $accentName',
                  trailing: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: <String>['auto', '#00F0FF', '#8A2BE2', '#FF2E93'].contains(s.accentMode) ? s.accentMode : 'auto',
                      dropdownColor: AppColors.zinc900,
                      style: AppText.mono(9, 600, AppColors.zinc300),
                      items: const <DropdownMenuItem<String>>[
                        DropdownMenuItem<String>(value: 'auto', child: Text('ARTWORK')),
                        DropdownMenuItem<String>(value: '#00F0FF', child: Text('CYAN')),
                        DropdownMenuItem<String>(value: '#8A2BE2', child: Text('VIOLET')),
                        DropdownMenuItem<String>(value: '#FF2E93', child: Text('MAGENTA')),
                      ],
                      onChanged: (String? v) { if (v != null) controller.updateSettings(s.copyWith(accentMode: v)); },
                    ),
                  ),
                ),
                Divider(height: 1, color: AppColors.white(0.07)),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    Row(children: <Widget>[Icon(Icons.graphic_eq_rounded, size: 18, color: accent), const SizedBox(width: 10), Text('Visualizer style', style: AppText.body(12, 600, Colors.white))]),
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, children: <Widget>[
                      for (final VisualizerStyle style in VisualizerStyle.values)
                        ChoiceChip(
                          label: Text(style.name.toUpperCase(), style: AppText.mono(9, 700, s.visualizerStyle == style ? Colors.black : AppColors.zinc400)),
                          selected: s.visualizerStyle == style,
                          selectedColor: accent,
                          backgroundColor: AppColors.white(0.035),
                          side: BorderSide(color: AppColors.white(0.1)),
                          showCheckmark: false,
                          onSelected: (_) => controller.updateSettings(s.copyWith(visualizerStyle: style)),
                        ),
                    ]),
                  ]),
                ),
                Divider(height: 1, color: AppColors.white(0.07)),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    Row(children: <Widget>[
                      Icon(Icons.format_size_rounded, size: 18, color: accent),
                      const SizedBox(width: 10),
                      Expanded(child: Text('App font size', style: AppText.body(12, 600, Colors.white))),
                      Text('${(s.fontScale * 100).round()}%', style: AppText.mono(10, 700, accent)),
                    ]),
                    Slider(
                      value: s.fontScale.clamp(0.8, 1.4).toDouble(),
                      min: 0.8,
                      max: 1.4,
                      divisions: 12,
                      label: '${(s.fontScale * 100).round()}%',
                      activeColor: accent,
                      inactiveColor: AppColors.white(0.12),
                      onChanged: (double v) => controller.updateSettings(s.copyWith(fontScale: v)),
                    ),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: <Widget>[
                      Text('SMALL', style: AppText.mono(8, 600, AppColors.zinc500)),
                      Text('DEFAULT', style: AppText.mono(8, 600, AppColors.zinc500)),
                      Text('LARGE', style: AppText.mono(8, 600, AppColors.zinc500)),
                    ]),
                  ]),
                ),
                Divider(height: 1, color: AppColors.white(0.07)),
                _row(
                  icon: Icons.volume_up_rounded,
                  title: 'Volume stabilizer',
                  subtitle: s.volumeStabilizerEnabled
                      ? 'Uses ReplayGain tags; analyzes untagged songs on first play'
                      : 'Disabled: no ReplayGain correction or loudness scans',
                  trailing: Switch(
                    value: s.volumeStabilizerEnabled,
                    activeThumbColor: accent,
                    onChanged: (bool value) => controller.updateSettings(
                      s.copyWith(volumeStabilizerEnabled: value),
                    ),
                  ),
                ),
              ])),
              const SizedBox(height: 16),
              _section('SYSTEM LOCK SCREEN', accent),
              _panel(Column(children: <Widget>[
                _row(
                  icon: Icons.lock_outline_rounded,
                  title: 'System lock-screen player',
                  subtitle: s.lockscreenPlayerEnabled ? 'Metadata and controls enabled for lock screen + notification' : 'Transport controls hidden from lock screen + notification',
                  trailing: Switch(
                    value: s.lockscreenPlayerEnabled,
                    activeThumbColor: accent,
                    onChanged: (bool value) => controller.updateSettings(s.copyWith(lockscreenPlayerEnabled: value)),
                  ),
                ),
                if (s.lockscreenPlayerEnabled) ...<Widget>[
                  Divider(height: 1, color: AppColors.white(0.07)),
                  _row(
                    icon: Icons.skip_previous_rounded,
                    title: 'Previous button',
                    subtitle: 'Show Previous in lock-screen and notification controls',
                    trailing: Switch(
                      value: s.lockscreenShowPrevious,
                      activeThumbColor: accent,
                      onChanged: (bool value) => controller.updateSettings(s.copyWith(lockscreenShowPrevious: value)),
                    ),
                  ),
                  Divider(height: 1, color: AppColors.white(0.07)),
                  _row(
                    icon: Icons.skip_next_rounded,
                    title: 'Next button',
                    subtitle: 'Show Next in lock-screen and notification controls',
                    trailing: Switch(
                      value: s.lockscreenShowNext,
                      activeThumbColor: accent,
                      onChanged: (bool value) => controller.updateSettings(s.copyWith(lockscreenShowNext: value)),
                    ),
                  ),
                ],
              ])),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.panelBackground,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.white(0.08)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      key: const PageStorageKey<String>('screenlock-kry-player-settings'),
                      initiallyExpanded: false,
                      tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                      childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                      leading: Icon(Icons.phonelink_lock_rounded, color: accent, size: 19),
                      title: Text('SCREENLOCK KRY PLAYER', style: AppText.mono(9, 700, accent, tracking: 0.15)),
                      subtitle: Text(
                        s.lockscreen.enabled
                            ? 'Custom lock-screen enabled · Tap to configure'
                            : 'Tap to configure the custom lock-screen player',
                        style: AppText.body(10, 400, AppColors.zinc500, lineHeight: 15),
                      ),
                      collapsedIconColor: accent,
                      iconColor: accent,
                      backgroundColor: Colors.transparent,
                      collapsedBackgroundColor: Colors.transparent,
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                      collapsedShape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                      children: <Widget>[
                        LockscreenSettingsPanel(controller: controller, accent: accent),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _section('PLAYBACK', accent),
              _panel(Column(children: <Widget>[
                _row(
                  icon: Icons.swap_horiz_rounded,
                  title: 'Fading',
                  subtitle: s.crossfadeDuration == 0
                      ? (s.gapless ? 'Off · gapless switch between songs' : 'Off')
                      : 'Crossfade ${s.crossfadeDuration} sec · songs overlap while one fades out and the next fades in',
                  trailing: OutlinedButton(
                    onPressed: () => showFadingSheet(context, controller),
                    style: OutlinedButton.styleFrom(foregroundColor: accent, side: BorderSide(color: accent.withValues(alpha: 0.55)), padding: const EdgeInsets.symmetric(horizontal: 12)),
                    child: Text(s.crossfadeDuration == 0 ? 'OFF' : '${s.crossfadeDuration} S', style: AppText.mono(9, 700, accent)),
                  ),
                ),
                Divider(height: 1, color: AppColors.white(0.07)),
                _row(
                  icon: Icons.nightlight_round,
                  title: 'Sleep timer',
                  subtitle: timerLabel,
                  trailing: Wrap(spacing: 4, children: <Widget>[
                    _timerButton(context, 15, timer, accent),
                    _timerButton(context, 30, timer, accent),
                    _timerButton(context, 60, timer, accent),
                    IconButton(tooltip: 'Disable sleep timer', onPressed: () => controller.setSleepTimer(null), icon: Icon(Icons.close_rounded, size: 17, color: AppColors.zinc500)),
                  ]),
                ),
                Divider(height: 1, color: AppColors.white(0.07)),
                _row(
                  icon: Icons.equalizer_rounded,
                  title: 'EQ Lab',
                  subtitle: s.eqEnabled ? 'Equalizer enabled' : 'Effects bypassed',
                  trailing: OutlinedButton(onPressed: onOpenEqualizer, style: OutlinedButton.styleFrom(foregroundColor: accent, side: BorderSide(color: accent.withValues(alpha: 0.55)), padding: const EdgeInsets.symmetric(horizontal: 12)), child: Text('OPEN', style: AppText.mono(9, 700, accent))),
                ),
              ])),
              const SizedBox(height: 16),
              _section('LIBRARY & DATA', accent),
              _panel(Column(children: <Widget>[
                _row(
                  icon: Icons.library_music_rounded,
                  title: 'Local music library',
                  subtitle: '${controller.tracks.length} tracks visible · ${controller.availableFolders.length} folders found',
                  trailing: OutlinedButton(onPressed: controller.scanning ? null : controller.scan, style: OutlinedButton.styleFrom(foregroundColor: AppColors.zinc300, side: BorderSide(color: AppColors.white(0.12)), padding: const EdgeInsets.symmetric(horizontal: 12)), child: Text(controller.scanning ? 'SCANNING' : 'RESCAN', style: AppText.mono(9, 700, controller.scanning ? AppColors.zinc600 : AppColors.zinc300))),
                ),
                Divider(height: 1, color: AppColors.white(0.07)),
                _row(
                  icon: Icons.subtitles_outlined,
                  title: 'External synced lyrics (.lrc)',
                  subtitle: controller.externalLyricsFolder == null
                      ? 'Choose the music folder once to allow matching .lrc files'
                      : 'Folder access: ${controller.externalLyricsFolder}',
                  trailing: OutlinedButton(
                    onPressed: controller.chooseExternalLyricsFolder,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: accent,
                      side: BorderSide(color: accent.withValues(alpha: 0.55)),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: Text(
                      controller.externalLyricsFolder == null ? 'CHOOSE' : 'CHANGE',
                      style: AppText.mono(9, 700, accent),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 29, right: 4, bottom: 9),
                  child: Text(
                    'Select the highest common folder containing your songs (for example Music). Files must share the song filename, such as Track.mp3 and Track.lrc.',
                    style: AppText.body(9, 400, AppColors.zinc600, lineHeight: 14),
                  ),
                ),
                Divider(height: 1, color: AppColors.white(0.07)),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(left: 2, right: 2, bottom: 8),
                  leading: Icon(Icons.folder_off_outlined, color: accent, size: 20),
                  title: Text('Hide folders from library scan', style: AppText.body(12, 600, Colors.white)),
                  subtitle: Text('${s.hiddenFolders.length} excluded folder${s.hiddenFolders.length == 1 ? '' : 's'}', style: AppText.body(10, 400, AppColors.zinc500)),
                  iconColor: accent,
                  collapsedIconColor: AppColors.zinc500,
                  children: controller.availableFolders.isEmpty
                      ? <Widget>[
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text('Scan the device music library to find folders.', style: AppText.body(11, 400, AppColors.zinc500)),
                          ),
                        ]
                      : <Widget>[
                          for (final String folder in controller.availableFolders)
                            SwitchListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                              dense: true,
                              activeThumbColor: accent,
                              value: s.hiddenFolders.contains(folder),
                              title: Text(folder, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppText.body(10, 600, Colors.white)),
                              subtitle: Text('Exclude these tracks from the library and queue', style: AppText.body(9, 400, AppColors.zinc600)),
                              onChanged: (bool hidden) => controller.setFolderHidden(folder, hidden),
                            ),
                        ],
                ),
                Divider(height: 1, color: AppColors.white(0.07)),
                _row(
                  icon: Icons.insights_rounded,
                  title: 'Listening statistics',
                  subtitle: 'Real listen time stored locally on this device',
                  trailing: IconButton(onPressed: onOpenStats, icon: Icon(Icons.arrow_forward_ios_rounded, size: 16, color: accent)),
                ),
                Divider(height: 1, color: AppColors.white(0.07)),
                _row(
                  icon: Icons.security_rounded,
                  title: 'Audio permissions',
                  subtitle: 'Music: ${controller.mediaGranted ? 'granted' : 'missing'}  ·  visualizer: procedural (no recording permission)  ·  notifications: ${controller.notificationsGranted ? 'granted' : 'disabled'}',
                  trailing: TextButton(
                    onPressed: controller.notificationsGranted ? controller.openSystemSettings : controller.requestNotificationPermission,
                    child: Text(controller.notificationsGranted ? 'SYSTEM' : 'ENABLE', style: AppText.mono(9, 700, accent)),
                  ),
                ),
              ])),
              const SizedBox(height: 16),
              _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text('KRYPTON m.PLAYER / NATIVE AUDIO', style: AppText.mono(10, 700, accent, tracking: 0.1)),
                const SizedBox(height: 6),
                Text('Settings, favorites, queue and playback session are stored locally. The EQ uses Android audio effects when available. Album artwork and listening history stay local to this device.', style: AppText.body(10, 400, AppColors.zinc500, lineHeight: 16)),
              ])),
            ],
          );
        },
      ),
    );
  }

  Widget _timerButton(BuildContext context, int minutes, int current, Color accent) {
    return TextButton(
      onPressed: () => controller.setSleepTimer(minutes),
      style: TextButton.styleFrom(
        minimumSize: const Size(30, 30),
        padding: const EdgeInsets.symmetric(horizontal: 7),
        backgroundColor: current == minutes ? accent.withValues(alpha: 0.15) : Colors.transparent,
        foregroundColor: current == minutes ? accent : AppColors.zinc500,
      ),
      child: Text('$minutes', style: AppText.mono(9, 700, current == minutes ? accent : AppColors.zinc500)),
    );
  }

  Widget _section(String label, Color accent) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(label, style: AppText.mono(9, 700, accent, tracking: 0.15)),
  );

  Widget _row({required IconData icon, required String title, required String subtitle, required Widget trailing}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(children: <Widget>[
      Icon(icon, size: 19, color: AppColors.zinc400),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text(title, style: AppText.body(12, 600, Colors.white)),
        const SizedBox(height: 3),
        Text(subtitle, style: AppText.body(10, 400, AppColors.zinc500, lineHeight: 15)),
      ])),
      const SizedBox(width: 8),
      trailing,
    ]),
  );
}

Widget _panel(Widget child) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
  decoration: BoxDecoration(color: AppColors.panelBackground, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.white(0.08))),
  child: child,
);
