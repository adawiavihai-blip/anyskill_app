/// Sound Studio §53 — Screen 1 (Studio).
///
/// Mirrors `docs/ui-specs/sound_studio_mockups/sound_studio_mockups/index.html`.
/// Owns the existing event ↔ sound mapping functionality:
///   • 5 rows, one per AppEvent
///   • Per-row Play preview button + dropdown
///   • Live Firestore writes on selection change (via AudioService.setEventMapping)
///   • Health bar with sync indicator + mapping count
///   • Footer "AI suggestions" CTA (placeholder snackbar for now)
library;

import 'package:flutter/material.dart';

import '../../../services/audio_service.dart';
import '../../../services/sounds_log_service.dart';
import '../sound_studio_tokens.dart';
import '../sound_studio_screen.dart';

class StudioTab extends StatefulWidget {
  const StudioTab({super.key});

  @override
  State<StudioTab> createState() => _StudioTabState();
}

class _StudioTabState extends State<StudioTab>
    with SingleTickerProviderStateMixin {
  AppSound? _previewing;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: SingleChildScrollView(
        key: const ValueKey('studio_scroll'),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            const SizedBox(height: 20),
            _healthBar(),
            const SizedBox(height: 18),
            _eventList(),
            const SizedBox(height: 20),
            _aiCta(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Text(
          'איזה צליל מתנגן ומתי',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: StudioPalette.textPrimary,
            height: 1.2,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'בחר אירוע, בחר צליל. השינוי נכנס לתוקף מיד אצל כל המשתמשים.',
          style: TextStyle(fontSize: 13, color: StudioPalette.textSecondary),
        ),
      ],
    );
  }

  Widget _healthBar() {
    return StreamBuilder<AudioServiceState>(
      stream: AudioService.instance.audioServiceStateStream,
      initialData: AudioService.instance.currentState(),
      builder: (context, snap) {
        final state = snap.data ?? AudioService.instance.currentState();
        final isHealthy = state.allBuffered &&
            state.firestoreSyncLatency.inSeconds < 5;
        final mappedCount = AppEvent.values
            .where((e) => AudioService.instance.soundForEvent(e) != null)
            .length;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: StudioPalette.bgSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: StudioPalette.borderLight, width: 0.5),
          ),
          child: Row(
            children: [
              StudioPills.statusDot(
                color: isHealthy ? StudioPalette.green : StudioPalette.amber,
                pulse: isHealthy,
              ),
              const SizedBox(width: 12),
              const Text(
                'המערכת פעילה',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: StudioPalette.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              const Text('·', style: TextStyle(color: StudioPalette.textTertiary)),
              const SizedBox(width: 8),
              Text(
                '$mappedCount מתוך ${AppEvent.values.length} אירועים ממופים',
                style: const TextStyle(
                  fontSize: 13,
                  color: StudioPalette.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                _syncLabel(state.lastSyncAt),
                style: const TextStyle(
                  fontSize: 12,
                  color: StudioPalette.textTertiary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _syncLabel(DateTime? at) {
    if (at == null) return 'ממתין לסנכרון…';
    final delta = DateTime.now().difference(at);
    if (delta.inSeconds < 5) return 'סנכרון אחרון: עכשיו';
    if (delta.inSeconds < 60) return 'סנכרון אחרון לפני ${delta.inSeconds} שניות';
    if (delta.inMinutes < 60) return 'סנכרון אחרון לפני ${delta.inMinutes} דק׳';
    return 'סנכרון אחרון לפני ${delta.inHours} שעות';
  }

  Widget _eventList() {
    return Column(
      children: [
        for (final event in AppEvent.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _EventRow(
              event: event,
              previewing: _previewing,
              onPreview: (s) {
                setState(() => _previewing = s);
                AudioService.instance.play(s);
                Future.delayed(const Duration(milliseconds: 1200), () {
                  if (!mounted) return;
                  if (_previewing == s) setState(() => _previewing = null);
                });
              },
              onPick: (s) async {
                final old = AudioService.instance.soundForEvent(event);
                try {
                  await AudioService.instance.setEventMapping(event, s);
                } catch (e) {
                  if (!mounted) return;
                  showStudioToast(context, 'שגיאה בשמירה: $e');
                  return;
                }
                final newLabel = s == null ? 'ללא צליל' : soundEnglishLabel(s);
                final oldLabel = old == null ? 'ללא צליל' : soundEnglishLabel(old);
                await SoundsLogService.instance.write(
                  type: SoundsLogType.change,
                  title: 'מיפוי אירוע עודכן',
                  description:
                      '${event.hebrewLabel} שונה מ-$oldLabel ל-$newLabel',
                  metadata: {
                    'eventId': event.name,
                    'fromSoundId': old?.name,
                    'toSoundId': s?.name,
                  },
                );
                if (!mounted) return;
                setState(() {});
                showStudioToast(
                  context,
                  '✓ ${event.hebrewLabel} ← $newLabel',
                );
                if (s != null) {
                  AudioService.instance.play(s);
                }
              },
            ),
          ),
      ],
    );
  }

  Widget _aiCta() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: StudioPalette.bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: StudioPalette.borderLight, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: StudioPalette.primaryLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: StudioPalette.primary,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'לא בטוח איזה צליל הכי מתאים?',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: StudioPalette.textPrimary,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'AI יציע התאמות לפי פסיכואקוסטיקה והתנהגות משתמשים',
                  style: TextStyle(
                    fontSize: 12,
                    color: StudioPalette.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () => showStudioToast(
              context,
              '🤖 AI מנתח את המיפוי הנוכחי…',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: StudioPalette.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              textStyle:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            child: const Text('קבל הצעות AI ←'),
          ),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  final AppEvent event;
  final AppSound? previewing;
  final ValueChanged<AppSound> onPreview;
  final ValueChanged<AppSound?> onPick;

  const _EventRow({
    required this.event,
    required this.previewing,
    required this.onPreview,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final current = AudioService.instance.soundForEvent(event);
    final isSilent = current == null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: StudioPalette.bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: StudioPalette.borderLight, width: 0.5),
      ),
      child: Row(
        children: [
          _leadingButton(current),
          const SizedBox(width: 16),
          Expanded(child: _info(isSilent)),
          const SizedBox(width: 12),
          _SoundDropdown(
            current: current,
            onPick: onPick,
          ),
        ],
      ),
    );
  }

  Widget _leadingButton(AppSound? current) {
    if (current == null) {
      return Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          color: StudioPalette.bgMuted,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.volume_off_rounded,
          color: StudioPalette.textTertiary,
          size: 18,
        ),
      );
    }
    final isPlaying = previewing == current;
    final tint = StudioPalette.soundColor(current.name);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => onPreview(current),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isPlaying ? tint : StudioPalette.soundLight(current.name),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.play_arrow_rounded,
            color: isPlaying ? Colors.white : tint,
            size: 20,
          ),
        ),
      ),
    );
  }

  Widget _info(bool isSilent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                event.hebrewLabel,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: StudioPalette.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isSilent) ...[
              const SizedBox(width: 8),
              StudioPills.pill(text: 'שקט מכוון'),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          _eventDescription(event),
          style: const TextStyle(
            fontSize: 12,
            color: StudioPalette.textTertiary,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  static String _eventDescription(AppEvent event) {
    switch (event) {
      case AppEvent.onPaymentSuccess:
        return 'כשאסקרו משחרר תשלום למשתמש';
      case AppEvent.onAiMatchFound:
        return 'כשהאלגוריתם מצא שידוך מתאים';
      case AppEvent.onNewOpportunity:
        return 'כשמופיע ג׳וב מתאים לפרופיל';
      case AppEvent.onCourseCompleted:
        return 'כשמשתמש סיים קורס וקיבל XP';
      case AppEvent.onLogin:
        return 'פתיחת אפליקציה תכופה — שקט עדיף';
    }
  }
}

class _SoundDropdown extends StatelessWidget {
  final AppSound? current;
  final ValueChanged<AppSound?> onPick;
  const _SoundDropdown({required this.current, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final isSilent = current == null;
    final tint =
        isSilent ? StudioPalette.textSecondary : StudioPalette.soundColor(current!.name);
    final bg = isSilent
        ? StudioPalette.bgTertiary
        : StudioPalette.soundLight(current!.name);

    return PopupMenuButton<AppSound?>(
      tooltip: 'בחר צליל',
      position: PopupMenuPosition.under,
      color: StudioPalette.bgSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: StudioPalette.borderMedium, width: 0.5),
      ),
      onSelected: onPick,
      itemBuilder: (context) => [
        for (final s in AppSound.values)
          PopupMenuItem<AppSound?>(
            value: s,
            child: _menuItem(s),
          ),
        const PopupMenuItem<AppSound?>(
          value: null,
          child: _SilentMenuItem(),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StudioPills.statusDot(
              color: isSilent ? StudioPalette.textTertiary : tint,
            ),
            const SizedBox(width: 8),
            Text(
              isSilent ? 'ללא צליל' : soundEnglishLabel(current!),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: tint,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: tint,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _menuItem(AppSound s) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StudioPills.statusDot(color: StudioPalette.soundColor(s.name)),
        const SizedBox(width: 8),
        Text(
          soundEnglishLabel(s),
          style: const TextStyle(fontSize: 13),
        ),
      ],
    );
  }
}

class _SilentMenuItem extends StatelessWidget {
  const _SilentMenuItem();
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: const [
        Icon(
          Icons.volume_off_rounded,
          size: 14,
          color: StudioPalette.textTertiary,
        ),
        SizedBox(width: 8),
        Text(
          'ללא צליל',
          style: TextStyle(fontSize: 13, color: StudioPalette.textTertiary),
        ),
      ],
    );
  }
}
