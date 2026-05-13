// Step 1 of the babysitter emergency flow — children + time + duration.
//
// Premium-tier UX: warm pink/purple cream, big tap targets (parents
// often use one hand while holding a baby), all chips pre-populated
// with smart defaults so the customer can blast through in <30s.
//
// Inputs collected:
//   • reason          — why this is urgent (6-grid)
//   • numChildren     — 1..maxChildrenInPicker (counter)
//   • childrenAgeGroups — multi-select chips (5 buckets, optional)
//   • startTime       — preset chips (now / +30m / +1h / +2h / custom)
//   • durationHours   — preset chips (2 / 3 / 4 / 6 / overnight)
//   • specialNotes    — single-line text (allergies, etc.) optional
//
// On "המשך": pushes BabysitterEmergencyLocationScreen with the
// captured data.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants/babysitter_emergency_constants.dart';
import 'babysitter_emergency_palette.dart';
import 'babysitter_emergency_safety_dialog.dart';
import 'babysitter_emergency_location_screen.dart';

class BabysitterEmergencyDetailsScreen extends StatefulWidget {
  const BabysitterEmergencyDetailsScreen({super.key});

  @override
  State<BabysitterEmergencyDetailsScreen> createState() =>
      _BabysitterEmergencyDetailsScreenState();
}

class _BabysitterEmergencyDetailsScreenState
    extends State<BabysitterEmergencyDetailsScreen> {
  String? _selectedReason;
  int _numChildren = 1;
  final Set<String> _selectedAgeGroups = {};

  /// Minutes-from-now offset for the start time. null means custom (we
  /// open a TimePicker).
  int? _startOffsetMinutes = 0;
  DateTime? _customStart;

  int _durationHours = BabysitterEmergencyConfig.defaultDurationHours;
  bool _overnight = false;

  final _notesCtrl = TextEditingController();

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  bool get _canContinue => _selectedReason != null;

  DateTime _resolvedStart() {
    if (_customStart != null) return _customStart!;
    final mins = _startOffsetMinutes ?? 0;
    return DateTime.now().add(Duration(minutes: mins));
  }

  DateTime _resolvedEnd() {
    final start = _resolvedStart();
    if (_overnight) {
      // Overnight = 10h (e.g. 22:00 → 08:00). Clamp inside the
      // BabysitterEmergencyConfig max — provider can still set
      // overnightFlatRate on their pricing config, but here we treat
      // it as a 10h shift for the estimate.
      return start.add(const Duration(hours: 10));
    }
    return start.add(Duration(hours: _durationHours));
  }

  Future<void> _pickCustomStart() async {
    final now = DateTime.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      helpText: 'מתי המטפלת תגיע?',
    );
    if (picked == null) return;
    var dt = DateTime(now.year, now.month, now.day, picked.hour, picked.minute);
    if (dt.isBefore(now)) {
      // Picked a time earlier today — assume tomorrow.
      dt = dt.add(const Duration(days: 1));
    }
    setState(() {
      _customStart = dt;
      _startOffsetMinutes = null;
    });
  }

  void _onContinue() {
    HapticFeedback.lightImpact();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BabysitterEmergencyLocationScreen(
          reason: _selectedReason!,
          numChildren: _numChildren,
          childrenAgeGroups: _selectedAgeGroups.toList(),
          agreedStartTime: _resolvedStart(),
          agreedEndTime: _resolvedEnd(),
          specialNotes: _notesCtrl.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: BabyEmergencyPalette.bgSecondary,
        appBar: AppBar(
          backgroundColor: BabyEmergencyPalette.bgPrimary,
          elevation: 0,
          title: const Text(
            'בייביסיטר חירום',
            style: TextStyle(
              color: BabyEmergencyPalette.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          iconTheme: const IconThemeData(
              color: BabyEmergencyPalette.textPrimary),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          children: [
            // ── Urgency banner ──────────────────────────────────────
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                  colors: [
                    BabyEmergencyPalette.pink400,
                    BabyEmergencyPalette.purple500,
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: const [
                  Icon(Icons.bolt_rounded,
                      color: Colors.white, size: 24),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'נמצא לך מטפלת מאומתת בתוך דקות. כל ההצעות מבייביסיטרים שעברו ביקורת רקע.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),

            // ── Reason ──────────────────────────────────────────────
            const _SectionHeading('מה הסיטואציה?'),
            const SizedBox(height: 10),
            _ReasonGrid(
              selected: _selectedReason,
              onSelect: (id) {
                HapticFeedback.selectionClick();
                setState(() => _selectedReason = id);
              },
            ),
            const SizedBox(height: 22),

            // ── Children count ──────────────────────────────────────
            const _SectionHeading('כמה ילדים?'),
            const SizedBox(height: 10),
            _ChildrenCounter(
              value: _numChildren,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                setState(() => _numChildren = v);
              },
            ),
            const SizedBox(height: 22),

            // ── Age groups ──────────────────────────────────────────
            const _SectionHeading('גילאי הילדים', optional: true),
            const SizedBox(height: 10),
            _AgeGroupChips(
              selected: _selectedAgeGroups,
              onToggle: (id) {
                HapticFeedback.selectionClick();
                setState(() {
                  if (_selectedAgeGroups.contains(id)) {
                    _selectedAgeGroups.remove(id);
                  } else {
                    _selectedAgeGroups.add(id);
                  }
                });
              },
            ),
            const SizedBox(height: 22),

            // ── Start time ──────────────────────────────────────────
            const _SectionHeading('מתי המטפלת תגיע?'),
            const SizedBox(height: 10),
            _StartTimeChips(
              selectedOffsetMinutes: _startOffsetMinutes,
              customStart: _customStart,
              onPreset: (mins) {
                HapticFeedback.selectionClick();
                setState(() {
                  _startOffsetMinutes = mins;
                  _customStart = null;
                });
              },
              onCustom: _pickCustomStart,
            ),
            const SizedBox(height: 22),

            // ── Duration ────────────────────────────────────────────
            const _SectionHeading('כמה זמן צריכה?'),
            const SizedBox(height: 10),
            _DurationChips(
              hours: _durationHours,
              overnight: _overnight,
              onPick: (h, isOvernight) {
                HapticFeedback.selectionClick();
                setState(() {
                  _durationHours = h;
                  _overnight = isOvernight;
                });
              },
            ),
            const SizedBox(height: 22),

            // ── Special notes ───────────────────────────────────────
            const _SectionHeading('הוראות מיוחדות', optional: true),
            const SizedBox(height: 6),
            const Text(
              'אלרגיות, תרופות קבועות, שעת שינה, פוביות, חיות מחמד…',
              style: TextStyle(
                color: BabyEmergencyPalette.textTertiary,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notesCtrl,
              maxLines: 3,
              maxLength: 240,
              decoration: InputDecoration(
                hintText: 'לדוגמה: "אלרגיה לבוטנים, ארוחת ערב מוכנה במקרר"',
                hintStyle: const TextStyle(
                  color: BabyEmergencyPalette.textTertiary,
                  fontSize: 13,
                ),
                filled: true,
                fillColor: BabyEmergencyPalette.bgPrimary,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                      color: BabyEmergencyPalette.borderTertiary),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                      color: BabyEmergencyPalette.borderTertiary),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                      color: BabyEmergencyPalette.purple500, width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
              ),
            ),
            const SizedBox(height: 18),

            // ── Safety strip ────────────────────────────────────────
            Material(
              color: BabyEmergencyPalette.purple50,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () =>
                    showBabysitterEmergencySafetyDialog(context),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: const [
                      Icon(Icons.health_and_safety_rounded,
                          color: BabyEmergencyPalette.purple700, size: 22),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'מדריך בטיחות + מספרי חירום',
                          style: TextStyle(
                            color: BabyEmergencyPalette.purple700,
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_left_rounded,
                          color: BabyEmergencyPalette.purple500),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        // ── Sticky CTA ────────────────────────────────────────────────
        bottomNavigationBar: SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            decoration: const BoxDecoration(
              color: BabyEmergencyPalette.bgPrimary,
              border: Border(
                top: BorderSide(
                  color: BabyEmergencyPalette.borderTertiary,
                  width: 1,
                ),
              ),
            ),
            child: SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _canContinue ? _onContinue : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: BabyEmergencyPalette.purple500,
                  disabledBackgroundColor:
                      BabyEmergencyPalette.borderSecondary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Text(
                      'המשך לכתובת',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_back_rounded, size: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════
// Helper widgets (private to this screen)
// ═════════════════════════════════════════════════════════════════════════

class _SectionHeading extends StatelessWidget {
  final String text;
  final bool optional;
  const _SectionHeading(this.text, {this.optional = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          text,
          style: const TextStyle(
            color: BabyEmergencyPalette.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (optional) ...[
          const SizedBox(width: 6),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: BabyEmergencyPalette.bgTertiary,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'אופציונלי',
              style: TextStyle(
                color: BabyEmergencyPalette.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ReasonGrid extends StatelessWidget {
  final String? selected;
  final ValueChanged<String> onSelect;
  const _ReasonGrid({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.05,
      children: BabysitterEmergencyReason.all.map((id) {
        final isSelected = id == selected;
        return Material(
          color: isSelected
              ? BabyEmergencyPalette.purple500
              : BabyEmergencyPalette.bgPrimary,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => onSelect(id),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected
                      ? BabyEmergencyPalette.purple500
                      : BabyEmergencyPalette.borderTertiary,
                  width: 1.5,
                ),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    BabysitterEmergencyReason.iconOf(id),
                    color: isSelected
                        ? Colors.white
                        : BabyEmergencyPalette.purple500,
                    size: 26,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    BabysitterEmergencyReason.labelOf(id),
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : BabyEmergencyPalette.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ChildrenCounter extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const _ChildrenCounter({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: BabyEmergencyPalette.bgPrimary,
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: BabyEmergencyPalette.borderTertiary, width: 1),
      ),
      child: Row(
        children: [
          _CircleStepperButton(
            icon: Icons.remove_rounded,
            enabled: value > 1,
            onTap: () => onChanged((value - 1).clamp(1, 99)),
          ),
          const Spacer(),
          Column(
            children: [
              Text(
                '$value',
                style: const TextStyle(
                  color: BabyEmergencyPalette.purple700,
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value == 1 ? 'ילד אחד' : '$value ילדים',
                style: const TextStyle(
                  color: BabyEmergencyPalette.textTertiary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const Spacer(),
          _CircleStepperButton(
            icon: Icons.add_rounded,
            enabled:
                value < BabysitterEmergencyConfig.maxChildrenInPicker,
            onTap: () => onChanged((value + 1)
                .clamp(1, BabysitterEmergencyConfig.maxChildrenInPicker)),
          ),
        ],
      ),
    );
  }
}

class _CircleStepperButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  const _CircleStepperButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled
          ? BabyEmergencyPalette.purple50
          : BabyEmergencyPalette.bgTertiary,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(28),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(
            icon,
            color: enabled
                ? BabyEmergencyPalette.purple700
                : BabyEmergencyPalette.borderSecondary,
            size: 22,
          ),
        ),
      ),
    );
  }
}

class _AgeGroupChips extends StatelessWidget {
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  const _AgeGroupChips({required this.selected, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: BabysitterEmergencyAgeGroup.all.map((id) {
        final isSelected = selected.contains(id);
        return GestureDetector(
          onTap: () => onToggle(id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? BabyEmergencyPalette.pink400
                  : BabyEmergencyPalette.bgPrimary,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: isSelected
                    ? BabyEmergencyPalette.pink400
                    : BabyEmergencyPalette.borderTertiary,
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  BabysitterEmergencyAgeGroup.emojiOf(id),
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(width: 6),
                Text(
                  BabysitterEmergencyAgeGroup.labelOf(id),
                  style: TextStyle(
                    color: isSelected
                        ? Colors.white
                        : BabyEmergencyPalette.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _StartTimeChips extends StatelessWidget {
  final int? selectedOffsetMinutes;
  final DateTime? customStart;
  final ValueChanged<int> onPreset;
  final VoidCallback onCustom;

  const _StartTimeChips({
    required this.selectedOffsetMinutes,
    required this.customStart,
    required this.onPreset,
    required this.onCustom,
  });

  @override
  Widget build(BuildContext context) {
    final presets = [
      (0, 'מיד'),
      (30, 'בעוד 30 דק׳'),
      (60, 'בעוד שעה'),
      (120, 'בעוד שעתיים'),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ...presets.map((p) {
          final mins = p.$1;
          final label = p.$2;
          final isSelected = customStart == null && selectedOffsetMinutes == mins;
          return _Chip(
            label: label,
            selected: isSelected,
            onTap: () => onPreset(mins),
          );
        }),
        _Chip(
          label: customStart != null
              ? 'בשעה ${customStart!.hour.toString().padLeft(2, "0")}:${customStart!.minute.toString().padLeft(2, "0")}'
              : 'בחירת זמן…',
          selected: customStart != null,
          icon: Icons.access_time_rounded,
          onTap: onCustom,
        ),
      ],
    );
  }
}

class _DurationChips extends StatelessWidget {
  final int hours;
  final bool overnight;
  final void Function(int hours, bool overnight) onPick;
  const _DurationChips({
    required this.hours,
    required this.overnight,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final presets = [2, 3, 4, 6];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ...presets.map((h) {
          final isSelected = !overnight && hours == h;
          return _Chip(
            label: '$h שעות',
            selected: isSelected,
            onTap: () => onPick(h, false),
          );
        }),
        _Chip(
          label: 'לילה (10ש)',
          icon: Icons.nights_stay_rounded,
          selected: overnight,
          onTap: () => onPick(hours, true),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? BabyEmergencyPalette.purple500
              : BabyEmergencyPalette.bgPrimary,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected
                ? BabyEmergencyPalette.purple500
                : BabyEmergencyPalette.borderTertiary,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 14,
                  color: selected
                      ? Colors.white
                      : BabyEmergencyPalette.purple500),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? Colors.white
                    : BabyEmergencyPalette.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
