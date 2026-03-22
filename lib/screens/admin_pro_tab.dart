// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/pro_service.dart';

class AdminProTab extends StatefulWidget {
  const AdminProTab({super.key});

  @override
  State<AdminProTab> createState() => _AdminProTabState();
}

class _AdminProTabState extends State<AdminProTab> {
  static const _primary = Color(0xFF6366F1);
  static const _gold    = Color(0xFFFBBF24);

  // ── Threshold controllers ─────────────────────────────────────────────────
  final _thresholdFormKey = GlobalKey<FormState>();
  final _ratingCtrl       = TextEditingController();
  final _ordersCtrl       = TextEditingController();
  final _responseCtrl     = TextEditingController();
  bool _thresholdsFilled  = false;
  bool _savingThresholds  = false;

  // ── Provider search ───────────────────────────────────────────────────────
  final _searchCtrl   = TextEditingController();
  bool  _searching    = false;
  bool  _overrideLoading = false;
  String? _foundUid;
  Map<String, dynamic>? _foundData;
  String? _searchError;

  // ── Per-row refresh tracking (Pro list) ───────────────────────────────────
  final Map<String, bool> _refreshingRow = {};

  @override
  void dispose() {
    _ratingCtrl.dispose();
    _ordersCtrl.dispose();
    _responseCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Threshold helpers ─────────────────────────────────────────────────────

  void _applyThresholds(Map<String, dynamic> t) {
    if (_thresholdsFilled) return;
    _ratingCtrl.text   = (t['minRating']          as double).toString();
    _ordersCtrl.text   = (t['minOrders']           as int).toString();
    _responseCtrl.text = (t['maxResponseMinutes']  as int).toString();
    _thresholdsFilled  = true;
  }

  Future<void> _saveThresholds() async {
    if (!(_thresholdFormKey.currentState?.validate() ?? false)) return;
    setState(() => _savingThresholds = true);
    try {
      await ProService.saveThresholds(
        minRating:          double.parse(_ratingCtrl.text.trim()),
        minOrders:          int.parse(_ordersCtrl.text.trim()),
        maxResponseMinutes: int.parse(_responseCtrl.text.trim()),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('הגדרות עודכנו ✓'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('שגיאה: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _savingThresholds = false);
    }
  }

  // ── Provider search ───────────────────────────────────────────────────────

  /// Searches by UID (direct lookup) → email → phoneNumber.
  Future<void> _searchProvider() async {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _searching   = true;
      _foundUid    = null;
      _foundData   = null;
      _searchError = null;
    });

    try {
      final db = FirebaseFirestore.instance;

      // 1. Direct UID lookup
      final directDoc = await db.collection('users').doc(query).get();
      if (directDoc.exists) {
        _setFound(directDoc.id, directDoc.data());
        return;
      }

      // 2. Email match
      final emailSnap = await db
          .collection('users')
          .where('email', isEqualTo: query)
          .limit(1)
          .get();
      if (emailSnap.docs.isNotEmpty) {
        _setFound(emailSnap.docs.first.id, emailSnap.docs.first.data());
        return;
      }

      // 3. Phone number match (handles +972 and local formats)
      final phoneSnap = await db
          .collection('users')
          .where('phoneNumber', isEqualTo: query)
          .limit(1)
          .get();
      if (phoneSnap.docs.isNotEmpty) {
        _setFound(phoneSnap.docs.first.id, phoneSnap.docs.first.data());
        return;
      }

      // Not found
      if (mounted) setState(() => _searchError = 'לא נמצא ספק עם פרטים אלה');
    } catch (e) {
      if (mounted) setState(() => _searchError = 'שגיאה: $e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _setFound(String uid, Map<String, dynamic>? data) {
    if (mounted) {
      setState(() {
        _foundUid  = uid;
        _foundData = data ?? {};
        _searching = false;
      });
    }
  }

  void _clearSearch() {
    setState(() {
      _searchCtrl.clear();
      _foundUid    = null;
      _foundData   = null;
      _searchError = null;
    });
  }

  // ── Override actions ──────────────────────────────────────────────────────

  Future<void> _grantPro() async {
    if (_foundUid == null) return;
    final uid          = _foundUid!;
    final providerName = _foundData?['name'] as String? ?? 'ספק';
    setState(() { _overrideLoading = true; _searchError = null; });
    try {
      await ProService.setManualOverride(uid, isPro: true);

      // ── In-app notification to the provider ────────────────────────────
      await FirebaseFirestore.instance.collection('notifications').add({
        'userId':    uid,
        'title':     '🏆 מזל טוב! קיבלת תג AnySkill Pro!',
        'body':      'המנהל העניק לך סטטוס Pro. החשיפה שלך עלתה והלקוחות '
                     'יראו את תו האיכות שלך ⭐ לחץ לצפייה בתובנות שלך.',
        'isRead':    false,
        'type':      'pro_granted',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      setState(() {
        _foundData = Map<String, dynamic>.from(_foundData ?? {})
          ..['isAnySkillPro']     = true
          ..['proManualOverride'] = true;
        _overrideLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🎉 Pro הוענק ל-$providerName! הודעה נשלחה לספק.'),
          backgroundColor: const Color(0xFF6366F1),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (mounted) setState(() { _searchError = e.toString(); _overrideLoading = false; });
    }
  }

  Future<void> _revokePro() async {
    if (_foundUid == null) return;
    setState(() { _overrideLoading = true; _searchError = null; });
    try {
      await ProService.setManualOverride(_foundUid!, isPro: false);
      if (!mounted) return;
      setState(() {
        _foundData = Map<String, dynamic>.from(_foundData ?? {})
          ..['isAnySkillPro'] = false
          ..['proManualOverride'] = true;
        _overrideLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pro נשלל'), backgroundColor: Colors.orange),
      );
    } catch (e) {
      if (mounted) setState(() { _searchError = e.toString(); _overrideLoading = false; });
    }
  }

  Future<void> _clearOverride() async {
    if (_foundUid == null) return;
    setState(() { _overrideLoading = true; _searchError = null; });
    try {
      await ProService.clearManualOverride(_foundUid!);
      if (!mounted) return;
      setState(() {
        _foundData = Map<String, dynamic>.from(_foundData ?? {})
          ..['proManualOverride'] = false;
        _overrideLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Override הוסר — בדיקה אוטומטית פעילה'),
          backgroundColor: _primary,
        ),
      );
    } catch (e) {
      if (mounted) setState(() { _searchError = e.toString(); _overrideLoading = false; });
    }
  }

  Future<void> _refreshRow(String uid) async {
    setState(() => _refreshingRow[uid] = true);
    try {
      final isPro = await ProService.checkAndRefreshProStatus(uid);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isPro ? 'סטטוס Pro אושר ✓' : 'סטטוס Pro בוטל'),
          backgroundColor: isPro ? Colors.green : Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('שגיאה: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _refreshingRow.remove(uid));
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildThresholdsCard(),
          const SizedBox(height: 16),
          _buildOverrideCard(),
          const SizedBox(height: 16),
          _buildProListCard(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ── Section 1: Thresholds ─────────────────────────────────────────────────

  Widget _buildThresholdsCard() {
    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: StreamBuilder<Map<String, dynamic>>(
          stream: ProService.streamThresholds(),
          builder: (context, snap) {
            if (snap.hasData && !_thresholdsFilled) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _applyThresholds(snap.data!);
              });
            }
            return Form(
              key: _thresholdFormKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionHeader(Icons.tune_rounded, 'סף קריטריונים ל-Pro'),
                  const Divider(height: 24),
                  _thresholdField(
                    label: 'דירוג מינימלי',
                    hint: '4.8',
                    controller: _ratingCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) {
                      final n = double.tryParse(v ?? '');
                      if (n == null || n < 1 || n > 5) return 'ערך בין 1 ל-5';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  _thresholdField(
                    label: 'הזמנות שהושלמו (מינימום)',
                    hint: '20',
                    controller: _ordersCtrl,
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      if (n == null || n < 0) return 'מספר חיובי';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  _thresholdField(
                    label: "זמן תגובה מקס׳ (דקות)",
                    hint: '15',
                    controller: _responseCtrl,
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      if (n == null || n < 1) return 'לפחות דקה אחת';
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _savingThresholds ? null : _saveThresholds,
                      icon: _savingThresholds
                          ? const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.save_rounded),
                      label: const Text('שמור'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _thresholdField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required TextInputType keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _primary, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  // ── Section 2: Smart Override Search ──────────────────────────────────────

  Widget _buildOverrideCard() {
    final userFound = _foundUid != null && _foundData != null;

    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(
                Icons.manage_accounts_rounded, 'חיפוש וניהול ספק Pro'),
            const Divider(height: 24),

            // ── Search field ────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _searchProvider(),
                    decoration: InputDecoration(
                      hintText: 'חפש לפי טלפון, אימייל, או UID',
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: _primary, size: 20),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close_rounded,
                                  size: 18, color: Colors.grey),
                              onPressed: _clearSearch,
                            )
                          : null,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: _primary, width: 2),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _searching ? null : _searchProvider,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primary,
                      foregroundColor: Colors.white,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 18),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _searching
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('חפש',
                            style:
                                TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),

            // ── Error ────────────────────────────────────────────────────────
            if (_searchError != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.error_outline,
                      color: Colors.red, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(_searchError!,
                        style: const TextStyle(
                            color: Colors.red, fontSize: 13)),
                  ),
                ],
              ),
            ],

            // ── Preview card (shown after successful search) ──────────────
            if (userFound) ...[
              const SizedBox(height: 16),
              _buildPreviewCard(_foundUid!, _foundData!),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // ── Action buttons ─────────────────────────────────────────
              if (_overrideLoading)
                const Center(
                    child: CircularProgressIndicator(color: _primary))
              else
                _buildActionButtons(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewCard(String uid, Map<String, dynamic> d) {
    final name       = d['name']         as String? ?? 'ללא שם';
    final imgUrl     = d['profileImage'] as String? ?? '';
    final rating     = (d['rating']      as num?)?.toDouble() ?? 0.0;
    final orders     = (d['reviewsCount']  as num?)?.toInt() ??
                       (d['orderCount']    as num?)?.toInt() ?? 0;
    final isPro      = d['isAnySkillPro']     == true;
    final isOverride = d['proManualOverride'] == true;
    final initial    = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          // Avatar
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: imgUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: imgUrl,
                    width: 56, height: 56,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) =>
                        _avatarFallback(initial),
                  )
                : _avatarFallback(initial),
          ),
          const SizedBox(width: 14),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Name + Pro chip row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        _buildProChip(isPro),
                        if (isOverride) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: Colors.orange.shade200),
                            ),
                            child: const Text('Manual',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.orange,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // Metrics row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // UID snippet
                    Text(
                      uid.length > 14
                          ? '${uid.substring(0, 14)}…'
                          : uid,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.grey,
                        fontFamily: 'monospace',
                      ),
                    ),
                    // Rating + orders
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 14, color: Color(0xFFF59E0B)),
                        const SizedBox(width: 2),
                        Text(
                          rating > 0
                              ? rating.toStringAsFixed(1)
                              : '—',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 10),
                        const Icon(Icons.check_circle_outline,
                            size: 14, color: Colors.green),
                        const SizedBox(width: 2),
                        Text(
                          '$orders הזמנות',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    final userFound = _foundUid != null;
    return Row(
      children: [
        // Grant Pro
        Expanded(
          child: ElevatedButton.icon(
            onPressed: userFound ? _grantPro : null,
            icon: const Icon(Icons.star_rounded, size: 16),
            label: const Text('הענק Pro'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _gold,
              foregroundColor: Colors.black87,
              disabledBackgroundColor: Colors.grey.shade100,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        const SizedBox(width: 8),

        // Revoke Pro
        Expanded(
          child: ElevatedButton.icon(
            onPressed: userFound ? _revokePro : null,
            icon: const Icon(Icons.star_border_rounded, size: 16),
            label: const Text('שלול Pro'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade400,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey.shade100,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        const SizedBox(width: 8),

        // Clear override
        Expanded(
          child: OutlinedButton.icon(
            onPressed: userFound ? _clearOverride : null,
            icon: const Icon(Icons.restart_alt_rounded, size: 16),
            label: const Text('אוטומטי'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _primary,
              side: BorderSide(
                  color: userFound ? _primary : Colors.grey.shade300),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ],
    );
  }

  // ── Section 3: Current Pro list ───────────────────────────────────────────

  Widget _buildProListCard() {
    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(Icons.verified_rounded, 'ספקי Pro פעילים'),
            const Divider(height: 24),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .where('isAnySkillPro', isEqualTo: true)
                  .limit(50)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(color: _primary),
                    ),
                  );
                }
                if (snap.hasError) {
                  return Text('שגיאה: ${snap.error}',
                      style: const TextStyle(color: Colors.red));
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('אין ספקי Pro כרגע',
                        style: TextStyle(color: Colors.grey)),
                  );
                }
                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final d   = docs[i].data() as Map<String, dynamic>? ?? {};
                    final uid = docs[i].id;
                    final name    = d['name']         as String? ?? 'ללא שם';
                    final imgUrl  = d['profileImage'] as String? ?? '';
                    final rating  = (d['rating']      as num?)?.toDouble() ?? 0.0;
                    final phone   = d['phoneNumber']  as String? ?? '';
                    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
                    final isRefreshing = _refreshingRow[uid] == true;

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 4, horizontal: 0),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: imgUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: imgUrl,
                                width: 42, height: 42,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) =>
                                    _avatarFallback(initial, size: 42),
                              )
                            : _avatarFallback(initial, size: 42),
                      ),
                      title: Text(name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14)),
                      subtitle: Row(
                        children: [
                          if (rating > 0) ...[
                            const Icon(Icons.star_rounded,
                                size: 12,
                                color: Color(0xFFF59E0B)),
                            const SizedBox(width: 2),
                            Text(rating.toStringAsFixed(1),
                                style: const TextStyle(fontSize: 11)),
                            const SizedBox(width: 8),
                          ],
                          if (phone.isNotEmpty) ...[
                            const Icon(Icons.phone_rounded,
                                size: 12, color: Colors.grey),
                            const SizedBox(width: 2),
                            Text(phone,
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey)),
                          ] else
                            Text(
                              uid.length > 16
                                  ? '${uid.substring(0, 16)}…'
                                  : uid,
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                                fontFamily: 'monospace',
                              ),
                            ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildProChip(true),
                          const SizedBox(width: 4),
                          isRefreshing
                              ? const SizedBox(
                                  width: 20, height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: _primary),
                                )
                              : IconButton(
                                  icon: const Icon(
                                      Icons.refresh_rounded,
                                      color: _primary,
                                      size: 20),
                                  tooltip: 'רענן סטטוס',
                                  onPressed: () => _refreshRow(uid),
                                ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Shared helpers ────────────────────────────────────────────────────────

  Widget _sectionHeader(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, color: _primary, size: 20),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: _primary,
          ),
        ),
      ],
    );
  }

  Widget _buildProChip(bool isPro) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isPro
            ? _gold.withValues(alpha: 0.15)
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: isPro ? _gold : Colors.grey.shade300),
      ),
      child: Text(
        isPro ? 'Pro ⭐' : 'רגיל',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: isPro ? Colors.amber.shade800 : Colors.grey,
        ),
      ),
    );
  }

  Widget _avatarFallback(String initial, {double size = 56}) {
    return Container(
      width: size, height: size,
      color: _primary.withValues(alpha: 0.12),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontSize: size * 0.4,
            fontWeight: FontWeight.bold,
            color: _primary,
          ),
        ),
      ),
    );
  }
}
