import 'package:flutter/material.dart';

import '../models/lockscreen_settings.dart';
import '../state/player_controller.dart';
import '../theme/app_theme.dart';

/// Settings > Screenlock KRY player.
///
/// Master switch off  -> Android's own music lock-screen card is used (the section
/// above it still decides which buttons that card shows).
/// Master switch on   -> the custom slide-to-unlock player is shown over the lock
/// screen, built from the toggles below.
class LockscreenSettingsPanel extends StatelessWidget {
  const LockscreenSettingsPanel({super.key, required this.controller, required this.accent});

  final PlayerController controller;
  final Color accent;

  LockscreenSettings get _ls => controller.settings.lockscreen;

  void _set(String key, Object value) => controller.updateLockscreen(_ls.set(key, value));

  @override
  Widget build(BuildContext context) {
    final LockscreenSettings ls = _ls;
    final bool on = ls.enabled;
    final List<Widget> children = <Widget>[
      _row(
        icon: Icons.phonelink_lock_rounded,
        title: 'Screenlock KRY player',
        subtitle: on
            ? 'Custom slide-to-unlock player is shown over your lock screen'
            : 'Off - Android\'s own music lock-screen controls are used',
        trailing: Switch(
          value: on,
          activeThumbColor: accent,
          onChanged: (bool value) {
            _set('enabled', value);
            if (value && !controller.overlayGranted) controller.openOverlaySettings();
          },
        ),
      ),
    ];

    if (on) {
      children.addAll(<Widget>[
        _divider(),
        _row(
          icon: Icons.layers_outlined,
          title: 'Display over other apps',
          subtitle: controller.overlayGranted
              ? 'Granted - the player can appear when the screen locks'
              : 'Required so Android lets the player appear over the lock screen',
          trailing: controller.overlayGranted
              ? Icon(Icons.check_circle_rounded, color: accent, size: 20)
              : _button('GRANT', controller.openOverlaySettings),
        ),
        _divider(),
        _row(
          icon: Icons.visibility_outlined,
          title: 'Preview',
          subtitle: 'Open it now to see your changes without locking the phone',
          trailing: _button('OPEN', controller.previewLockscreen),
        ),
        _divider(),
        _switch('onlyWhilePlaying', Icons.music_note_rounded, 'Only while music is playing',
            'Off: also show it when playback is paused'),
        _group('CLOCK'),
        _switch('showClock', Icons.access_time_rounded, 'Clock', 'Large time at the top'),
        _divider(),
        _switch('showDate', Icons.calendar_today_rounded, 'Date', 'Weekday and date under the clock'),
        _divider(),
        _chips(
          icon: Icons.schedule_rounded,
          title: 'Time format',
          key: 'clockFormat',
          options: const <String, String>{'system': 'SYSTEM', '12h': '12 H', '24h': '24 H'},
        ),
        _group('COVER & BACKGROUND'),
        _switch('showCover', Icons.album_outlined, 'Cover art', 'Album artwork in the middle of the screen'),
        if (ls.flag('showCover')) ...<Widget>[
          _divider(),
          _chips(
            icon: Icons.crop_square_rounded,
            title: 'Cover shape',
            key: 'coverShape',
            options: const <String, String>{'rounded': 'ROUNDED', 'square': 'SQUARE', 'circle': 'CIRCLE'},
          ),
          if (ls.text('coverShape') == 'circle') ...<Widget>[
            _divider(),
            _switch('coverSpin', Icons.sync_rounded, 'Spinning vinyl', 'Cover rotates while music plays'),
          ],
          _divider(),
          _slider('coverSize', Icons.photo_size_select_large_rounded, 'Cover size', 40, 95),
        ],
        _divider(),
        _switch('blurBackground', Icons.blur_on_rounded, 'Blurred cover background',
            'Off: pure black AMOLED background'),
        if (ls.flag('blurBackground')) ...<Widget>[
          _divider(),
          _slider('dim', Icons.brightness_medium_rounded, 'Background dimming', 0, 95),
        ],
        _divider(),
        _switch('accentTint', Icons.color_lens_outlined, 'Artwork accent color',
            'Tint the seek bar and highlights from the cover'),
        _group('TRACK INFO'),
        _switch('showTitle', Icons.title_rounded, 'Title', 'Scrolls when the title is long'),
        _divider(),
        _switch('showArtist', Icons.person_outline_rounded, 'Artist', ''),
        _divider(),
        _switch('showAlbum', Icons.library_music_outlined, 'Album', ''),
        _group('CONTROLS'),
        _switch('showSeekbar', Icons.linear_scale_rounded, 'Seek bar', 'Drag to seek without unlocking'),
        if (ls.flag('showSeekbar')) ...<Widget>[
          _divider(),
          _switch('remainingTime', Icons.hourglass_bottom_rounded, 'Show remaining time',
              'Counts down on the left instead of elapsed time'),
        ],
        _divider(),
        _switch('showSeekButtons', Icons.forward_10_rounded, 'Rewind / forward 10 s', 'Buttons beside the title'),
        _divider(),
        _switch('showPrevNext', Icons.skip_next_rounded, 'Previous / Next', ''),
        _divider(),
        _slider('transportButtonScale', Icons.open_in_full_rounded, 'Transport button size', 70, 130),
        _divider(),
        _switch('showFavorite', Icons.favorite_border_rounded, 'Favorite button', ''),
        _divider(),
        _switch('showShuffle', Icons.shuffle_rounded, 'Shuffle button', ''),
        _divider(),
        _switch('showRepeat', Icons.repeat_rounded, 'Repeat button', 'Cycles off / all / one'),
        _divider(),
        _switch('showQueueButton', Icons.queue_music_rounded, 'Up-next button', 'Top left - shows the next tracks'),
        _divider(),
        _switch('showLyricsButton', Icons.subtitles_outlined, 'Lyrics button',
            'Top right - shows synced lyrics when the track has them'),
        _divider(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => controller.updateLockscreen(const LockscreenSettings().set('enabled', true)),
              icon: Icon(Icons.restart_alt_rounded, size: 18, color: accent),
              label: Text('RESET LAYOUT TO DEFAULT', style: AppText.mono(9, 700, accent)),
            ),
          ),
        ),
      ]);
    }

    // The parent ExpansionTile owns the panel surface and padding so these options
    // don't consume any vertical space while the section is collapsed.
    return Column(children: children);
  }

  Widget _divider() => Divider(height: 1, color: AppColors.white(0.07));

  Widget _group(String label) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(label, style: AppText.mono(9, 700, accent, tracking: 0.15)),
        ),
      );

  Widget _button(String label, VoidCallback onTap) => OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          side: BorderSide(color: accent.withValues(alpha: 0.55)),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: Text(label, style: AppText.mono(9, 700, accent)),
      );

  Widget _switch(String key, IconData icon, String title, String subtitle) {
    return _row(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: Switch(
        value: _ls.flag(key),
        activeThumbColor: accent,
        onChanged: (bool value) => _set(key, value),
      ),
    );
  }

  Widget _chips({
    required IconData icon,
    required String title,
    required String key,
    required Map<String, String> options,
  }) {
    final String current = _ls.text(key);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          Icon(icon, size: 18, color: accent),
          const SizedBox(width: 10),
          Text(title, style: AppText.body(12, 600, Colors.white)),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, children: <Widget>[
          for (final MapEntry<String, String> o in options.entries)
            ChoiceChip(
              label: Text(o.value, style: AppText.mono(9, 700, current == o.key ? Colors.black : AppColors.zinc400)),
              selected: current == o.key,
              selectedColor: accent,
              backgroundColor: AppColors.white(0.035),
              side: BorderSide(color: AppColors.white(0.1)),
              showCheckmark: false,
              onSelected: (_) => _set(key, o.key),
            ),
        ]),
      ]),
    );
  }

  Widget _slider(String key, IconData icon, String title, int min, int max) {
    final int value = _ls.number(key).clamp(min, max).toInt();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          Icon(icon, size: 18, color: accent),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: AppText.body(12, 600, Colors.white))),
          Text('$value%', style: AppText.mono(10, 700, accent)),
        ]),
        Slider(
          value: value.toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: (max - min) ~/ 5,
          activeColor: accent,
          inactiveColor: AppColors.white(0.12),
          onChanged: (double v) => _set(key, (v / 5).round() * 5),
        ),
      ]),
    );
  }

  Widget _row({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: <Widget>[
        Icon(icon, size: 19, color: AppColors.zinc400),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(title, style: AppText.body(12, 600, Colors.white)),
            if (subtitle.isNotEmpty) ...<Widget>[
              const SizedBox(height: 3),
              Text(subtitle, style: AppText.body(10, 400, AppColors.zinc500, lineHeight: 15)),
            ],
          ]),
        ),
        const SizedBox(width: 8),
        trailing,
      ]),
    );
  }
}
