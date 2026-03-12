import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import '../category_results_screen.dart';

const Map<String, IconData> _iconMap = {
  'build':              Icons.build,
  'cleaning_services':  Icons.cleaning_services,
  'camera_alt':         Icons.camera_alt,
  'fitness_center':     Icons.fitness_center,
  'school':             Icons.school,
  'palette':            Icons.palette,
};

class SearchPage extends StatelessWidget {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    final bool isAdmin =
        FirebaseAuth.instance.currentUser?.email == 'adawiavihai@gmail.com';

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 24, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    "גלה מומחים",
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "בחר תחום ומצא את המומחה המושלם",
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('categories')
                    .orderBy('order')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Center(
                      child: Text(
                        "לא נמצאו קטגוריות.\nבצע אתחול מלוח הניהול.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 15),
                      ),
                    );
                  }

                  final docs = snapshot.data!.docs;

                  return GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                      childAspectRatio: 0.85,
                    ),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final doc  = docs[index];
                      final data = doc.data() as Map<String, dynamic>;
                      final name     = data['name']     as String? ?? '';
                      final imageUrl = data['img']      as String? ?? '';
                      final iconName = data['iconName'] as String? ?? '';
                      final icon     = _iconMap[iconName] ?? Icons.category;

                      return _CategoryCard(
                        docId:    doc.id,
                        name:     name,
                        imageUrl: imageUrl,
                        icon:     icon,
                        isAdmin:  isAdmin,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                CategoryResultsScreen(categoryName: name),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── כרטיס קטגוריה ────────────────────────────────────────────────────────────

class _CategoryCard extends StatelessWidget {
  final String   docId;
  final String   name;
  final String   imageUrl;
  final IconData icon;
  final bool     isAdmin;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.docId,
    required this.name,
    required this.imageUrl,
    required this.icon,
    required this.isAdmin,
    required this.onTap,
  });

  void _openEditSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditCategorySheet(
        docId:       docId,
        currentName: name,
        currentImg:  imageUrl,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // תמונת רקע
            Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(color: Colors.grey[200]),
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Container(color: Colors.grey[100]);
              },
            ),

            // גרדיאנט כהה מלמטה
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.68),
                  ],
                  stops: const [0.4, 1.0],
                ),
              ),
            ),

            // שם + אייקון בתחתית
            Positioned(
              bottom: 16,
              left: 14,
              right: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Icon(icon, color: Colors.white, size: 22),
                  const SizedBox(height: 6),
                  Text(
                    name,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            // כפתור עריכה — רק לאדמין
            if (isAdmin)
              Positioned(
                top: 10,
                right: 10,
                child: GestureDetector(
                  onTap: () => _openEditSheet(context),
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.edit, color: Colors.white, size: 16),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Bottom Sheet עריכת קטגוריה ──────────────────────────────────────────────

class _EditCategorySheet extends StatefulWidget {
  final String docId;
  final String currentName;
  final String currentImg;

  const _EditCategorySheet({
    required this.docId,
    required this.currentName,
    required this.currentImg,
  });

  @override
  State<_EditCategorySheet> createState() => _EditCategorySheetState();
}

class _EditCategorySheetState extends State<_EditCategorySheet> {
  late TextEditingController _nameController;
  Uint8List? _newImageBytes;
  String?   _newImageName;
  bool      _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.currentName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 80,
    );
    if (file != null) {
      final bytes = await file.readAsBytes();
      setState(() {
        _newImageBytes = bytes;
        _newImageName  = file.name;
      });
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _isSaving = true);

    try {
      String imgUrl = widget.currentImg;

      // העלאת תמונה חדשה אם נבחרה
      if (_newImageBytes != null) {
        final ext = _newImageName?.split('.').last ?? 'jpg';
        final ref = FirebaseStorage.instance
            .ref('categories/${widget.docId}/image.$ext');
        await ref.putData(
          _newImageBytes!,
          SettableMetadata(contentType: 'image/$ext'),
        );
        imgUrl = await ref.getDownloadURL();
      }

      // עדכון Firestore
      await FirebaseFirestore.instance
          .collection('categories')
          .doc(widget.docId)
          .update({'name': name, 'img': imgUrl});

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("שגיאה בשמירה: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          24, 16, 24, MediaQuery.of(context).viewInsets.bottom + 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ידית
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(10)),
          ),
          const SizedBox(height: 22),

          const Text(
            "עריכת קטגוריה",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),

          // תצוגה מקדימה של התמונה
          GestureDetector(
            onTap: _pickImage,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: _newImageBytes != null
                      ? Image.memory(_newImageBytes!,
                          height: 160, width: double.infinity,
                          fit: BoxFit.cover)
                      : Image.network(widget.currentImg,
                          height: 160, width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              Container(height: 160, color: Colors.grey[200])),
                ),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_outlined,
                            color: Colors.white, size: 34),
                        SizedBox(height: 6),
                        Text("לחץ להחלפת תמונה",
                            style: TextStyle(color: Colors.white, fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // שדה שם
          TextField(
            controller: _nameController,
            textAlign: TextAlign.right,
            decoration: InputDecoration(
              labelText: "שם קטגוריה",
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              prefixIcon: const Icon(Icons.label_outline),
            ),
          ),
          const SizedBox(height: 24),

          // כפתור שמירה
          ElevatedButton(
            onPressed: _isSaving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: _isSaving
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text("שמור שינויים",
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
