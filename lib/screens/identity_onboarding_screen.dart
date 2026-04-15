// ignore_for_file: use_build_context_synchronously
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import '../services/category_service.dart';
import '../services/provider_listing_service.dart';
import '../utils/safe_image_provider.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// AnySkill — Second Identity Onboarding (v10.2.0)
//
// Premium 4-step full-screen flow for adding a second professional identity:
//   Step 1: Main Category selection (visual grid)
//   Step 2: Sub-Category selection (dynamic, synced to main)
//   Step 3: Service Details (price, description)
//   Step 4: Gallery + Live Preview card
// ═══════════════════════════════════════════════════════════════════════════════

const _kIndigo     = Color(0xFF6366F1);
const _kIndigoSoft = Color(0xFFEEF2FF);
const _kGreen      = Color(0xFF10B981);
const _kDarkText   = Color(0xFF1A1A2E);
const _kMuted      = Color(0xFF6B7280);
const _kScaffold   = Color(0xFFF8FAFC);

class IdentityOnboardingScreen extends StatefulWidget {
  const IdentityOnboardingScreen({super.key});

  @override
  State<IdentityOnboardingScreen> createState() =>
      _IdentityOnboardingScreenState();
}

class _IdentityOnboardingScreenState extends State<IdentityOnboardingScreen> {
  final _pageCtrl = PageController();
  int _currentStep = 0;
  static const _totalSteps = 5; // 0=Profile, 1=Category, 2=SubCat, 3=Details, 4=Gallery

  // Step 0: User profile data (pre-filled, non-editable)
  Map<String, dynamic> _userData = {};
  bool _profileLoaded = false;

  // Step 1: Main category
  List<Map<String, dynamic>> _allCategories = [];
  String? _selectedMainCatId;
  String _selectedMainCatName = '';
  String _selectedMainCatIcon = '';

  // Step 2: Sub-category
  List<Map<String, dynamic>> _subCategories = [];
  String? _selectedSubCatId;
  String _selectedSubCatName = '';

  // Step 3: Details
  final _priceCtrl = TextEditingController();
  final _aboutCtrl = TextEditingController();

  // Step 4: Gallery
  final List<Uint8List> _galleryBytes = [];
  final List<String> _galleryBase64 = [];

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadUserProfile();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _priceCtrl.dispose();
    _aboutCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!mounted) return;
      setState(() {
        _userData = snap.data() ?? {};
        _profileLoaded = true;
      });
    } catch (_) {}
  }

  Future<void> _loadCategories() async {
    final snap = await FirebaseFirestore.instance
        .collection('categories')
        .limit(200)
        .get();
    if (!mounted) return;
    final cats = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    cats.sort((a, b) {
      final oA = (a['order'] as num? ?? 999).toInt();
      final oB = (b['order'] as num? ?? 999).toInt();
      return oA.compareTo(oB);
    });
    setState(() => _allCategories = cats);
  }

  List<Map<String, dynamic>> get _mainCategories => _allCategories
      .where((c) => (c['parentId'] as String? ?? '').isEmpty)
      .where((c) => c['isHidden'] != true)
      .toList();

  void _onMainCatSelected(Map<String, dynamic> cat) {
    setState(() {
      _selectedMainCatId = cat['id'] as String?;
      _selectedMainCatName = cat['name'] as String? ?? '';
      _selectedMainCatIcon = cat['iconName'] as String? ?? '';
      _selectedSubCatId = null;
      _selectedSubCatName = '';
      // Filter subcategories
      _subCategories = _allCategories
          .where((c) => c['parentId'] == _selectedMainCatId)
          .where((c) => c['isHidden'] != true)
          .toList();
    });
    // If no subcategories, skip to step 3 (details)
    if (_subCategories.isEmpty) {
      _goToStep(3);
    } else {
      _goToStep(2);
    }
  }

  void _onSubCatSelected(Map<String, dynamic> sub) {
    setState(() {
      _selectedSubCatId = sub['id'] as String?;
      _selectedSubCatName = sub['name'] as String? ?? '';
    });
    _goToStep(3);
  }

  void _goToStep(int step) {
    setState(() => _currentStep = step);
    _pageCtrl.animateToPage(
      step,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  bool get _canProceedFromDetails {
    final price = double.tryParse(_priceCtrl.text.trim());
    return price != null && price > 0 && _aboutCtrl.text.trim().length >= 10;
  }

  Future<void> _pickImage() async {
    if (_galleryBytes.length >= 6) return; // max 6 photos
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 65,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _galleryBytes.add(bytes);
      _galleryBase64.add(base64Encode(bytes));
    });
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() => _saving = true);

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final serviceType = _selectedSubCatName.isNotEmpty
        ? _selectedSubCatName
        : _selectedMainCatName;

    try {
      // Ensure primary listing exists
      await ProviderListingService.migrateIfNeeded(uid);

      await ProviderListingService.createListing(
        uid: uid,
        identityIndex: 1,
        serviceType: serviceType,
        parentCategory:
            _selectedSubCatName.isNotEmpty ? _selectedMainCatName : '',
        subCategory: _selectedSubCatName,
        aboutMe: _aboutCtrl.text.trim(),
        pricePerHour: double.tryParse(_priceCtrl.text.trim()) ?? 0,
        gallery: _galleryBase64,
      );

      if (mounted) {
        Navigator.pop(context, true); // true = created
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kScaffold,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _kDarkText,
        elevation: 0,
        title: const Text('זהות מקצועית חדשה',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // ── Progress bar ──────────────────────────────────────────────
          _buildProgressBar(),
          // ── Step pages ────────────────────────────────────────────────
          Expanded(
            child: PageView(
              controller: _pageCtrl,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildStep0Profile(),
                _buildStep1Categories(),
                _buildStep2SubCategories(),
                _buildStep3Details(),
                _buildStep4GalleryPreview(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Progress Bar ──────────────────────────────────────────────────────────

  Widget _buildProgressBar() {
    final labels = ['פרופיל', 'קטגוריה', 'התמחות', 'פרטים', 'גלריה'];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 14),
      child: Column(
        children: [
          Row(
            children: List.generate(_totalSteps * 2 - 1, (i) {
              if (i.isOdd) {
                final stepBefore = i ~/ 2;
                return Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    height: 3,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: stepBefore < _currentStep
                          ? _kIndigo
                          : const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                );
              }
              final step = i ~/ 2;
              final isDone = step < _currentStep;
              final isCurrent = step == _currentStep;
              final isActive = step <= _currentStep;
              return GestureDetector(
                onTap: isDone ? () => _goToStep(step) : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive ? _kIndigo : const Color(0xFFE5E7EB),
                    boxShadow: isCurrent
                        ? [BoxShadow(
                            color: _kIndigo.withValues(alpha: 0.35),
                            blurRadius: 10,
                            spreadRadius: 1)]
                        : null,
                  ),
                  child: Center(
                    child: isDone
                        ? const Icon(Icons.check_rounded,
                            color: Colors.white, size: 16)
                        : Text(
                            '${step + 1}',
                            style: TextStyle(
                              color: isActive ? Colors.white : const Color(0xFF9CA3AF),
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(labels.length, (i) {
              final isCurrent = i == _currentStep;
              return Text(labels[i],
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                    color: isCurrent ? _kIndigo : const Color(0xFF9CA3AF),
                  ));
            }),
          ),
        ],
      ),
    );
  }

  // ── Shared tile builder — mirrors the main onboarding dropdown aesthetic ──

  Widget _buildCategoryTile({
    required String name,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? _kIndigoSoft : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? _kIndigo : Colors.grey.shade200,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Leading icon
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: isSelected
                    ? _kIndigo.withValues(alpha: 0.12)
                    : const Color(0xFFF4F7F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20,
                  color: isSelected ? _kIndigo : _kMuted),
            ),
            const SizedBox(width: 14),
            // Title
            Expanded(
              child: Text(name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? _kIndigo : _kDarkText,
                  )),
            ),
            // Trailing: checkmark or chevron
            if (isSelected)
              const Icon(Icons.check_circle_rounded,
                  color: _kIndigo, size: 22)
            else
              Icon(Icons.chevron_left_rounded,
                  color: Colors.grey[400], size: 22),
          ],
        ),
      ),
    );
  }

  // ── Step header — consistent across all steps ─────────────────────────────

  Widget _buildStepHeader({
    required String title,
    required String subtitle,
    int? backStep,
  }) {
    return Column(
      children: [
        if (backStep != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: IconButton(
              icon: const Icon(Icons.arrow_forward_rounded, color: _kMuted),
              onPressed: () => _goToStep(backStep),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
        if (backStep != null) const SizedBox(height: 4),
        Text(title,
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold, color: _kDarkText),
            textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text(subtitle,
            style: TextStyle(fontSize: 13, color: Colors.grey[600], height: 1.4),
            textAlign: TextAlign.center),
        const SizedBox(height: 20),
      ],
    );
  }

  // ── Step 0: Synced Profile Card ────────────────────────────────────────────

  Widget _buildStep0Profile() {
    if (!_profileLoaded) {
      return const Center(child: CircularProgressIndicator(color: _kIndigo));
    }
    final user = FirebaseAuth.instance.currentUser;
    final name = _userData['name'] as String? ?? user?.displayName ?? '';
    final email = _userData['email'] as String? ?? user?.email ?? '';
    final phone = _userData['phone'] as String? ?? user?.phoneNumber ?? '';
    final imageUrl = _userData['profileImage'] as String? ?? user?.photoURL;
    final serviceType = _userData['serviceType'] as String? ?? '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStepHeader(
            title: 'הפרופיל שלך',
            subtitle: 'אנחנו משתמשים בפרטים האישיים שלך מהחשבון הקיים.\nבוא נקים את העסק השני שלך.',
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // ── Profile card ─────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      children: [
                        // Avatar
                        buildProfileAvatar(
                          imageUrl: imageUrl,
                          name: name,
                          radius: 40,
                        ),
                        const SizedBox(height: 14),
                        // Name
                        Text(name,
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: _kDarkText)),
                        if (serviceType.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _kIndigoSoft,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(serviceType,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: _kIndigo,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ],
                        const SizedBox(height: 16),
                        const Divider(height: 1),
                        const SizedBox(height: 16),
                        // Details rows
                        if (email.isNotEmpty)
                          _profileRow(Icons.email_rounded, email),
                        if (phone.isNotEmpty)
                          _profileRow(Icons.phone_rounded, phone),
                        _profileRow(Icons.verified_rounded, 'חשבון מאומת'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // ── Info notice ──────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline_rounded,
                            color: Color(0xFFF59E0B), size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'הפרטים האישיים (שם, תמונה, טלפון) משותפים בין כל הזהויות המקצועיות שלך. בשלב הבא תגדיר את פרטי השירות החדש.',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.grey[700],
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // ── Continue button ──────────────────────────────────
                  SizedBox(
                    height: 52,
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _goToStep(1),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kIndigo,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.arrow_back_rounded, size: 20),
                      label: const Text('המשך לבחירת קטגוריה',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold)),
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

  Widget _profileRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFFF4F7F9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: _kMuted),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 14, color: _kDarkText)),
          ),
        ],
      ),
    );
  }

  // ── Step 1: Main Category ─────────────────────────────────────────────────

  Widget _buildStep1Categories() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStepHeader(
            title: 'באיזה תחום השירות החדש שלך?',
            subtitle: 'בחר את הקטגוריה המקצועית שמתאימה לשירות הנוסף',
          ),
          Expanded(
            child: _mainCategories.isEmpty
                ? const Center(child: CircularProgressIndicator(color: _kIndigo))
                : ListView.separated(
                    itemCount: _mainCategories.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final cat = _mainCategories[i];
                      final name = cat['name'] as String? ?? '';
                      final iconName = cat['iconName'] as String? ?? '';
                      return _buildCategoryTile(
                        name: name,
                        icon: CategoryService.getIcon(iconName),
                        isSelected: cat['id'] == _selectedMainCatId,
                        onTap: () => _onMainCatSelected(cat),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ── Step 2: Sub-Category ──────────────────────────────────────────────────

  Widget _buildStep2SubCategories() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStepHeader(
            title: 'מה ההתמחות ב$_selectedMainCatName?',
            subtitle: 'בחר תת-קטגוריה ספציפית',
            backStep: 1,
          ),
          Expanded(
            child: _subCategories.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 64, height: 64,
                          decoration: BoxDecoration(
                            color: _kIndigoSoft,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.category_rounded,
                              size: 32, color: _kIndigo),
                        ),
                        const SizedBox(height: 16),
                        const Text('אין תתי-קטגוריות לתחום זה',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: _kDarkText)),
                        const SizedBox(height: 6),
                        Text('תמשיך ישירות לפרטי השירות',
                            style: TextStyle(fontSize: 13, color: Colors.grey[500])),
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 48,
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () => _goToStep(3),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kIndigo,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                            child: const Text('המשך',
                                style: TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: _subCategories.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final sub = _subCategories[i];
                      final name = sub['name'] as String? ?? '';
                      return _buildCategoryTile(
                        name: name,
                        icon: Icons.label_rounded,
                        isSelected: sub['id'] == _selectedSubCatId,
                        onTap: () => _onSubCatSelected(sub),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ── Step 3: Service Details ───────────────────────────────────────────────

  Widget _buildStep3Details() {
    final serviceName = _selectedSubCatName.isNotEmpty
        ? _selectedSubCatName
        : _selectedMainCatName;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStepHeader(
            title: 'פרטי השירות',
            subtitle: serviceName,
            backStep: _subCategories.isNotEmpty ? 2 : 1,
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Selected category badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: _kIndigoSoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(CategoryService.getIcon(_selectedMainCatIcon),
                            size: 20, color: _kIndigo),
                        const SizedBox(width: 10),
                        Text(serviceName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: _kIndigo)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Price
                  const Text('מחיר לשעה',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _kDarkText)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _priceCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      prefixText: '₪ ',
                      prefixStyle: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: _kIndigo),
                      hintText: '0',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: _kIndigo, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Description
                  const Text('תיאור השירות',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _kDarkText)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _aboutCtrl,
                    maxLines: 4,
                    maxLength: 500,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText:
                          'ספר/י ללקוחות על הניסיון, הגישה והשירות שלך...',
                      hintStyle: TextStyle(color: Colors.grey[400]),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: _kIndigo, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Continue button
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _canProceedFromDetails
                          ? () => _goToStep(4)
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kIndigo,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey[300],
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: const Text('המשך לגלריה ותצוגה מקדימה',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold)),
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

  // ── Step 4: Gallery + Live Preview ────────────────────────────────────────

  Widget _buildStep4GalleryPreview() {
    final serviceName = _selectedSubCatName.isNotEmpty
        ? _selectedSubCatName
        : _selectedMainCatName;
    final userName =
        FirebaseAuth.instance.currentUser?.displayName ?? 'המומחה שלך';
    final price = double.tryParse(_priceCtrl.text.trim()) ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStepHeader(
            title: 'גלריה ותצוגה מקדימה',
            subtitle: 'הוסף תמונות ובדוק איך הפרופיל ייראה',
            backStep: 3,
          ),

          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Gallery upload ────────────────────────────────────
                  const Text('תמונות עבודה (עד 6)',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _kDarkText)),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 90,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        // Add button
                        if (_galleryBytes.length < 6)
                          GestureDetector(
                            onTap: _pickImage,
                            child: Container(
                              width: 90,
                              margin: const EdgeInsetsDirectional.only(end: 10),
                              decoration: BoxDecoration(
                                color: _kIndigoSoft,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color: _kIndigo.withValues(alpha: 0.3),
                                    style: BorderStyle.solid),
                              ),
                              child: const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_photo_alternate_rounded,
                                      color: _kIndigo, size: 28),
                                  SizedBox(height: 4),
                                  Text('הוסף',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: _kIndigo,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                          ),
                        // Existing photos
                        for (int i = 0; i < _galleryBytes.length; i++)
                          Stack(
                            children: [
                              Container(
                                width: 90,
                                margin:
                                    const EdgeInsetsDirectional.only(end: 10),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  image: DecorationImage(
                                    image: MemoryImage(_galleryBytes[i]),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 4,
                                right: 14,
                                child: GestureDetector(
                                  onTap: () => setState(() {
                                    _galleryBytes.removeAt(i);
                                    _galleryBase64.removeAt(i);
                                  }),
                                  child: Container(
                                    width: 22,
                                    height: 22,
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.close,
                                        size: 14, color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ── Live preview card ─────────────────────────────────
                  const Text('כך תופיע בתוצאות החיפוש:',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _kDarkText)),
                  const SizedBox(height: 12),
                  _buildPreviewCard(userName, serviceName, price),
                  const SizedBox(height: 28),

                  // ── Submit button ──────────────────────────────────────
                  SizedBox(
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kGreen,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey[300],
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      icon: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check_circle_rounded),
                      label: Text(
                          _saving ? 'שומר...' : 'אישור ויצירת הזהות החדשה',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
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

  Widget _buildPreviewCard(String name, String service, double price) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06), blurRadius: 10),
        ],
      ),
      child: Row(
        children: [
          // Avatar
          buildProfileAvatar(
            imageUrl: FirebaseAuth.instance.currentUser?.photoURL,
            name: name,
            radius: 26,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(CategoryService.getIcon(_selectedMainCatIcon),
                        size: 14, color: _kMuted),
                    const SizedBox(width: 4),
                    Text(service,
                        style:
                            TextStyle(fontSize: 12.5, color: Colors.grey[600])),
                  ],
                ),
                if (price > 0) ...[
                  const SizedBox(height: 3),
                  Text('₪${price.toStringAsFixed(0)}/שעה',
                      style: const TextStyle(
                          fontSize: 13,
                          color: _kIndigo,
                          fontWeight: FontWeight.w700)),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFDCFCE7),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text('חדש!',
                style: TextStyle(
                    fontSize: 10,
                    color: Color(0xFF16A34A),
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
