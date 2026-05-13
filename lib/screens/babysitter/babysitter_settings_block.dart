// Babysitter — provider-side settings block (CLAUDE.md §53).
//
// Mirrors the size/feel of pest_control_settings_block.dart:
//   • warm cream card with section headers
//   • Material chips for multi-select (age groups, services)
//   • inline editable list (certifications)
//   • slider+number-field hybrids for the Smart Auto-Billing rules
//
// onChanged is called every time the provider edits anything — the parent
// (edit_profile_screen / admin_demo_experts_tab) holds the source of truth
// and writes to Firestore on Save.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/babysitter_profile.dart';
import '../../constants/babysitter_age_groups.dart';
import '../../constants/babysitter_services_catalog.dart';
import '../../constants/babysitter_certifications.dart';
import '../../services/csm_text_override_service.dart';

const _kBabyPink = Color(0xFFEC4899);
const _kBabyPinkBg = Color(0xFFFCE7F3);
const _kBabyIndigo = Color(0xFF6366F1);
const _kBabyIndigoBg = Color(0xFFEEF2FF);
const _kBabyAmberBg = Color(0xFFFEF3C7);
const _kBabyAmberBorder = Color(0xFFFBBF24);
const _kBabyGreen = Color(0xFF10B981);
const _kBabyGreenBg = Color(0xFFDCFCE7);
const _kCardBg = Colors.white;
const _kCreamBorder = Color(0xFFEAE7DF);
const _kBgCream = Color(0xFFFAF7F2);

class BabysitterSettingsBlock extends StatefulWidget {
  final BabysitterProfile initialProfile;
  final ValueChanged<BabysitterProfile> onChanged;

  const BabysitterSettingsBlock({
    super.key,
    required this.initialProfile,
    required this.onChanged,
  });

  @override
  State<BabysitterSettingsBlock> createState() =>
      _BabysitterSettingsBlockState();
}

class _BabysitterSettingsBlockState extends State<BabysitterSettingsBlock> {
  late BabysitterExperience _experience;
  late Set<String> _ageGroups;
  late Set<String> _services;
  late List<BabysitterCertification> _certifications;
  late BabysitterPricingConfig _pricing;
  late BabysitterAvailability _availability;
  late BabysitterServiceArea _serviceArea;
  late BabysitterTrustBadges _trust;

  late TextEditingController _yearsCtrl;
  late TextEditingController _familiesCtrl;
  late TextEditingController _introCtrl;
  late TextEditingController _refCountCtrl;
  late TextEditingController _citiesCtrl;

  // Pricing controllers (kept in sync with state on every onChanged).
  late TextEditingController _rate1Ctrl;
  late TextEditingController _rate2Ctrl;
  late TextEditingController _rate3Ctrl;
  late TextEditingController _lateFeeCtrl;
  late TextEditingController _lateFeeMaxCtrl;
  late TextEditingController _overnightFlatCtrl;

  // ── CSM text override wiring ──
  static const _csmId = 'babysitter';
  final _textOverrides = CsmTextOverrideService.instance;
  String _t(String key, String fallback) =>
      _textOverrides.t(_csmId, key, fallback);
  void _onTextOverridesChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _textOverrides.ensureLoaded(_csmId);
    _textOverrides.addListener(_onTextOverridesChanged);
    final p = widget.initialProfile;
    _experience = p.experience;
    _ageGroups = p.ageGroups.toSet();
    _services = p.servicesOffered.toSet();
    _certifications = List.of(p.certifications);
    _pricing = p.pricing;
    _availability = p.availability;
    _serviceArea = p.serviceArea;
    _trust = p.trust;

    _yearsCtrl =
        TextEditingController(text: _experience.yearsExperience.toString());
    _familiesCtrl =
        TextEditingController(text: _experience.totalFamilies.toString());
    _introCtrl = TextEditingController(text: p.introNote);
    _refCountCtrl =
        TextEditingController(text: _trust.referencesCount.toString());
    _citiesCtrl =
        TextEditingController(text: _serviceArea.cities.join(', '));

    _rate1Ctrl =
        TextEditingController(text: _pricing.rateOneChild.toStringAsFixed(0));
    _rate2Ctrl = TextEditingController(
        text: _pricing.rateTwoChildren.toStringAsFixed(0));
    _rate3Ctrl = TextEditingController(
        text: _pricing.rateThreePlusChildren.toStringAsFixed(0));
    _lateFeeCtrl = TextEditingController(
        text: _pricing.lateFeePerInterval.toStringAsFixed(0));
    _lateFeeMaxCtrl = TextEditingController(
        text: _pricing.lateFeeMaxAmount.toStringAsFixed(0));
    _overnightFlatCtrl = TextEditingController(
        text: _pricing.overnightFlatRate.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _textOverrides.removeListener(_onTextOverridesChanged);
    _yearsCtrl.dispose();
    _familiesCtrl.dispose();
    _introCtrl.dispose();
    _refCountCtrl.dispose();
    _citiesCtrl.dispose();
    _rate1Ctrl.dispose();
    _rate2Ctrl.dispose();
    _rate3Ctrl.dispose();
    _lateFeeCtrl.dispose();
    _lateFeeMaxCtrl.dispose();
    _overnightFlatCtrl.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onChanged(BabysitterProfile(
      experience: _experience,
      ageGroups: _ageGroups.toList(),
      servicesOffered: _services.toList(),
      certifications: _certifications,
      pricing: _pricing,
      availability: _availability,
      serviceArea: _serviceArea,
      trust: _trust,
      introNote: _introCtrl.text.trim(),
    ));
  }

  // ── Pricing helpers ─────────────────────────────────────────────────────
  void _updatePricing(BabysitterPricingConfig next) {
    setState(() => _pricing = next);
    _emit();
  }

  // ── Certification add/remove ────────────────────────────────────────────
  void _addCertificationDialog() async {
    final picked = await showModalBottomSheet<BabysitterCertificationDef>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'בחרי תעודה להוספה',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
            for (final def in kBabysitterCertifications)
              if (!_certifications.any((c) => c.id == def.id))
                ListTile(
                  leading: Text(def.emoji,
                      style: const TextStyle(fontSize: 24)),
                  title: Text(def.labelHe),
                  onTap: () => Navigator.pop(ctx, def),
                ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null) return;
    setState(() {
      _certifications.add(BabysitterCertification(
        id: picked.id,
        type: picked.type,
        nameHe: picked.labelHe,
      ));
    });
    _emit();
  }

  void _removeCertification(String id) {
    setState(() => _certifications.removeWhere((c) => c.id == id));
    _emit();
  }

  // ── UI build ────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _kBgCream,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kCreamBorder),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _hero(),
          const SizedBox(height: 16),
          _sectionExperience(),
          const SizedBox(height: 16),
          _sectionAgeGroups(),
          const SizedBox(height: 16),
          _sectionServices(),
          const SizedBox(height: 16),
          _sectionCertifications(),
          const SizedBox(height: 16),
          _sectionPricing(),
          const SizedBox(height: 16),
          _sectionAvailability(),
          const SizedBox(height: 16),
          _sectionServiceArea(),
          const SizedBox(height: 16),
          _sectionTrust(),
          const SizedBox(height: 16),
          _sectionIntroNote(),
          const SizedBox(height: 16),
          _liveBillingNotice(),
        ],
      ),
    );
  }

  Widget _hero() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_kBabyPink, Color(0xFF8B5CF6)],
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Text('👶', style: TextStyle(fontSize: 32)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t('hero.title', 'בייביסיטר — ההגדרות שלך'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _t('hero.subtitle',
                        'תעריפים, ניסיון, אזורי שירות וחיוב חכם על איחור הורים'),
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _sectionTitle(String title, {String? hint}) => Padding(
        padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 15)),
            if (hint != null && hint.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(hint,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF6B7280))),
              ),
          ],
        ),
      );

  Widget _card({required Widget child}) => Container(
        decoration: BoxDecoration(
          color: _kCardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _kCreamBorder),
        ),
        padding: const EdgeInsets.all(14),
        child: child,
      );

  // ── Experience ──────────────────────────────────────────────────────────
  Widget _sectionExperience() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(_t('experience.title', '🌟 ניסיון'),
                hint: 'עוזר ללקוחות לבחור אותך'),
            Row(
              children: [
                Expanded(
                  child: _intField(
                    label: 'שנות ניסיון',
                    controller: _yearsCtrl,
                    onChanged: (v) {
                      _experience = BabysitterExperience(
                        yearsExperience: int.tryParse(v) ?? 0,
                        totalFamilies: _experience.totalFamilies,
                        hasOwnChildren: _experience.hasOwnChildren,
                      );
                      _emit();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _intField(
                    label: 'מספר משפחות',
                    controller: _familiesCtrl,
                    onChanged: (v) {
                      _experience = BabysitterExperience(
                        yearsExperience: _experience.yearsExperience,
                        totalFamilies: int.tryParse(v) ?? 0,
                        hasOwnChildren: _experience.hasOwnChildren,
                      );
                      _emit();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              value: _experience.hasOwnChildren,
              onChanged: (v) {
                setState(() {
                  _experience = BabysitterExperience(
                    yearsExperience: _experience.yearsExperience,
                    totalFamilies: _experience.totalFamilies,
                    hasOwnChildren: v,
                  );
                });
                _emit();
              },
              contentPadding: EdgeInsets.zero,
              title: const Text('יש לי ילדים משלי',
                  style: TextStyle(fontSize: 13)),
              dense: true,
              activeColor: _kBabyPink,
            ),
          ],
        ),
      );

  // ── Age Groups ──────────────────────────────────────────────────────────
  Widget _sectionAgeGroups() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(_t('ageGroups.title', '👶 גילאים שאני מטפלת בהם')),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final g in kBabysitterAgeGroups)
                  _toggleChip(
                    label: '${g.emoji} ${g.labelHe}',
                    sub: g.hint,
                    selected: _ageGroups.contains(g.id),
                    color: g.color,
                    onTap: () {
                      setState(() {
                        if (_ageGroups.contains(g.id)) {
                          _ageGroups.remove(g.id);
                        } else {
                          _ageGroups.add(g.id);
                        }
                      });
                      _emit();
                    },
                  ),
              ],
            ),
          ],
        ),
      );

  // ── Services ────────────────────────────────────────────────────────────
  Widget _sectionServices() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(_t('services.title', '🤲 שירותים נוספים שאני מציעה')),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in kBabysitterServices)
                  _toggleChip(
                    label: '${s.emoji} ${s.labelHe}',
                    selected: _services.contains(s.id),
                    color: _kBabyIndigo,
                    onTap: () {
                      setState(() {
                        if (_services.contains(s.id)) {
                          _services.remove(s.id);
                        } else {
                          _services.add(s.id);
                        }
                      });
                      _emit();
                    },
                  ),
              ],
            ),
          ],
        ),
      );

  // ── Certifications ──────────────────────────────────────────────────────
  Widget _sectionCertifications() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _sectionTitle(
                      _t('certifications.title', '🎓 תעודות והכשרות'),
                      hint: 'מוצגות כתגי אמון בפרופיל'),
                ),
                IconButton(
                  onPressed: _addCertificationDialog,
                  icon: const Icon(Icons.add_circle, color: _kBabyPink),
                  tooltip: 'הוסף תעודה',
                ),
              ],
            ),
            if (_certifications.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('עדיין לא הוספת תעודות',
                    style: TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
              )
            else
              for (final cert in _certifications)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _kBabyPinkBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            cert.nameHe,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                        ),
                        if (cert.verified)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _kBabyGreenBg,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('✓ מאומת',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: _kBabyGreen,
                                    fontWeight: FontWeight.w700)),
                          ),
                        IconButton(
                          onPressed: () => _removeCertification(cert.id),
                          icon: const Icon(Icons.close, size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      );

  // ── Pricing (Smart Auto-Billing) ────────────────────────────────────────
  Widget _sectionPricing() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(_t('pricing.title', '💰 חיוב חכם — תעריפי שעה'),
                hint: 'תעריפים שונים לפי מספר ילדים'),
            Row(
              children: [
                Expanded(
                  child: _moneyField(
                    label: '1 ילד',
                    controller: _rate1Ctrl,
                    onChanged: (v) => _updatePricing(_pricing.copyWith(
                        rateOneChild: double.tryParse(v) ?? 60)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _moneyField(
                    label: '2 ילדים',
                    controller: _rate2Ctrl,
                    onChanged: (v) => _updatePricing(_pricing.copyWith(
                        rateTwoChildren: double.tryParse(v) ?? 80)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _moneyField(
                    label: '3+ ילדים',
                    controller: _rate3Ctrl,
                    onChanged: (v) => _updatePricing(_pricing.copyWith(
                        rateThreePlusChildren: double.tryParse(v) ?? 100)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            _sectionTitle(_t('nightSurcharge.title', '🌙 תוספת לילה'),
                hint:
                    'אחוז שמתווסף לתעריף השעתי בשעות הלילה (משעה ${_pricing.nightStartsAtHour.toString().padLeft(2, '0')}:00)'),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _pricing.nightSurchargePercent.toDouble(),
                    min: 0,
                    max: 60,
                    divisions: 12,
                    label: '+${_pricing.nightSurchargePercent}%',
                    activeColor: _kBabyPink,
                    onChanged: (v) {
                      _updatePricing(_pricing.copyWith(
                          nightSurchargePercent: v.round()));
                    },
                  ),
                ),
                Container(
                  width: 56,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: _kBabyPinkBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('+${_pricing.nightSurchargePercent}%',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _sectionTitle(_t('holidaySurcharge.title', '🎉 תוספת חג'),
                hint: 'תוספת על כלל החיוב בימי חג מוכרים'),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _pricing.holidaySurchargePercent.toDouble(),
                    min: 0,
                    max: 100,
                    divisions: 20,
                    label: '+${_pricing.holidaySurchargePercent}%',
                    activeColor: _kBabyPink,
                    onChanged: (v) {
                      _updatePricing(_pricing.copyWith(
                          holidaySurchargePercent: v.round()));
                    },
                  ),
                ),
                Container(
                  width: 56,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: _kBabyPinkBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('+${_pricing.holidaySurchargePercent}%',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            _sectionTitle(_t('lateFee.title', '⏰ קנס איחור'),
                hint:
                    'נגבה אוטומטית מההורה כשהוא חוזר אחרי הזמן שסוכם — קנס לכל ${_pricing.lateFeeIntervalMinutes} דקות איחור'),
            Row(
              children: [
                Expanded(
                  child: _moneyField(
                    label: 'לכל ${_pricing.lateFeeIntervalMinutes} דק׳',
                    controller: _lateFeeCtrl,
                    onChanged: (v) => _updatePricing(_pricing.copyWith(
                        lateFeePerInterval: double.tryParse(v) ?? 40)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _moneyField(
                    label: 'תקרה לקנס',
                    controller: _lateFeeMaxCtrl,
                    onChanged: (v) => _updatePricing(_pricing.copyWith(
                        lateFeeMaxAmount: double.tryParse(v) ?? 500)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: _kBabyAmberBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _kBabyAmberBorder, width: 1),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Color(0xFF92400E)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'הקנס נגבה אוטומטית בלחיצת "סיימתי" ומועבר אלייך — בלי שיחות מביכות עם ההורה.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF92400E)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            _sectionTitle(_t('overnightFlat.title', '🌃 תעריף לילה (Flat)'),
                hint: 'אופציונלי — מחיר אחיד למשמרת לילה (₪0 = כיבוי)'),
            _moneyField(
              label: 'תעריף Flat לכל הלילה',
              controller: _overnightFlatCtrl,
              onChanged: (v) => _updatePricing(
                  _pricing.copyWith(overnightFlatRate: double.tryParse(v) ?? 0)),
            ),
            const SizedBox(height: 12),
            _sectionTitle(_t('lastMinute.title', '⚡ הזמנה ברגע האחרון'),
                hint: 'תוספת אם ההזמנה ${_pricing.lastMinuteThresholdHours} שעות לפני המשמרת'),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _pricing.lastMinuteSurchargePercent.toDouble(),
                    min: 0,
                    max: 80,
                    divisions: 16,
                    label: '+${_pricing.lastMinuteSurchargePercent}%',
                    activeColor: _kBabyIndigo,
                    onChanged: (v) {
                      _updatePricing(_pricing.copyWith(
                          lastMinuteSurchargePercent: v.round()));
                    },
                  ),
                ),
                Container(
                  width: 56,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: _kBabyIndigoBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('+${_pricing.lastMinuteSurchargePercent}%',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ],
        ),
      );

  // ── Availability ────────────────────────────────────────────────────────
  Widget _sectionAvailability() {
    const dayLabels = ['א', 'ב', 'ג', 'ד', 'ה', 'ו', 'ש'];
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(_t('availability.title', '📅 ימי זמינות')),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (int i = 0; i < 7; i++)
                ChoiceChip(
                  label: Text(dayLabels[i],
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  selected: _availability.availableDays.contains(i),
                  selectedColor: _kBabyIndigo,
                  labelStyle: TextStyle(
                    color: _availability.availableDays.contains(i)
                        ? Colors.white
                        : Colors.black87,
                  ),
                  onSelected: (sel) {
                    setState(() {
                      final days = _availability.availableDays.toSet();
                      if (sel) {
                        days.add(i);
                      } else {
                        days.remove(i);
                      }
                      _availability = BabysitterAvailability(
                        availableDays: days.toList()..sort(),
                        acceptsLastMinute: _availability.acceptsLastMinute,
                        acceptsOvernight: _availability.acceptsOvernight,
                        acceptsHolidays: _availability.acceptsHolidays,
                      );
                    });
                    _emit();
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            value: _availability.acceptsLastMinute,
            onChanged: (v) {
              setState(() {
                _availability = BabysitterAvailability(
                  availableDays: _availability.availableDays,
                  acceptsLastMinute: v,
                  acceptsOvernight: _availability.acceptsOvernight,
                  acceptsHolidays: _availability.acceptsHolidays,
                );
              });
              _emit();
            },
            contentPadding: EdgeInsets.zero,
            dense: true,
            activeColor: _kBabyIndigo,
            title: const Text('מקבלת הזמנות ברגע האחרון',
                style: TextStyle(fontSize: 13)),
          ),
          SwitchListTile.adaptive(
            value: _availability.acceptsOvernight,
            onChanged: (v) {
              setState(() {
                _availability = BabysitterAvailability(
                  availableDays: _availability.availableDays,
                  acceptsLastMinute: _availability.acceptsLastMinute,
                  acceptsOvernight: v,
                  acceptsHolidays: _availability.acceptsHolidays,
                );
              });
              _emit();
            },
            contentPadding: EdgeInsets.zero,
            dense: true,
            activeColor: _kBabyIndigo,
            title: const Text('זמינה למשמרת לילה (Overnight)',
                style: TextStyle(fontSize: 13)),
          ),
          SwitchListTile.adaptive(
            value: _availability.acceptsHolidays,
            onChanged: (v) {
              setState(() {
                _availability = BabysitterAvailability(
                  availableDays: _availability.availableDays,
                  acceptsLastMinute: _availability.acceptsLastMinute,
                  acceptsOvernight: _availability.acceptsOvernight,
                  acceptsHolidays: v,
                );
              });
              _emit();
            },
            contentPadding: EdgeInsets.zero,
            dense: true,
            activeColor: _kBabyIndigo,
            title: const Text('עובדת בחגים', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  // ── Service Area ────────────────────────────────────────────────────────
  Widget _sectionServiceArea() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(_t('serviceArea.title', '📍 אזור שירות'),
                hint: 'הערים שאת מוכנה לעבוד בהן'),
            TextField(
              controller: _citiesCtrl,
              decoration: const InputDecoration(
                hintText: 'תל אביב, רמת גן, גבעתיים...',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) {
                _serviceArea = BabysitterServiceArea(
                  cities: v
                      .split(',')
                      .map((s) => s.trim())
                      .where((s) => s.isNotEmpty)
                      .toList(),
                  arrivalRadiusMeters: _serviceArea.arrivalRadiusMeters,
                  travelFeeOutsideRadius: _serviceArea.travelFeeOutsideRadius,
                  freeRadiusKm: _serviceArea.freeRadiusKm,
                );
                _emit();
              },
            ),
            const SizedBox(height: 12),
            _sectionTitle(_t('arrivalRadius.title', '🎯 רדיוס הגעה ל-GPS'),
                hint:
                    'בלחיצה על "התחלתי משמרת" המערכת תוודא שאת במרחק ${_serviceArea.arrivalRadiusMeters} מ׳ מהבית'),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _serviceArea.arrivalRadiusMeters.toDouble(),
                    min: 25,
                    max: 200,
                    divisions: 35,
                    label: '${_serviceArea.arrivalRadiusMeters} מ׳',
                    activeColor: _kBabyGreen,
                    onChanged: (v) {
                      setState(() {
                        _serviceArea = BabysitterServiceArea(
                          cities: _serviceArea.cities,
                          arrivalRadiusMeters: v.round(),
                          travelFeeOutsideRadius:
                              _serviceArea.travelFeeOutsideRadius,
                          freeRadiusKm: _serviceArea.freeRadiusKm,
                        );
                      });
                      _emit();
                    },
                  ),
                ),
                Container(
                  width: 70,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: _kBabyGreenBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('${_serviceArea.arrivalRadiusMeters} מ׳',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ],
        ),
      );

  // ── Trust ───────────────────────────────────────────────────────────────
  Widget _sectionTrust() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(_t('trust.title', '🛡️ אמון'),
                hint: 'מוצג כתגי אמון בפרופיל שלך'),
            SwitchListTile.adaptive(
              value: _trust.backgroundChecked,
              onChanged: (v) {
                setState(() {
                  _trust = BabysitterTrustBadges(
                    backgroundChecked: v,
                    idVerified: _trust.idVerified,
                    referencesAvailable: _trust.referencesAvailable,
                    referencesCount: _trust.referencesCount,
                  );
                });
                _emit();
              },
              activeColor: _kBabyGreen,
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('עברתי בדיקת רקע',
                  style: TextStyle(fontSize: 13)),
            ),
            SwitchListTile.adaptive(
              value: _trust.referencesAvailable,
              onChanged: (v) {
                setState(() {
                  _trust = BabysitterTrustBadges(
                    backgroundChecked: _trust.backgroundChecked,
                    idVerified: _trust.idVerified,
                    referencesAvailable: v,
                    referencesCount: _trust.referencesCount,
                  );
                });
                _emit();
              },
              activeColor: _kBabyGreen,
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('יש לי המלצות מהורים קודמים',
                  style: TextStyle(fontSize: 13)),
            ),
            if (_trust.referencesAvailable)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: _intField(
                  label: 'מספר המלצות',
                  controller: _refCountCtrl,
                  onChanged: (v) {
                    _trust = BabysitterTrustBadges(
                      backgroundChecked: _trust.backgroundChecked,
                      idVerified: _trust.idVerified,
                      referencesAvailable: _trust.referencesAvailable,
                      referencesCount: int.tryParse(v) ?? 0,
                    );
                    _emit();
                  },
                ),
              ),
          ],
        ),
      );

  // ── Intro Note ──────────────────────────────────────────────────────────
  Widget _sectionIntroNote() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle(_t('introNote.title', '💌 הודעה אישית להורים'),
                hint: 'מופיעה בפרופיל הציבורי שלך מעל הזמנת משמרת'),
            TextField(
              controller: _introCtrl,
              maxLines: 4,
              maxLength: 280,
              decoration: const InputDecoration(
                hintText: 'שלום, אני שרה. אני אוהבת ילדים מאוד וגדלתי...',
                border: OutlineInputBorder(),
                counterText: '',
              ),
              onChanged: (_) => _emit(),
            ),
          ],
        ),
      );

  // ── Live Billing Notice ─────────────────────────────────────────────────
  Widget _liveBillingNotice() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _kBabyIndigoBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kBabyIndigo, width: 1),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.bolt, color: _kBabyIndigo, size: 22),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Smart Auto-Billing פעיל',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: _kBabyIndigo,
                          fontSize: 13)),
                  SizedBox(height: 4),
                  Text(
                    'בסוף כל משמרת המערכת מחשבת את הסכום הסופי לפי השעות בפועל, תוספות לילה/חג וקנס איחור — וגובה מההורה אוטומטית.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF1E3A8A)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  // ── Helpers ─────────────────────────────────────────────────────────────
  Widget _toggleChip({
    required String label,
    String? sub,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? color : _kCreamBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            if (sub != null && sub.isNotEmpty)
              Text(
                sub,
                style: TextStyle(
                  color: selected ? Colors.white70 : const Color(0xFF6B7280),
                  fontSize: 10,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _intField({
    required String label,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
  }) =>
      TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: onChanged,
      );

  Widget _moneyField({
    required String label,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
  }) =>
      TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          prefixText: '₪ ',
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: onChanged,
      );
}
