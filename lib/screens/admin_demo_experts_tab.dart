// ignore_for_file: use_build_context_synchronously
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

/// Admin tab — create, edit, delete and toggle visibility of Demo Experts.
///
/// Firestore:
///   users/{uid}           — profile + gallery + stats
///   reviews/{id}          — 3 fake reviews written on create
class AdminDemoExpertsTab extends StatefulWidget {
  const AdminDemoExpertsTab({super.key});

  @override
  State<AdminDemoExpertsTab> createState() => _AdminDemoExpertsTabState();
}

class _AdminDemoExpertsTabState extends State<AdminDemoExpertsTab> {
  final _db = FirebaseFirestore.instance;

  Stream<QuerySnapshot<Map<String, dynamic>>> get _demoStream => _db
      .collection('users')
      .where('isDemo', isEqualTo: true)
      .limit(100)
      .snapshots();

  Future<void> _toggleHidden(String uid, bool current) =>
      _db.collection('users').doc(uid).update({'isHidden': !current});

  Future<void> _delete(BuildContext ctx, String uid, String name) async {
    final confirm = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('מחק מומחה דמו'),
        content: Text('האם למחוק את "$name"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ביטול')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('מחק', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    // Also delete fake reviews for this expert
    final reviews = await _db
        .collection('reviews')
        .where('expertId', isEqualTo: uid)
        .where('isDemo', isEqualTo: true)
        .get();
    for (final r in reviews.docs) {
      await r.reference.delete();
    }
    await _db.collection('users').doc(uid).delete();
  }

  void _showForm({String? uid, Map<String, dynamic>? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DemoExpertForm(uid: uid, existing: existing),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _demoStream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];

        return Scaffold(
          backgroundColor: Colors.grey[50],
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: const Color(0xFF6366F1),
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text('הוסף מומחה דמו',
                style: TextStyle(color: Colors.white)),
            onPressed: () => _showForm(),
          ),
          body: docs.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.people_outline, size: 64, color: Colors.grey),
                      SizedBox(height: 12),
                      Text('אין מומחי דמו עדיין',
                          style: TextStyle(color: Colors.grey, fontSize: 16)),
                      SizedBox(height: 6),
                      Text('לחץ על + כדי ליצור פרופיל ראשון',
                          style: TextStyle(color: Colors.grey, fontSize: 13)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (ctx, i) {
                    final doc    = docs[i];
                    final d      = doc.data();
                    final uid    = doc.id;
                    final name   = d['name']         as String? ?? '—';
                    final img    = d['profileImage'] as String? ?? '';
                    final cat    = d['serviceType']  as String? ?? '—';
                    final rating = (d['rating']      as num? ?? 0).toDouble();
                    final reviews = (d['reviewsCount'] as num? ?? 0).toInt();
                    final gallery = (d['gallery']    as List? ?? []).length;
                    final hidden = d['isHidden']     as bool? ?? false;
                    final isTopRated = d['isTopRated'] as bool? ?? false;

                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(12),
                        leading: CircleAvatar(
                          radius: 28,
                          backgroundColor: Colors.grey[200],
                          backgroundImage:
                              img.isNotEmpty ? NetworkImage(img) : null,
                          child: img.isEmpty
                              ? const Icon(Icons.person, color: Colors.grey)
                              : null,
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                            ),
                            if (isTopRated)
                              const Padding(
                                padding: EdgeInsets.only(left: 4),
                                child: Icon(Icons.workspace_premium,
                                    color: Color(0xFFF59E0B), size: 16),
                              ),
                            Container(
                              margin: const EdgeInsets.only(left: 4),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6366F1)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text('DEMO',
                                  style: TextStyle(
                                    color: Color(0xFF6366F1),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  )),
                            ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 3),
                            Text(cat,
                                style: TextStyle(
                                    color: Colors.grey[600], fontSize: 12)),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                const Icon(Icons.star_rounded,
                                    size: 13, color: Color(0xFFF59E0B)),
                                Text(' ${rating.toStringAsFixed(1)}',
                                    style: const TextStyle(fontSize: 12)),
                                Text('  •  $reviews ביקורות',
                                    style: TextStyle(
                                        fontSize: 11, color: Colors.grey[500])),
                                Text('  •  $gallery תמונות',
                                    style: TextStyle(
                                        fontSize: 11, color: Colors.grey[500])),
                              ],
                            ),
                            const SizedBox(height: 5),
                            GestureDetector(
                              onTap: () => _toggleHidden(uid, hidden),
                              child: Row(
                                children: [
                                  Icon(
                                    hidden
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    size: 14,
                                    color: hidden
                                        ? Colors.red[400]
                                        : Colors.green[600],
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    hidden ? 'מוסתר מחיפוש' : 'מוצג בחיפוש',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: hidden
                                          ? Colors.red[400]
                                          : Colors.green[600],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: !hidden,
                              onChanged: (_) => _toggleHidden(uid, hidden),
                              activeColor: const Color(0xFF10B981),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined,
                                  color: Color(0xFF6366F1), size: 20),
                              onPressed: () =>
                                  _showForm(uid: uid, existing: d),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.redAccent, size: 20),
                              onPressed: () => _delete(ctx, uid, name),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

// ── Fake review data model ────────────────────────────────────────────────────

class _FakeReview {
  final nameCtrl    = TextEditingController();
  final commentCtrl = TextEditingController();
  double rating  = 5.0;
  int    daysAgo = 14;

  void dispose() {
    nameCtrl.dispose();
    commentCtrl.dispose();
  }
}

// ── Create / Edit form ────────────────────────────────────────────────────────

class _DemoExpertForm extends StatefulWidget {
  final String?               uid;
  final Map<String, dynamic>? existing;

  const _DemoExpertForm({this.uid, this.existing});

  @override
  State<_DemoExpertForm> createState() => _DemoExpertFormState();
}

class _DemoExpertFormState extends State<_DemoExpertForm> {
  final _formKey = GlobalKey<FormState>();
  final _db      = FirebaseFirestore.instance;
  final _rng     = Random();

  // ── Text controllers ──────────────────────────────────────────────────────
  late final TextEditingController _nameCtrl;
  late final TextEditingController _bioCtrl;
  late final TextEditingController _jobsCtrl;

  // ── Category ──────────────────────────────────────────────────────────────
  String? _selectedCategoryName;
  String? _selectedSubCategory;
  List<Map<String, String>> _mainCats   = []; // [{id, name}]
  List<String>              _subCats    = [];
  bool                      _catsLoaded = false;

  // ── Images ────────────────────────────────────────────────────────────────
  String       _profileImageUrl  = '';
  bool         _uploadingProfile = false;
  final List<String> _galleryUrls      = ['', '', ''];
  final List<bool>   _uploadingGallery = [false, false, false];

  // ── Fake reviews ──────────────────────────────────────────────────────────
  final List<_FakeReview> _reviews = [
    _FakeReview(), _FakeReview(), _FakeReview()
  ];

  // ── Misc ──────────────────────────────────────────────────────────────────
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing ?? {};
    _nameCtrl = TextEditingController(text: e['name']    as String? ?? '');
    _bioCtrl  = TextEditingController(text: e['aboutMe'] as String? ?? '');
    _jobsCtrl = TextEditingController(
        text: (e['completedJobs'] as num? ?? 54).toString());

    _profileImageUrl = e['profileImage'] as String? ?? '';
    final gallery    = (e['gallery']  as List? ?? []).cast<String>();
    for (int i = 0; i < 3 && i < gallery.length; i++) {
      _galleryUrls[i] = gallery[i];
    }

    _selectedCategoryName  = e['serviceType']  as String?;
    _selectedSubCategory   = e['subCategory']  as String?;

    _loadCategories();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _jobsCtrl.dispose();
    for (final r in _reviews) {
      r.dispose();
    }
    super.dispose();
  }

  // ── Load categories once ──────────────────────────────────────────────────

  Future<void> _loadCategories() async {
    final snap = await _db.collection('categories').get();
    final mains = <Map<String, String>>[];
    for (final doc in snap.docs) {
      final d        = doc.data();
      final parentId = (d['parentId'] as String?) ?? '';
      if (parentId.isEmpty) {
        mains.add({'id': doc.id, 'name': (d['name'] as String? ?? '')});
      }
    }
    mains.sort((a, b) => a['name']!.compareTo(b['name']!));
    if (!mounted) return;
    setState(() {
      _mainCats   = mains;
      _catsLoaded = true;
    });

    // If editing, ensure sub-categories are loaded for existing category
    if (_selectedCategoryName != null) {
      final match = mains.firstWhere(
        (c) => c['name'] == _selectedCategoryName,
        orElse: () => {},
      );
      if (match.isNotEmpty) {
        await _loadSubCategories(match['id']!);
      }
    }
  }

  Future<void> _loadSubCategories(String parentDocId) async {
    final snap = await _db
        .collection('categories')
        .where('parentId', isEqualTo: parentDocId)
        .get();
    final subs = snap.docs
        .map((d) => (d.data()['name'] as String? ?? ''))
        .where((n) => n.isNotEmpty)
        .toList()
      ..sort();
    if (!mounted) return;
    setState(() => _subCats = subs);
  }

  // ── Image upload helpers ──────────────────────────────────────────────────

  Future<String?> _pickAndUpload(String storagePath) async {
    try {
      final picker = ImagePicker();
      final xfile  = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );
      if (xfile == null) return null;
      final bytes = await xfile.readAsBytes();
      final ext   = xfile.name.split('.').last.toLowerCase();
      final ref   = FirebaseStorage.instance.ref(storagePath);
      final task  = await ref.putData(
        bytes,
        SettableMetadata(contentType: 'image/$ext'),
      );
      return await task.ref.getDownloadURL();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאת העלאה: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    }
  }

  Future<void> _uploadProfileImage() async {
    setState(() => _uploadingProfile = true);
    final ts  = DateTime.now().millisecondsSinceEpoch;
    final url = await _pickAndUpload('demo_experts/${ts}_profile.jpg');
    if (mounted) {
      setState(() {
        if (url != null) _profileImageUrl = url;
        _uploadingProfile = false;
      });
    }
  }

  Future<void> _uploadGalleryImage(int index) async {
    setState(() => _uploadingGallery[index] = true);
    final ts  = DateTime.now().millisecondsSinceEpoch;
    final url = await _pickAndUpload('demo_experts/${ts}_gallery_$index.jpg');
    if (mounted) {
      setState(() {
        if (url != null) _galleryUrls[index] = url;
        _uploadingGallery[index] = false;
      });
    }
  }

  // ── Calculated rating ─────────────────────────────────────────────────────

  double get _calculatedRating {
    if (_reviews.isEmpty) return 5.0;
    final sum = _reviews.fold<double>(0, (acc, r) => acc + r.rating);
    return double.parse((sum / _reviews.length).toStringAsFixed(1));
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategoryName == null || _selectedCategoryName!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('נא לבחור קטגוריה')),
      );
      return;
    }
    setState(() => _isSaving = true);

    try {
      final rating     = _calculatedRating;
      final isTopRated = rating >= 4.8;
      final gallery    = _galleryUrls.where((u) => u.isNotEmpty).toList();
      final uid        = widget.uid ?? _db.collection('users').doc().id;

      final data = <String, dynamic>{
        'name':          _nameCtrl.text.trim(),
        'aboutMe':       _bioCtrl.text.trim(),
        'profileImage':  _profileImageUrl,
        'serviceType':   _selectedCategoryName ?? '',
        'subCategory':   _selectedSubCategory  ?? '',
        'gallery':       gallery,
        'completedJobs': int.tryParse(_jobsCtrl.text.trim()) ?? 54,
        'rating':        rating,
        'reviewsCount':  _reviews.length,
        'isProvider':    true,
        'isCustomer':    false,
        'isDemo':        true,
        'isOnline':      true,
        'isVerified':    true,
        'isTopRated':    isTopRated,
        'isHidden':      widget.existing?['isHidden'] as bool? ?? false,
        'balance':       0,
        'pricePerHour':  150,
      };

      if (widget.uid != null) {
        await _db.collection('users').doc(uid).update(data);
      } else {
        await _db.collection('users').doc(uid).set(data);

        // Write 3 fake reviews only on create
        for (final r in _reviews) {
          final name    = r.nameCtrl.text.trim();
          final comment = r.commentCtrl.text.trim();
          if (name.isEmpty || comment.isEmpty) continue;
          final date = DateTime.now()
              .subtract(Duration(days: r.daysAgo + _rng.nextInt(3)));
          await _db.collection('reviews').add({
            'expertId':    uid,
            'reviewerId':  'demo_${_db.collection('users').doc().id}',
            'reviewerName': name,
            'rating':      r.rating,
            'comment':     comment,
            'timestamp':   Timestamp.fromDate(date),
            'traitTags':   ['professional', 'punctual'],
            'isDemo':      true,
          });
        }
      }

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.uid != null;
    return DraggableScrollableSheet(
      initialChildSize: 0.95,
      maxChildSize:     0.97,
      minChildSize:     0.5,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color:        Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Form(
          key: _formKey,
          child: ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 48),
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                isEdit ? 'ערוך מומחה דמו' : 'צור מומחה דמו חדש',
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              // ── 1. Basic info ─────────────────────────────────────────────
              _sectionHeader('📋 פרטים בסיסיים'),
              _field(_nameCtrl, 'שם המומחה *', Icons.person_outline),
              _field(_bioCtrl, 'ביו קצר', Icons.notes_outlined, maxLines: 3),
              _field(_jobsCtrl, 'עבודות שהושלמו', Icons.work_outline,
                  keyboard: TextInputType.number),

              // ── 2. Category ───────────────────────────────────────────────
              _sectionHeader('🏷️ קטגוריה'),
              if (!_catsLoaded)
                const Center(child: CircularProgressIndicator())
              else ...[
                DropdownButtonFormField<String>(
                  value: _selectedCategoryName,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'קטגוריה ראשית *',
                    prefixIcon: const Icon(Icons.category_outlined, size: 20),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                  ),
                  items: _mainCats
                      .map((c) => DropdownMenuItem<String>(
                            value: c['name'],
                            child: Text(c['name']!,
                                overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) {
                    setState(() {
                      _selectedCategoryName = v;
                      _selectedSubCategory  = null;
                      _subCats              = [];
                    });
                    final match = _mainCats.firstWhere(
                      (c) => c['name'] == v,
                      orElse: () => {},
                    );
                    if (match.isNotEmpty) {
                      _loadSubCategories(match['id']!);
                    }
                  },
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'נא לבחור קטגוריה' : null,
                ),
                if (_subCats.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: _selectedSubCategory,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'תת-קטגוריה (אופציונלי)',
                      prefixIcon:
                          const Icon(Icons.subdirectory_arrow_right, size: 20),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('— ללא תת-קטגוריה —',
                            style: TextStyle(color: Colors.grey)),
                      ),
                      ..._subCats.map((s) => DropdownMenuItem<String>(
                            value: s,
                            child:
                                Text(s, overflow: TextOverflow.ellipsis),
                          )),
                    ],
                    onChanged: (v) =>
                        setState(() => _selectedSubCategory = v),
                  ),
                ],
              ],
              const SizedBox(height: 14),

              // ── 3. Profile image ──────────────────────────────────────────
              _sectionHeader('📸 תמונת פרופיל'),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Preview
                  Container(
                    width: 80, height: 80,
                    decoration: BoxDecoration(
                      color:        Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                      border:       Border.all(color: Colors.grey.shade300),
                      image: _profileImageUrl.isNotEmpty
                          ? DecorationImage(
                              image: NetworkImage(_profileImageUrl),
                              fit:   BoxFit.cover,
                            )
                          : null,
                    ),
                    child: _profileImageUrl.isEmpty
                        ? const Icon(Icons.person_outline,
                            color: Colors.grey, size: 36)
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _uploadingProfile ? null : _uploadProfileImage,
                          icon: _uploadingProfile
                              ? const SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : const Icon(Icons.upload_rounded, size: 18),
                          label: Text(_uploadingProfile
                              ? 'מעלה...'
                              : 'העלה מהמחשב'),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(
                                color: Color(0xFF6366F1)),
                            foregroundColor: const Color(0xFF6366F1),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          initialValue: _profileImageUrl,
                          decoration: InputDecoration(
                            hintText: 'או הדבק URL של תמונה',
                            hintStyle: TextStyle(
                                color: Colors.grey[400], fontSize: 12),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            isDense: true,
                          ),
                          onChanged: (v) =>
                              setState(() => _profileImageUrl = v.trim()),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── 4. Gallery ────────────────────────────────────────────────
              _sectionHeader('🖼️ גלריית עבודות (3 תמונות)'),
              Row(
                children: List.generate(3, (i) {
                  final url = _galleryUrls[i];
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                          left: i < 2 ? 8 : 0),
                      child: GestureDetector(
                        onTap: () => _uploadGalleryImage(i),
                        child: Container(
                          height: 90,
                          decoration: BoxDecoration(
                            color:        Colors.grey[100],
                            borderRadius: BorderRadius.circular(10),
                            border:       Border.all(
                              color: const Color(0xFF6366F1)
                                  .withValues(alpha: 0.4),
                              style: BorderStyle.solid,
                            ),
                            image: url.isNotEmpty
                                ? DecorationImage(
                                    image: NetworkImage(url),
                                    fit:   BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: _uploadingGallery[i]
                              ? const Center(
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : url.isEmpty
                                  ? Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.add_photo_alternate_outlined,
                                            color: Colors.grey[400], size: 28),
                                        Text('תמונה ${i + 1}',
                                            style: TextStyle(
                                                color:    Colors.grey[400],
                                                fontSize: 11)),
                                      ],
                                    )
                                  : Align(
                                      alignment: Alignment.topRight,
                                      child: GestureDetector(
                                        onTap: () => setState(
                                            () => _galleryUrls[i] = ''),
                                        child: Container(
                                          margin: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color:        Colors.black54,
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: const Icon(Icons.close,
                                              color: Colors.white, size: 14),
                                        ),
                                      ),
                                    ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'לחץ על תיבה להעלאת תמונה מהמחשב',
                  style: TextStyle(color: Colors.grey[400], fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 20),

              // ── 5. Fake reviews ───────────────────────────────────────────
              _sectionHeader('⭐ ביקורות מדומות'),
              if (isEdit)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:        Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: const Text(
                    'ביקורות נוצרות רק בעת יצירה חדשה. לעדכן ביקורות — מחק ובנה מחדש.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF92400E)),
                    textAlign: TextAlign.center,
                  ),
                )
              else
                ...List.generate(_reviews.length, (i) =>
                    _buildReviewSlot(i)),

              const SizedBox(height: 8),
              // Rating preview
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color:        const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.star_rounded,
                        color: Color(0xFFF59E0B), size: 22),
                    const SizedBox(width: 6),
                    Text(
                      'דירוג מחושב: ${_calculatedRating.toStringAsFixed(1)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color:      Color(0xFF4338CA),
                        fontSize:   14,
                      ),
                    ),
                    if (_calculatedRating >= 4.8) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.workspace_premium,
                          color: Color(0xFFF59E0B), size: 18),
                      const Text(' Top Rated',
                          style: TextStyle(
                              fontSize: 12,
                              color:    Color(0xFFF59E0B),
                              fontWeight: FontWeight.w600)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // ── Save button ───────────────────────────────────────────────
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Text(
                        isEdit ? 'שמור שינויים' : 'צור מומחה',
                        style: const TextStyle(
                            color:      Colors.white,
                            fontSize:   16,
                            fontWeight: FontWeight.bold),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Review slot ───────────────────────────────────────────────────────────

  Widget _buildReviewSlot(int i) {
    final r = _reviews[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:        const Color(0xFFFAFAFF),
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: const Color(0xFFE0E7FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ביקורת ${i + 1}',
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize:   13,
                  color:      Color(0xFF4338CA))),
          const SizedBox(height: 10),
          TextFormField(
            controller: r.nameCtrl,
            textDirection: TextDirection.rtl,
            decoration: InputDecoration(
              labelText:    'שם הלקוח (למשל: ישראל ישראלי)',
              prefixIcon:   const Icon(Icons.person_outline, size: 18),
              border:       OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller:    r.commentCtrl,
            maxLines:      2,
            textDirection: TextDirection.rtl,
            decoration: InputDecoration(
              labelText:  'תוכן הביקורת',
              prefixIcon: const Icon(Icons.rate_review_outlined, size: 18),
              border:     OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          // Star rating picker
          Row(
            children: [
              const Text('דירוג: ',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
              ...List.generate(5, (s) {
                final filled = s < r.rating.round();
                return GestureDetector(
                  onTap: () => setState(() => r.rating = (s + 1).toDouble()),
                  child: Icon(
                    filled ? Icons.star_rounded : Icons.star_border_rounded,
                    color: const Color(0xFFF59E0B),
                    size: 26,
                  ),
                );
              }),
              const SizedBox(width: 8),
              Text(r.rating.toStringAsFixed(0),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color:      Color(0xFFF59E0B))),
            ],
          ),
          const SizedBox(height: 8),
          // Days ago slider
          Row(
            children: [
              Text('לפני ${r.daysAgo} ימים',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              Expanded(
                child: Slider(
                  value:       r.daysAgo.toDouble(),
                  min:         1,
                  max:         90,
                  divisions:   89,
                  activeColor: const Color(0xFF6366F1),
                  onChanged: (v) =>
                      setState(() => r.daysAgo = v.round()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Section header ────────────────────────────────────────────────────────

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Text(title,
          style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize:   14,
              color:      Color(0xFF1E293B))),
    );
  }

  // ── Text field helper ─────────────────────────────────────────────────────

  Widget _field(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    int maxLines              = 1,
    TextInputType keyboard    = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller:    ctrl,
        maxLines:      maxLines,
        keyboardType:  keyboard,
        textDirection: TextDirection.rtl,
        decoration: InputDecoration(
          labelText:  label,
          prefixIcon: Icon(icon, size: 20),
          border:     OutlineInputBorder(
              borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 14),
        ),
        validator: label.endsWith('*')
            ? (v) => (v == null || v.trim().isEmpty) ? 'שדה חובה' : null
            : null,
      ),
    );
  }
}
