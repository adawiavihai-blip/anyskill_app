// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Admin tab — create, edit, delete and toggle visibility of Demo Experts
/// (fake provider profiles used to seed the app before real supply arrives).
///
/// Firestore path:  users/{uid}  with  isDemo: true
/// Required fields: name, bio, profileImage (AI image URL), serviceType,
///                  isProvider, isCustomer, isDemo, isHidden, balance
class AdminDemoExpertsTab extends StatefulWidget {
  const AdminDemoExpertsTab({super.key});

  @override
  State<AdminDemoExpertsTab> createState() => _AdminDemoExpertsTabState();
}

class _AdminDemoExpertsTabState extends State<AdminDemoExpertsTab> {
  final _db = FirebaseFirestore.instance;

  // ── Stream ────────────────────────────────────────────────────────────────

  Stream<QuerySnapshot<Map<String, dynamic>>> get _demoStream =>
      _db
          .collection('users')
          .where('isDemo', isEqualTo: true)
          .limit(100)
          .snapshots();

  // ── Toggle hidden ──────────────────────────────────────────────────────────

  Future<void> _toggleHidden(String uid, bool current) async {
    await _db.collection('users').doc(uid).update({'isHidden': !current});
  }

  // ── Delete ─────────────────────────────────────────────────────────────────

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
              child:
                  const Text('מחק', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    await _db.collection('users').doc(uid).delete();
  }

  // ── Create / Edit sheet ────────────────────────────────────────────────────

  void _showForm({String? uid, Map<String, dynamic>? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DemoExpertForm(
        uid:      uid,
        existing: existing,
        onSaved:  () {},
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

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
                      Icon(Icons.people_outline,
                          size: 64, color: Colors.grey),
                      SizedBox(height: 12),
                      Text('אין מומחי דמו עדיין',
                          style:
                              TextStyle(color: Colors.grey, fontSize: 16)),
                      SizedBox(height: 6),
                      Text('לחץ על + כדי ליצור פרופיל ראשון',
                          style:
                              TextStyle(color: Colors.grey, fontSize: 13)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (ctx, i) {
                    final doc  = docs[i];
                    final d    = doc.data();
                    final uid  = doc.id;
                    final name = d['name'] as String? ?? '—';
                    final img  = d['profileImage'] as String? ?? '';
                    final cat  = d['serviceType'] as String? ?? '—';
                    final hidden = d['isHidden'] as bool? ?? false;

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
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
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
                            const SizedBox(height: 2),
                            Text(cat,
                                style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 12)),
                            const SizedBox(height: 6),
                            // Visibility toggle
                            GestureDetector(
                              onTap: () =>
                                  _toggleHidden(uid, hidden),
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
                                    hidden
                                        ? 'מוסתר מחיפוש'
                                        : 'מוצג בחיפוש',
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
                            // Visibility toggle icon
                            Switch(
                              value: !hidden,
                              onChanged: (_) =>
                                  _toggleHidden(uid, hidden),
                              activeColor: const Color(0xFF10B981),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                            // Edit
                            IconButton(
                              icon: const Icon(Icons.edit_outlined,
                                  color: Color(0xFF6366F1), size: 20),
                              onPressed: () =>
                                  _showForm(uid: uid, existing: d),
                            ),
                            // Delete
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.redAccent, size: 20),
                              onPressed: () =>
                                  _delete(ctx, uid, name),
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

// ── Create / Edit form ─────────────────────────────────────────────────────────

class _DemoExpertForm extends StatefulWidget {
  final String?               uid;
  final Map<String, dynamic>? existing;
  final VoidCallback          onSaved;

  const _DemoExpertForm({
    this.uid,
    this.existing,
    required this.onSaved,
  });

  @override
  State<_DemoExpertForm> createState() => _DemoExpertFormState();
}

class _DemoExpertFormState extends State<_DemoExpertForm> {
  final _formKey = GlobalKey<FormState>();
  final _db      = FirebaseFirestore.instance;

  late final TextEditingController _nameCtrl;
  late final TextEditingController _bioCtrl;
  late final TextEditingController _imageCtrl;
  late final TextEditingController _categoryCtrl;
  late final TextEditingController _ratingCtrl;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing ?? {};
    _nameCtrl     = TextEditingController(text: e['name']         as String? ?? '');
    _bioCtrl      = TextEditingController(text: e['aboutMe']      as String? ?? '');
    _imageCtrl    = TextEditingController(text: e['profileImage'] as String? ?? '');
    _categoryCtrl = TextEditingController(text: e['serviceType']  as String? ?? '');
    _ratingCtrl   = TextEditingController(
        text: (e['rating'] as num? ?? 4.8).toStringAsFixed(1));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _imageCtrl.dispose();
    _categoryCtrl.dispose();
    _ratingCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final data = {
      'name':         _nameCtrl.text.trim(),
      'aboutMe':      _bioCtrl.text.trim(),
      'profileImage': _imageCtrl.text.trim(),
      'serviceType':  _categoryCtrl.text.trim(),
      'rating':       double.tryParse(_ratingCtrl.text.trim()) ?? 4.8,
      'isProvider':   true,
      'isCustomer':   false,
      'isDemo':       true,
      'isOnline':     true,
      'isVerified':   true,
      'isHidden':     widget.existing?['isHidden'] as bool? ?? false,
      'balance':      0,
      'reviewsCount': (widget.existing?['reviewsCount'] as num? ?? 0).toInt(),
    };

    try {
      if (widget.uid != null) {
        // Edit
        await _db.collection('users').doc(widget.uid).update(data);
      } else {
        // Create — use auto-generated ID
        await _db.collection('users').add(data);
      }
      if (mounted) Navigator.of(context).pop();
      widget.onSaved();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('שגיאה: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.uid != null;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Form(
          key: _formKey,
          child: ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
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
              const SizedBox(height: 16),
              Text(
                isEdit ? 'ערוך מומחה דמו' : 'צור מומחה דמו חדש',
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              _field(_nameCtrl,     'שם המומחה *',            Icons.person_outline),
              _field(_categoryCtrl, 'קטגוריה / תחום *',       Icons.category_outlined),
              _field(_bioCtrl,      'ביו קצר',                 Icons.notes_outlined,
                  maxLines: 3),
              _field(_imageCtrl,    'URL תמונה (AI generated)', Icons.image_outlined),
              _field(_ratingCtrl,   'דירוג (0.0–5.0)',         Icons.star_outline,
                  keyboard: TextInputType.number),

              const SizedBox(height: 24),
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
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    int maxLines = 1,
    TextInputType keyboard = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: ctrl,
        maxLines: maxLines,
        keyboardType: keyboard,
        textDirection: TextDirection.rtl,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
        validator: label.endsWith('*')
            ? (v) =>
                (v == null || v.trim().isEmpty) ? 'שדה חובה' : null
            : null,
      ),
    );
  }
}
