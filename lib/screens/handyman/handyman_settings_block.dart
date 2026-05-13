// Handyman CSM — Provider settings block ("ההגדרות שלך").
// Appears in edit_profile_screen.dart AFTER the sub-category dropdown AND ONLY
// when the selected sub-category resolves to "הנדימן" via isHandymanCategory().
//
// 8 sections (spec 02_PROVIDER_EDIT_HANDYMAN.md):
//   1. Hero + revenue banner (no profile-card duplicates)
//   2. Verifications — 2 badges only (NO ID, NO insurance)
//   3. AI Photo-to-Quote settings
//   4. 23 specialties grid
//   5. Pricing editor
//   6. Punch List graduated discount
//   7. Service area (cities + emergency 24/7 + buffer + CALENDAR BANNER)
//      — NO working-hours section
//   8. Materials management
//   9. Maintenance packages (3 tiers)
//
// Palette: Dark premium orange/amber (scoped — does NOT replace Brand.*).
import 'package:flutter/material.dart';

import '../../constants/handyman_specialties_catalog.dart';
import '../../models/handyman_profile.dart';
import '../../services/csm_text_override_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SCOPED PALETTE
// ═══════════════════════════════════════════════════════════════════════════

class _HPalette {
  static const darkBase = Color(0xFF0A0E1A);
  static const darkBaseMid = Color(0xFF1A1612);
  static const darkBaseDeep = Color(0xFF0F1420);
  static const orange = Color(0xFFF97316);
  static const orangeDark = Color(0xFFEA580C);
  static const amberPale = Color(0xFFFDBA74);
  static const amber = Color(0xFFF59E0B);
  static const green = Color(0xFF16A34A);
  static const red = Color(0xFFDC2626);
  static const purple = Color(0xFFA855F7);
  static const blue = Color(0xFF3B82F6);
  static const indigoDark = Color(0xFF1E3A8A);
  static final glassBg = Colors.white.withValues(alpha: 0.04);
  static final glassBorder = Colors.white.withValues(alpha: 0.08);
}

// ═══════════════════════════════════════════════════════════════════════════
// PUBLIC WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class HandymanSettingsBlock extends StatefulWidget {
  final HandymanProfile initialProfile;
  final ValueChanged<HandymanProfile> onChanged;

  const HandymanSettingsBlock({
    super.key,
    required this.initialProfile,
    required this.onChanged,
  });

  @override
  State<HandymanSettingsBlock> createState() => _HandymanSettingsBlockState();
}

class _HandymanSettingsBlockState extends State<HandymanSettingsBlock> {
  late HandymanProfile _profile;
  late final Map<String, TextEditingController> _priceCtrls;
  late final TextEditingController _emergencySurchargeCtrl;
  late final TextEditingController _bufferMinutesCtrl;

  // ── CSM text override wiring ──
  static const _csmId = 'handyman';
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
    // If a brand-new provider has no specialties yet, seed the 8 default "hot"
    // ones so they can immediately edit prices instead of being shown 0/23.
    var profile = widget.initialProfile;
    if (profile.specialties.isEmpty) {
      profile = profile.copyWith(specialties: defaultActiveSpecialties());
    }
    if (profile.maintenancePackages.isEmpty) {
      profile = profile.copyWith(
        maintenancePackages: kDefaultMaintenancePackages
            .map((m) => HandymanMaintenancePackage.fromMap(
                Map<String, dynamic>.from(m)))
            .toList(),
      );
    }
    _profile = profile;
    _priceCtrls = {
      for (final s in _profile.specialties)
        s.id: TextEditingController(
            text: _profile.pricing.priceFor(s.id, s.basePrice).toStringAsFixed(0)),
    };
    _emergencySurchargeCtrl = TextEditingController(
        text: _profile.pricing.emergencySurcharge.toStringAsFixed(0));
    _bufferMinutesCtrl = TextEditingController(
        text: _profile.serviceArea.bufferMinutes.toString());
    // Inform parent of seeded defaults.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onChanged(_profile);
    });
  }

  @override
  void dispose() {
    _textOverrides.removeListener(_onTextOverridesChanged);
    for (final c in _priceCtrls.values) {
      c.dispose();
    }
    _emergencySurchargeCtrl.dispose();
    _bufferMinutesCtrl.dispose();
    super.dispose();
  }

  void _emit(HandymanProfile next) {
    setState(() => _profile = next);
    widget.onChanged(next);
  }

  // ── Helpers for sub-updates ──────────────────────────────────────────────

  void _toggleSpecialtyActive(String id) {
    final updated = _profile.specialties.map((s) {
      if (s.id == id) return s.copyWith(active: !s.active);
      return s;
    }).toList();
    _emit(_profile.copyWith(specialties: updated));
  }

  void _addSpecialtyFromCatalog(HandymanSpecialty source) {
    if (_profile.specialties.any((s) => s.id == source.id)) return;
    final added = [..._profile.specialties, source.copyWith(active: true)];
    _priceCtrls[source.id] ??= TextEditingController(
        text: source.basePrice.toStringAsFixed(0));
    _emit(_profile.copyWith(specialties: added));
  }

  void _setCustomPrice(String serviceId, double price) {
    final next = Map<String, double>.from(_profile.pricing.customPrices);
    next[serviceId] = price;
    _emit(_profile.copyWith(
        pricing: _profile.pricing.copyWith(customPrices: next)));
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _HPalette.darkBase,
              _HPalette.darkBaseMid,
              _HPalette.darkBaseDeep,
            ],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHero(),
            const SizedBox(height: 16),
            _buildVerifications(),
            const SizedBox(height: 14),
            _buildAiPhotoSettings(),
            const SizedBox(height: 14),
            _buildSpecialties(),
            const SizedBox(height: 14),
            _buildPricing(),
            const SizedBox(height: 14),
            _buildPunchListDiscount(),
            const SizedBox(height: 14),
            _buildServiceArea(),
            const SizedBox(height: 14),
            _buildMaterials(),
            const SizedBox(height: 14),
            _buildMaintenancePackages(),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 1. HERO
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildHero() {
    final activeCount = _profile.specialties.where((s) => s.active).length;
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Pill(
                text: '● הנדימן פעיל',
                color: _HPalette.green,
                bg: _HPalette.green.withValues(alpha: 0.18),
              ),
              const Spacer(),
              _Pill(
                text: '⚡ Pro Verified',
                color: _HPalette.blue,
                bg: _HPalette.blue.withValues(alpha: 0.18),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _t('hero.title', 'ההגדרות שלך'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _t('hero.subtitle',
                'ככל שתגדיר יותר טוב — יותר לקוחות ימצאו אותך'),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _HPalette.purple.withValues(alpha: 0.22),
                  _HPalette.purple.withValues(alpha: 0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: _HPalette.purple.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                const Text('📈', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$activeCount תחומים פעילים',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'טיפ: 12+ תחומים = פי 2.3 הכנסה',
                        style: TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 2. VERIFICATIONS — 2 badges only (NO ID, NO insurance)
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildVerifications() {
    final v = _profile.verifications;
    return _GlassCard(
      borderColor: _HPalette.red.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: '!',
            title: _t('verifications.title', 'אימותים (חובה)'),
            trailing: _Pill(
              text: v.backgroundCheck.verified && v.warrantyEnabled
                  ? '2/2 מאושרים'
                  : '${(v.backgroundCheck.verified ? 1 : 0) + (v.warrantyEnabled ? 1 : 0)}/2',
              color: _HPalette.green,
              bg: _HPalette.green.withValues(alpha: 0.2),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _t('verifications.subtitle',
                'חובה לאישור פרופיל — מוכיח ללקוחות שאפשר לסמוך עליך'),
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 14),
          // Background check
          _VerificationRow(
            icon: '📋',
            title: 'בדיקת רקע',
            subtitle: v.backgroundCheck.verified
                ? 'מאושר · ללא רישום פלילי'
                : 'נדרש אישור ממנהל האפליקציה',
            trailing: Switch(
              value: v.backgroundCheck.verified,
              activeColor: _HPalette.green,
              onChanged: (val) {
                _emit(_profile.copyWith(
                  verifications: v.copyWith(
                    backgroundCheck:
                        v.backgroundCheck.copyWith(verified: val, verifiedAt: val ? DateTime.now() : null),
                  ),
                ));
              },
            ),
          ),
          const SizedBox(height: 10),
          // Warranty toggle
          _VerificationRow(
            icon: '📜',
            title: 'אחריות 12 חודש',
            subtitle: 'תאושר אוטומטית על כל עבודה',
            trailing: Switch(
              value: v.warrantyEnabled,
              activeColor: _HPalette.green,
              onChanged: (val) {
                _emit(_profile.copyWith(
                  verifications: v.copyWith(warrantyEnabled: val),
                ));
              },
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 3. AI PHOTO-TO-QUOTE SETTINGS
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildAiPhotoSettings() {
    final ai = _profile.aiPhotoToQuote;
    return _GlassCard(
      borderColor: _HPalette.orange.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🤖', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _t('aiPhoto.title', 'AI Photo-to-Quote'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      _t('aiPhoto.subtitle',
                          '⭐ פרופיל עם AI = +40% הזמנות'),
                      style: const TextStyle(
                          color: _HPalette.amberPale, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Switch(
                value: ai.enabled,
                activeColor: _HPalette.orange,
                onChanged: (v) =>
                    _emit(_profile.copyWith(aiPhotoToQuote: ai.copyWith(enabled: v))),
              ),
            ],
          ),
          if (ai.enabled) ...[
            const SizedBox(height: 14),
            const Text(
              'מה AI יזהה עבורך',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            _CategoryToggle(
              emoji: '🚿',
              label: 'בעיות אינסטלציה',
              value: ai.plumbing,
              onChanged: (v) => _emit(_profile.copyWith(
                  aiPhotoToQuote: ai.copyWith(plumbing: v))),
            ),
            _CategoryToggle(
              emoji: '💡',
              label: 'בעיות חשמל',
              value: ai.electrical,
              onChanged: (v) => _emit(_profile.copyWith(
                  aiPhotoToQuote: ai.copyWith(electrical: v))),
            ),
            _CategoryToggle(
              emoji: '🔨',
              label: 'בעיות גבס/צבע',
              value: ai.drywall,
              onChanged: (v) => _emit(_profile.copyWith(
                  aiPhotoToQuote: ai.copyWith(drywall: v))),
            ),
            _CategoryToggle(
              emoji: '🪑',
              label: 'הרכבת רהיטים',
              value: ai.furniture,
              onChanged: (v) => _emit(_profile.copyWith(
                  aiPhotoToQuote: ai.copyWith(furniture: v))),
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 4. 23 SPECIALTIES
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildSpecialties() {
    final active = _profile.specialties.where((s) => s.active).length;
    final inactiveInProfile =
        _profile.specialties.where((s) => !s.active).toList();
    final notYetInProfile = kHandymanSpecialtiesCatalog
        .where((c) => !_profile.specialties.any((s) => s.id == c.id))
        .toList();

    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: '🧰',
            title: _t('specialties.title', 'תחומי ההתמחות שלך'),
            subtitle:
                '$active פעיל · ${inactiveInProfile.length + notYetInProfile.length} פוטנציאל',
          ),
          const SizedBox(height: 12),
          // Active
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _profile.specialties
                .where((s) => s.active)
                .map((s) => _SpecialtyChip(
                      specialty: s,
                      active: true,
                      onTap: () => _toggleSpecialtyActive(s.id),
                    ))
                .toList(),
          ),
          if (inactiveInProfile.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'לא פעילים:',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: inactiveInProfile
                  .map((s) => _SpecialtyChip(
                        specialty: s,
                        active: false,
                        onTap: () => _toggleSpecialtyActive(s.id),
                      ))
                  .toList(),
            ),
          ],
          if (notYetInProfile.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'הוסף מהרשימה (${notYetInProfile.length}):',
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: notYetInProfile
                  .map((c) => _SpecialtyChip(
                        specialty: c,
                        active: false,
                        isDashed: true,
                        onTap: () => _addSpecialtyFromCatalog(c),
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 5. PRICING
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildPricing() {
    final activeSpecs = _profile.specialties.where((s) => s.active).toList();
    return _GlassCard(
      borderColor: _HPalette.amber.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: '💰',
            title: _t('pricing.title', 'מחירון חכם לפי עבודה'),
            subtitle:
                _t('pricing.subtitle', 'AI משווה למחירי שוק תל אביב'),
          ),
          const SizedBox(height: 12),
          // Market intelligence helper (static for now — future: Gemini)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _HPalette.blue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _HPalette.blue.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: const [
                Text('📊', style: TextStyle(fontSize: 18)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'מחירי שוק ת"א: זול ₪120-150 · ממוצע ₪150-200 · יקר ₪220+',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Active specialties price list
          ...activeSpecs.map((s) => _PriceRow(
                specialty: s,
                controller: _priceCtrls[s.id] ??= TextEditingController(
                    text: _profile.pricing
                        .priceFor(s.id, s.basePrice)
                        .toStringAsFixed(0)),
                onChanged: (raw) {
                  final v = double.tryParse(raw);
                  if (v != null && v >= 0) _setCustomPrice(s.id, v);
                },
              )),
          const SizedBox(height: 14),
          // Emergency surcharge
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _HPalette.red.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _HPalette.red.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Text('🚨', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'תוספת חירום',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        'על הגעה תוך 25 דק\'',
                        style:
                            TextStyle(color: Colors.white60, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 70,
                  child: TextField(
                    controller: _emergencySurchargeCtrl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700),
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixText: '₪',
                      prefixStyle: TextStyle(color: Colors.white70),
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                      enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white30)),
                      focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: _HPalette.red)),
                    ),
                    onChanged: (raw) {
                      final v = double.tryParse(raw);
                      if (v != null && v >= 0) {
                        _emit(_profile.copyWith(
                            pricing:
                                _profile.pricing.copyWith(emergencySurcharge: v)));
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 6. PUNCH LIST DISCOUNT
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildPunchListDiscount() {
    final d = _profile.punchListDiscount;
    return _GlassCard(
      borderColor: _HPalette.purple.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: '📋',
            title: _t('punchList.title', 'Punch List Discount'),
            subtitle: _t('punchList.subtitle', 'עוד עבודות בביקור = יותר הנחה'),
          ),
          const SizedBox(height: 12),
          _DiscountBar(
            label: '2 עבודות',
            percent: d.twoJobs,
            maxPercent: 40,
            onChanged: (v) => _emit(_profile.copyWith(
                punchListDiscount: d.copyWith(twoJobs: v))),
          ),
          const SizedBox(height: 10),
          _DiscountBar(
            label: '3 עבודות',
            percent: d.threeJobs,
            maxPercent: 40,
            onChanged: (v) => _emit(_profile.copyWith(
                punchListDiscount: d.copyWith(threeJobs: v))),
          ),
          const SizedBox(height: 10),
          _DiscountBar(
            label: '4+ עבודות',
            percent: d.fourPlusJobs,
            maxPercent: 50,
            onChanged: (v) => _emit(_profile.copyWith(
                punchListDiscount: d.copyWith(fourPlusJobs: v))),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 7. SERVICE AREA — cities + emergency 24/7 + buffer + CALENDAR BANNER
  //    NO working-hours section (spec-critical constraint)
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildServiceArea() {
    final sa = _profile.serviceArea;
    final defaultCities = kHandymanDefaultCities;

    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: '🗺️',
            title: _t('serviceArea.title', 'אזורי שירות'),
            subtitle: _t('serviceArea.subtitle', 'איפה אתה עובד'),
          ),
          const SizedBox(height: 12),
          // Emergency 24/7
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _HPalette.red.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _HPalette.red.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Text('🚨', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'חירום 24/7',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        'הגעה תוך 25 דק\' · הכנסה גבוהה',
                        style: TextStyle(color: Colors.white60, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: sa.emergency24_7,
                  activeColor: _HPalette.red,
                  onChanged: (v) => _emit(_profile.copyWith(
                      serviceArea: sa.copyWith(emergency24_7: v))),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'ערים',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: defaultCities.map((city) {
              final selected = sa.cities.contains(city);
              return GestureDetector(
                onTap: () {
                  final next = List<String>.from(sa.cities);
                  if (selected) {
                    next.remove(city);
                  } else {
                    next.add(city);
                  }
                  _emit(_profile.copyWith(
                      serviceArea: sa.copyWith(cities: next)));
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected
                        ? _HPalette.orange.withValues(alpha: 0.25)
                        : Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selected
                          ? _HPalette.orange
                          : Colors.white.withValues(alpha: 0.15),
                      style: selected ? BorderStyle.solid : BorderStyle.solid,
                    ),
                  ),
                  child: Text(
                    selected ? '$city ✓' : city,
                    style: TextStyle(
                      color: selected ? Colors.white : Colors.white70,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 12,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          // Buffer minutes
          Row(
            children: [
              const Text('🕐', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'זמן חייץ בין עבודות',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
              SizedBox(
                width: 70,
                child: TextField(
                  controller: _bufferMinutesCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700),
                  decoration: const InputDecoration(
                    isDense: true,
                    suffixText: 'דק\'',
                    suffixStyle: TextStyle(color: Colors.white70),
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                    enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white30)),
                    focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: _HPalette.orange)),
                  ),
                  onChanged: (raw) {
                    final v = int.tryParse(raw);
                    if (v != null && v >= 0) {
                      _emit(_profile.copyWith(
                          serviceArea: sa.copyWith(bufferMinutes: v)));
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // CALENDAR BANNER — spec-critical: instead of work-hours UI,
          // direct the provider to the existing calendar.
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _HPalette.blue.withValues(alpha: 0.2),
                  _HPalette.blue.withValues(alpha: 0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _HPalette.blue.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: const [
                Text('🗓️', style: TextStyle(fontSize: 20)),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'שעות פעילות נקבעות ביומן',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'סמן ביומן הקיים למטה את הימים והשעות שלך',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_downward_rounded,
                    color: _HPalette.blue, size: 22),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 8. MATERIALS MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildMaterials() {
    final m = _profile.materials;
    return _GlassCard(
      borderColor: _HPalette.amber.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: '🛒',
            title: _t('materials.title', 'ניהול חומרים וציוד'),
            subtitle: _t('materials.subtitle',
                'שקיפות = יותר לקוחות סומכים עליך'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('🔧', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'כל הציוד המקצועי כלול (50+ כלים)',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
              Switch(
                value: m.toolsIncluded,
                activeColor: _HPalette.green,
                onChanged: (v) => _emit(_profile.copyWith(
                    materials: m.copyWith(toolsIncluded: v))),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'מדיניות חומרים',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _MaterialPolicyChip(
                emoji: '🛍️',
                label: 'אני קונה',
                value: 'i_buy',
                selected: m.policy == 'i_buy',
                onTap: () => _emit(_profile.copyWith(
                    materials: m.copyWith(policy: 'i_buy'))),
              ),
              const SizedBox(width: 8),
              _MaterialPolicyChip(
                emoji: '🏪',
                label: 'הלקוח קונה',
                value: 'client_buys',
                selected: m.policy == 'client_buys',
                onTap: () => _emit(_profile.copyWith(
                    materials: m.copyWith(policy: 'client_buys'))),
              ),
              const SizedBox(width: 8),
              _MaterialPolicyChip(
                emoji: '🔄',
                label: 'גמיש',
                value: 'flexible',
                selected: m.policy == 'flexible',
                onTap: () => _emit(_profile.copyWith(
                    materials: m.copyWith(policy: 'flexible'))),
              ),
            ],
          ),
          if (m.policy == 'i_buy') ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _HPalette.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                '💡 "אני קונה חומרים" = +32% המרות בממוצע',
                style: TextStyle(color: _HPalette.amberPale, fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 9. MAINTENANCE PACKAGES
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildMaintenancePackages() {
    final packs = _profile.maintenancePackages;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_HPalette.indigoDark, Color(0xFF1E40AF)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _HPalette.amber.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🔁', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _t('maintenance.title', 'חוזי תחזוקה שנתיים'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      _t('maintenance.subtitle', 'הכנסה קבועה'),
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...packs.asMap().entries.map((entry) {
            final i = entry.key;
            final p = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _MaintenancePackageRow(
                package: p,
                onChanged: (updated) {
                  final list = List<HandymanMaintenancePackage>.from(packs);
                  list[i] = updated;
                  _emit(_profile.copyWith(maintenancePackages: list));
                },
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PRIVATE HELPER WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class _GlassCard extends StatelessWidget {
  final Widget child;
  final Color? borderColor;
  const _GlassCard({required this.child, this.borderColor});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _HPalette.glassBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor ?? _HPalette.glassBorder),
      ),
      child: child,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  const _SectionHeader({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
  });
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(icon, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  final Color bg;
  const _Pill({required this.text, required this.color, required this.bg});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _VerificationRow extends StatelessWidget {
  final String icon;
  final String title;
  final String subtitle;
  final Widget trailing;
  const _VerificationRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _HPalette.green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _HPalette.green.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

class _CategoryToggle extends StatelessWidget {
  final String emoji;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _CategoryToggle({
    required this.emoji,
    required this.label,
    required this.value,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          Transform.scale(
            scale: 0.85,
            child: Switch(
              value: value,
              activeColor: _HPalette.orange,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _SpecialtyChip extends StatelessWidget {
  final HandymanSpecialty specialty;
  final bool active;
  final bool isDashed;
  final VoidCallback onTap;
  const _SpecialtyChip({
    required this.specialty,
    required this.active,
    required this.onTap,
    this.isDashed = false,
  });
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: active
              ? const LinearGradient(
                  colors: [_HPalette.orange, _HPalette.orangeDark])
              : null,
          color: active ? null : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active
                ? _HPalette.orange
                : Colors.white.withValues(alpha: isDashed ? 0.4 : 0.15),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(specialty.icon, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 6),
            Text(
              specialty.nameHe,
              style: TextStyle(
                color: active ? Colors.white : Colors.white70,
                fontSize: 12,
                fontWeight:
                    active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            if (active) ...[
              const SizedBox(width: 6),
              const Icon(Icons.check_rounded,
                  color: Colors.white, size: 14),
            ],
            if (isDashed) ...[
              const SizedBox(width: 6),
              const Icon(Icons.add_rounded,
                  color: Colors.white60, size: 14),
            ],
          ],
        ),
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  final HandymanSpecialty specialty;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  const _PriceRow({
    required this.specialty,
    required this.controller,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(specialty.icon, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              specialty.nameHe,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          SizedBox(
            width: 80,
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(
                isDense: true,
                prefixText: '₪',
                prefixStyle: TextStyle(color: Colors.white70),
                contentPadding: EdgeInsets.symmetric(vertical: 8),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white30)),
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: _HPalette.orange)),
              ),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _DiscountBar extends StatelessWidget {
  final String label;
  final int percent;
  final int maxPercent;
  final ValueChanged<int> onChanged;
  const _DiscountBar({
    required this.label,
    required this.percent,
    required this.maxPercent,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    final pct = (percent / maxPercent).clamp(0.0, 1.0);
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
        Expanded(
          child: Container(
            height: 10,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: FractionallySizedBox(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: pct,
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [_HPalette.purple, _HPalette.orange]),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 64,
          child: TextField(
            controller: TextEditingController(text: '$percent'),
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700),
            decoration: const InputDecoration(
              isDense: true,
              suffixText: '%',
              suffixStyle: TextStyle(color: Colors.white70),
              contentPadding: EdgeInsets.symmetric(vertical: 8),
              enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white30)),
              focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: _HPalette.purple)),
            ),
            onSubmitted: (raw) {
              final v = int.tryParse(raw);
              if (v != null && v >= 0 && v <= 50) onChanged(v);
            },
          ),
        ),
      ],
    );
  }
}

class _MaterialPolicyChip extends StatelessWidget {
  final String emoji;
  final String label;
  final String value;
  final bool selected;
  final VoidCallback onTap;
  const _MaterialPolicyChip({
    required this.emoji,
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            gradient: selected
                ? const LinearGradient(
                    colors: [_HPalette.orange, _HPalette.orangeDark])
                : null,
            color: selected ? null : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? _HPalette.orange
                  : Colors.white.withValues(alpha: 0.15),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white70,
                  fontSize: 11,
                  fontWeight:
                      selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MaintenancePackageRow extends StatelessWidget {
  final HandymanMaintenancePackage package;
  final ValueChanged<HandymanMaintenancePackage> onChanged;
  const _MaintenancePackageRow({
    required this.package,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    final ctrl = TextEditingController(text: package.yearlyPrice.toStringAsFixed(0));
    final visitsText = package.visitsPerYear == -1
        ? 'ללא הגבלה'
        : '${package.visitsPerYear} ביקורים/שנה';
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: package.popular
            ? _HPalette.amber.withValues(alpha: 0.15)
            : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: package.popular
              ? _HPalette.amber.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.12),
          width: package.popular ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      package.nameHe,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    if (package.popular) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _HPalette.amber,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '⭐',
                          style: TextStyle(fontSize: 10),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  '$visitsText · ${package.activeCustomers} לקוחות פעילים',
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 90,
            child: TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(
                isDense: true,
                prefixText: '₪',
                suffixText: '/שנה',
                prefixStyle: TextStyle(color: Colors.white70, fontSize: 11),
                suffixStyle: TextStyle(color: Colors.white70, fontSize: 10),
                contentPadding: EdgeInsets.symmetric(vertical: 6),
                enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white30)),
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: _HPalette.amber)),
              ),
              onSubmitted: (raw) {
                final v = double.tryParse(raw);
                if (v != null && v >= 0) {
                  onChanged(package.copyWith(yearlyPrice: v));
                }
              },
            ),
          ),
          const SizedBox(width: 6),
          Switch(
            value: package.enabled,
            activeColor: _HPalette.amber,
            onChanged: (v) => onChanged(package.copyWith(enabled: v)),
          ),
        ],
      ),
    );
  }
}
