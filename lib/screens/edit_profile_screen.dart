import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import '../services/category_service.dart';

class EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  const EditProfileScreen({super.key, required this.userData});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late TextEditingController _nameController;
  late TextEditingController _aboutController;
  late TextEditingController _priceController;
  
  String? _selectedCategory;       // kept for backward compat but unused in save
  String? _selectedMainCatId;       // doc ID of selected main category
  String? _selectedSubCatId;        // doc ID of selected sub-category (nullable)
  List<Map<String, dynamic>> _mainCategories = [];
  List<Map<String, dynamic>> _subCategories  = []; // subs for selected main

  String? _profileImageUrl;
  List<dynamic> _galleryImages = [];
  bool _isLoading = false;

  bool _isCustomer = false;
  bool _isProvider = false;

  List<Map<String, dynamic>> _categories = [];
  late StreamSubscription<List<Map<String, dynamic>>> _categorySub;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.userData['name']);
    _aboutController = TextEditingController(text: widget.userData['aboutMe'] ?? widget.userData['bio'] ?? "");
    _priceController = TextEditingController(text: (widget.userData['pricePerHour'] ?? "0").toString());
    _galleryImages = List.from(widget.userData['gallery'] ?? []);
    _profileImageUrl = widget.userData['profileImage'];
    
    _isCustomer = widget.userData['isCustomer'] ?? true;
    _isProvider = widget.userData['isProvider'] ?? false;

    _selectedCategory = widget.userData['serviceType'] as String?;

    _categorySub = CategoryService.stream().listen((cats) {
      if (!mounted) return;
      final mains = cats.where((c) => (c['parentId'] as String? ?? '').isEmpty).toList();
      final serviceType = widget.userData['serviceType'] as String?;

      // Resolve existing serviceType into main-category ID + optional sub-category ID
      final subMatch = cats.firstWhere(
        (c) => c['name'] == serviceType && (c['parentId'] as String? ?? '').isNotEmpty,
        orElse: () => <String, dynamic>{},
      );
      String? mainId, subId;
      if (subMatch.isNotEmpty) {
        subId  = subMatch['id']       as String?;
        mainId = subMatch['parentId'] as String?;
      } else {
        final mainMatch = mains.firstWhere(
          (c) => c['name'] == serviceType,
          orElse: () => <String, dynamic>{},
        );
        mainId = mainMatch.isNotEmpty ? mainMatch['id'] as String? : null;
      }

      final subs = mainId != null
          ? cats.where((c) => c['parentId'] == mainId).toList()
          : <Map<String, dynamic>>[];

      setState(() {
        _categories        = cats;
        _mainCategories    = mains;
        _selectedMainCatId = _selectedMainCatId ?? mainId;
        _subCategories     = subs;
        _selectedSubCatId  = _selectedSubCatId ?? subId;
      });
    });
  }

  @override
  void dispose() {
    _categorySub.cancel();
    _nameController.dispose();
    _aboutController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _pickProfileImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery, maxWidth: 300, maxHeight: 300, imageQuality: 50);

    if (image != null) {
      Uint8List imageBytes = await image.readAsBytes();
      setState(() {
        _profileImageUrl = "data:image/png;base64,${base64Encode(imageBytes)}";
      });
    }
  }

  Future<void> _pickAndCompressGalleryImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery, maxWidth: 600, maxHeight: 600);

    if (image != null) {
      setState(() => _isLoading = true);
      Uint8List imageBytes = await image.readAsBytes();
      // דחיסה קלה לטובת ביצועים ב-Web
      if (imageBytes.length > 500000) {
        // אם התמונה גדולה מדי, נדחוס אותה במידת הצורך (אופציונלי ב-Web)
      }
      setState(() => _galleryImages.add(base64Encode(imageBytes)));
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("נא להזין שם"), backgroundColor: Colors.orange));
      return;
    }
    if (name.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("השם חייב להכיל לפחות 2 תווים"), backgroundColor: Colors.orange));
      return;
    }

    if (!_isCustomer && !_isProvider) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("יש לבחור לפחות תפקיד אחד")));
      return;
    }

    if (_isProvider) {
      if (_selectedCategory == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("נא לבחור תחום התמחות"), backgroundColor: Colors.orange));
        return;
      }
      final price = double.tryParse(_priceController.text.trim());
      if (price == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("המחיר חייב להיות מספר תקין"), backgroundColor: Colors.orange));
        return;
      }
      if (price <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("המחיר חייב להיות גדול מ-0"), backgroundColor: Colors.orange));
        return;
      }
    }

    setState(() => _isLoading = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      // Resolve the most-specific category name (sub → main → null)
      String? serviceTypeName;
      if (_selectedSubCatId != null) {
        final sub = _categories.firstWhere(
          (c) => c['id'] == _selectedSubCatId,
          orElse: () => <String, dynamic>{},
        );
        serviceTypeName = sub.isNotEmpty ? sub['name'] as String? : null;
      } else if (_selectedMainCatId != null) {
        final main = _mainCategories.firstWhere(
          (c) => c['id'] == _selectedMainCatId,
          orElse: () => <String, dynamic>{},
        );
        serviceTypeName = main.isNotEmpty ? main['name'] as String? : null;
      }

      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'name': _nameController.text.trim(),
        'serviceType':   _isProvider ? serviceTypeName : 'לקוח',
        'subCategoryId': _isProvider ? _selectedSubCatId : null,
        'pricePerHour': double.tryParse(_priceController.text) ?? 0.0,
        'aboutMe': _aboutController.text.trim(),
        'profileImage': _profileImageUrl,
        'gallery': _galleryImages,
        'isCustomer': _isCustomer,
        'isProvider': _isProvider,
      });
      if (mounted) {
        navigator.pop();
        messenger.showSnackBar(const SnackBar(backgroundColor: Colors.green, content: Text("הפרופיל עודכן בהצלחה!")));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text("שגיאה בשמירה: $e")));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("עריכת פרופיל Elite", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [IconButton(onPressed: _saveProfile, icon: const Icon(Icons.check, color: Colors.blue, size: 30))],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(25),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // --- צילום תמונת פרופיל ---
                Center(
                  child: GestureDetector(
                    onTap: _pickProfileImage,
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 55,
                          backgroundColor: Colors.grey[200],
                          backgroundImage: (_profileImageUrl != null && _profileImageUrl!.isNotEmpty)
                              ? (_profileImageUrl!.startsWith('http') 
                                  ? NetworkImage(_profileImageUrl!) 
                                  : MemoryImage(base64Decode(_profileImageUrl!.split(',').last)) as ImageProvider)
                              : null,
                          child: (_profileImageUrl == null || _profileImageUrl!.isEmpty)
                              ? const Icon(Icons.person, size: 50, color: Colors.grey) : null,
                        ),
                        Positioned(bottom: 0, right: 0, child: CircleAvatar(radius: 18, backgroundColor: Colors.blue, child: const Icon(Icons.camera_alt, size: 18, color: Colors.white))),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 30),

                const Text("שם מלא", style: TextStyle(fontWeight: FontWeight.bold)),
                TextField(controller: _nameController, textAlign: TextAlign.right, decoration: const InputDecoration(hintText: "איך יקראו לך באפליקציה?")),
                
                const SizedBox(height: 25),
                
                const Text("הגדרת תפקיד", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FilterChip(
                      label: const Text("נותן שירות"),
                      selected: _isProvider,
                      onSelected: (val) => setState(() => _isProvider = val),
                      selectedColor: Colors.green[100],
                    ),
                    const SizedBox(width: 10),
                    FilterChip(
                      label: const Text("לקוח"),
                      selected: _isCustomer,
                      onSelected: (val) => setState(() => _isCustomer = val),
                      selectedColor: Colors.blue[100],
                    ),
                  ],
                ),

                if (_isProvider) ...[
                  const SizedBox(height: 25),
                  // ── Main Category dropdown ──────────────────────────────
                  const Text("תחום התמחות (ראשי)", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: _mainCategories.any((c) => c['id'] == _selectedMainCatId) ? _selectedMainCatId : null,
                    hint: const Text("בחר תחום", textAlign: TextAlign.right),
                    items: _mainCategories.map((c) => DropdownMenuItem(
                      value: c['id'] as String,
                      child: Text(c['name'] as String? ?? '', textAlign: TextAlign.right),
                    )).toList(),
                    onChanged: (val) => setState(() {
                      _selectedMainCatId = val;
                      _selectedSubCatId  = null;
                      _subCategories = _categories.where((c) => c['parentId'] == val).toList();
                    }),
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                  ),
                  // ── Sub-Category dropdown (shown only when subs exist) ──
                  if (_subCategories.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text("התמחות ספציפית (תת-קטגוריה)", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: _subCategories.any((c) => c['id'] == _selectedSubCatId) ? _selectedSubCatId : null,
                      hint: const Text("בחר התמחות", textAlign: TextAlign.right),
                      items: _subCategories.map((c) => DropdownMenuItem(
                        value: c['id'] as String,
                        child: Text(c['name'] as String? ?? '', textAlign: TextAlign.right),
                      )).toList(),
                      onChanged: (val) => setState(() => _selectedSubCatId = val),
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                    ),
                  ],
                  const SizedBox(height: 20),
                  const Text("מחיר לשעה (₪)", style: TextStyle(fontWeight: FontWeight.bold)),
                  TextField(controller: _priceController, keyboardType: TextInputType.number, textAlign: TextAlign.right, decoration: const InputDecoration(hintText: "כמה תרצה להרוויח?")),
                ],

                const SizedBox(height: 25),
                const Text("תיאור אישי (About)", style: TextStyle(fontWeight: FontWeight.bold)),
                TextField(controller: _aboutController, maxLines: 4, textAlign: TextAlign.right, decoration: const InputDecoration(border: OutlineInputBorder(), hintText: "ספר קצת על הניסיון שלך...")),
                
                const SizedBox(height: 30),
                const Text("גלריית עבודות (הוכחת יכולת)", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10),
                  itemCount: _galleryImages.length + 1,
                  itemBuilder: (context, index) {
                    if (index == _galleryImages.length) {
                      return GestureDetector(
                        onTap: _pickAndCompressGalleryImage,
                        child: Container(
                          decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.blue.shade100, style: BorderStyle.solid)),
                          child: const Icon(Icons.add_photo_alternate_outlined, color: Colors.blue, size: 35),
                        ),
                      );
                    }
                    return Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.memory(base64Decode(_galleryImages[index]), fit: BoxFit.cover, width: double.infinity, height: double.infinity),
                        ),
                        Positioned(top: 0, right: 0, child: GestureDetector(onTap: () => setState(() => _galleryImages.removeAt(index)), child: Container(padding: const EdgeInsets.all(2), decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: const Icon(Icons.cancel, color: Colors.red, size: 20)))),
                      ],
                    );
                  },
                ),
                
                const SizedBox(height: 40),
                ElevatedButton(
                  onPressed: _saveProfile,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 60),
                    backgroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                  ),
                  child: const Text("שמור שינויים", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 50),
              ],
            ),
          ),
    );
  }
}