// Safety bottom-sheet for the babysitter emergency flow.
//
// Mirror of FlashAuctionSafetyDialog (CLAUDE.md §57) but tuned for
// CHILDCARE emergencies — different tips, different emergency numbers.
//
// Israeli emergency numbers used here:
//   • 101 — מד"א (medical / ambulance) — primary for child medical events
//   • 100 — משטרה (police)
//   • 102 — כיבוי אש
//   • 105 — מערך הסייבר הלאומי (cyber emergencies — relevant for online safety)
//   • 1-800-223-966 — מועצה לשלום הילד / ילדים בסיכון (child welfare hotline)
//
// All copy in Hebrew; intentionally generic guidance.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'babysitter_emergency_palette.dart';

/// Opens the safety dialog as a modal bottom sheet.
Future<void> showBabysitterEmergencySafetyDialog(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _SafetyDialogContent(),
  );
}

class _SafetyDialogContent extends StatelessWidget {
  const _SafetyDialogContent();

  Future<void> _call(String number) async {
    final uri = Uri(scheme: 'tel', path: number);
    try {
      await launchUrl(uri);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: BabyEmergencyPalette.bgPrimary,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: BabyEmergencyPalette.borderTertiary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  children: [
                    // Emergency banner
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: BabyEmergencyPalette.red50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: BabyEmergencyPalette.red500,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              color: BabyEmergencyPalette.red700, size: 32),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'אם הילד נפצע או יש מקרה רפואי דחוף — חיוג 101 מיד',
                              style: TextStyle(
                                color: BabyEmergencyPalette.red700,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    _SectionTitle('בטיחות הילדים — כללי'),
                    _Bullet('ודאי שהילדים בסביבה בטוחה — דלתות נעולות, חלונות סגורים, אבטחת תינוק במידת הצורך.'),
                    _Bullet('ודאי שיש לך טלפון טעון בהישג יד.'),
                    _Bullet('שמרי על קווי תקשורת פתוחים — היי בקשר עם המטפלת והודיעי על שינויים בתוכנית.'),

                    const SizedBox(height: 16),
                    _SectionTitle('בעת הזמנת בייביסיטר חדשה'),
                    _Bullet('בדקי שהמטפלת עברה ביקורת רקע (תופיע התווית הירוקה ✅ בכרטיס שלה).'),
                    _Bullet('העדיפי מטפלות עם תעודת עזרה ראשונה (תופיע התווית 🩹).'),
                    _Bullet('הציגי לה את הילדים ואת ההוראות המיוחדות (אלרגיות, תרופות, שעת שינה) לפני שיוצאים.'),
                    _Bullet('השאירי מספר טלפון ליצירת קשר במקרה חירום.'),

                    const SizedBox(height: 16),
                    _SectionTitle('אם יש לילד אלרגיה או מצב רפואי'),
                    _Bullet('כתבי בבירור בהוראות המיוחדות — אלרגיות, תרופות קבועות, מצבים מיוחדים.'),
                    _Bullet('אם יש EpiPen או מינון תרופה — הראי למטפלת איפה ואיך להשתמש.'),
                    _Bullet('שימרי את מספר רופא הילדים בהישג יד של המטפלת.'),

                    const SizedBox(height: 16),
                    _SectionTitle('אם זה אירוע רפואי דחוף'),
                    _Bullet('חיוג מיידי ל-101 (מד"א).'),
                    _Bullet('המטפלת מצויידת באוטו? היפנו לבית חולים הקרוב.'),
                    _Bullet('מסרי לרופא: גיל הילד, אלרגיות, תרופות שלוקח, מה קרה.'),

                    const SizedBox(height: 24),
                    _SectionTitle('חיוג מהיר'),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _CallButton(
                            number: '101',
                            label: 'מד"א',
                            color: BabyEmergencyPalette.red500,
                            onTap: () => _call('101'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _CallButton(
                            number: '100',
                            label: 'משטרה',
                            color: BabyEmergencyPalette.red700,
                            onTap: () => _call('100'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _CallButton(
                            number: '102',
                            label: 'כיבוי אש',
                            color: BabyEmergencyPalette.amber500,
                            onTap: () => _call('102'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _CallButton(
                      number: '1-800-223-966',
                      label: 'מועצה לשלום הילד',
                      color: BabyEmergencyPalette.purple500,
                      onTap: () => _call('18002239 66'),
                      fullWidth: true,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'ההנחיות הללו כלליות. בכל מקרה של ספק או דחיפות — חיוג מיידי ל-101.',
                      style: TextStyle(
                        color: BabyEmergencyPalette.textTertiary,
                        fontSize: 12,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          color: BabyEmergencyPalette.purple700,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 6, start: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 7),
            child: Icon(Icons.circle,
                size: 5, color: BabyEmergencyPalette.purple500),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: BabyEmergencyPalette.textSecondary,
                fontSize: 13.5,
                height: 1.55,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  final String number;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool fullWidth;

  const _CallButton({
    required this.number,
    required this.label,
    required this.color,
    required this.onTap,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          child: Row(
            mainAxisAlignment: fullWidth
                ? MainAxisAlignment.center
                : MainAxisAlignment.center,
            children: [
              const Icon(Icons.phone_in_talk_rounded,
                  color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '$number · $label',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
