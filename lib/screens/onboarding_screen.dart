import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:typed_data';
import '../constants.dart';
import 'home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isSaving = false;

  // Step 1 — role
  bool _isCustomer = true;
  bool _isProvider = false;

  // Step 2 — provider details
  String? _selectedCategory;
  final _priceController = TextEditingController();

  // Step 3 — profile
  String? _profileImageBase64;
  final _bioController = TextEditingController();

  int get _totalPages => _isProvider ? 3 : 2;

  void _nextPage() {
    if (_currentPage == 0) {
      if (!_isCustomer && !_isProvider) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("יש לבחור לפחות תפקיד אחד")),
        );
        return;
      }
      // If customer-only, skip step 2
      if (!_isProvider) {
        _pageController.animateToPage(2,
            duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
        setState(() => _currentPage = 2);
        return;
      }
    }
    if (_currentPage == 1) {
      if (_selectedCategory == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("נא לבחור תחום התמחות"), backgroundColor: Colors.orange),
        );
        return;
      }
      final price = double.tryParse(_priceController.text.trim());
      if (price == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("המחיר חייב להיות מספר תקין"), backgroundColor: Colors.orange),
        );
        return;
      }
      if (price <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("המחיר חייב להיות גדול מ-0"), backgroundColor: Colors.orange),
        );
        return;
      }
    }
    _pageController.nextPage(
        duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
    setState(() => _currentPage++);
  }

  Future<void> _finish() async {
    setState(() => _isSaving = true);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    try {
      final Map<String, dynamic> updates = {
        'isCustomer': _isCustomer,
        'isProvider': _isProvider,
        'onboardingComplete': true,
      };

      if (_isProvider) {
        updates['serviceType'] = _selectedCategory;
        updates['pricePerHour'] =
            double.tryParse(_priceController.text.trim()) ?? 0.0;
      }

      if (_bioController.text.trim().isNotEmpty) {
        updates['aboutMe'] = _bioController.text.trim();
      }

      if (_profileImageBase64 != null) {
        updates['profileImage'] =
            'data:image/png;base64,$_profileImageBase64';
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update(updates);

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("שגיאה: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _pickProfileImage() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 300,
        maxHeight: 300,
        imageQuality: 50);
    if (image != null) {
      Uint8List bytes = await image.readAsBytes();
      setState(() => _profileImageBase64 = base64Encode(bytes));
    }
  }

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
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildStep1(),
                  _buildStep2(),
                  _buildStep3(),
                ],
              ),
            ),
            _buildBottomButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    // Compute effective step index for display (0-based out of _totalPages)
    int displayStep = _currentPage == 2 && !_isProvider ? 1 : _currentPage;
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
            'שלב ${displayStep + 1} מתוך $displayTotal',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  // ── Step 1: Role selection ────────────────────────────────────────────────
  Widget _buildStep1() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          const Text('ברוך הבא ל-AnySkill! 👋',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('ספר לנו מי אתה כדי שנוכל להתאים את החוויה',
              style: TextStyle(color: Colors.grey[600], fontSize: 15)),
          const SizedBox(height: 40),
          _RoleCard(
            icon: Icons.search,
            title: 'אני מחפש שירות',
            subtitle: 'אני רוצה להזמין מומחים לצרכים שלי',
            selected: _isCustomer,
            onTap: () => setState(() => _isCustomer = !_isCustomer),
          ),
          const SizedBox(height: 16),
          _RoleCard(
            icon: Icons.star_outline,
            title: 'אני נותן שירות',
            subtitle: 'יש לי מיומנות ואני רוצה לעבוד דרך AnySkill',
            selected: _isProvider,
            onTap: () => setState(() => _isProvider = !_isProvider),
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
                      'מעולה! תוכל גם להזמין וגם לתת שירות.',
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

  // ── Step 2: Provider details ──────────────────────────────────────────────
  Widget _buildStep2() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          const Text('פרטי השירות שלך',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('מה תחום ההתמחות שלך ומה המחיר שלך לשעה?',
              style: TextStyle(color: Colors.grey[600], fontSize: 15)),
          const SizedBox(height: 32),
          const Text('תחום התמחות',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _selectedCategory,
            isExpanded: true,
            decoration: InputDecoration(
              hintText: 'בחר תחום...',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            items: APP_CATEGORIES
                .map((c) => DropdownMenuItem(
                    value: c['name'] as String,
                    child: Text(c['name'], textAlign: TextAlign.right)))
                .toList(),
            onChanged: (val) => setState(() => _selectedCategory = val),
          ),
          const SizedBox(height: 24),
          const Text('מחיר לשעה (₪)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          TextField(
            controller: _priceController,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.right,
            decoration: InputDecoration(
              hintText: 'למשל: 150',
              prefixText: '₪ ',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                  child: Text(
                    'המחיר הממוצע בקטגוריה זו הוא ₪100–₪200 לשעה.',
                    style: TextStyle(color: Colors.green[700], fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 3: Profile photo + bio ───────────────────────────────────────────
  Widget _buildStep3() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          const Text('הפרופיל שלך',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('תמונה ותיאור קצר עוזרים לאנשים לסמוך עליך',
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
                    bottom: 0,
                    right: 0,
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
              child: const Text('הוסף תמונת פרופיל',
                  style: TextStyle(color: Colors.black)),
            ),
          ),
          const SizedBox(height: 24),
          const Text('כמה מילים עליך (אופציונלי)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          TextField(
            controller: _bioController,
            maxLines: 4,
            textAlign: TextAlign.right,
            decoration: InputDecoration(
              hintText: 'ספר קצת על עצמך...',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomButton() {
    final isLastPage = _currentPage == 2;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLastPage && !_isSaving)
            TextButton(
              onPressed: _finish,
              child: const Text('דלג ולחץ לסיום',
                  style: TextStyle(color: Colors.grey)),
            ),
          const SizedBox(height: 4),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: _isSaving
                ? null
                : isLastPage
                    ? _finish
                    : _nextPage,
            child: _isSaving
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text(
                    isLastPage ? 'התחל להשתמש ב-AnySkill' : 'המשך',
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
}

// ── Reusable role card ────────────────────────────────────────────────────────
class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
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
          color: selected ? Colors.black : Colors.grey[50],
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
              child:
                  Icon(icon, color: selected ? Colors.white : Colors.black, size: 24),
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
