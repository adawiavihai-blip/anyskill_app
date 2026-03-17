import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:async';
import 'dart:convert';
import '../services/category_service.dart';
import 'home_screen.dart';
import '../l10n/app_localizations.dart';

// ── Palette ────────────────────────────────────────────────────────────────────
const _kPurple = Color(0xFF6366F1);
const _kGreen  = Color(0xFF10B981);

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int  _currentPage = 0;
  bool _isSaving    = false;

  // Step 1 — role
  bool _isCustomer = true;
  bool _isProvider = false;

  // Step 2 — provider details
  String? _selectedCategory;
  final _priceController = TextEditingController();
  List<Map<String, dynamic>> _categories = [];
  StreamSubscription<List<Map<String, dynamic>>>? _categorySub;

  // Step 3 — tax compliance (provider only)
  String? _taxStatus;          // 'business' | 'individual'
  String? _complianceDocUrl;   // Firebase Storage download URL
  String? _complianceDocName;
  bool   _isUploadingDoc  = false;
  double _uploadProgress  = 0;

  // Step 4 — profile
  String? _profileImageBase64;
  final _bioController = TextEditingController();

  // Pages: [role, service, tax, profile]
  // Customers jump: 0 → 3
  // Providers go:   0 → 1 → 2 → 3
  int get _totalPages => _isProvider ? 4 : 2;

  // Index of the profile page in the PageView
  static const _profilePageIndex = 3;

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
    _priceController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  void _nextPage() {
    final l10n = AppLocalizations.of(context);

    // Step 1 — role
    if (_currentPage == 0) {
      if (!_isCustomer && !_isProvider) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.validationRoleRequired)),
        );
        return;
      }
      if (!_isProvider) {
        // Customer-only → jump straight to profile page
        _pageController.animateToPage(_profilePageIndex,
            duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
        setState(() => _currentPage = _profilePageIndex);
        return;
      }
    }

    // Step 2 — service details
    if (_currentPage == 1) {
      if (_selectedCategory == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.validationCategoryRequired), backgroundColor: Colors.orange),
        );
        return;
      }
      final price = double.tryParse(_priceController.text.trim());
      if (price == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.validationPriceInvalid), backgroundColor: Colors.orange),
        );
        return;
      }
      if (price <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.validationPricePositive), backgroundColor: Colors.orange),
        );
        return;
      }
    }

    // Step 3 — tax compliance
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
        duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
    setState(() => _currentPage++);
  }

  // ── Finish / Save ─────────────────────────────────────────────────────────

  Future<void> _finish() async {
    setState(() => _isSaving = true);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    try {
      final Map<String, dynamic> updates = {
        'isCustomer':        _isCustomer,
        'isProvider':        _isProvider,
        'onboardingComplete': true,
      };

      if (_isProvider) {
        updates['serviceType']   = _selectedCategory;
        updates['pricePerHour']  = double.tryParse(_priceController.text.trim()) ?? 0.0;
        // Hard-block: unverified until admin approves
        updates['isVerifiedProvider'] = false;
        updates['compliance'] = {
          'taxStatus':   _taxStatus,
          'docUrl':      _complianceDocUrl,
          'docName':     _complianceDocName,
          'submittedAt': FieldValue.serverTimestamp(),
          'verified':    false,
        };
      }

      if (_bioController.text.trim().isNotEmpty) {
        updates['aboutMe'] = _bioController.text.trim();
      }
      if (_profileImageBase64 != null) {
        updates['profileImage'] = 'data:image/png;base64,$_profileImageBase64';
      }

      await FirebaseFirestore.instance.collection('users').doc(uid).update(updates);

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
          SnackBar(content: Text(AppLocalizations.of(context).onboardingError(e.toString()))),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Compliance doc upload ─────────────────────────────────────────────────

  Future<void> _pickAndUploadDoc() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (image == null) return;

    setState(() {
      _isUploadingDoc = true;
      _uploadProgress = 0;
    });

    try {
      final uid   = FirebaseAuth.instance.currentUser?.uid ?? 'unknown';
      final ext   = image.name.split('.').last;
      final bytes = await image.readAsBytes();

      final ref = FirebaseStorage.instance
          .ref()
          .child('compliance_docs')
          .child('$uid/tax_document.$ext');

      final task = ref.putData(
        bytes,
        SettableMetadata(contentType: 'image/$ext'),
      );

      task.snapshotEvents.listen((snap) {
        if (mounted && snap.totalBytes > 0) {
          setState(() => _uploadProgress = snap.bytesTransferred / snap.totalBytes);
        }
      });

      await task;
      final url = await ref.getDownloadURL();

      if (mounted) {
        setState(() {
          _complianceDocUrl  = url;
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
            content: Text(AppLocalizations.of(context).onboardingUploadError(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ── Welcome message ───────────────────────────────────────────────────────

  Future<void> _sendWelcomeMessage(String uid, bool isProvider) async {
    const systemUid = 'anyskill_system';
    final firestore  = FirebaseFirestore.instance;

    const customerMsg =
        'ברוכים הבאים ל-AnySkill! 🌟 צריכים עזרה במשהו? הגעתם למקום הנכון. '
        'אלפי אנשי מקצוע זמינים עבורכם עכשיו כדי להפוך כל תוכנית למציאות. '
        'חיפוש קל: מצאו את איש המקצוע המדויק לפי דירוג ומיקום. '
        "צ'אט ישיר: שלחו הודעה וקבלו מענה מהיר. "
        'סוגרים ויוצאים לדרך: תיאום פשוט ובטוח ישירות מהאפליקציה. '
        'במה נתחיל היום?';

    const providerMsg =
        'איזה כיף שהצטרפת לנבחרת אנשי המקצוע של AnySkill! 🚀 '
        'המסמכים שלך התקבלו ובביקורת. תקבל עדכון ברגע שהחשבון יאושר. '
        'בינתיים, השלם את הפרופיל שלך כדי להיות מוכן ללקוח הראשון!';

    final welcomeText = isProvider ? providerMsg : customerMsg;

    try {
      await firestore.collection('users').doc(systemUid).set({
        'uid':       systemUid,
        'name':      'AnySkill',
        'profileImage': '',
        'isProvider': false,
        'isCustomer': false,
        'isOnline':  true,
        'balance':   0,
      }, SetOptions(merge: true));
    } catch (_) {}

    final ids        = [uid, systemUid]..sort();
    final chatRoomId = ids.join('_');

    await firestore.collection('chats').doc(chatRoomId).set({
      'users':           [uid, systemUid],
      'lastMessage':     welcomeText.length > 50 ? '${welcomeText.substring(0, 50)}...' : welcomeText,
      'lastMessageTime': FieldValue.serverTimestamp(),
      'lastSenderId':    systemUid,
      'unreadCount_$uid': 1,
      'unreadCount_$systemUid': 0,
    }, SetOptions(merge: true));

    await firestore
        .collection('chats').doc(chatRoomId)
        .collection('messages').add({
      'senderId':   systemUid,
      'receiverId': uid,
      'message':    welcomeText,
      'type':       'text',
      'timestamp':  FieldValue.serverTimestamp(),
      'isRead':     false,
    });
  }

  // ── Profile image picker ──────────────────────────────────────────────────

  Future<void> _pickProfileImage() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
        source: ImageSource.gallery, maxWidth: 300, maxHeight: 300, imageQuality: 50);
    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() => _profileImageBase64 = base64Encode(bytes));
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

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
                  _buildStep1(),      // page 0 — role
                  _buildStep2(),      // page 1 — service details (provider)
                  _buildStep3Tax(),   // page 2 — tax compliance (provider)
                  _buildStep4Profile(), // page 3 — photo + bio
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
    final l10n = AppLocalizations.of(context);

    // Customers: page 0 → displayStep 0, page 3 → displayStep 1
    int displayStep = (!_isProvider && _currentPage == _profilePageIndex) ? 1 : _currentPage;
    int displayTotal = _totalPages;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(displayTotal, (i) {
              final active = i <= displayStep;
              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  height: 4,
                  decoration: BoxDecoration(
                    color: active ? Colors.black : Colors.grey[200],
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

  // ── Step 1: Role selection ────────────────────────────────────────────────

  Widget _buildStep1() {
    final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Text(l10n.onboardingWelcome,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(l10n.onboardingWelcomeSub,
              style: TextStyle(color: Colors.grey[600], fontSize: 15)),
          const SizedBox(height: 40),
          _RoleCard(
            icon:     Icons.search,
            title:    l10n.onboardingRoleCustomerTitle,
            subtitle: l10n.onboardingRoleCustomerSub,
            selected: _isCustomer,
            onTap:    () => setState(() => _isCustomer = !_isCustomer),
          ),
          const SizedBox(height: 16),
          _RoleCard(
            icon:     Icons.star_outline,
            title:    l10n.onboardingRoleProviderTitle,
            subtitle: l10n.onboardingRoleProviderSub,
            selected: _isProvider,
            onTap:    () => setState(() => _isProvider = !_isProvider),
          ),
          const SizedBox(height: 16),
          if (_isCustomer && _isProvider)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue[700], size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.onboardingBothRoles,
                      style: TextStyle(color: Colors.blue[700], fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Step 2: Provider service details ──────────────────────────────────────

  Widget _buildStep2() {
    final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Text(l10n.onboardingServiceTitle,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(l10n.onboardingServiceSub,
              style: TextStyle(color: Colors.grey[600], fontSize: 15)),
          const SizedBox(height: 32),
          Text(l10n.onboardingCategory,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _selectedCategory,
            isExpanded: true,
            decoration: InputDecoration(
              hintText: l10n.onboardingCategoryHint,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            items: _categories
                .map((c) => DropdownMenuItem(
                    value: c['name'] as String,
                    child: Text(c['name'], textAlign: TextAlign.right)))
                .toList(),
            onChanged: (val) => setState(() => _selectedCategory = val),
          ),
          const SizedBox(height: 24),
          Text(l10n.onboardingPriceLabel,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          TextField(
            controller: _priceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.right,
            decoration: InputDecoration(
              hintText: l10n.onboardingPriceHint,
              prefixText: '₪ ',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
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

  // ── Step 3: Tax compliance (provider only) ────────────────────────────────

  Widget _buildStep3Tax() {
    final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),

          // ── Header ────────────────────────────────────────────────────────
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
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    Text(l10n.onboardingTaxSubtitle,
                        style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // ── Safety notice ─────────────────────────────────────────────────
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
                Icon(Icons.verified_user_outlined, color: Colors.blue[700], size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(l10n.onboardingTaxNotice,
                      style: TextStyle(color: Colors.blue[800], fontSize: 13, height: 1.4)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // ── Tax status selection ──────────────────────────────────────────
          Text(l10n.onboardingTaxStatusLabel,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 12),

          _TaxStatusCard(
            title:    l10n.onboardingTaxBusiness,
            subtitle: l10n.onboardingTaxBusinessSub,
            icon:     Icons.business_center_outlined,
            value:    'business',
            selected: _taxStatus == 'business',
            onTap:    () => setState(() {
              _taxStatus = 'business';
              // Reset doc if switching type
              _complianceDocUrl  = null;
              _complianceDocName = null;
              _uploadProgress    = 0;
            }),
          ),
          const SizedBox(height: 12),
          _TaxStatusCard(
            title:    l10n.onboardingTaxIndividual,
            subtitle: l10n.onboardingTaxIndividualSub,
            icon:     Icons.badge_outlined,
            value:    'individual',
            selected: _taxStatus == 'individual',
            onTap:    () => setState(() {
              _taxStatus = 'individual';
              _complianceDocUrl  = null;
              _complianceDocName = null;
              _uploadProgress    = 0;
            }),
          ),
          const SizedBox(height: 28),

          // ── Document upload (shown once tax status is selected) ───────────
          if (_taxStatus != null) ...[
            Text(
              _taxStatus == 'business'
                  ? l10n.onboardingDocLabelBusiness
                  : l10n.onboardingDocLabelIndividual,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(
              _taxStatus == 'business'
                  ? l10n.onboardingDocHintBusiness
                  : l10n.onboardingDocHintIndividual,
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
            const SizedBox(height: 12),

            // Upload box
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
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildUploadProgress(AppLocalizations l10n) {
    return Column(
      children: [
        const SizedBox(height: 4),
        SizedBox(
          height: 36,
          width: 36,
          child: CircularProgressIndicator(
            value: _uploadProgress > 0 ? _uploadProgress : null,
            strokeWidth: 3,
            color: _kPurple,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _uploadProgress > 0
              ? '${(_uploadProgress * 100).toInt()}%'
              : l10n.onboardingUploading,
          style: TextStyle(color: Colors.grey[600], fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildDocUploaded(AppLocalizations l10n) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _kGreen.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_circle_rounded, color: _kGreen, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.onboardingDocUploaded,
                  style: const TextStyle(
                      color: _kGreen, fontWeight: FontWeight.bold, fontSize: 14)),
              if (_complianceDocName != null)
                Text(_complianceDocName!,
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        TextButton(
          onPressed: _pickAndUploadDoc,
          child: Text(l10n.onboardingDocReplace,
              style: const TextStyle(fontSize: 12, color: _kPurple)),
        ),
      ],
    );
  }

  Widget _buildDocPrompt(AppLocalizations l10n) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _kPurple.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.folder_open_outlined, color: _kPurple, size: 28),
        ),
        const SizedBox(height: 10),
        Text(l10n.onboardingDocUploadPrompt,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 4),
        Text(l10n.onboardingDocUploadSub,
            style: TextStyle(color: Colors.grey[500], fontSize: 12)),
      ],
    );
  }

  // ── Step 4: Profile photo + bio ───────────────────────────────────────────

  Widget _buildStep4Profile() {
    final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Text(l10n.onboardingProfileTitle,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
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
                        ? MemoryImage(base64Decode(_profileImageBase64!)) as ImageProvider
                        : null,
                    child: _profileImageBase64 == null
                        ? Icon(Icons.person, size: 56, color: Colors.grey[400])
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: Colors.black,
                      child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
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
          Text(l10n.onboardingBioLabel,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          TextField(
            controller: _bioController,
            maxLines: 4,
            textAlign: TextAlign.right,
            decoration: InputDecoration(
              hintText: l10n.onboardingBioHint,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom button ─────────────────────────────────────────────────────────

  Widget _buildBottomButton() {
    final l10n      = AppLocalizations.of(context);
    final isLastPage = _currentPage == _profilePageIndex;

    // For providers: finish is blocked until the compliance doc is uploaded
    // (validated in _nextPage for step 3, but the finish button itself is fine)
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: _isSaving ? null : (isLastPage ? _finish : _nextPage),
            child: _isSaving
                ? const SizedBox(
                    height: 22, width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(
                    isLastPage ? l10n.onboardingStart : l10n.onboardingNext,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Reusable role card ─────────────────────────────────────────────────────────

class _RoleCard extends StatelessWidget {
  final IconData    icon;
  final String      title;
  final String      subtitle;
  final bool        selected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color:  selected ? Colors.black : Colors.grey[50],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? Colors.black : Colors.grey[200]!,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: selected ? Colors.white12 : Colors.grey[200],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: selected ? Colors.white : Colors.black, size: 24),
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
                          color: selected ? Colors.white70 : Colors.grey[600])),
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

// ── Tax status card ────────────────────────────────────────────────────────────

class _TaxStatusCard extends StatelessWidget {
  final String       title;
  final String       subtitle;
  final IconData     icon;
  final String       value;
  final bool         selected;
  final VoidCallback onTap;

  const _TaxStatusCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.selected,
    required this.onTap,
  });

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
            color:  selected ? _kPurple : Colors.grey.shade200,
            width:  selected ? 1.5 : 1,
          ),
          boxShadow: selected
              ? [BoxShadow(color: _kPurple.withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, 2))]
              : [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4)],
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 22, height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color:  selected ? _kPurple : Colors.transparent,
                border: Border.all(
                    color:  selected ? _kPurple : Colors.grey.shade300, width: 2),
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
              child: Icon(icon, color: selected ? _kPurple : Colors.grey[600], size: 20),
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
