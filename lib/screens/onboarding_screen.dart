// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:async';
import 'dart:convert';
import '../services/category_service.dart';
import '../services/profile_setup_service.dart';
import 'home_screen.dart';
import '../l10n/app_localizations.dart';

// ── Palette ───────────────────────────────────────────────────────────────────
const _kPurple = Color(0xFF6366F1);
const _kGreen  = Color(0xFF10B981);

// ── Role enum ─────────────────────────────────────────────────────────────────
// Two-value enum — no "none" state.  Customer is the default.
// ONE variable, never two booleans.
enum UserRole { customer, expert }

// ── Business type options ─────────────────────────────────────────────────────
const _kBusinessTypes = [
  'עוסק פטור',
  'עוסק מורשה',
  'חברה בע"מ',
  'שכיר המוציא חשבונית דרך חברה חיצונית',
];

// ─────────────────────────────────────────────────────────────────────────────

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int  _currentPage = 0;
  bool _isSaving    = false;

  // ── Step 1: role ─────────────────────────────────────────────────────────
  // Single source of truth.  Defaults to customer.
  // Changing _currentRole triggers setState → full Column rebuild.
  UserRole _currentRole = UserRole.customer;

  // Convenience getters used by the rest of the file.
  bool get _isProvider => _currentRole == UserRole.expert;
  bool get _isCustomer => _currentRole == UserRole.customer;

  // ── Expert inline fields (Step 1, visible when _selectedRole == expert) ──
  String? _businessType;
  final   _idController = TextEditingController(); // ת.ז. / ח.פ.

  // ── Step 2: service details ───────────────────────────────────────────────
  String? _selectedCategory;
  final   _priceController       = TextEditingController();
  final   _descriptionController = TextEditingController();
  bool    _classifying           = false;
  bool?   _isNewCategory;
  List<Map<String, dynamic>> _categories = [];
  StreamSubscription<List<Map<String, dynamic>>>? _categorySub;

  // ── Step 3: tax compliance ────────────────────────────────────────────────
  String? _taxStatus;
  String? _complianceDocUrl;
  String? _complianceDocName;
  bool   _isUploadingDoc = false;
  double _uploadProgress = 0;

  // ── Step 4: profile ───────────────────────────────────────────────────────
  String? _profileImageBase64;
  final   _bioController = TextEditingController();

  // Customers: page 0 → page 3 (skip pages 1–2)
  // Providers: page 0 → 1 → 2 → 3
  int get _totalPages => _isProvider ? 4 : 2;
  static const _profilePageIndex = 3;

  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _categorySub = CategoryService.stream().listen((cats) {
      if (mounted) setState(() => _categories = cats);
    });
  }

  @override
  void dispose() {
    _categorySub?.cancel();
    _pageController.dispose();
    _idController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  void _nextPage() {
    final l10n = AppLocalizations.of(context);

    // Step 0: role validation
    if (_currentPage == 0) {
      if (_isProvider && _businessType == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('יש לבחור סוג עסק'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      if (_isCustomer) {
        // Customers skip service + tax steps
        _pageController.animateToPage(
          _profilePageIndex,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
        );
        setState(() => _currentPage = _profilePageIndex);
        return;
      }
    }

    // Step 1: service details validation
    if (_currentPage == 1) {
      if (_selectedCategory == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.validationCategoryRequired),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      final price = double.tryParse(_priceController.text.trim());
      if (price == null || price <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(price == null
                ? l10n.validationPriceInvalid
                : l10n.validationPricePositive),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    // Step 2: tax compliance validation
    if (_currentPage == 2) {
      if (_taxStatus == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.onboardingTaxStatusRequired),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      if (_complianceDocUrl == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.onboardingDocRequired),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    _pageController.nextPage(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
    setState(() => _currentPage++);
  }

  // ── Finish / Save ─────────────────────────────────────────────────────────

  Future<void> _finish() async {
    setState(() => _isSaving = true);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    try {
      final updates = <String, dynamic>{
        'isCustomer':         _isCustomer,
        'isProvider':         _isProvider,
        'onboardingComplete': true,
      };

      if (_isProvider) {
        updates['serviceType']  = _selectedCategory;
        updates['pricePerHour'] = double.tryParse(_priceController.text.trim()) ?? 0.0;
        updates['businessType'] = _businessType;
        updates['idNumber']     = _idController.text.trim();
        // compliance is NOT in the rules' blocked-field list — safe to write.
        updates['compliance'] = {
          'taxStatus':   _taxStatus,
          'docUrl':      _complianceDocUrl,
          'docName':     _complianceDocName,
          'submittedAt': FieldValue.serverTimestamp(),
          'verified':    false,
        };
        // NOTE: isVerifiedProvider is server-only (blocked in Firestore rules).
        // Do NOT write it from the client.
      }

      if (_bioController.text.trim().isNotEmpty) {
        updates['aboutMe'] = _bioController.text.trim();
      }
      if (_profileImageBase64 != null) {
        updates['profileImage'] = 'data:image/png;base64,$_profileImageBase64';
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update(updates);

      // Notify admin via Trigger Email extension
      try {
        final authUser   = FirebaseAuth.instance.currentUser;
        final userName   = authUser?.displayName ?? 'לא צוין';
        final userEmail  = authUser?.email ?? 'לא צוין';
        final userType   = _isProvider ? 'נותן שירות (ספק)' : 'לקוח';
        final serviceStr = _isProvider ? (_selectedCategory ?? 'לא צוין') : '—';
        final bizStr     = _isProvider ? (_businessType ?? 'לא צוין') : null;
        await FirebaseFirestore.instance.collection('mail').add({
          'to': 'adawiavihai@gmail.com',
          'message': {
            'subject': '🆕 [AnySkill] נרשם $userType: $userName',
            'html': '''<div dir="rtl" style="font-family:Arial;padding:16px">
              <h2>משתמש חדש נרשם ל-AnySkill</h2>
              <p><b>שם:</b> $userName</p>
              <p><b>אימייל:</b> $userEmail</p>
              <p><b>סוג:</b> $userType</p>
              <p><b>תחום:</b> $serviceStr</p>
              ${bizStr != null ? '<p><b>סוג עסק:</b> $bizStr</p>' : ''}
              <p><b>UID:</b> $uid</p>
            </div>''',
          },
        });
      } catch (_) {}

      try {
        await _sendWelcomeMessage(uid, _isProvider);
      } catch (_) {}

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).onboardingError(e.toString())),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Compliance doc upload ─────────────────────────────────────────────────

  Future<void> _pickAndUploadDoc() async {
    final XFile? image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (image == null) return;

    setState(() { _isUploadingDoc = true; _uploadProgress = 0; });

    try {
      final uid   = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
      final ext   = image.name.split('.').last;
      final bytes = await image.readAsBytes();
      final ref   = FirebaseStorage.instance
          .ref()
          .child('compliance_docs/$uid/tax_document.$ext');

      final task = ref.putData(bytes, SettableMetadata(contentType: 'image/$ext'));
      task.snapshotEvents.listen((snap) {
        if (mounted && snap.totalBytes > 0) {
          setState(() => _uploadProgress = snap.bytesTransferred / snap.totalBytes);
        }
      });
      await task;

      final downloadUrl = await ref.getDownloadURL();
      if (mounted) {
        setState(() {
          _complianceDocUrl  = downloadUrl;
          _complianceDocName = image.name;
          _isUploadingDoc    = false;
          _uploadProgress    = 1;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploadingDoc = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)
                .onboardingUploadError(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ── Welcome message ───────────────────────────────────────────────────────

  Future<void> _sendWelcomeMessage(String uid, bool isProvider) async {
    const systemUid = 'anyskill_system';
    final db = FirebaseFirestore.instance;

    final text = isProvider
        ? 'איזה כיף שהצטרפת לנבחרת אנשי המקצוע של AnySkill! 🚀 '
          'המסמכים שלך התקבלו ובביקורת. תקבל עדכון ברגע שהחשבון יאושר. '
          'בינתיים, השלם את הפרופיל שלך כדי להיות מוכן ללקוח הראשון!'
        : 'ברוכים הבאים ל-AnySkill! 🌟 צריכים עזרה במשהו? הגעתם למקום הנכון. '
          'אלפי אנשי מקצוע זמינים עבורכם עכשיו. חיפוש קל, צ\'אט ישיר, '
          'תיאום פשוט ובטוח ישירות מהאפליקציה. במה נתחיל היום?';

    try {
      await db.collection('users').doc(systemUid).set({
        'uid': systemUid, 'name': 'AnySkill', 'profileImage': '',
        'isProvider': false, 'isCustomer': false, 'isOnline': true, 'balance': 0,
      }, SetOptions(merge: true));
    } catch (_) {}

    final ids        = [uid, systemUid]..sort();
    final chatRoomId = ids.join('_');

    await db.collection('chats').doc(chatRoomId).set({
      'users':                  [uid, systemUid],
      'lastMessage':            text.length > 50 ? '${text.substring(0, 50)}...' : text,
      'lastMessageTime':        FieldValue.serverTimestamp(),
      'lastSenderId':           systemUid,
      'unreadCount_$uid':       1,
      'unreadCount_$systemUid': 0,
    }, SetOptions(merge: true));

    await db.collection('chats').doc(chatRoomId).collection('messages').add({
      'senderId':   systemUid,
      'receiverId': uid,
      'message':    text,
      'type':       'text',
      'timestamp':  FieldValue.serverTimestamp(),
      'isRead':     false,
    });
  }

  // ── Profile image picker ──────────────────────────────────────────────────

  Future<void> _pickProfileImage() async {
    final XFile? image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 300,
      maxHeight: 300,
      imageQuality: 50,
    );
    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() => _profileImageBase64 = base64Encode(bytes));
    }
  }

  // ── AI classifier ─────────────────────────────────────────────────────────

  Future<void> _classifyDescription() async {
    final text = _descriptionController.text.trim();
    if (text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('תאר את השירות שלך בכמה מילים לפחות')),
      );
      return;
    }
    setState(() { _classifying = true; _isNewCategory = null; });

    final result = await ProfileSetupService.classifyAndResolve(text);
    if (!mounted) return;

    if (result.categoryName.isEmpty) {
      setState(() => _classifying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('לא הצלחנו לזהות קטגוריה — בחר מהרשימה ידנית'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _selectedCategory = result.categoryName;
      _isNewCategory    = result.isNewCategory;
      _classifying      = false;
      if (result.isNewCategory &&
          !_categories.any((c) => c['name'] == result.categoryName)) {
        _categories = [..._categories, {'name': result.categoryName}];
      }
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildProgressBar(),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics:    const NeverScrollableScrollPhysics(),
                children: [
                  _buildStep1RoleAndExpertFields(),
                  _buildStep2ServiceDetails(),
                  _buildStep3TaxCompliance(),
                  _buildStep4Profile(),
                ],
              ),
            ),
            _buildBottomButton(),
          ],
        ),
      ),
    );
  }

  // ── Progress bar ──────────────────────────────────────────────────────────

  Widget _buildProgressBar() {
    final l10n       = AppLocalizations.of(context);
    final displayStep  = (!_isProvider && _currentPage == _profilePageIndex)
        ? 1
        : _currentPage;
    final displayTotal = _totalPages;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(displayTotal, (i) {
              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  height: 4,
                  decoration: BoxDecoration(
                    color: i <= displayStep ? Colors.black : Colors.grey[200],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.onboardingStep(displayStep + 1, displayTotal),
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // STEP 1 — Role selection + Expert inline fields
  // ══════════════════════════════════════════════════════════════════════════
  //
  // _currentRole is a two-value enum (customer | expert).
  // Customer is the default — no "none" state.
  // Tapping Expert: setState(() { _currentRole = UserRole.expert; })
  //   → full Column rebuild → if (_currentRole == UserRole.expert) block
  //     becomes true → all three expert fields appear immediately.
  // Tapping Customer: opposite — fields disappear.

  Widget _buildStep1RoleAndExpertFields() {
    final l10n = AppLocalizations.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Text(l10n.onboardingWelcome,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(l10n.onboardingWelcomeSub,
              style: TextStyle(color: Colors.grey[600], fontSize: 15)),
          const SizedBox(height: 28),

          // ── Customer card ─────────────────────────────────────────────────
          _RoleCard(
            key:      const ValueKey('card_customer'),
            icon:     Icons.search_rounded,
            title:    l10n.onboardingRoleCustomerTitle,
            subtitle: l10n.onboardingRoleCustomerSub,
            selected: _currentRole == UserRole.customer,
            onTap: () => setState(() {
              _currentRole  = UserRole.customer;
              _businessType = null;
            }),
          ),
          const SizedBox(height: 14),

          // ── Expert card ───────────────────────────────────────────────────
          _RoleCard(
            key:      const ValueKey('card_expert'),
            icon:     Icons.star_outline_rounded,
            title:    l10n.onboardingRoleProviderTitle,
            subtitle: l10n.onboardingRoleProviderSub,
            selected: _currentRole == UserRole.expert,
            onTap: () => setState(() {
              _currentRole = UserRole.expert;
            }),
          ),

          // ── Expert-only fields ────────────────────────────────────────────
          // ONE if-block with a spread.  All three fields live here.
          // setState above guarantees a rebuild; this condition is then true.
          if (_currentRole == UserRole.expert) ...[
            const SizedBox(height: 28),

            // 1. Business type ───────────────────────────────────────────────
            _sectionLabel('סוג עסק'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _businessType,
              isExpanded: true,
              decoration: _inputDecoration('בחר סוג עסק...'),
              items: _kBusinessTypes
                  .map((t) => DropdownMenuItem(
                        value: t,
                        child: Text(t,
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 14)),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _businessType = v),
            ),
            const SizedBox(height: 20),

            // 2. ID / Business number ────────────────────────────────────────
            _sectionLabel('מספר תעודת זהות / ח.פ.'),
            const SizedBox(height: 4),
            Text('נדרש לאימות זהות ועמידה בדרישות חוקיות',
                style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            const SizedBox(height: 8),
            TextField(
              controller: _idController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.right,
              decoration: _inputDecoration('הזן מספר ת.ז. או ח.פ...').copyWith(
                prefixIcon: const Icon(Icons.badge_outlined, color: _kPurple),
              ),
            ),
            const SizedBox(height: 20),

            // 3. AI category classifier ──────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFEEF2FF), Color(0xFFF5F3FF)],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _kPurple.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.smart_toy_rounded, color: _kPurple, size: 18),
                      SizedBox(width: 8),
                      Text('AI זיהוי קטגוריה',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: _kPurple)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _descriptionController,
                    maxLines: 2,
                    textAlign: TextAlign.right,
                    decoration: InputDecoration(
                      hintText:
                          'תאר את השירות שלך... (למשל: אני שרברב מוסמך עם 5 שנות ניסיון)',
                      hintStyle:
                          const TextStyle(fontSize: 13, color: Colors.grey),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kPurple,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: _classifying ? null : _classifyDescription,
                      icon: _classifying
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.auto_awesome_rounded,
                              color: Colors.white, size: 18),
                      label: Text(
                        _classifying ? 'מזהה...' : 'זהה קטגוריה אוטומטית',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  if (_selectedCategory != null && _isNewCategory != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _isNewCategory!
                            ? const Color(0xFFFFF7ED)
                            : const Color(0xFFF0FFF4),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _isNewCategory!
                              ? const Color(0xFFF97316)
                              : const Color(0xFF22C55E),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _isNewCategory!
                                ? Icons.add_circle_outline_rounded
                                : Icons.check_circle_outline_rounded,
                            size: 18,
                            color: _isNewCategory!
                                ? const Color(0xFFF97316)
                                : const Color(0xFF22C55E),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _isNewCategory!
                                      ? 'קטגוריה חדשה נוצרה 🎉'
                                      : 'קטגוריה זוהתה ✓',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _isNewCategory!
                                        ? const Color(0xFFC2410C)
                                        : const Color(0xFF166534),
                                  ),
                                ),
                                Text(_selectedCategory!,
                                    style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
          ], // end if (_currentRole == UserRole.expert)
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // STEP 2 — Service category + price (provider only)
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildStep2ServiceDetails() {
    final l10n       = AppLocalizations.of(context);
    final hasAiResult = _selectedCategory != null && _isNewCategory != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.onboardingServiceTitle,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(l10n.onboardingServiceSub,
              style: TextStyle(color: Colors.grey[600], fontSize: 15)),
          const SizedBox(height: 24),

          // AI pre-fill hint
          if (hasAiResult) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FFF4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF22C55E)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome_rounded,
                      color: Color(0xFF22C55E), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('AI זיהה: $_selectedCategory',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF166534))),
                  ),
                ],
              ),
            ),
          ],

          // Category dropdown
          _sectionLabel(l10n.onboardingCategory),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _selectedCategory != null &&
                    _categories.any((c) => c['name'] == _selectedCategory)
                ? _selectedCategory
                : null,
            isExpanded: true,
            decoration: _inputDecoration(l10n.onboardingCategoryHint),
            items: _categories
                .map((c) => DropdownMenuItem(
                      value: c['name'] as String,
                      child: Text(c['name'], textAlign: TextAlign.right),
                    ))
                .toList(),
            onChanged: (v) =>
                setState(() { _selectedCategory = v; _isNewCategory = false; }),
          ),
          const SizedBox(height: 24),

          // Price
          _sectionLabel(l10n.onboardingPriceLabel),
          const SizedBox(height: 8),
          TextField(
            controller: _priceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.right,
            decoration: _inputDecoration(l10n.onboardingPriceHint)
                .copyWith(prefixText: '₪ '),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.lightbulb_outline, color: Colors.green[700], size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(l10n.onboardingPriceTip,
                      style: TextStyle(color: Colors.green[700], fontSize: 13)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // STEP 3 — Tax compliance (provider only)
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildStep3TaxCompliance() {
    final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _kPurple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.shield_outlined, color: _kPurple, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.onboardingTaxTitle,
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold)),
                    Text(l10n.onboardingTaxSubtitle,
                        style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.verified_user_outlined,
                    color: Colors.blue[700], size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(l10n.onboardingTaxNotice,
                      style: TextStyle(
                          color: Colors.blue[800], fontSize: 13, height: 1.4)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          _sectionLabel(l10n.onboardingTaxStatusLabel),
          const SizedBox(height: 12),
          _TaxStatusCard(
            title: l10n.onboardingTaxBusiness,
            subtitle: l10n.onboardingTaxBusinessSub,
            icon: Icons.business_center_outlined,
            value: 'business',
            selected: _taxStatus == 'business',
            onTap: () => setState(() {
              _taxStatus = 'business';
              _complianceDocUrl  = null;
              _complianceDocName = null;
              _uploadProgress    = 0;
            }),
          ),
          const SizedBox(height: 12),
          _TaxStatusCard(
            title: l10n.onboardingTaxIndividual,
            subtitle: l10n.onboardingTaxIndividualSub,
            icon: Icons.badge_outlined,
            value: 'individual',
            selected: _taxStatus == 'individual',
            onTap: () => setState(() {
              _taxStatus = 'individual';
              _complianceDocUrl  = null;
              _complianceDocName = null;
              _uploadProgress    = 0;
            }),
          ),
          const SizedBox(height: 28),
          if (_taxStatus != null) ...[
            _sectionLabel(_taxStatus == 'business'
                ? l10n.onboardingDocLabelBusiness
                : l10n.onboardingDocLabelIndividual),
            const SizedBox(height: 6),
            Text(
              _taxStatus == 'business'
                  ? l10n.onboardingDocHintBusiness
                  : l10n.onboardingDocHintIndividual,
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _isUploadingDoc ? null : _pickAndUploadDoc,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _complianceDocUrl != null
                      ? _kGreen.withValues(alpha: 0.06)
                      : Colors.grey[50],
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _complianceDocUrl != null
                        ? _kGreen.withValues(alpha: 0.4)
                        : Colors.grey.shade300,
                    width: _complianceDocUrl != null ? 1.5 : 1,
                  ),
                ),
                child: _isUploadingDoc
                    ? _buildUploadProgress(l10n)
                    : _complianceDocUrl != null
                        ? _buildDocUploaded(l10n)
                        : _buildDocPrompt(l10n),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUploadProgress(AppLocalizations l10n) => Column(children: [
        const SizedBox(height: 4),
        SizedBox(
          height: 36, width: 36,
          child: CircularProgressIndicator(
            value: _uploadProgress > 0 ? _uploadProgress : null,
            strokeWidth: 3, color: _kPurple,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _uploadProgress > 0
              ? '${(_uploadProgress * 100).toInt()}%'
              : l10n.onboardingUploading,
          style: TextStyle(color: Colors.grey[600], fontSize: 13),
        ),
      ]);

  Widget _buildDocUploaded(AppLocalizations l10n) => Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _kGreen.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: const Icon(Icons.check_circle_rounded, color: _kGreen, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l10n.onboardingDocUploaded,
                style: const TextStyle(
                    color: _kGreen, fontWeight: FontWeight.bold, fontSize: 14)),
            if (_complianceDocName != null)
              Text(_complianceDocName!,
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  overflow: TextOverflow.ellipsis),
          ]),
        ),
        TextButton(
          onPressed: _pickAndUploadDoc,
          child: Text(l10n.onboardingDocReplace,
              style: const TextStyle(fontSize: 12, color: _kPurple)),
        ),
      ]);

  Widget _buildDocPrompt(AppLocalizations l10n) => Column(children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _kPurple.withValues(alpha: 0.08), shape: BoxShape.circle),
          child: const Icon(Icons.folder_open_outlined, color: _kPurple, size: 28),
        ),
        const SizedBox(height: 10),
        Text(l10n.onboardingDocUploadPrompt,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 4),
        Text(l10n.onboardingDocUploadSub,
            style: TextStyle(color: Colors.grey[500], fontSize: 12)),
      ]);

  // ══════════════════════════════════════════════════════════════════════════
  // STEP 4 — Profile photo + bio
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildStep4Profile() {
    final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.onboardingProfileTitle,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(l10n.onboardingProfileSub,
              style: TextStyle(color: Colors.grey[600], fontSize: 15)),
          const SizedBox(height: 32),
          Center(
            child: GestureDetector(
              onTap: _pickProfileImage,
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 56,
                    backgroundColor: Colors.grey[100],
                    backgroundImage: _profileImageBase64 != null
                        ? MemoryImage(base64Decode(_profileImageBase64!))
                            as ImageProvider
                        : null,
                    child: _profileImageBase64 == null
                        ? Icon(Icons.person, size: 56, color: Colors.grey[400])
                        : null,
                  ),
                  Positioned(
                    bottom: 0, right: 0,
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: Colors.black,
                      child: const Icon(Icons.camera_alt,
                          size: 16, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: _pickProfileImage,
              child: Text(l10n.onboardingAddPhoto,
                  style: const TextStyle(color: Colors.black)),
            ),
          ),
          const SizedBox(height: 24),
          _sectionLabel(l10n.onboardingBioLabel),
          const SizedBox(height: 8),
          TextField(
            controller: _bioController,
            maxLines: 4,
            textAlign: TextAlign.right,
            decoration: _inputDecoration(l10n.onboardingBioHint),
          ),
        ],
      ),
    );
  }

  // ── Bottom button ─────────────────────────────────────────────────────────

  Widget _buildBottomButton() {
    final l10n       = AppLocalizations.of(context);
    final isLastPage = _currentPage == _profilePageIndex;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLastPage && !_isSaving)
            TextButton(
              onPressed: _finish,
              child: Text(l10n.onboardingSkipFinish,
                  style: const TextStyle(color: Colors.grey)),
            ),
          const SizedBox(height: 4),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: _isSaving ? null : (isLastPage ? _finish : _nextPage),
            child: _isSaving
                ? const SizedBox(
                    height: 22, width: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text(
                    isLastPage ? l10n.onboardingStart : l10n.onboardingNext,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold),
                  ),
          ),
        ],
      ),
    );
  }

  // ── Shared style helpers ──────────────────────────────────────────────────

  static Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
      );

  static InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// _RoleCard
// ══════════════════════════════════════════════════════════════════════════════
//
// `selected` drives the visual state:
//   true  → _kPurple background, white text, check icon
//   false → grey background, black text

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    super.key,          // ValueKey passed from parent
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData     icon;
  final String       title;
  final String       subtitle;
  final bool         selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: selected ? _kPurple : Colors.grey[50],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? _kPurple : Colors.grey[200]!,
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [BoxShadow(
                  color: _kPurple.withValues(alpha: 0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 4))]
              : [],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white.withValues(alpha: 0.2)
                    : Colors.grey[200],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon,
                  color: selected ? Colors.white : Colors.black, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: selected ? Colors.white : Colors.black)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 13,
                          color: selected
                              ? Colors.white70
                              : Colors.grey[600])),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle, color: Colors.white, size: 22),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _TaxStatusCard
// ══════════════════════════════════════════════════════════════════════════════

class _TaxStatusCard extends StatelessWidget {
  const _TaxStatusCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final String       title;
  final String       subtitle;
  final IconData     icon;
  final String       value;
  final bool         selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? _kPurple.withValues(alpha: 0.06) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? _kPurple : Colors.grey.shade200,
            width: selected ? 1.5 : 1,
          ),
          boxShadow: selected
              ? [BoxShadow(
                  color: _kPurple.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2))]
              : [BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 4)],
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 22, height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? _kPurple : Colors.transparent,
                border: Border.all(
                  color: selected ? _kPurple : Colors.grey.shade300,
                  width: 2,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check_rounded, color: Colors.white, size: 14)
                  : null,
            ),
            const SizedBox(width: 14),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: selected
                    ? _kPurple.withValues(alpha: 0.1)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon,
                  color: selected ? _kPurple : Colors.grey[600], size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: selected ? _kPurple : Colors.black87)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
