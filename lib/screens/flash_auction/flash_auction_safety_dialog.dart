// Flash Auction — generic Israeli motorcycle-emergency safety dialog.
//
// Opened from the "אתה במקום בטוח?" row on FlashAuctionIssueScreen.
// Content is intentionally generic — covers the most common emergency
// scenarios in Israel without knowing the customer's specific situation.
// If a future PR adds geo-aware rules (e.g. "you're on Highway 6 — do X"),
// it should layer ON TOP of these defaults, not replace them.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'flash_auction_palette.dart';

/// Show as a full-height bottom sheet so the user can scroll without
/// dismissing the parent screen.
Future<void> showFlashAuctionSafetyDialog(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _SafetyDialogContent(),
  );
}

class _SafetyDialogContent extends StatelessWidget {
  const _SafetyDialogContent();

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: DraggableScrollableSheet(
        initialChildSize: 0.78,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollCtrl) {
          return Container(
            decoration: const BoxDecoration(
              color: FlashPalette.bgPrimary,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: Column(
              children: [
                // Drag handle
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: FlashPalette.borderSecondary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Header
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: FlashPalette.red50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.health_and_safety_rounded,
                          color: FlashPalette.red500,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              'הנחיות בטיחות',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: FlashPalette.textPrimary,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'קודם כל — הבטיחות שלך',
                              style: TextStyle(
                                fontSize: 12,
                                color: FlashPalette.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                        color: FlashPalette.textSecondary,
                      ),
                    ],
                  ),
                ),
                const Divider(
                  height: 1,
                  thickness: 0.5,
                  color: FlashPalette.borderTertiary,
                ),
                Expanded(
                  child: ListView(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    children: const [
                      _EmergencyBanner(),
                      SizedBox(height: 18),
                      _Section(
                        icon: Icons.directions_car_filled_rounded,
                        title: 'אם אתה על כביש מהיר או בכביש סואן',
                        bullets: [
                          'דחוף את האופנוע לשול הימני, רחוק ככל האפשר מהנתיב',
                          'הדלק את הפנסים — גם אם רק הפנס הקדמי עובד',
                          'לבש חולצה זוהרת אם יש לך באחסון',
                          'הצב משולש אזהרה לפחות 50 מטר אחורה (100 מטר בכביש מהיר)',
                          'התרחק מהאופנוע ועבור לשול — אל תעמוד לידו',
                        ],
                      ),
                      SizedBox(height: 14),
                      _Section(
                        icon: Icons.nightlight_round,
                        title: 'אם זה לילה או ראות נמוכה',
                        bullets: [
                          'השאר את הקסדה — היא חוסכת זמן בחירום ומגנה',
                          'עבור לאזור מואר אם אפשר (תחנת דלק, צומת)',
                          'הדלק את הטלפון על מצב פנס',
                          'אל תנסה לתקן את האופנוע בצד הכביש',
                        ],
                      ),
                      SizedBox(height: 14),
                      _Section(
                        icon: Icons.warning_amber_rounded,
                        title: 'אם הייתה תאונה',
                        bullets: [
                          'בדוק את עצמך — פציעות נמצאות לפעמים רק לאחר זמן',
                          'אל תזיז את האופנוע אם יש חשד לפגיעה בגב/בצוואר',
                          'תעד את הזירה (תמונות) — שמירת זכויות מול ביטוח',
                          'התקשר ל-101 מיד אם יש פציעה',
                        ],
                      ),
                      SizedBox(height: 14),
                      _Section(
                        icon: Icons.battery_alert_rounded,
                        title: 'אם זו תקלת מנוע / מצבר / פנצ\'ר',
                        bullets: [
                          'אל תנסה לדחוף את האופנוע למרחק ארוך — תזיז ל-shoulder וזהו',
                          'כבה את המנוע אם יש ריח שריפה / עשן',
                          'הוצא את המפתח, אבל אל תזיז כלום אחר',
                        ],
                      ),
                      SizedBox(height: 22),
                      _CallButton(
                        label: 'משטרה — 100',
                        number: '100',
                        color: FlashPalette.red500,
                        icon: Icons.local_police_rounded,
                      ),
                      SizedBox(height: 8),
                      _CallButton(
                        label: 'מד"א (חירום רפואי) — 101',
                        number: '101',
                        color: FlashPalette.red700,
                        icon: Icons.medical_services_rounded,
                      ),
                      SizedBox(height: 8),
                      _CallButton(
                        label: 'כיבוי אש — 102',
                        number: '102',
                        color: FlashPalette.amber600,
                        icon: Icons.fire_truck_rounded,
                      ),
                      SizedBox(height: 18),
                      _BottomFooter(),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _EmergencyBanner extends StatelessWidget {
  const _EmergencyBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: FlashPalette.red50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: FlashPalette.red500.withValues(alpha: 0.25)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.priority_high_rounded,
            color: FlashPalette.red500,
            size: 22,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'אם נפצעת או יש פצוע — התקשר 101 מיד. הגרר נשאר משני בכל מקרה כזה.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: FlashPalette.red700,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<String> bullets;
  const _Section({
    required this.icon,
    required this.title,
    required this.bullets,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: FlashPalette.bgSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: FlashPalette.borderTertiary, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: FlashPalette.purple500),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: FlashPalette.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...bullets.map(
            (b) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Icon(
                      Icons.fiber_manual_record,
                      size: 6,
                      color: FlashPalette.purple500,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      b,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: FlashPalette.textPrimary,
                        height: 1.55,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  final String label;
  final String number;
  final Color color;
  final IconData icon;
  const _CallButton({
    required this.label,
    required this.number,
    required this.color,
    required this.icon,
  });

  Future<void> _call(BuildContext context) async {
    // Capture the messenger BEFORE the await so the analyzer's
    // BuildContext-across-async lint stays clean.
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri(scheme: 'tel', path: number);
    try {
      final ok = await launchUrl(uri);
      if (!ok) {
        await Clipboard.setData(ClipboardData(text: number));
        messenger.showSnackBar(
          SnackBar(content: Text('המספר הועתק: $number')),
        );
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: number));
      messenger.showSnackBar(
        SnackBar(content: Text('המספר הועתק: $number')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () => _call(context),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomFooter extends StatelessWidget {
  const _BottomFooter();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        'ההנחיות הללו כלליות. בכל מקרה של ספק — 100 או 101.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          color: FlashPalette.textTertiary.withValues(alpha: 0.85),
          height: 1.5,
        ),
      ),
    );
  }
}
