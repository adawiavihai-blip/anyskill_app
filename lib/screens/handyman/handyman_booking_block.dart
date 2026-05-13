// Handyman CSM — Client booking block ("מה תרצו לתקן?").
// Appears in expert_profile_screen.dart between the About section and the
// Service menu ONLY when the provider has a non-empty handymanProfile.
//
// Sections (spec 03_CLIENT_BOOKING_HANDYMAN.md):
//   1. LIVE urgency banner
//   2. Hero
//   3. Trust Center (4 badges — NO ID, NO insurance)
//   4. AI Photo-to-Quote ⭐
//   5. 23 specialties with search
//   6. Punch List
//   7. Problem description
//   8. Property info
//   9. Materials transparency
//   10. Urgency selector (4 options)
//   11. Warranty section
//   12. Reviews insights
//   13. Chat preview + Quick Replies → existing ChatScreen
//   14. Maintenance packages (3 tiers)
//   15. Sticky bottom summary
//
// IMPORTANT: this block does NOT own the calendar or chat. The final CTA
// bubbles (preferences, total) to the parent (expert_profile_screen),
// which threads them through the existing "Pay & Secure" escrow flow.
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../constants/handyman_quick_replies.dart';
import '../../constants/handyman_urgency_options.dart';
import '../../models/handyman_profile.dart';
import '../../services/handyman_booking_service.dart';
import '../chat_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════
// PALETTE (scoped)
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
  static final glassBg = Colors.white.withValues(alpha: 0.04);
  static final glassBorder = Colors.white.withValues(alpha: 0.08);
}

// ═══════════════════════════════════════════════════════════════════════════
// PUBLIC WIDGET
// ═══════════════════════════════════════════════════════════════════════════

typedef HandymanPreferencesChanged =
    void Function(HandymanBookingPreferences prefs, double total);

class HandymanBookingBlock extends StatefulWidget {
  final String expertId;
  final String expertName;
  final String? expertAvatarUrl;
  final HandymanProfile handymanProfile;
  final HandymanPreferencesChanged onChanged;

  const HandymanBookingBlock({
    super.key,
    required this.expertId,
    required this.expertName,
    this.expertAvatarUrl,
    required this.handymanProfile,
    required this.onChanged,
  });

  @override
  State<HandymanBookingBlock> createState() => _HandymanBookingBlockState();
}

class _HandymanBookingBlockState extends State<HandymanBookingBlock> {
  // ── State ────────────────────────────────────────────────────────────────
  final List<HandymanPunchListItem> _punchList = [];
  HandymanAiDiagnosis? _aiDiagnosis;
  bool _aiLoading = false;
  final TextEditingController _descriptionCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();
  String _search = '';

  // Property info
  HandymanPropertyInfo _propertyInfo = const HandymanPropertyInfo();

  // Materials
  String _materialsOption = 'provider_buys';

  // Urgency
  String _urgency = 'today';
  String? _maintenancePackageId;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() => _search = _searchCtrl.text));
    // Notify parent with initial (empty) prefs so the CTA resolves.
    WidgetsBinding.instance.addPostFrameCallback((_) => _emit());
  }

  @override
  void dispose() {
    _descriptionCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Emit preferences + total to parent ──────────────────────────────────

  void _emit() {
    final total = HandymanBookingService.calculateTotal(
      profile: widget.handymanProfile,
      punchList: _punchList,
      materialsOption: _materialsOption,
      materialsEstimate: _aiDiagnosis?.estimatedMaterialsCost ?? 0,
      urgency: _urgency,
    );
    final breakdown = HandymanBookingService.buildPriceBreakdown(
      profile: widget.handymanProfile,
      punchList: _punchList,
      materialsOption: _materialsOption,
      materialsEstimate: _aiDiagnosis?.estimatedMaterialsCost ?? 0,
      urgency: _urgency,
    );
    final prefs = HandymanBookingPreferences(
      punchList: List.unmodifiable(_punchList),
      aiPhotoDiagnosis: _aiDiagnosis,
      problemDescription: _descriptionCtrl.text,
      propertyInfo: _propertyInfo,
      materialsOption: _materialsOption,
      estimatedMaterialsCost: _aiDiagnosis?.estimatedMaterialsCost ?? 0,
      materialsBreakdown: _aiDiagnosis?.recommendedMaterials ?? const [],
      urgency: _urgency,
      maintenancePackageId: _maintenancePackageId,
      priceBreakdown: breakdown,
      warranty12MonthsIncluded:
          widget.handymanProfile.verifications.warrantyEnabled,
    );
    widget.onChanged(prefs, total);
  }

  // ── Punch List helpers ──────────────────────────────────────────────────

  void _addToPunchList(HandymanSpecialty spec) {
    if (_punchList.any((p) => p.serviceId == spec.id)) return;
    final price = widget.handymanProfile.pricing.priceFor(
      spec.id,
      spec.basePrice,
    );
    setState(() {
      _punchList.add(
        HandymanPunchListItem(
          serviceId: spec.id,
          nameHe: spec.nameHe,
          icon: spec.icon,
          estimatedMinutes: spec.estimatedMinutes,
          price: price,
          priority: _punchList.length + 1,
        ),
      );
    });
    _emit();
  }

  void _removeFromPunchList(String serviceId) {
    setState(() {
      _punchList.removeWhere((p) => p.serviceId == serviceId);
      // Re-number priorities.
      for (int i = 0; i < _punchList.length; i++) {
        final p = _punchList[i];
        _punchList[i] = HandymanPunchListItem(
          serviceId: p.serviceId,
          nameHe: p.nameHe,
          icon: p.icon,
          estimatedMinutes: p.estimatedMinutes,
          price: p.price,
          priority: i + 1,
        );
      }
    });
    _emit();
  }

  // ── AI Photo-to-Quote ───────────────────────────────────────────────────

  Future<void> _pickAndAnalyzePhoto(ImageSource source) async {
    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (file == null || !mounted) return;
    setState(() => _aiLoading = true);
    try {
      // Upload to Firebase Storage first.
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anon';
      final ref = FirebaseStorage.instance.ref(
        'handyman_diagnosis/$uid/${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await ref.putFile(File(file.path));
      final url = await ref.getDownloadURL();
      // Call Gemini CF.
      final callable = FirebaseFunctions.instance.httpsCallable(
        'diagnoseHandymanProblemFromPhoto',
      );
      final result = await callable.call<Map<String, dynamic>>({
        'photoUrls': [url],
        'additionalDescription': _descriptionCtrl.text,
      });
      final data = Map<String, dynamic>.from(result.data);
      data['photoUrls'] = [url];
      final diag = HandymanAiDiagnosis.fromJson(data);
      if (!mounted) return;
      setState(() {
        _aiDiagnosis = diag;
        _aiLoading = false;
      });
      _emit();
    } catch (e) {
      if (!mounted) return;
      setState(() => _aiLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'לא הצלחנו לנתח את התמונה. נסה שוב או בחר מתחומים למטה.',
          ),
        ),
      );
    }
  }

  // ── Chat deep-link (SYNCED with existing ChatScreen) ────────────────────

  void _openChat({String? initialMessage}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => ChatScreen(
              receiverId: widget.expertId,
              receiverName: widget.expertName,
              initialMessage: initialMessage,
            ),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hasActiveSpecialties = widget.handymanProfile.specialties.any(
      (s) => s.active,
    );
    if (!hasActiveSpecialties) return const SizedBox.shrink();

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
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildLiveBanner(),
            const SizedBox(height: 14),
            _buildHero(),
            const SizedBox(height: 14),
            _buildTrustCenter(),
            const SizedBox(height: 14),
            if (widget.handymanProfile.aiPhotoToQuote.enabled) ...[
              _buildAiPhotoToQuote(),
              const SizedBox(height: 14),
            ],
            _buildSpecialtiesSelector(),
            const SizedBox(height: 14),
            if (_punchList.isNotEmpty) ...[
              _buildPunchList(),
              const SizedBox(height: 14),
            ],
            _buildDescription(),
            const SizedBox(height: 14),
            _buildPropertyInfo(),
            const SizedBox(height: 14),
            _buildMaterials(),
            const SizedBox(height: 14),
            _buildUrgency(),
            const SizedBox(height: 14),
            _buildWarranty(),
            const SizedBox(height: 14),
            _buildChatPreview(),
            const SizedBox(height: 14),
            if (widget.handymanProfile.maintenancePackages.any(
              (p) => p.enabled,
            )) ...[
              _buildMaintenancePackages(),
              const SizedBox(height: 14),
            ],
            _buildStickySummary(),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 1. LIVE banner
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildLiveBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _HPalette.orange.withValues(alpha: 0.22),
            _HPalette.orangeDark.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _HPalette.orange.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _HPalette.orange,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _HPalette.orange.withValues(alpha: 0.6),
                  blurRadius: 8,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'LIVE · לקוחות בוחרים עכשיו',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 2. Hero
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildHero() {
    final sa = widget.handymanProfile.serviceArea;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _Pill(
              text: '● זמין היום',
              color: _HPalette.green,
              bg: _HPalette.green.withValues(alpha: 0.18),
            ),
            if (sa.emergency24_7)
              _Pill(
                text: '🚨 חירום 24/7',
                color: _HPalette.red,
                bg: _HPalette.red.withValues(alpha: 0.18),
              ),
            _Pill(
              text: '⚡ Pro Verified',
              color: _HPalette.blue,
              bg: _HPalette.blue.withValues(alpha: 0.18),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ShaderMask(
          shaderCallback:
              (bounds) => const LinearGradient(
                colors: [Colors.white, _HPalette.amberPale, Color(0xFFFB923C)],
              ).createShader(bounds),
          child: const Text(
            'בוא נתקן\nאת זה ביחד',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '📸 צלם → 🤖 AI → 💰 אומדן → ✅ תיקון',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 3. Trust Center — 4 badges (NO ID, NO insurance)
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildTrustCenter() {
    final v = widget.handymanProfile.verifications;
    return _GlassCard(
      borderColor: _HPalette.green.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: '🛡️',
            title: 'Trust Center',
            subtitle: 'הגנה מלאה — הכל מאומת',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _TrustBadge(
                icon: '✓',
                label: 'Verified',
                sub: 'פרופיל מאומת',
                color: _HPalette.green,
              ),
              const SizedBox(width: 8),
              _TrustBadge(
                icon: '📋',
                label: 'בדיקת רקע',
                sub: v.backgroundCheck.verified ? 'מאושר' : '—',
                color: _HPalette.blue,
              ),
              const SizedBox(width: 8),
              _TrustBadge(
                icon: '📜',
                label: 'אחריות',
                sub: v.warrantyEnabled ? '12 חודש' : '—',
                color: _HPalette.amber,
              ),
              const SizedBox(width: 8),
              _TrustBadge(
                icon: '💎',
                label: 'Escrow',
                sub: 'תשלום בנאמנות',
                color: _HPalette.purple,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _HPalette.green.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              '💎 תשלום בנאמנות — אתה משלם רק אחרי שאישרת',
              style: TextStyle(color: _HPalette.amberPale, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 4. AI Photo-to-Quote ⭐
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildAiPhotoToQuote() {
    return _GlassCard(
      borderColor: _HPalette.orange.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('📸', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'תאר/צלם את הבעיה',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '3 דרכי קלט · בחר מה הכי נוח',
                      style: TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ],
                ),
              ),
              _Pill(
                text: '⚡ AI · 5 שניות',
                color: _HPalette.orange,
                bg: _HPalette.orange.withValues(alpha: 0.2),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _InputMethodButton(
                icon: Icons.photo_camera_rounded,
                label: 'צלם עכשיו',
                onTap:
                    _aiLoading
                        ? null
                        : () => _pickAndAnalyzePhoto(ImageSource.camera),
              ),
              const SizedBox(width: 8),
              _InputMethodButton(
                icon: Icons.photo_library_rounded,
                label: 'גלריה',
                onTap:
                    _aiLoading
                        ? null
                        : () => _pickAndAnalyzePhoto(ImageSource.gallery),
              ),
            ],
          ),
          if (_aiLoading) ...[
            const SizedBox(height: 12),
            const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _HPalette.orange,
                  ),
                ),
                SizedBox(width: 10),
                Text(
                  'AI מנתח את התמונה...',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ],
          if (_aiDiagnosis != null) ...[
            const SizedBox(height: 12),
            _AiResultCard(
              diagnosis: _aiDiagnosis!,
              onAddToPunchList: () {
                // Add a synthetic item for the diagnosed problem so it shows
                // up in the Punch List + price breakdown.
                final id = 'ai_${_aiDiagnosis!.category}';
                if (!_punchList.any((p) => p.serviceId == id)) {
                  setState(() {
                    _punchList.add(
                      HandymanPunchListItem(
                        serviceId: id,
                        nameHe:
                            _aiDiagnosis!.identifiedProblem.isNotEmpty
                                ? _aiDiagnosis!.identifiedProblem
                                : 'אבחון AI',
                        icon: '🤖',
                        estimatedMinutes:
                            _aiDiagnosis!.estimatedDurationMinutes,
                        price: _aiDiagnosis!.estimatedPrice,
                        priority: _punchList.length + 1,
                      ),
                    );
                  });
                  _emit();
                }
              },
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 5. Specialties selector (search + grid)
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildSpecialtiesSelector() {
    final active =
        widget.handymanProfile.specialties.where((s) => s.active).toList();
    final filtered =
        _search.isEmpty
            ? active
            : active
                .where(
                  (s) =>
                      s.nameHe.contains(_search) ||
                      s.id.contains(_search.toLowerCase()),
                )
                .toList();
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: '🔍',
            title: 'בחר שירות',
            subtitle: '${active.length} תחומים זמינים אצל ${widget.expertName}',
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _searchCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'חפש: \'דלת חורקת\', \'שקע חשמל\'...',
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
              prefixIcon: const Icon(
                Icons.search,
                color: Colors.white38,
                size: 18,
              ),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.12),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.12),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _HPalette.orange),
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                filtered.map((s) {
                  final inPunchList = _punchList.any(
                    (p) => p.serviceId == s.id,
                  );
                  return GestureDetector(
                    onTap:
                        () =>
                            inPunchList
                                ? _removeFromPunchList(s.id)
                                : _addToPunchList(s),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      width: 110,
                      decoration: BoxDecoration(
                        gradient:
                            inPunchList
                                ? const LinearGradient(
                                  colors: [
                                    _HPalette.orange,
                                    _HPalette.orangeDark,
                                  ],
                                )
                                : null,
                        color:
                            inPunchList
                                ? null
                                : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color:
                              inPunchList
                                  ? _HPalette.orange
                                  : Colors.white.withValues(alpha: 0.12),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(s.icon, style: const TextStyle(fontSize: 22)),
                          const SizedBox(height: 4),
                          Text(
                            s.nameHe,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color:
                                  inPunchList ? Colors.white : Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '₪${widget.handymanProfile.pricing.priceFor(s.id, s.basePrice).toStringAsFixed(0)} · ${s.estimatedMinutes ~/ 60 >= 1 ? '${(s.estimatedMinutes / 60).toStringAsFixed(1)}ש\'' : '${s.estimatedMinutes}ד\''}',
                            style: const TextStyle(
                              color: _HPalette.amberPale,
                              fontSize: 10,
                            ),
                          ),
                          if (s.popularity == 'hot') ...[
                            const SizedBox(height: 2),
                            const Text('🔥', style: TextStyle(fontSize: 11)),
                          ] else if (s.popularity == 'urgent') ...[
                            const SizedBox(height: 2),
                            const Text('⚡', style: TextStyle(fontSize: 11)),
                          ],
                        ],
                      ),
                    ),
                  );
                }).toList(),
          ),
          if (filtered.isEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'לא נמצאו תחומים תואמים',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 6. Punch List
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildPunchList() {
    final discount = HandymanBookingService.punchListDiscountAmount(
      profile: widget.handymanProfile,
      punchList: _punchList,
    );
    final pct = widget.handymanProfile.punchListDiscount.percentFor(
      _punchList.length,
    );
    return _GlassCard(
      borderColor: _HPalette.purple.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: '📋',
            title: 'Punch List חכם',
            subtitle: 'הוסף עוד עבודות באותו ביקור = חיסכון',
            trailing: _Pill(
              text: '${_punchList.length} פעיל',
              color: _HPalette.purple,
              bg: _HPalette.purple.withValues(alpha: 0.2),
            ),
          ),
          if (discount > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _HPalette.green.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _HPalette.green.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Text('💰', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'חוסך ₪${discount.toStringAsFixed(0)} בדמי-נסיעה',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  _Pill(
                    text: '−$pct%',
                    color: _HPalette.green,
                    bg: _HPalette.green.withValues(alpha: 0.25),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          ..._punchList.map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_HPalette.orange, _HPalette.orangeDark],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(p.icon, style: const TextStyle(fontSize: 16)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '#${p.priority} ${p.nameHe}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '~${p.estimatedMinutes} דק\'',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '₪${p.price.toStringAsFixed(0)}',
                    style: const TextStyle(
                      color: _HPalette.amberPale,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: _HPalette.red,
                      size: 18,
                    ),
                    onPressed: () => _removeFromPunchList(p.serviceId),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 7. Problem description
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildDescription() {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: '📝',
            title: 'תיאור מפורט',
            subtitle: 'פרט כדי שיגיע מוכן',
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _descriptionCtrl,
            maxLines: 4,
            maxLength: 500,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            onChanged: (_) => _emit(),
            decoration: InputDecoration(
              hintText: 'תיאור הבעיה... (גובה קיר, סוג חומר, עומס וכו\')',
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.12),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.12),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _HPalette.orange),
              ),
              counterStyle: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 8. Property info
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildPropertyInfo() {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: '📐',
            title: 'מידע על הנכס',
            subtitle: 'נשמר אוטומטית',
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _PropertyChip(
                label: 'גובה תקרה: ${_propertyInfo.ceilingHeight ?? "?"}',
                selected: _propertyInfo.ceilingHeight != null,
                onTap: () => _pickCeilingHeight(),
              ),
              _PropertyChip(
                label: 'סוג קיר: ${_wallTypeLabel(_propertyInfo.wallType)}',
                selected: _propertyInfo.wallType != null,
                onTap: () => _pickWallType(),
              ),
              _PropertyChip(
                label: 'קומה: ${_propertyInfo.floor ?? "?"}',
                selected: _propertyInfo.floor != null,
                onTap: () => _pickFloor(),
              ),
              _PropertyChip(
                label: _propertyInfo.hasElevator ? 'מעלית: כן ✓' : 'מעלית: לא',
                selected: _propertyInfo.hasElevator,
                onTap: () {
                  setState(
                    () =>
                        _propertyInfo = _propertyInfo.copyWith(
                          hasElevator: !_propertyInfo.hasElevator,
                        ),
                  );
                  _emit();
                },
              ),
              _PropertyChip(
                label:
                    _propertyInfo.parkingAvailable
                        ? 'חניה: פנויה ✓'
                        : 'חניה: ?',
                selected: _propertyInfo.parkingAvailable,
                onTap: () {
                  setState(
                    () =>
                        _propertyInfo = _propertyInfo.copyWith(
                          parkingAvailable: !_propertyInfo.parkingAvailable,
                        ),
                  );
                  _emit();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _wallTypeLabel(String? t) {
    switch (t) {
      case 'drywall':
        return 'גבס';
      case 'concrete':
        return 'בטון';
      case 'brick':
        return 'לבנים';
      default:
        return '?';
    }
  }

  void _pickCeilingHeight() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _HPalette.darkBase,
      builder:
          (_) => Column(
            mainAxisSize: MainAxisSize.min,
            children:
                ['2.4m', '2.6m', '2.8m', '3.0m+']
                    .map(
                      (h) => ListTile(
                        title: Text(
                          h,
                          style: const TextStyle(color: Colors.white),
                        ),
                        onTap: () {
                          setState(
                            () =>
                                _propertyInfo = _propertyInfo.copyWith(
                                  ceilingHeight: h,
                                ),
                          );
                          _emit();
                          Navigator.pop(context);
                        },
                      ),
                    )
                    .toList(),
          ),
    );
  }

  void _pickWallType() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _HPalette.darkBase,
      builder:
          (_) => Column(
            mainAxisSize: MainAxisSize.min,
            children:
                [('drywall', 'גבס'), ('concrete', 'בטון'), ('brick', 'לבנים')]
                    .map(
                      (e) => ListTile(
                        title: Text(
                          e.$2,
                          style: const TextStyle(color: Colors.white),
                        ),
                        onTap: () {
                          setState(
                            () =>
                                _propertyInfo = _propertyInfo.copyWith(
                                  wallType: e.$1,
                                ),
                          );
                          _emit();
                          Navigator.pop(context);
                        },
                      ),
                    )
                    .toList(),
          ),
    );
  }

  void _pickFloor() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _HPalette.darkBase,
      builder:
          (_) => SizedBox(
            height: 220,
            child: ListView.builder(
              itemCount: 20,
              itemBuilder:
                  (_, i) => ListTile(
                    title: Text(
                      'קומה $i',
                      style: const TextStyle(color: Colors.white),
                    ),
                    onTap: () {
                      setState(
                        () => _propertyInfo = _propertyInfo.copyWith(floor: i),
                      );
                      _emit();
                      Navigator.pop(context);
                    },
                  ),
            ),
          ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 9. Materials
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildMaterials() {
    final cost = _aiDiagnosis?.estimatedMaterialsCost ?? 0;
    final breakdown = _aiDiagnosis?.recommendedMaterials ?? const [];
    return _GlassCard(
      borderColor: _HPalette.amber.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: '🛒',
            title: 'חומרים וציוד · שקיפות מלאה',
            subtitle:
                _aiDiagnosis != null
                    ? '✨ AI חישב את כל החומרים'
                    : 'AI יחשב את החומרים לאחר העלאת תמונה',
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _HPalette.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Text('🔧', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'כל הציוד המקצועי כלול (50+ כלים)',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                _Pill(
                  text: 'חינם',
                  color: _HPalette.green,
                  bg: _HPalette.green.withValues(alpha: 0.25),
                ),
              ],
            ),
          ),
          if (cost > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _HPalette.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _HPalette.amber.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('📦', style: TextStyle(fontSize: 18)),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'חומרים נדרשים',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Text(
                        '~₪${cost.toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: _HPalette.amberPale,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  if (breakdown.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ...breakdown.map(
                      (m) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            const Text(
                              '•  ',
                              style: TextStyle(color: Colors.white70),
                            ),
                            Expanded(
                              child: Text(
                                m.name,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Text(
                              '₪${m.price.toStringAsFixed(0)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _MaterialsOptionBtn(
                        label: 'יקנה עבורי',
                        selected: _materialsOption == 'provider_buys',
                        onTap: () {
                          setState(() => _materialsOption = 'provider_buys');
                          _emit();
                        },
                      ),
                      const SizedBox(width: 8),
                      _MaterialsOptionBtn(
                        label: 'אני אביא',
                        selected: _materialsOption == 'client_brings',
                        onTap: () {
                          setState(() => _materialsOption = 'client_brings');
                          _emit();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 10. Urgency selector
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildUrgency() {
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: '🚨',
            title: 'מתי שיגיע?',
            subtitle: 'בחר דחיפות',
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.4,
            children:
                kHandymanUrgencyOptions.map((opt) {
                  final selected = _urgency == opt.id;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _urgency = opt.id);
                      _emit();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient:
                            selected
                                ? LinearGradient(
                                  colors: [opt.gradientStart, opt.gradientEnd],
                                )
                                : null,
                        color:
                            selected
                                ? null
                                : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color:
                              selected
                                  ? opt.gradientStart
                                  : Colors.white.withValues(alpha: 0.15),
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(opt.emoji, style: const TextStyle(fontSize: 22)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  opt.labelHe,
                                  style: TextStyle(
                                    color:
                                        selected ? Colors.white : Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  opt.subtitleHe,
                                  style: TextStyle(
                                    color:
                                        selected
                                            ? Colors.white.withValues(
                                              alpha: 0.85,
                                            )
                                            : Colors.white60,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (selected)
                            const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 11. Warranty
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildWarranty() {
    return _GlassCard(
      borderColor: _HPalette.green.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: '📜',
            title: 'אחריות 12 חודשים מלאה',
            subtitle: 'משהו התקלקל? חוזרים חינם!',
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _WarrantyPillar(
                icon: '📅',
                title: '12 חודש',
                sub: 'מסיום העבודה',
              ),
              const SizedBox(width: 8),
              _WarrantyPillar(icon: '🔧', title: 'תיקון חוזר', sub: 'חינם'),
              const SizedBox(width: 8),
              _WarrantyPillar(
                icon: '🛡️',
                title: 'הגנת Escrow',
                sub: 'תשלום בנאמנות',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _HPalette.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              '📞 תמיכה זמינה 24/7 · גיבוי מקצועי במקרה הצורך',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 12. Chat preview + Quick Replies → Existing ChatScreen
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildChatPreview() {
    return _GlassCard(
      borderColor: _HPalette.blue.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: '💬',
            title: 'שאלות ל${widget.expertName}?',
            subtitle: 'תגובה ב-3 דק\' · עברית/EN/RU',
            trailing: _Pill(
              text: '● מקוון',
              color: _HPalette.green,
              bg: _HPalette.green.withValues(alpha: 0.2),
            ),
          ),
          const SizedBox(height: 10),
          // Main chat button
          GestureDetector(
            onTap: () => _openChat(),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _HPalette.blue,
                    _HPalette.blue.withValues(alpha: 0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text(
                  '💬 פתח צ\'אט',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                kHandymanQuickReplies
                    .map(
                      (t) => GestureDetector(
                        onTap: () => _openChat(initialMessage: t),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.15),
                            ),
                          ),
                          child: Text(
                            '💭 "$t"',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 13. Maintenance packages
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildMaintenancePackages() {
    final packs =
        widget.handymanProfile.maintenancePackages
            .where((p) => p.enabled)
            .toList();
    if (packs.isEmpty) return const SizedBox.shrink();
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: '🔁',
            title: 'תחזוקה שנתית · חיסכון עד 30%',
            subtitle: 'חוזה שנתי · עדיפות · מחירים קבועים',
          ),
          const SizedBox(height: 10),
          Row(
            children:
                packs.map((p) {
                  final selected = _maintenancePackageId == p.id;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(end: 6),
                      child: GestureDetector(
                        onTap: () {
                          setState(
                            () =>
                                _maintenancePackageId = selected ? null : p.id,
                          );
                          _emit();
                        },
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            gradient:
                                selected
                                    ? const LinearGradient(
                                      colors: [
                                        _HPalette.amber,
                                        _HPalette.orange,
                                      ],
                                    )
                                    : null,
                            color:
                                selected
                                    ? null
                                    : Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color:
                                  selected
                                      ? _HPalette.amber
                                      : (p.popular
                                          ? _HPalette.amber.withValues(
                                            alpha: 0.4,
                                          )
                                          : Colors.white.withValues(
                                            alpha: 0.15,
                                          )),
                              width: p.popular || selected ? 1.5 : 1,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (p.popular)
                                const Text('⭐', style: TextStyle(fontSize: 14)),
                              Text(
                                p.nameHe,
                                style: TextStyle(
                                  color: selected ? Colors.white : Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                p.visitsPerYear == -1
                                    ? 'ללא הגבלה'
                                    : '${p.visitsPerYear}/שנה',
                                style: TextStyle(
                                  color:
                                      selected
                                          ? Colors.white.withValues(alpha: 0.9)
                                          : Colors.white60,
                                  fontSize: 10,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '₪${p.yearlyPrice.toStringAsFixed(0)}',
                                style: TextStyle(
                                  color:
                                      selected
                                          ? Colors.white
                                          : _HPalette.amberPale,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // 14. Sticky bottom summary (informational — no CTA; parent owns booking)
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildStickySummary() {
    final total = HandymanBookingService.calculateTotal(
      profile: widget.handymanProfile,
      punchList: _punchList,
      materialsOption: _materialsOption,
      materialsEstimate: _aiDiagnosis?.estimatedMaterialsCost ?? 0,
      urgency: _urgency,
    );
    final discount = HandymanBookingService.punchListDiscountAmount(
      profile: widget.handymanProfile,
      punchList: _punchList,
    );
    final duration = HandymanBookingService.estimatedDurationMinutes(
      profile: widget.handymanProfile,
      punchList: _punchList,
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_HPalette.darkBase, _HPalette.darkBaseMid],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _HPalette.orange.withValues(alpha: 0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: _HPalette.orange.withValues(alpha: 0.25),
            blurRadius: 24,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'סך לתשלום (משוער)',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '₪${total.toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (_punchList.isNotEmpty)
                      Text(
                        '${_punchList.length} עבודות · חיסכון ₪${discount.toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: _HPalette.amberPale,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              if (duration > 0)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'משך',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                    Text(
                      duration >= 60
                          ? '~${(duration / 60).toStringAsFixed(1)}ש\''
                          : '~$duration דק\'',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 10),
          // Trust signals
          Row(
            children: const [
              Expanded(
                child: Text(
                  '🔒 תשלום בנאמנות · 📜 12 חודש אחריות · ↩️ ביטול חופשי',
                  style: TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // CTA nudge — the actual "Pay & Secure" button lives in the
          // parent expert_profile_screen.dart just below the calendar.
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _HPalette.blue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _HPalette.blue.withValues(alpha: 0.3)),
            ),
            child: const Row(
              children: [
                Text('🗓️', style: TextStyle(fontSize: 18)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'לקביעת מועד — גלול ליומן הזמינות למטה',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                Icon(
                  Icons.arrow_downward_rounded,
                  color: _HPalette.blue,
                  size: 18,
                ),
              ],
            ),
          ),
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
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
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

class _TrustBadge extends StatelessWidget {
  final String icon;
  final String label;
  final String sub;
  final Color color;
  const _TrustBadge({
    required this.icon,
    required this.label,
    required this.sub,
    required this.color,
  });
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(icon, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              sub,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 9),
            ),
          ],
        ),
      ),
    );
  }
}

class _InputMethodButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _InputMethodButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            gradient:
                disabled
                    ? null
                    : const LinearGradient(
                      colors: [_HPalette.orange, _HPalette.orangeDark],
                    ),
            color: disabled ? Colors.white.withValues(alpha: 0.05) : null,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(height: 4),
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
      ),
    );
  }
}

class _AiResultCard extends StatelessWidget {
  final HandymanAiDiagnosis diagnosis;
  final VoidCallback onAddToPunchList;
  const _AiResultCard({
    required this.diagnosis,
    required this.onAddToPunchList,
  });
  @override
  Widget build(BuildContext context) {
    final confPct = (diagnosis.confidence * 100).round();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _HPalette.green.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Pill(
            text: '✓ AI ניתח',
            color: _HPalette.green,
            bg: _HPalette.green.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 8),
          Text(
            diagnosis.identifiedProblem.isEmpty
                ? 'זוהתה בעיה'
                : diagnosis.identifiedProblem,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '🎯 רמת ביטחון: $confPct%',
            style: const TextStyle(color: _HPalette.amberPale, fontSize: 11),
          ),
          const SizedBox(height: 10),
          if (diagnosis.aiAnalysis.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _HPalette.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '🤖 ${diagnosis.aiAnalysis}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              _AiMetricChip(
                label: 'משך',
                value: '~${diagnosis.estimatedDurationMinutes} דק\'',
              ),
              const SizedBox(width: 6),
              _AiMetricChip(
                label: 'מחיר',
                value: '₪${diagnosis.estimatedPrice.toStringAsFixed(0)}',
              ),
              const SizedBox(width: 6),
              _AiMetricChip(
                label: 'חומרים',
                value:
                    '~₪${diagnosis.estimatedMaterialsCost.toStringAsFixed(0)}',
              ),
            ],
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: onAddToPunchList,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_HPalette.orange, _HPalette.orangeDark],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Text(
                  'הוסף ל-Punch List',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AiMetricChip extends StatelessWidget {
  final String label;
  final String value;
  const _AiMetricChip({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white60, fontSize: 10),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PropertyChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _PropertyChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color:
              selected
                  ? _HPalette.orange.withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color:
                selected
                    ? _HPalette.orange
                    : Colors.white.withValues(alpha: 0.15),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _MaterialsOptionBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _MaterialsOptionBtn({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            gradient:
                selected
                    ? const LinearGradient(
                      colors: [_HPalette.orange, _HPalette.orangeDark],
                    )
                    : null,
            color: selected ? null : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color:
                  selected
                      ? _HPalette.orange
                      : Colors.white.withValues(alpha: 0.15),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _WarrantyPillar extends StatelessWidget {
  final String icon;
  final String title;
  final String sub;
  const _WarrantyPillar({
    required this.icon,
    required this.title,
    required this.sub,
  });
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _HPalette.green.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _HPalette.green.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Text(icon, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 4),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sub,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}
