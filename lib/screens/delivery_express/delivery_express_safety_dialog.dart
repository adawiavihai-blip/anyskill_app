// Delivery Express — generic safety + handling guide for emergency
// delivery requests.
//
// Opened from the "טיפים לפני שליחה" row on DeliveryExpressPackageScreen.
// Content focuses on:
//   • Hazardous content awareness (no dangerous goods / flammable items)
//   • Package handling (don't tamper, double-check contents)
//   • Recipient coordination (call ahead, share access notes)
//   • Israeli emergency numbers — 100/101/102 + 1-800-CONSUMER
//
// Layered ON TOP of the regular Delivery CSM rules (CourierRules) — those
// live on the provider's profile and tell the courier what they will/won't
// carry. This dialog tells the CUSTOMER what's expected of them BEFORE the
// dispatch fires.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'delivery_express_palette.dart';

/// Show as a draggable bottom sheet so the user can scroll without
/// dismissing the parent screen.
Future<void> showDeliveryExpressSafetyDialog(BuildContext context) async {
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
              color: DeliveryExpressPalette.bgPrimary,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: DeliveryExpressPalette.borderSecondary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: DeliveryExpressPalette.gold50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.inventory_2_rounded,
                          color: DeliveryExpressPalette.gold700,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'טיפים לשליחה דחופה',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: DeliveryExpressPalette.textPrimary,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'שלוש דקות קריאה — חוסכות זמן והרבה חיכוך',
                              style: TextStyle(
                                fontSize: 12,
                                color: DeliveryExpressPalette.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                        color: DeliveryExpressPalette.textSecondary,
                      ),
                    ],
                  ),
                ),
                const Divider(
                  height: 1,
                  thickness: 0.5,
                  color: DeliveryExpressPalette.borderTertiary,
                ),
                Expanded(
                  child: ListView(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    children: const [
                      _HazardBanner(),
                      SizedBox(height: 18),
                      _Section(
                        icon: Icons.inventory_rounded,
                        title: 'לפני שאריזים',
                        bullets: [
                          'ארוז ברגישות לסחורה — חבילות שבירות עוטפים בנייר/בועות',
                          'סגור היטב את האריזה — חבילה פתוחה היא הסיכון מספר 1',
                          'אל תשלח חפצים אסורים: אש, נשק, חומרים כימיים, מזומן',
                          'תרופות מרשם — צרף העתק של המרשם בתוך החבילה',
                        ],
                      ),
                      SizedBox(height: 14),
                      _Section(
                        icon: Icons.phone_in_talk_rounded,
                        title: 'תיאום עם הנמען',
                        bullets: [
                          'ודא שהנמען זמין בכתובת בשעה שבחרת',
                          'אם הכניסה דרך קוד שער / קומה — ציין בשדה "פרטים נוספים"',
                          'תייג את החבילה בשם הנמען וטלפון (לא חובה — אבל עוזר)',
                          'אם יש כלב באזור — ציין זאת לשליח',
                        ],
                      ),
                      SizedBox(height: 14),
                      _Section(
                        icon: Icons.local_florist_rounded,
                        title: 'פרחים, עוגות, מזון טרי',
                        bullets: [
                          'ציין בתיאור שזה פריט רגיש',
                          'עוגות / מאפים — קנה אריזה יציבה מהקונדיטור',
                          'פרחים — חבילה אנכית עם מים בבסיס',
                          'בקיץ — בקש מהשליח לשמור החבילה במזגן בדרך',
                        ],
                      ),
                      SizedBox(height: 14),
                      _Section(
                        icon: Icons.security_rounded,
                        title: 'אם החבילה לא הגיעה / נפגעה',
                        bullets: [
                          'דווח בצ\'אט מיד עם הגעת השליח',
                          'צלם את החבילה ברגע הקבלה — שמירת זכויות',
                          'פנה ל"תמיכה" באפליקציה לבקשת זיכוי/החזר',
                        ],
                      ),
                      SizedBox(height: 22),
                      _CallButton(
                        label: 'משטרה — 100',
                        number: '100',
                        color: DeliveryExpressPalette.red500,
                        icon: Icons.local_police_rounded,
                      ),
                      SizedBox(height: 8),
                      _CallButton(
                        label: 'מד"א (חירום רפואי) — 101',
                        number: '101',
                        color: DeliveryExpressPalette.red700,
                        icon: Icons.medical_services_rounded,
                      ),
                      SizedBox(height: 8),
                      _CallButton(
                        label: 'כיבוי אש — 102',
                        number: '102',
                        color: DeliveryExpressPalette.amber600,
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

class _HazardBanner extends StatelessWidget {
  const _HazardBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DeliveryExpressPalette.red50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: DeliveryExpressPalette.red500.withValues(alpha: 0.25),
        ),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.priority_high_rounded,
            color: DeliveryExpressPalette.red500,
            size: 22,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'אסור לשלוח חומרים מסוכנים, נשק, סמים, מזומן בכמות גדולה. '
              'שליחים רשאים לסרב לקחת חבילה שמראה סימני פגיעה.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: DeliveryExpressPalette.red700,
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
        color: DeliveryExpressPalette.bgSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: DeliveryExpressPalette.borderTertiary,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: DeliveryExpressPalette.gold700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: DeliveryExpressPalette.textPrimary,
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
                      color: DeliveryExpressPalette.gold700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      b,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: DeliveryExpressPalette.textPrimary,
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
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
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
        'ההנחיות כלליות. בכל מקרה של ספק — 100/101/102 או "תמיכה" באפליקציה.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          color: DeliveryExpressPalette.textTertiary.withValues(alpha: 0.85),
          height: 1.5,
        ),
      ),
    );
  }
}
