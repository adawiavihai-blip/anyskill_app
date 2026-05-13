// Fitness Trainer CSM — Provider settings block ("ההגדרות שלך").
// Appears in edit_profile_screen.dart AFTER the sub-category dropdown AND ONLY
// when the selected sub-category resolves to "מאמני כושר" via
// isFitnessTrainerCategory().
//
// 9 sections (spec 01_MAIN_PROMPT.md):
//   1. Hero + "auto-opened" pill
//   2. AI Coach Score (0-100 + target 90 marker + improvement hint)
//   3. Specialties (12 options, max 5 selected, × on each chip)
//   4. Pricing Packages (editable list + Smart Tip + ➕)
//   5. Training Locations (home/park/gym only — NO online)
//   6. Certifications (editable list + ✓ verified badge)
//   7. Success Stories (before/after + editable list)
//   8. Special Offers (editable list + active badge + countdown)
//   9. Performance Dashboard (4 KPIs — read-only, private)
//  10. AI Suggestions (5 improvement tips + "Apply All")
//
// Every list item exposes ✏️ edit + 🗑️ delete. Every section has ➕ add.
// Confirmation dialog always before delete (HapticFeedback.lightImpact).
//
// Palette: Dark premium orange/gold/purple (scoped — does NOT replace Brand.*).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../models/fitness_trainer_profile.dart';
import '../../services/csm_text_override_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SCOPED PALETTE
// ═══════════════════════════════════════════════════════════════════════════

class _FPalette {
  static const darkBase = Color(0xFF0A0E1A);
  static const darkBaseMid = Color(0xFF1A120C);
  static const darkBaseDeep = Color(0xFF0F1420);
  static const orange = Color(0xFFFF6B35);
  static const gold = Color(0xFFF59E0B);
  static const green = Color(0xFF10B981);
  static const red = Color(0xFFDC2626);
  static const purple = Color(0xFF8B5CF6);
  static const blue = Color(0xFF3B82F6);
  static final glassBg = Colors.white.withValues(alpha: 0.04);
  static final glassBorder = Colors.white.withValues(alpha: 0.08);
}

// ═══════════════════════════════════════════════════════════════════════════
// PUBLIC WIDGET
// ═══════════════════════════════════════════════════════════════════════════

class FitnessTrainerSettingsBlock extends StatefulWidget {
  final FitnessTrainerProfile initialProfile;
  final ValueChanged<FitnessTrainerProfile> onChanged;

  const FitnessTrainerSettingsBlock({
    super.key,
    required this.initialProfile,
    required this.onChanged,
  });

  @override
  State<FitnessTrainerSettingsBlock> createState() =>
      _FitnessTrainerSettingsBlockState();
}

class _FitnessTrainerSettingsBlockState
    extends State<FitnessTrainerSettingsBlock> {
  late FitnessTrainerProfile _profile;

  // ── CSM text override wiring ──
  // Subscribes to admin overrides so the labels rendered here match what the
  // admin has CMS-edited. Service is a ChangeNotifier; we re-render on each
  // snapshot. Fallbacks (the second arg of `_t(...)`) MUST equal the original
  // hardcoded literal so behaviour is identical when no override exists.
  static const _csmId = 'fitness_trainer';
  final _textOverrides = CsmTextOverrideService.instance;

  @override
  void initState() {
    super.initState();
    _profile = widget.initialProfile;
    _textOverrides.ensureLoaded(_csmId);
    _textOverrides.addListener(_onTextOverridesChanged);
  }

  @override
  void dispose() {
    _textOverrides.removeListener(_onTextOverridesChanged);
    super.dispose();
  }

  void _onTextOverridesChanged() {
    if (mounted) setState(() {});
  }

  String _t(String key, String fallback) =>
      _textOverrides.t(_csmId, key, fallback);

  void _emit(FitnessTrainerProfile next) {
    if (!mounted) return;
    setState(() => _profile = next);
    widget.onChanged(next);
  }

  // ── Specialties ──────────────────────────────────────────────────────────

  void _toggleSpecialty(SpecialtyType t) {
    HapticFeedback.lightImpact();
    final current = List<SpecialtyType>.from(_profile.selectedSpecialties);
    if (current.contains(t)) {
      current.remove(t);
    } else {
      if (current.length >= 5) {
        _showSnack('ניתן לבחור עד 5 התמחויות');
        return;
      }
      current.add(t);
    }
    _emit(_profile.copyWith(selectedSpecialties: current));
  }

  // ── Packages CRUD ────────────────────────────────────────────────────────

  Future<void> _addPackage() async {
    HapticFeedback.lightImpact();
    final result = await _showPackageModal(context);
    if (result == null) return;
    final popular = result.isPopular;
    var list = List<PricingPackage>.from(_profile.packages);
    if (popular) {
      list = list
          .map((p) => p.copyWith(isPopular: false))
          .toList(); // only one popular
    }
    list.add(result);
    _emit(_profile.copyWith(packages: list));
  }

  Future<void> _editPackage(PricingPackage p) async {
    HapticFeedback.lightImpact();
    final result = await _showPackageModal(context, initial: p);
    if (result == null) return;
    var list = List<PricingPackage>.from(_profile.packages);
    if (result.isPopular) {
      list = list.map((x) => x.copyWith(isPopular: false)).toList();
    }
    final idx = list.indexWhere((x) => x.id == result.id);
    if (idx >= 0) {
      list[idx] = result;
    } else {
      list.add(result);
    }
    _emit(_profile.copyWith(packages: list));
  }

  Future<void> _deletePackage(PricingPackage p) async {
    final confirmed = await _confirmDelete(
      title: 'מחיקת חבילה',
      body: 'האם למחוק את החבילה "${p.name}"?',
    );
    if (!confirmed) return;
    final list = _profile.packages.where((x) => x.id != p.id).toList();
    _emit(_profile.copyWith(packages: list));
  }

  // ── Locations CRUD ───────────────────────────────────────────────────────

  Future<void> _addLocation() async {
    HapticFeedback.lightImpact();
    if (_profile.locations.length >= 3) {
      _showSnack('יש 3 מיקומים אפשריים בלבד: בית, פארק, חדר כושר');
      return;
    }
    final used = _profile.locations.map((l) => l.type).toSet();
    final result = await _showLocationModal(context, blockedTypes: used);
    if (result == null) return;
    final list = [..._profile.locations, result];
    _emit(_profile.copyWith(locations: list));
  }

  Future<void> _editLocation(TrainingLocation l) async {
    HapticFeedback.lightImpact();
    final usedByOthers =
        _profile.locations.where((x) => x.id != l.id).map((x) => x.type).toSet();
    final result = await _showLocationModal(
      context,
      initial: l,
      blockedTypes: usedByOthers,
    );
    if (result == null) return;
    final list = _profile.locations
        .map((x) => x.id == result.id ? result : x)
        .toList();
    _emit(_profile.copyWith(locations: list));
  }

  Future<void> _deleteLocation(TrainingLocation l) async {
    final confirmed = await _confirmDelete(
      title: 'מחיקת מיקום',
      body: 'האם למחוק את המיקום "${l.displayName}"?',
    );
    if (!confirmed) return;
    final list = _profile.locations.where((x) => x.id != l.id).toList();
    _emit(_profile.copyWith(locations: list));
  }

  // ── Certifications CRUD ──────────────────────────────────────────────────

  Future<void> _addCertification() async {
    HapticFeedback.lightImpact();
    final result = await _showCertificationModal(context);
    if (result == null) return;
    final list = [..._profile.certifications, result];
    _emit(_profile.copyWith(certifications: list));
  }

  Future<void> _editCertification(Certification c) async {
    HapticFeedback.lightImpact();
    final result = await _showCertificationModal(context, initial: c);
    if (result == null) return;
    final list = _profile.certifications
        .map((x) => x.id == result.id ? result : x)
        .toList();
    _emit(_profile.copyWith(certifications: list));
  }

  Future<void> _deleteCertification(Certification c) async {
    final confirmed = await _confirmDelete(
      title: 'מחיקת תעודה',
      body: 'האם למחוק את התעודה "${c.name}"?',
    );
    if (!confirmed) return;
    final list = _profile.certifications.where((x) => x.id != c.id).toList();
    _emit(_profile.copyWith(certifications: list));
  }

  // ── Success Stories CRUD ─────────────────────────────────────────────────

  Future<void> _addStory() async {
    HapticFeedback.lightImpact();
    final result = await _showStoryModal(context);
    if (result == null) return;
    final list = [..._profile.successStories, result];
    _emit(_profile.copyWith(successStories: list));
  }

  Future<void> _editStory(SuccessStory s) async {
    HapticFeedback.lightImpact();
    final result = await _showStoryModal(context, initial: s);
    if (result == null) return;
    final list = _profile.successStories
        .map((x) => x.id == result.id ? result : x)
        .toList();
    _emit(_profile.copyWith(successStories: list));
  }

  Future<void> _deleteStory(SuccessStory s) async {
    final confirmed = await _confirmDelete(
      title: 'מחיקת סיפור הצלחה',
      body: 'האם למחוק את הסיפור של ${s.clientName}?',
    );
    if (!confirmed) return;
    final list =
        _profile.successStories.where((x) => x.id != s.id).toList();
    _emit(_profile.copyWith(successStories: list));
  }

  // ── Offers CRUD ──────────────────────────────────────────────────────────

  Future<void> _addOffer() async {
    HapticFeedback.lightImpact();
    final result = await _showOfferModal(context);
    if (result == null) return;
    final list = [..._profile.offers, result];
    _emit(_profile.copyWith(offers: list));
  }

  Future<void> _editOffer(SpecialOffer o) async {
    HapticFeedback.lightImpact();
    final result = await _showOfferModal(context, initial: o);
    if (result == null) return;
    final list = _profile.offers
        .map((x) => x.id == result.id ? result : x)
        .toList();
    _emit(_profile.copyWith(offers: list));
  }

  Future<void> _deleteOffer(SpecialOffer o) async {
    final confirmed = await _confirmDelete(
      title: 'מחיקת מבצע',
      body: 'האם למחוק את המבצע "${o.title}"?',
    );
    if (!confirmed) return;
    final list = _profile.offers.where((x) => x.id != o.id).toList();
    _emit(_profile.copyWith(offers: list));
  }

  // ── Utility helpers ──────────────────────────────────────────────────────

  Future<bool> _confirmDelete({
    required String title,
    required String body,
  }) async {
    HapticFeedback.mediumImpact();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: _FPalette.darkBaseMid,
          title: Text(title,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700)),
          content: Text(body,
              style: const TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ביטול',
                  style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: _FPalette.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('מחק'),
            ),
          ],
        ),
      ),
    );
    return result == true;
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, textAlign: TextAlign.right),
        backgroundColor: _FPalette.darkBaseMid,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════

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
              _FPalette.darkBase,
              _FPalette.darkBaseMid,
              _FPalette.darkBaseDeep,
            ],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHero(),
            const SizedBox(height: 16),
            _buildAiCoachScore(),
            const SizedBox(height: 14),
            _buildSpecialties(),
            const SizedBox(height: 14),
            _buildPricing(),
            const SizedBox(height: 14),
            _buildLocations(),
            const SizedBox(height: 14),
            _buildCertifications(),
            const SizedBox(height: 14),
            _buildStories(),
            const SizedBox(height: 14),
            _buildOffers(),
            const SizedBox(height: 14),
            _buildDashboard(),
            const SizedBox(height: 14),
            _buildAiSuggestions(),
            const SizedBox(height: 10),
            _buildCalendarBanner(),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 1. HERO
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildHero() {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Pill(
                text: '⚡ נפתח אוטומטית',
                color: _FPalette.orange,
                bg: _FPalette.orange.withValues(alpha: 0.18),
              ),
              const Spacer(),
              _Pill(
                text: '🏋️ מאמני כושר',
                color: _FPalette.gold,
                bg: _FPalette.gold.withValues(alpha: 0.18),
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
            _t('hero.subtitle', '9 סקציות לבניית פרופיל מנצח — כל פריט עריך'),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 2. AI COACH SCORE
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildAiCoachScore() {
    final score = _profile.profileScore > 0
        ? _profile.profileScore
        : _profile.fallbackScore;
    final target = 90;
    final progress = (score / 100).clamp(0.0, 1.0);
    final nextSuggestion = _nextImprovementHint(score);

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1F1B3A),
            Color(0xFF2A1F4F),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _FPalette.purple.withValues(alpha: 0.4)),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _FPalette.purple.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  '🤖 AI Coach',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                _profile.lastOptimized == null
                    ? 'טרם חושב'
                    : 'עודכן ${_relativeTime(_profile.lastOptimized!)}',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$score',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 42,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
              const SizedBox(width: 4),
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  '/100',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                'יעד: $target',
                style: const TextStyle(
                  color: _FPalette.gold,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _ProgressBar(progress: progress, targetFraction: target / 100),
          const SizedBox(height: 14),
          if (nextSuggestion != null)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: _FPalette.purple.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Text('💡', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      nextSuggestion,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String? _nextImprovementHint(int score) {
    if (score >= 90) return null;
    if (_profile.successStories.isEmpty) {
      return 'הוסיפי סיפור הצלחה עם תמונה → +15 נק׳';
    }
    if (_profile.activeOffers.isEmpty) {
      return 'הפעילי "אימון ראשון בחינם" → +25 נק׳';
    }
    if (_profile.certifications.isEmpty) {
      return 'הוסיפי תעודה מ-NASM / Wingate → +15 נק׳';
    }
    if (_profile.packages.length < 2) {
      return 'בניית 3 חבילות = +10 נק׳';
    }
    if (_profile.selectedSpecialties.length < 3) {
      return 'בחרי לפחות 3 התמחויות → +8 נק׳';
    }
    return 'הצעות נוספות בתחתית הבלוק';
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 3. SPECIALTIES
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildSpecialties() {
    final selected = _profile.selectedSpecialties;
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: '🎯',
            title: _t('specialties.title', 'תחומי התמחות'),
            subtitle: 'בחרי עד 5 (נבחרו ${selected.length}/5)',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: TrainerSpecialty.all.map((cat) {
              final isSelected = selected.contains(cat.type);
              return _SpecialtyChip(
                catalog: cat,
                isSelected: isSelected,
                onTap: () => _toggleSpecialty(cat.type),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          if (selected.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _FPalette.green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: _FPalette.green.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Text('✨', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'ההתמחויות שלך תואמות ${_matchPercentForSpecs()}% מהחיפושים באזור',
                      style: const TextStyle(
                        color: _FPalette.green,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  int _matchPercentForSpecs() {
    final n = _profile.selectedSpecialties.length;
    if (n == 0) return 0;
    if (n <= 2) return 35 + n * 10;
    if (n == 3) return 68;
    if (n == 4) return 82;
    return 94; // 5 = max
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 4. PRICING PACKAGES
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildPricing() {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: '💰',
            title: _t('pricing.title', 'חבילות ומחירים'),
            subtitle: _t('pricing.subtitle', 'הוסיפי חבילות ומנויים'),
            trailing: _AddButton(
              label: 'חבילה חדשה',
              onTap: _addPackage,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _FPalette.green.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: _FPalette.green.withValues(alpha: 0.3)),
            ),
            child: const Row(
              children: [
                Text('💡', style: TextStyle(fontSize: 16)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'טיפ: מחיר ממוצע באזור ₪180-₪250 לאימון אישי',
                    style: TextStyle(
                      color: _FPalette.green,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_profile.packages.isEmpty)
            const _EmptyState(
              emoji: '💰',
              title: 'אין חבילות עדיין',
              hint: '3 חבילות = יותר אופציות ללקוחות',
            )
          else
            Column(
              children: _profile.packages
                  .map((p) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _PackageRow(
                          package: p,
                          onEdit: () => _editPackage(p),
                          onDelete: () => _deletePackage(p),
                        ),
                      ))
                  .toList(),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 5. LOCATIONS (no online!)
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildLocations() {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: '📍',
            title: _t('locations.title', 'איפה את מאמנת'),
            subtitle:
                _t('locations.subtitle', '3 אפשרויות: בית / פארק / חדר כושר'),
            trailing: _profile.locations.length < 3
                ? _AddButton(label: 'מיקום', onTap: _addLocation)
                : null,
          ),
          const SizedBox(height: 12),
          if (_profile.locations.isEmpty)
            const _EmptyState(
              emoji: '📍',
              title: 'אין מיקומים עדיין',
              hint: 'הוסיפי לפחות מיקום אחד',
            )
          else
            LayoutBuilder(
              builder: (ctx, cons) {
                // 3-column on wide, 1-column on narrow
                final twoUp = cons.maxWidth >= 520;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _profile.locations.map((loc) {
                    return SizedBox(
                      width: twoUp ? (cons.maxWidth - 10) / 2 : cons.maxWidth,
                      child: _LocationCard(
                        location: loc,
                        onEdit: () => _editLocation(loc),
                        onDelete: () => _deleteLocation(loc),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 6. CERTIFICATIONS
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildCertifications() {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: '🎓',
            title: _t('certs.title', 'תעודות והסמכות'),
            subtitle: _t('certs.subtitle', 'NASM, Wingate, ACSM, ISSA ועוד'),
            trailing: _AddButton(label: 'תעודה', onTap: _addCertification),
          ),
          const SizedBox(height: 12),
          if (_profile.certifications.isEmpty)
            const _EmptyState(
              emoji: '🎓',
              title: 'אין תעודות',
              hint: 'תעודה אחת = +15 נקודות לפרופיל',
            )
          else
            Column(
              children: _profile.certifications
                  .map((c) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _CertificationRow(
                          cert: c,
                          onEdit: () => _editCertification(c),
                          onDelete: () => _deleteCertification(c),
                        ),
                      ))
                  .toList(),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 7. SUCCESS STORIES
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildStories() {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: '📸',
            title: _t('stories.title', 'סיפורי הצלחה'),
            subtitle:
                _t('stories.subtitle', 'תמונות לפני/אחרי עם אישור הלקוח'),
            trailing: _AddButton(label: 'סיפור חדש', onTap: _addStory),
          ),
          const SizedBox(height: 12),
          if (_profile.successStories.isEmpty)
            const _EmptyState(
              emoji: '📸',
              title: 'אין סיפורי הצלחה',
              hint: 'סיפור אחד = +15% בהמרה',
            )
          else
            Column(
              children: _profile.successStories
                  .map((s) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _StoryRow(
                          story: s,
                          onEdit: () => _editStory(s),
                          onDelete: () => _deleteStory(s),
                        ),
                      ))
                  .toList(),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 8. SPECIAL OFFERS
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildOffers() {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: '🎁',
            title: _t('offers.title', 'מבצעים והטבות'),
            subtitle: _t('offers.subtitle', 'מגדיל פניות פי 3'),
            trailing: _AddButton(label: 'מבצע חדש', onTap: _addOffer),
          ),
          const SizedBox(height: 12),
          if (_profile.offers.isEmpty)
            const _EmptyState(
              emoji: '🎁',
              title: 'אין מבצעים פעילים',
              hint: '"אימון ראשון חינם" = +25% פניות',
            )
          else
            Column(
              children: _profile.offers
                  .map((o) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _OfferRow(
                          offer: o,
                          onEdit: () => _editOffer(o),
                          onDelete: () => _deleteOffer(o),
                        ),
                      ))
                  .toList(),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 9. PERFORMANCE DASHBOARD (read-only)
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildDashboard() {
    // Derived visual-only metrics (real data flows through the existing
    // Performance Observatory — this is a quick at-a-glance preview).
    final activeClients = _profile.successStories.length * 3 + 8;
    final revenue = _profile.packages.fold<int>(0, (acc, p) => acc + p.price);
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B1220), Color(0xFF111827)],
        ),
        borderRadius: BorderRadius.all(Radius.circular(18)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _t('dashboard.title', '📊 לוח ביצועים'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              _Pill(
                text: '🔒 פרטי',
                color: _FPalette.gold,
                bg: _FPalette.gold.withValues(alpha: 0.18),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _KpiTile(
                  emoji: '👥',
                  label: 'לקוחות פעילים',
                  value: '$activeClients',
                  trend: '+12%',
                  accent: _FPalette.blue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _KpiTile(
                  emoji: '💰',
                  label: 'הכנסה החודש',
                  value: '₪${_compactNum(revenue)}',
                  trend: '+18%',
                  accent: _FPalette.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _KpiTile(
                  emoji: '⭐',
                  label: 'דירוג ממוצע',
                  value: '—',
                  trend: 'לפי יבוא',
                  accent: _FPalette.gold,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _KpiTile(
                  emoji: '🔄',
                  label: 'שיעור חזרה',
                  value: '—',
                  trend: 'Milestone 3',
                  accent: _FPalette.purple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _FPalette.gold.withValues(alpha: 0.22),
                  _FPalette.orange.withValues(alpha: 0.14),
                ],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                Text('🏆', style: TextStyle(fontSize: 18)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'המשיכי לבנות — את על המסלול ל-Top 10% בארץ',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _compactNum(num n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toStringAsFixed(0);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 10. AI SUGGESTIONS
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildAiSuggestions() {
    final suggestions = _profile.aiSuggestions.isNotEmpty
        ? _profile.aiSuggestions
        : _deriveFallbackSuggestions();

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A1F4F), Color(0xFF1F1B3A)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _FPalette.purple.withValues(alpha: 0.4)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('✨',
                  style: TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _t('aiSuggestions.title', 'הצעות חכמות מה-AI'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _Pill(
                text: 'Gemini',
                color: _FPalette.purple,
                bg: _FPalette.purple.withValues(alpha: 0.24),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...suggestions.take(5).map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _SuggestionRow(data: s),
              )),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: suggestions.isEmpty ? null : _applyAllSuggestions,
              style: ElevatedButton.styleFrom(
                backgroundColor: _FPalette.purple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                _t('aiSuggestions.applyButton', '✨ החילי הכל אוטומטית'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _deriveFallbackSuggestions() {
    final out = <Map<String, dynamic>>[];
    if (_profile.successStories.isEmpty) {
      out.add({
        'icon': '📸',
        'title': 'הוסיפי תמונות לפני/אחרי',
        'description': '3 תמונות = +15% בקליקים',
        'impact': '+15%',
        'priority': 'high',
      });
    }
    if (_profile.activeOffers.isEmpty) {
      out.add({
        'icon': '🎁',
        'title': 'הפעילי "אימון ראשון בחינם"',
        'description': 'מגדיל פניות פי 3 בממוצע',
        'impact': '+25%',
        'priority': 'high',
      });
    }
    if (_profile.certifications.isEmpty) {
      out.add({
        'icon': '🏆',
        'title': 'הוסיפי תעודה מ-NASM',
        'description': 'אמינות + ביטחון ללקוח',
        'impact': '+15%',
        'priority': 'medium',
      });
    }
    if (_profile.selectedSpecialties.length < 3) {
      out.add({
        'icon': '🎯',
        'title': 'הוסיפי עוד התמחויות',
        'description': 'מינימום 3 מומלצות',
        'impact': '+8%',
        'priority': 'medium',
      });
    }
    if (_profile.packages.length < 3) {
      out.add({
        'icon': '💰',
        'title': 'הוסיפי חבילה נוספת',
        'description': '3 חבילות = יותר אופציות',
        'impact': '+5%',
        'priority': 'low',
      });
    }
    return out;
  }

  void _applyAllSuggestions() {
    HapticFeedback.mediumImpact();
    _showSnack('הצעות יופעלו — פתחי את הסקציות הרלוונטיות והוסיפי את הפריטים המוצעים');
  }

  // ═══════════════════════════════════════════════════════════════════════
  // CALENDAR BANNER (replaces "weekly availability" — calendar owns schedule)
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildCalendarBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _FPalette.blue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _FPalette.blue.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Text('🗓️', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _t(
                'calendarBanner.text',
                'שעות פעילות נקבעות דרך היומן — פתח/י את לוח המשימות שלך',
              ),
              style: const TextStyle(
                color: _FPalette.blue,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PRIVATE WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _FPalette.glassBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _FPalette.glassBorder),
      ),
      child: child,
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
        borderRadius: BorderRadius.circular(20),
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

class _SectionHeader extends StatelessWidget {
  final String icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(icon, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11.5,
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

class _AddButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _AddButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [_FPalette.orange, _FPalette.gold],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: _FPalette.orange.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add_rounded, color: Colors.white, size: 16),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditDeleteButtons extends StatelessWidget {
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _EditDeleteButtons({required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CircleIcon(
          icon: Icons.edit_rounded,
          color: _FPalette.blue,
          onTap: onEdit,
        ),
        const SizedBox(width: 6),
        _CircleIcon(
          icon: Icons.delete_outline_rounded,
          color: _FPalette.red,
          onTap: onDelete,
        ),
      ],
    );
  }
}

class _CircleIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _CircleIcon(
      {required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Icon(icon, color: color, size: 16),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final double progress;
  final double targetFraction;
  const _ProgressBar(
      {required this.progress, required this.targetFraction});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          height: 10,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        FractionallySizedBox(
          widthFactor: progress.clamp(0.0, 1.0),
          child: Container(
            height: 10,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_FPalette.orange, _FPalette.gold],
              ),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
        LayoutBuilder(
          builder: (ctx, cons) {
            final x = (cons.maxWidth * targetFraction).clamp(0.0, cons.maxWidth);
            return Positioned(
              left: x - 1,
              top: -2,
              child: Container(
                width: 2,
                height: 14,
                decoration: BoxDecoration(
                  color: _FPalette.gold,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _SpecialtyChip extends StatelessWidget {
  final TrainerSpecialty catalog;
  final bool isSelected;
  final VoidCallback onTap;
  const _SpecialtyChip({
    required this.catalog,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Color(catalog.colors[0]);
    final secondary = Color(catalog.colors[1]);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(colors: [primary, secondary])
              : null,
          color: isSelected ? null : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isSelected
                ? secondary.withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.12),
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: primary.withValues(alpha: 0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(catalog.emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Text(
              catalog.label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (isSelected) ...[
              const SizedBox(width: 6),
              const Icon(Icons.close_rounded,
                  color: Colors.white, size: 14),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String emoji;
  final String title;
  final String hint;
  const _EmptyState(
      {required this.emoji, required this.title, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    )),
                const SizedBox(height: 2),
                Text(hint,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11.5,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PackageRow extends StatelessWidget {
  final PricingPackage package;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _PackageRow({
    required this.package,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final pricePerSession = package.pricePerSession.toStringAsFixed(0);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: package.isPopular
              ? _FPalette.orange.withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.1),
          width: package.isPopular ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (package.isPopular)
                const Padding(
                  padding: EdgeInsetsDirectional.only(end: 6),
                  child: _Pill(
                    text: '⭐ פופולרי',
                    color: _FPalette.orange,
                    bg: Color(0x33FF6B35),
                  ),
                ),
              Expanded(
                child: Text(
                  package.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _EditDeleteButtons(onEdit: onEdit, onDelete: onDelete),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('₪${package.price}',
                  style: const TextStyle(
                    color: _FPalette.gold,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  )),
              const SizedBox(width: 8),
              Text(
                '${package.sessions} אימון · ${package.durationMinutes} דק׳',
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
              const Spacer(),
              if (package.sessions > 1)
                Text('₪$pricePerSession / אימון',
                    style: const TextStyle(
                        color: _FPalette.green,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
            ],
          ),
          if (package.discount != null && package.discount! > 0) ...[
            const SizedBox(height: 6),
            _Pill(
              text: 'חיסכון ${package.discount}%',
              color: _FPalette.green,
              bg: _FPalette.green.withValues(alpha: 0.18),
            ),
          ],
        ],
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  final TrainingLocation location;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _LocationCard({
    required this.location,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(location.emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  location.displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _EditDeleteButtons(onEdit: onEdit, onDelete: onDelete),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _Pill(
                text: 'רדיוס ${location.radiusKm} ק״מ',
                color: _FPalette.blue,
                bg: _FPalette.blue.withValues(alpha: 0.18),
              ),
              const SizedBox(width: 6),
              if (location.extraCost != null && location.extraCost! > 0)
                _Pill(
                  text: '+ ₪${location.extraCost}',
                  color: _FPalette.gold,
                  bg: _FPalette.gold.withValues(alpha: 0.18),
                ),
            ],
          ),
          if ((location.notes ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              location.notes!,
              style: const TextStyle(color: Colors.white60, fontSize: 11.5),
            ),
          ],
        ],
      ),
    );
  }
}

class _CertificationRow extends StatelessWidget {
  final Certification cert;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _CertificationRow({
    required this.cert,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _FPalette.blue.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: const Text('🎓', style: TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        cert.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (cert.isVerified) ...[
                      const SizedBox(width: 6),
                      _Pill(
                        text: '✓ מאומת',
                        color: _FPalette.blue,
                        bg: _FPalette.blue.withValues(alpha: 0.24),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${cert.institution} · ${cert.year}',
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          _EditDeleteButtons(onEdit: onEdit, onDelete: onDelete),
        ],
      ),
    );
  }
}

class _StoryRow extends StatelessWidget {
  final SuccessStory story;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _StoryRow({
    required this.story,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      story.clientName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      List.filled(story.rating.clamp(0, 5), '⭐').join(),
                      style: const TextStyle(fontSize: 10),
                    ),
                  ],
                ),
              ),
              _EditDeleteButtons(onEdit: onEdit, onDelete: onDelete),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            story.result,
            style: const TextStyle(
              color: _FPalette.gold,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          if ((story.beforeImageUrl ?? '').isNotEmpty ||
              (story.afterImageUrl ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _BeforeAfterPreview(
                    label: 'לפני',
                    imageUrl: story.beforeImageUrl,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _BeforeAfterPreview(
                    label: 'אחרי',
                    imageUrl: story.afterImageUrl,
                  ),
                ),
              ],
            ),
          ],
          if ((story.testimonial ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '"${story.testimonial!}"',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11.5,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          if (!story.clientApproved) ...[
            const SizedBox(height: 8),
            _Pill(
              text: '⚠️ ממתין לאישור הלקוח',
              color: _FPalette.gold,
              bg: _FPalette.gold.withValues(alpha: 0.2),
            ),
          ],
        ],
      ),
    );
  }
}

class _BeforeAfterPreview extends StatelessWidget {
  final String label;
  final String? imageUrl;
  const _BeforeAfterPreview({required this.label, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final hasImage = (imageUrl ?? '').isNotEmpty;
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        image: hasImage
            ? DecorationImage(
                image: NetworkImage(imageUrl!),
                fit: BoxFit.cover,
              )
            : null,
      ),
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: hasImage ? 0.5 : 0),
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(10),
            bottomRight: Radius.circular(10),
          ),
        ),
        child: Text(
          hasImage ? label : 'ללא תמונה',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: hasImage ? Colors.white : Colors.white38,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _OfferRow extends StatelessWidget {
  final SpecialOffer offer;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _OfferRow({
    required this.offer,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final daysLeft = offer.expiresAt.difference(DateTime.now()).inDays;
    final isLive = offer.isActive && !offer.isExpired;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isLive
              ? _FPalette.green.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  offer.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (isLive)
                _Pill(
                  text: '● פעיל',
                  color: _FPalette.green,
                  bg: _FPalette.green.withValues(alpha: 0.22),
                )
              else if (offer.isExpired)
                _Pill(
                  text: 'פג תוקף',
                  color: _FPalette.red,
                  bg: _FPalette.red.withValues(alpha: 0.22),
                ),
              const SizedBox(width: 6),
              _EditDeleteButtons(onEdit: onEdit, onDelete: onDelete),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            offer.description,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (offer.availableSpots != null) ...[
                _Pill(
                  text: 'נותרו ${offer.availableSpots} מקומות',
                  color: _FPalette.orange,
                  bg: _FPalette.orange.withValues(alpha: 0.2),
                ),
                const SizedBox(width: 6),
              ],
              _Pill(
                text: daysLeft < 0
                    ? 'פג'
                    : daysLeft == 0
                        ? 'מסתיים היום'
                        : 'עוד $daysLeft ימים',
                color: _FPalette.blue,
                bg: _FPalette.blue.withValues(alpha: 0.2),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  final String emoji;
  final String label;
  final String value;
  final String trend;
  final Color accent;
  const _KpiTile({
    required this.emoji,
    required this.label,
    required this.value,
    required this.trend,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            trend,
            style: TextStyle(
              color: accent,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  final Map<String, dynamic> data;
  const _SuggestionRow({required this.data});

  @override
  Widget build(BuildContext context) {
    final priority = (data['priority'] ?? 'medium').toString();
    final priColor = priority == 'high'
        ? _FPalette.red
        : priority == 'low'
            ? _FPalette.green
            : _FPalette.gold;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: priColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Text((data['icon'] ?? '💡').toString(),
              style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (data['title'] ?? '').toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  (data['description'] ?? '').toString(),
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _Pill(
            text: (data['impact'] ?? '').toString(),
            color: priColor,
            bg: priColor.withValues(alpha: 0.2),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════════════════════

String _relativeTime(DateTime ts) {
  final diff = DateTime.now().difference(ts);
  if (diff.inMinutes < 1) return 'עכשיו';
  if (diff.inHours < 1) return 'לפני ${diff.inMinutes} דק׳';
  if (diff.inDays < 1) return 'לפני ${diff.inHours} שעות';
  if (diff.inDays < 7) return 'לפני ${diff.inDays} ימים';
  return DateFormat('dd/MM', 'he').format(ts);
}

String _genId() =>
    '${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond}';

// ═══════════════════════════════════════════════════════════════════════════
// MODAL 1: PACKAGE
// ═══════════════════════════════════════════════════════════════════════════

Future<PricingPackage?> _showPackageModal(BuildContext context,
    {PricingPackage? initial}) {
  return showModalBottomSheet<PricingPackage?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _PackageModal(initial: initial),
  );
}

class _PackageModal extends StatefulWidget {
  final PricingPackage? initial;
  const _PackageModal({this.initial});

  @override
  State<_PackageModal> createState() => _PackageModalState();
}

class _PackageModalState extends State<_PackageModal> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _discountCtrl;
  late PackageType _type;
  late int _sessions;
  late int _duration;
  late int _validity;
  late bool _isPopular;
  late bool _freeOnboarding;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _nameCtrl = TextEditingController(text: i?.name ?? '');
    _priceCtrl =
        TextEditingController(text: i == null ? '' : i.price.toString());
    _discountCtrl =
        TextEditingController(text: i?.discount?.toString() ?? '');
    _type = i?.type ?? PackageType.package;
    _sessions = i?.sessions ?? 5;
    _duration = i?.durationMinutes ?? 60;
    _validity = i?.validityMonths ?? 3;
    _isPopular = i?.isPopular ?? false;
    _freeOnboarding = i?.includesFreeOnboarding ?? false;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _discountCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    final price = int.tryParse(_priceCtrl.text.trim()) ?? 0;
    if (name.isEmpty || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('שם ומחיר חובה', textAlign: TextAlign.right)),
      );
      return;
    }
    final pkg = PricingPackage(
      id: widget.initial?.id ?? _genId(),
      name: name,
      type: _type,
      sessions: _type == PackageType.single ? 1 : _sessions,
      durationMinutes: _duration,
      price: price,
      discount: int.tryParse(_discountCtrl.text.trim()),
      validityMonths: _type == PackageType.single ? null : _validity,
      isPopular: _isPopular,
      includesFreeOnboarding: _freeOnboarding,
    );
    Navigator.pop(context, pkg);
  }

  @override
  Widget build(BuildContext context) {
    return _ModalScaffold(
      title: widget.initial == null ? '➕ חבילה חדשה' : '✏️ עריכת חבילה',
      onSave: _save,
      children: [
        _ModalField(
          label: 'שם החבילה',
          child: TextField(
            controller: _nameCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: _inputDec('לדוגמה: חבילת 5 אימונים'),
          ),
        ),
        _ModalField(
          label: 'סוג',
          child: _SegmentedRadio<PackageType>(
            value: _type,
            options: const [
              _RadioOpt(label: 'אימון יחיד', value: PackageType.single),
              _RadioOpt(label: 'חבילה', value: PackageType.package),
              _RadioOpt(label: 'מנוי חודשי', value: PackageType.monthly),
            ],
            onChanged: (v) => setState(() => _type = v),
          ),
        ),
        if (_type != PackageType.single)
          Row(
            children: [
              Expanded(
                child: _ModalField(
                  label: 'מספר אימונים',
                  child: _NumPicker(
                    value: _sessions,
                    min: 2,
                    max: 60,
                    step: 1,
                    onChanged: (v) => setState(() => _sessions = v),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ModalField(
                  label: 'משך אימון (דק׳)',
                  child: _NumPicker(
                    value: _duration,
                    min: 30,
                    max: 120,
                    step: 15,
                    onChanged: (v) => setState(() => _duration = v),
                  ),
                ),
              ),
            ],
          ),
        Row(
          children: [
            Expanded(
              child: _ModalField(
                label: 'מחיר כולל (₪)',
                child: TextField(
                  controller: _priceCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDec('₪900'),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ModalField(
                label: 'חיסכון (%)',
                child: TextField(
                  controller: _discountCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDec('10'),
                ),
              ),
            ),
          ],
        ),
        if (_type != PackageType.single)
          _ModalField(
            label: 'תוקף החבילה (חודשים)',
            child: _NumPicker(
              value: _validity,
              min: 1,
              max: 12,
              step: 1,
              onChanged: (v) => setState(() => _validity = v),
            ),
          ),
        _ModalCheckbox(
          label: '⭐ סמני כפופולרי (אחת בלבד תופיע מודגשת)',
          value: _isPopular,
          onChanged: (v) => setState(() => _isPopular = v),
        ),
        _ModalCheckbox(
          label: '🎁 הצעי אונבורדינג חינם',
          value: _freeOnboarding,
          onChanged: (v) => setState(() => _freeOnboarding = v),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MODAL 2: LOCATION
// ═══════════════════════════════════════════════════════════════════════════

Future<TrainingLocation?> _showLocationModal(
  BuildContext context, {
  TrainingLocation? initial,
  Set<LocationType> blockedTypes = const {},
}) {
  return showModalBottomSheet<TrainingLocation?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _LocationModal(
      initial: initial,
      blockedTypes: blockedTypes,
    ),
  );
}

class _LocationModal extends StatefulWidget {
  final TrainingLocation? initial;
  final Set<LocationType> blockedTypes;
  const _LocationModal({this.initial, required this.blockedTypes});

  @override
  State<_LocationModal> createState() => _LocationModalState();
}

class _LocationModalState extends State<_LocationModal> {
  late LocationType _type;
  late int _radiusKm;
  late final TextEditingController _extraCtrl;
  late final TextEditingController _notesCtrl;

  @override
  void initState() {
    super.initState();
    _type = widget.initial?.type ??
        LocationType.values.firstWhere(
          (t) => !widget.blockedTypes.contains(t),
          orElse: () => LocationType.gym,
        );
    _radiusKm = widget.initial?.radiusKm ?? 15;
    _extraCtrl = TextEditingController(
        text: widget.initial?.extraCost?.toString() ?? '');
    _notesCtrl = TextEditingController(text: widget.initial?.notes ?? '');
  }

  @override
  void dispose() {
    _extraCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final loc = TrainingLocation(
      id: widget.initial?.id ?? _genId(),
      type: _type,
      radiusKm: _radiusKm,
      extraCost: int.tryParse(_extraCtrl.text.trim()),
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );
    Navigator.pop(context, loc);
  }

  @override
  Widget build(BuildContext context) {
    return _ModalScaffold(
      title: widget.initial == null ? '➕ מיקום חדש' : '✏️ עריכת מיקום',
      onSave: _save,
      children: [
        _ModalField(
          label: 'סוג מיקום (בית / פארק / חדר כושר — אין אונליין)',
          child: _SegmentedRadio<LocationType>(
            value: _type,
            options: LocationType.values.map((t) {
              final tmp = TrainingLocation(id: '_', type: t);
              final disabled = widget.blockedTypes.contains(t) &&
                  t != widget.initial?.type;
              return _RadioOpt(
                label: '${tmp.emoji} ${tmp.displayName}',
                value: t,
                disabled: disabled,
              );
            }).toList(),
            onChanged: (v) => setState(() => _type = v),
          ),
        ),
        _ModalField(
          label: 'רדיוס שירות (ק״מ)',
          child: Column(
            children: [
              Slider(
                min: 1,
                max: 50,
                divisions: 49,
                value: _radiusKm.toDouble(),
                label: '$_radiusKm ק״מ',
                activeColor: _FPalette.orange,
                onChanged: (v) => setState(() => _radiusKm = v.round()),
              ),
              Text(
                '$_radiusKm ק״מ',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ],
          ),
        ),
        _ModalField(
          label: 'תוספת מחיר (אופציונלי)',
          child: TextField(
            controller: _extraCtrl,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white),
            decoration: _inputDec('₪50'),
          ),
        ),
        _ModalField(
          label: 'הערות',
          child: TextField(
            controller: _notesCtrl,
            maxLines: 3,
            style: const TextStyle(color: Colors.white),
            decoration: _inputDec('מביאה ציוד...'),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MODAL 3: CERTIFICATION
// ═══════════════════════════════════════════════════════════════════════════

Future<Certification?> _showCertificationModal(
  BuildContext context, {
  Certification? initial,
}) {
  return showModalBottomSheet<Certification?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _CertificationModal(initial: initial),
  );
}

class _CertificationModal extends StatefulWidget {
  final Certification? initial;
  const _CertificationModal({this.initial});

  @override
  State<_CertificationModal> createState() => _CertificationModalState();
}

class _CertificationModalState extends State<_CertificationModal> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _imageCtrl;
  late String _institution;
  late int _year;

  static const List<String> _institutions = [
    'NASM',
    'Wingate',
    'ACSM',
    'ISSA',
    'אורט בראודה',
    'אחר',
  ];

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _nameCtrl = TextEditingController(text: i?.name ?? '');
    _imageCtrl = TextEditingController(text: i?.imageUrl ?? '');
    _institution = (i?.institution.isNotEmpty == true &&
            _institutions.contains(i!.institution))
        ? i.institution
        : _institutions.first;
    _year = i?.year ?? DateTime.now().year;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _imageCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('שם התעודה חובה', textAlign: TextAlign.right)),
      );
      return;
    }
    final cert = Certification(
      id: widget.initial?.id ?? _genId(),
      name: name,
      institution: _institution,
      year: _year,
      imageUrl: _imageCtrl.text.trim().isEmpty ? null : _imageCtrl.text.trim(),
      isVerified: widget.initial?.isVerified ?? false,
    );
    Navigator.pop(context, cert);
  }

  @override
  Widget build(BuildContext context) {
    final currentYear = DateTime.now().year;
    return _ModalScaffold(
      title: widget.initial == null ? '➕ תעודה חדשה' : '✏️ עריכת תעודה',
      onSave: _save,
      children: [
        _ModalField(
          label: 'שם התעודה',
          child: TextField(
            controller: _nameCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: _inputDec('NASM - Certified Personal Trainer'),
          ),
        ),
        _ModalField(
          label: 'מוסד מסמיך',
          child: DropdownButtonFormField<String>(
            value: _institution,
            dropdownColor: _FPalette.darkBaseMid,
            style: const TextStyle(color: Colors.white),
            decoration: _inputDec(''),
            items: _institutions
                .map((i) => DropdownMenuItem(
                      value: i,
                      child: Text(i,
                          style: const TextStyle(color: Colors.white)),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _institution = v);
            },
          ),
        ),
        _ModalField(
          label: 'שנת הסמכה',
          child: _NumPicker(
            value: _year,
            min: 1990,
            max: currentYear,
            step: 1,
            onChanged: (v) => setState(() => _year = v),
          ),
        ),
        _ModalField(
          label: 'קישור לתמונת תעודה (אופציונלי)',
          child: TextField(
            controller: _imageCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: _inputDec('https://...'),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _FPalette.gold.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _FPalette.gold.withValues(alpha: 0.3)),
          ),
          child: const Row(
            children: [
              Text('⚠️', style: TextStyle(fontSize: 16)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'התעודה תאומת ע״י הצוות תוך 48 שעות',
                  style: TextStyle(
                    color: _FPalette.gold,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MODAL 4: SUCCESS STORY
// ═══════════════════════════════════════════════════════════════════════════

Future<SuccessStory?> _showStoryModal(BuildContext context,
    {SuccessStory? initial}) {
  return showModalBottomSheet<SuccessStory?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _StoryModal(initial: initial),
  );
}

class _StoryModal extends StatefulWidget {
  final SuccessStory? initial;
  const _StoryModal({this.initial});

  @override
  State<_StoryModal> createState() => _StoryModalState();
}

class _StoryModalState extends State<_StoryModal> {
  late final TextEditingController _clientCtrl;
  late final TextEditingController _resultCtrl;
  late final TextEditingController _testimonialCtrl;
  late final TextEditingController _beforeCtrl;
  late final TextEditingController _afterCtrl;
  late int _rating;
  late bool _approved;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _clientCtrl = TextEditingController(text: i?.clientName ?? '');
    _resultCtrl = TextEditingController(text: i?.result ?? '');
    _testimonialCtrl = TextEditingController(text: i?.testimonial ?? '');
    _beforeCtrl = TextEditingController(text: i?.beforeImageUrl ?? '');
    _afterCtrl = TextEditingController(text: i?.afterImageUrl ?? '');
    _rating = i?.rating ?? 5;
    _approved = i?.clientApproved ?? false;
  }

  @override
  void dispose() {
    _clientCtrl.dispose();
    _resultCtrl.dispose();
    _testimonialCtrl.dispose();
    _beforeCtrl.dispose();
    _afterCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final name = _clientCtrl.text.trim();
    final result = _resultCtrl.text.trim();
    if (name.isEmpty || result.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('שם לקוח + תוצאה חובה', textAlign: TextAlign.right)),
      );
      return;
    }
    final story = SuccessStory(
      id: widget.initial?.id ?? _genId(),
      clientName: name,
      result: result,
      testimonial: _testimonialCtrl.text.trim().isEmpty
          ? null
          : _testimonialCtrl.text.trim(),
      beforeImageUrl:
          _beforeCtrl.text.trim().isEmpty ? null : _beforeCtrl.text.trim(),
      afterImageUrl:
          _afterCtrl.text.trim().isEmpty ? null : _afterCtrl.text.trim(),
      rating: _rating,
      createdAt: widget.initial?.createdAt ?? DateTime.now(),
      clientApproved: _approved,
    );
    Navigator.pop(context, story);
  }

  @override
  Widget build(BuildContext context) {
    return _ModalScaffold(
      title: widget.initial == null ? '➕ סיפור הצלחה חדש' : '✏️ עריכת סיפור',
      onSave: _save,
      children: [
        _ModalField(
          label: 'שם הלקוח',
          child: TextField(
            controller: _clientCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: _inputDec('רינה כהן'),
          ),
        ),
        _ModalField(
          label: 'התוצאה',
          child: TextField(
            controller: _resultCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: _inputDec('-15 ק״ג ב-4 חודשים'),
          ),
        ),
        _ModalField(
          label: 'קישור תמונת "לפני"',
          child: TextField(
            controller: _beforeCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: _inputDec('https://...'),
          ),
        ),
        _ModalField(
          label: 'קישור תמונת "אחרי"',
          child: TextField(
            controller: _afterCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: _inputDec('https://...'),
          ),
        ),
        _ModalField(
          label: 'עדות (אופציונלי)',
          child: TextField(
            controller: _testimonialCtrl,
            maxLines: 4,
            style: const TextStyle(color: Colors.white),
            decoration: _inputDec('סיגלית שינתה לי את החיים...'),
          ),
        ),
        _ModalField(
          label: 'דירוג',
          child: Row(
            children: List.generate(5, (i) {
              final filled = i < _rating;
              return IconButton(
                onPressed: () => setState(() => _rating = i + 1),
                icon: Icon(
                  filled ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: _FPalette.gold,
                  size: 28,
                ),
              );
            }),
          ),
        ),
        _ModalCheckbox(
          label: '✅ אישור הלקוח לפרסום נתקבל',
          value: _approved,
          onChanged: (v) => setState(() => _approved = v),
        ),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _FPalette.red.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _FPalette.red.withValues(alpha: 0.3)),
          ),
          child: const Row(
            children: [
              Text('⚠️', style: TextStyle(fontSize: 16)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'נדרש אישור הלקוח לפני פרסום תמונות לפני/אחרי',
                  style: TextStyle(
                    color: _FPalette.red,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MODAL 5: SPECIAL OFFER
// ═══════════════════════════════════════════════════════════════════════════

Future<SpecialOffer?> _showOfferModal(BuildContext context,
    {SpecialOffer? initial}) {
  return showModalBottomSheet<SpecialOffer?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _OfferModal(initial: initial),
  );
}

class _OfferModal extends StatefulWidget {
  final SpecialOffer? initial;
  const _OfferModal({this.initial});

  @override
  State<_OfferModal> createState() => _OfferModalState();
}

class _OfferModalState extends State<_OfferModal> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _discountCtrl;
  late final TextEditingController _spotsCtrl;
  late OfferType _type;
  late DateTime _expiresAt;
  late bool _isActive;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _titleCtrl = TextEditingController(text: i?.title ?? '');
    _descCtrl = TextEditingController(text: i?.description ?? '');
    _discountCtrl =
        TextEditingController(text: i?.discountPercent?.toString() ?? '');
    _spotsCtrl =
        TextEditingController(text: i?.availableSpots?.toString() ?? '');
    _type = i?.type ?? OfferType.firstFree;
    _expiresAt =
        i?.expiresAt ?? DateTime.now().add(const Duration(days: 30));
    _isActive = i?.isActive ?? true;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _discountCtrl.dispose();
    _spotsCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickExpiry() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiresAt,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _expiresAt = picked);
  }

  void _save() {
    final title = _titleCtrl.text.trim();
    final desc = _descCtrl.text.trim();
    if (title.isEmpty || desc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('כותרת ופרטים חובה', textAlign: TextAlign.right)),
      );
      return;
    }
    final offer = SpecialOffer(
      id: widget.initial?.id ?? _genId(),
      type: _type,
      title: title,
      description: desc,
      discountPercent: int.tryParse(_discountCtrl.text.trim()),
      availableSpots: int.tryParse(_spotsCtrl.text.trim()),
      expiresAt: _expiresAt,
      isActive: _isActive,
    );
    Navigator.pop(context, offer);
  }

  @override
  Widget build(BuildContext context) {
    return _ModalScaffold(
      title: widget.initial == null ? '➕ מבצע חדש' : '✏️ עריכת מבצע',
      onSave: _save,
      children: [
        _ModalField(
          label: 'סוג מבצע',
          child: _SegmentedRadio<OfferType>(
            value: _type,
            options: const [
              _RadioOpt(label: 'הנחה באחוזים', value: OfferType.discount),
              _RadioOpt(label: 'אימון ראשון חינם', value: OfferType.firstFree),
              _RadioOpt(label: 'X+1 חינם', value: OfferType.buyXgetY),
              _RadioOpt(label: 'מותאם', value: OfferType.custom),
            ],
            onChanged: (v) => setState(() => _type = v),
          ),
        ),
        _ModalField(
          label: 'כותרת',
          child: TextField(
            controller: _titleCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: _inputDec('🔥 שיעור ראשון ב-50%'),
          ),
        ),
        _ModalField(
          label: 'פרטים',
          child: TextField(
            controller: _descCtrl,
            maxLines: 2,
            style: const TextStyle(color: Colors.white),
            decoration: _inputDec('תקף ללקוחות חדשים בלבד...'),
          ),
        ),
        if (_type == OfferType.discount)
          _ModalField(
            label: 'אחוז הנחה',
            child: TextField(
              controller: _discountCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: _inputDec('50'),
            ),
          ),
        _ModalField(
          label: 'הגבלת מקומות (אופציונלי)',
          child: TextField(
            controller: _spotsCtrl,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white),
            decoration: _inputDec('3'),
          ),
        ),
        _ModalField(
          label: 'תאריך תפוגה',
          child: InkWell(
            onTap: _pickExpiry,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: Colors.white.withValues(alpha: 0.14)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_rounded,
                      color: Colors.white70, size: 18),
                  const SizedBox(width: 10),
                  Text(
                    DateFormat('dd/MM/yyyy').format(_expiresAt),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        _ModalCheckbox(
          label: 'הפעילי מיד',
          value: _isActive,
          onChanged: (v) => setState(() => _isActive = v),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SHARED MODAL WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class _ModalScaffold extends StatelessWidget {
  final String title;
  final VoidCallback onSave;
  final List<Widget> children;
  const _ModalScaffold({
    required this.title,
    required this.onSave,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
        child: Container(
          constraints: BoxConstraints(maxHeight: mq.size.height * 0.92),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_FPalette.darkBaseMid, _FPalette.darkBase],
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.white30),
                            foregroundColor: Colors.white70,
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('ביטול'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: () {
                            HapticFeedback.mediumImpact();
                            onSave();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _FPalette.orange,
                            foregroundColor: Colors.white,
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            '💾 שמרי',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModalField extends StatelessWidget {
  final String label;
  final Widget child;
  const _ModalField({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              )),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class _ModalCheckbox extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _ModalCheckbox({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: Checkbox(
                  value: value,
                  onChanged: (v) => onChanged(v ?? false),
                  fillColor: WidgetStateProperty.resolveWith(
                    (s) => s.contains(WidgetState.selected)
                        ? _FPalette.orange
                        : Colors.white12,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label,
                    style: const TextStyle(color: Colors.white, fontSize: 12.5)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RadioOpt<T> {
  final String label;
  final T value;
  final bool disabled;
  const _RadioOpt(
      {required this.label, required this.value, this.disabled = false});
}

class _SegmentedRadio<T> extends StatelessWidget {
  final T value;
  final List<_RadioOpt<T>> options;
  final ValueChanged<T> onChanged;
  const _SegmentedRadio({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: options.map((o) {
        final selected = o.value == value;
        return InkWell(
          onTap: o.disabled ? null : () => onChanged(o.value),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? _FPalette.orange.withValues(alpha: 0.25)
                  : Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected
                    ? _FPalette.orange.withValues(alpha: 0.6)
                    : Colors.white.withValues(alpha: 0.14),
              ),
            ),
            child: Text(
              o.label,
              style: TextStyle(
                color: o.disabled
                    ? Colors.white24
                    : (selected ? Colors.white : Colors.white70),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _NumPicker extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;
  const _NumPicker({
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: value - step >= min ? () => onChanged(value - step) : null,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(4),
              child: const Icon(Icons.remove_rounded,
                  color: Colors.white70, size: 20),
            ),
          ),
          Expanded(
            child: Center(
              child: Text('$value',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
            ),
          ),
          InkWell(
            onTap: value + step <= max ? () => onChanged(value + step) : null,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(4),
              child: const Icon(Icons.add_rounded,
                  color: Colors.white70, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

InputDecoration _inputDec(String hint) => InputDecoration(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.04),
      hintText: hint,
      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35)),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _FPalette.orange, width: 1.5),
      ),
    );
