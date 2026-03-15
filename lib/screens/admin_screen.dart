import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart';
import 'package:web/web.dart' as web;
import 'dart:js_interop';
import '../services/categories_seeder.dart';
import '../services/category_service.dart';
import 'chat_modules/payment_module.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  String _searchQuery = "";
  double _feePct        = 10.0;
  double _urgencyFeePct = 5.0;
  bool   _settingsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadAdminSettings();
  }

  Future<void> _loadAdminSettings() async {
    final doc = await FirebaseFirestore.instance
        .collection('admin').doc('admin')
        .collection('settings').doc('settings').get();
    if (!mounted) return;
    final d = doc.data() as Map<String, dynamic>? ?? {};
    setState(() {
      _feePct        = ((d['feePercentage']       as num?) ?? 10).toDouble();
      _urgencyFeePct = ((d['urgencyFeePercentage'] as num?) ?? 5).toDouble();
      _settingsLoaded = true;
    });
  }

  // ── CSV Export ────────────────────────────────────────────────────────────

  Future<void> _exportTransactionsCsv() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
        const SnackBar(content: Text("מכין קובץ CSV...")));

    try {
      final snap = await FirebaseFirestore.instance
          .collection('transactions')
          .orderBy('timestamp', descending: true)
          .get();

      final buf = StringBuffer();
      // UTF-8 BOM for Excel compatibility
      buf.write('\uFEFF');
      buf.writeln('מזהה,משתמש,כותרת,סכום,סוג,תאריך');

      for (final doc in snap.docs) {
        final d  = doc.data();
        final ts = (d['timestamp'] as Timestamp?)?.toDate();
        final dateStr = ts != null
            ? DateFormat('dd/MM/yyyy HH:mm').format(ts)
            : '';
        final amount = (d['amount'] as num? ?? 0).toStringAsFixed(2);
        // Escape any commas or quotes inside fields
        String _esc(dynamic v) {
          final s = (v ?? '').toString().replaceAll('"', '""');
          return '"$s"';
        }
        buf.writeln([
          _esc(doc.id),
          _esc(d['userId']),
          _esc(d['title']),
          _esc(amount),
          _esc(d['type']),
          _esc(dateStr),
        ].join(','));
      }

      final csvStr  = buf.toString();
      final filename =
          'anyskill_transactions_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv';

      // Trigger browser download using the web package
      final blob = web.Blob(
        [csvStr.toJS].toJS,
        web.BlobPropertyBag(type: 'text/csv;charset=utf-8;'),
      );
      final url = web.URL.createObjectURL(blob);
      final anchor =
          web.document.createElement('a') as web.HTMLAnchorElement;
      anchor.href      = url;
      anchor.download  = filename;
      anchor.click();
      web.URL.revokeObjectURL(url);

      if (mounted) {
        messenger.showSnackBar(SnackBar(
          backgroundColor: Colors.green,
          content: Text("${snap.size} רשומות יוצאו ל-$filename"),
        ));
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(
            backgroundColor: Colors.red, content: Text("שגיאה: $e")));
      }
    }
  }

  Future<void> _saveAdminSettings() async {
    await FirebaseFirestore.instance
        .collection('admin').doc('admin')
        .collection('settings').doc('settings')
        .set({
          'feePercentage':       _feePct,
          'urgencyFeePercentage': _urgencyFeePct,
        }, SetOptions(merge: true));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(backgroundColor: Colors.green, content: Text("ההגדרות נשמרו ✓")));
    }
  }

  String _calculateSeniority(DateTime createdAt) {
    final now = DateTime.now();
    final difference = now.difference(createdAt);
    if (difference.inDays >= 365) {
      return "${(difference.inDays / 365).toStringAsFixed(1)} שנים";
    } else if (difference.inDays >= 30) {
      return "${(difference.inDays / 30).floor()} חודשים";
    } else {
      return "${difference.inDays} ימים";
    }
  }

  // תפריט פעולות משודרג - הכל במקום אחד
  void _showUserActions(String uid, Map<String, dynamic> data) {
    bool isBanned    = data['isBanned']    ?? false;
    bool isVerified  = data['isVerified']  ?? false;
    bool isPromoted  = data['isPromoted']  ?? false;
    String name = data['name'] ?? "משתמש";
    String currentNote = data['adminNote'] ?? "";

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => SafeArea(
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
              const SizedBox(height: 20),
              Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const Divider(),
              
              // אימות מומחה (וי כחול)
              ListTile(
                leading: Icon(isVerified ? Icons.verified_user : Icons.verified, color: Colors.blue),
                title: Text(isVerified ? "בטל אימות (הסר וי כחול)" : "אמת מומחה (הענק וי כחול)"),
                onTap: () {
                  FirebaseFirestore.instance.collection('users').doc(uid).update({'isVerified': !isVerified});
                  Navigator.pop(context);
                },
              ),

              // ספק מומלץ (זוהר זהוב בחיפוש)
              ListTile(
                leading: Icon(isPromoted ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: isPromoted ? Colors.amber : Colors.grey),
                title: Text(isPromoted ? "בטל קידום (הסר זוהר זהוב)" : "קדם ספק (הוסף זוהר זהוב + עדיפות)"),
                subtitle: const Text("ספקים מקודמים מופיעים ראשונים בחיפוש",
                    style: TextStyle(fontSize: 11)),
                onTap: () {
                  FirebaseFirestore.instance.collection('users').doc(uid)
                      .update({'isPromoted': !isPromoted});
                  Navigator.pop(context);
                },
              ),

              // הערת מנהל
              ListTile(
                leading: const Icon(Icons.edit_note, color: Colors.amber),
                title: const Text("עדכן הערת מנהל פנימית"),
                subtitle: Text(currentNote.isNotEmpty ? currentNote : "אין הערות"),
                onTap: () {
                  Navigator.pop(context);
                  _showAddNoteDialog(uid, currentNote);
                },
              ),

              // חסימה/שחרור
              ListTile(
                leading: Icon(isBanned ? Icons.lock_open : Icons.block, color: Colors.orange),
                title: Text(isBanned ? "שחרר חסימת חשבון" : "חסום משתמש מהמערכת"),
                onTap: () {
                  FirebaseFirestore.instance.collection('users').doc(uid).update({'isBanned': !isBanned});
                  Navigator.pop(context);
                },
              ),

              // מחיקה
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: const Text("מחק חשבון לצמיתות", style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDelete(uid, name);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddNoteDialog(String uid, String currentNote) {
    final TextEditingController noteController = TextEditingController(text: currentNote);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("הערת מנהל"),
        content: TextField(controller: noteController, maxLines: 3, decoration: const InputDecoration(hintText: "כתוב הערה...", border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("ביטול")),
          ElevatedButton(onPressed: () {
            FirebaseFirestore.instance.collection('users').doc(uid).update({'adminNote': noteController.text});
            Navigator.pop(context);
          }, child: const Text("שמור")),
        ],
      ),
    );
  }

  void _showAddBalanceDialog(String uid, String name) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final TextEditingController amountController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text("הטענת ארנק ל-$name"),
        content: TextField(controller: amountController, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: "סכום להוספה", suffixText: "₪", border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text("ביטול")),
          ElevatedButton(onPressed: () async {
            final val = double.tryParse(amountController.text.trim());
            if (val == null || val <= 0) return;
            Navigator.pop(dialogContext);
            // FieldValue.increment מונע race condition
            await FirebaseFirestore.instance.runTransaction((tx) async {
              final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
              tx.update(userRef, {'balance': FieldValue.increment(val)});
              tx.set(FirebaseFirestore.instance.collection('transactions').doc(), {
                'userId': uid,
                'amount': val,
                'title': 'טעינת ארנק ע״י מנהל',
                'timestamp': FieldValue.serverTimestamp(),
                'type': 'admin_topup',
              });
            });
            scaffoldMessenger.showSnackBar(SnackBar(content: Text("נטענו ₪$val לארנק של $name")));
          }, child: const Text("אשר והטען")),
        ],
      ),
    );
  }

  void _confirmDelete(String uid, String name) {
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("מחיקה סופית"),
        content: Text("האם למחוק את $name לצמיתות?\nהחשבון יימחק גם מ-Auth וגם מהמסד. לא ניתן לשחזר."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ביטול")),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await FirebaseFunctions.instance.httpsCallable('deleteUser').call({'uid': uid});
                messenger.showSnackBar(
                  SnackBar(backgroundColor: Colors.green, content: Text("$name נמחק בהצלחה")),
                );
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(backgroundColor: Colors.red, content: Text("שגיאה במחיקה: $e")),
                );
              }
            },
            child: const Text("מחק", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showBroadcastDialog() {
    final TextEditingController broadcastController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("שלח הודעת מערכת (באנר כחול)"),
        content: TextField(controller: broadcastController, maxLines: 3, decoration: const InputDecoration(hintText: "ההודעה תופיע לכולם בדף הבית...", border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("ביטול")),
          ElevatedButton(onPressed: () {
            FirebaseFirestore.instance.collection('admin').doc('settings').set({'broadcastMessage': broadcastController.text}, SetOptions(merge: true));
            Navigator.pop(context);
          }, child: const Text("פרסם עכשיו")),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 9,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          title: const Text("Control Center", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2)),
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          actions: [
            IconButton(icon: const Icon(Icons.campaign_rounded, color: Colors.blueAccent, size: 30), onPressed: _showBroadcastDialog),
            const SizedBox(width: 10),
          ],
          bottom: const TabBar(
            isScrollable: true,
            labelColor: Colors.blueAccent,
            indicatorColor: Colors.blueAccent,
            tabs: [Tab(text: "הכל"), Tab(text: "לקוחות"), Tab(text: "ספקים"), Tab(text: "חסומים"), Tab(text: "מחלוקות 🔴"), Tab(text: "משיכות 💸"), Tab(text: "קטגוריות 🏷️"), Tab(text: "באנרים 🎨"), Tab(text: "מוניטיזציה 💰")],
          ),
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('users').limit(500).snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            var allUsers = snapshot.data!.docs;

            int customers = allUsers.where((d) => (d.data() as Map)['isCustomer'] == true).length;
            int providers = allUsers.where((d) => (d.data() as Map)['isProvider'] == true).length;

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(15),
                  child: TextField(
                    onChanged: (v) => setState(() => _searchQuery = v),
                    decoration: InputDecoration(
                      hintText: "חפש שם, מייל או מזהה...",
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _pulseBadge("👥 $customers לקוחות"),
                      _pulseBadge("🛠️ $providers ספקים"),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildList(allUsers),
                      _buildList(allUsers.where((d) => (d.data() as Map)['isCustomer'] == true).toList()),
                      _buildList(allUsers.where((d) => (d.data() as Map)['isProvider'] == true).toList()),
                      _buildList(allUsers.where((d) => (d.data() as Map)['isBanned'] == true).toList()),
                      _buildDisputesList(),
                      _buildWithdrawalsList(),
                      _buildCategoriesTab(),
                      _buildBannersTab(),
                      _buildMonetizationTab(allUsers),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ── Category Management ───────────────────────────────────────────────────

  Widget _buildCategoriesTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: CategoryService.stream(),
      builder: (context, snapshot) {
        final cats = snapshot.data ?? [];
        final mainCats = cats.where((c) => (c['parentId'] as String? ?? '').isEmpty).toList();
        final subCats  = cats.where((c) => (c['parentId'] as String? ?? '').isNotEmpty).toList();

        // Build grouped items: for each main cat append its subs
        final List<Map<String, dynamic>> grouped = [];
        for (final main in mainCats) {
          grouped.add({...main, '_isMain': true});
          final children = subCats.where((s) => s['parentId'] == main['id']).toList();
          for (final sub in children) {
            grouped.add({...sub, '_isMain': false, '_parentName': main['name']});
          }
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text("הוסף קטגוריה", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                onPressed: () => _showCategoryDialog(existingCount: cats.length),
              ),
            ),
            if (!snapshot.hasData)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (cats.isEmpty)
              const Expanded(
                child: Center(
                  child: Text("אין קטגוריות — לחץ 'הוסף'", style: TextStyle(color: Colors.grey, fontSize: 16)),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: grouped.length,
                  itemBuilder: (context, index) {
                    final cat = grouped[index];
                    final isMain = cat['_isMain'] as bool;
                    final parentName = cat['_parentName'] as String?;

                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: 10,
                        left: isMain ? 0 : 24, // indent sub-categories
                      ),
                      child: Card(
                        elevation: 0,
                        margin: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: isMain ? Colors.grey.shade200 : Colors.blue.shade100,
                          ),
                        ),
                        color: isMain ? Colors.white : Colors.blue.shade50,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isMain ? Colors.blue[50] : Colors.blue[100],
                            child: Icon(
                              CategoryService.getIcon(cat['iconName']),
                              color: isMain ? Colors.blueAccent : Colors.blue[700],
                              size: 20,
                            ),
                          ),
                          title: Row(
                            children: [
                              if (!isMain)
                                Container(
                                  margin: const EdgeInsets.only(left: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.blue[200],
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text("תת", style: TextStyle(fontSize: 10, color: Colors.blue[900], fontWeight: FontWeight.bold)),
                                ),
                              Expanded(
                                child: Text(
                                  cat['name'] ?? '',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: isMain ? 15 : 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            isMain ? (cat['iconName'] ?? '') : "תחת: $parentName",
                            style: TextStyle(color: Colors.grey[500], fontSize: 12),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, color: Colors.blueAccent, size: 20),
                                onPressed: () => _showCategoryDialog(existing: cat, existingCount: cats.length),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                onPressed: () => _confirmDeleteCategory(cat['id'] as String, cat['name'] ?? '', isMain: isMain),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  void _showCategoryDialog({Map<String, dynamic>? existing, int existingCount = 0}) {
    final nameController = TextEditingController(text: existing?['name'] ?? '');
    final imgController = TextEditingController(text: existing?['img'] ?? '');
    String selectedIcon = existing?['iconName'] ?? CategoryService.iconMap.keys.first;
    // parentId: '' = main category, non-empty = sub-category
    String selectedParentId = existing?['parentId'] as String? ?? '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(existing == null ? "הוסף קטגוריה" : "עריכת קטגוריה", textAlign: TextAlign.right),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // ── Parent category selector ──────────────────────────────
                const Text("קטגוריית אב", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                StreamBuilder<List<Map<String, dynamic>>>(
                  stream: CategoryService.streamMainCategories(),
                  builder: (_, snap) {
                    final mainCats = snap.data ?? [];
                    // Guard: if the currently-selected parentId no longer exists, reset to ''
                    final validParentId = mainCats.any((c) => c['id'] == selectedParentId)
                        ? selectedParentId
                        : '';
                    if (validParentId != selectedParentId) {
                      // Use addPostFrameCallback to avoid setState-during-build
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        setDialog(() => selectedParentId = validParentId);
                      });
                    }
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: DropdownButton<String>(
                        value: validParentId,
                        isExpanded: true,
                        underline: const SizedBox(),
                        onChanged: (val) {
                          if (val != null) setDialog(() => selectedParentId = val);
                        },
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Row(children: [
                              Icon(Icons.folder_outlined, size: 18, color: Colors.grey),
                              SizedBox(width: 8),
                              Text("ראשי (ללא הורה)", style: TextStyle(fontSize: 13)),
                            ]),
                          ),
                          ...mainCats.map((c) => DropdownMenuItem(
                            value: c['id'] as String,
                            child: Row(children: [
                              Icon(CategoryService.getIcon(c['iconName']), size: 18, color: Colors.blueAccent),
                              const SizedBox(width: 8),
                              Text(c['name'] ?? '', style: const TextStyle(fontSize: 13)),
                            ]),
                          )),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                // ── Name ─────────────────────────────────────────────────
                const Text("שם קטגוריה", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: nameController,
                  textAlign: TextAlign.right,
                  decoration: InputDecoration(
                    hintText: "לדוגמה: פילאטיס",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 16),
                // ── Icon ─────────────────────────────────────────────────
                const Text("אייקון", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: DropdownButton<String>(
                    value: selectedIcon,
                    isExpanded: true,
                    underline: const SizedBox(),
                    onChanged: (val) {
                      if (val != null) setDialog(() => selectedIcon = val);
                    },
                    items: CategoryService.iconMap.entries.map((e) => DropdownMenuItem(
                      value: e.key,
                      child: Row(
                        children: [
                          Icon(e.value, size: 20, color: Colors.blueAccent),
                          const SizedBox(width: 10),
                          Text(e.key, style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                    )).toList(),
                  ),
                ),
                const SizedBox(height: 16),
                // ── Image URL ────────────────────────────────────────────
                const Text("קישור תמונה (אופציונלי)", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: imgController,
                  textAlign: TextAlign.right,
                  decoration: InputDecoration(
                    hintText: "https://...",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ביטול")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(ctx);
                if (existing == null) {
                  await FirebaseFirestore.instance.collection('categories').doc(name).set({
                    'name': name,
                    'iconName': selectedIcon,
                    'img': imgController.text.trim(),
                    'order': existingCount,
                    'parentId': selectedParentId,
                  });
                } else {
                  await FirebaseFirestore.instance.collection('categories').doc(existing['id'] as String).update({
                    'name': name,
                    'iconName': selectedIcon,
                    'img': imgController.text.trim(),
                    'parentId': selectedParentId,
                  });
                }
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(backgroundColor: Colors.green, content: Text(existing == null ? "הקטגוריה נוספה!" : "הקטגוריה עודכנה!")),
                  );
                }
              },
              child: const Text("שמור", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteCategory(String docId, String name, {bool isMain = true}) async {
    // For main categories, check how many sub-categories will also be deleted
    int subCount = 0;
    if (isMain) {
      final subSnap = await FirebaseFirestore.instance
          .collection('categories')
          .where('parentId', isEqualTo: docId)
          .get();
      subCount = subSnap.docs.length;
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("מחיקת קטגוריה", textAlign: TextAlign.right),
        content: Text(
          subCount > 0
              ? "האם למחוק את הקטגוריה \"$name\"?\nגם $subCount תת-קטגוריות שלה יימחקו.\nפעולה זו אינה ניתנת לביטול."
              : "האם למחוק את הקטגוריה \"$name\"?\nפעולה זו אינה ניתנת לביטול.",
          textAlign: TextAlign.right,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ביטול")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              // Cascade delete: remove all sub-categories first, then the parent
              final subSnap = await FirebaseFirestore.instance
                  .collection('categories')
                  .where('parentId', isEqualTo: docId)
                  .get();
              final batch = FirebaseFirestore.instance.batch();
              for (final sub in subSnap.docs) {
                batch.delete(sub.reference);
              }
              batch.delete(FirebaseFirestore.instance.collection('categories').doc(docId));
              await batch.commit();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("הקטגוריה \"$name\" נמחקה")),
                );
              }
            },
            child: const Text("מחק", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _pulseBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
      child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
    );
  }

  Widget _buildWithdrawalsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('withdrawals')
          .where('status', isEqualTo: 'pending')
          .orderBy('requestedAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
                SizedBox(height: 12),
                Text("אין בקשות משיכה ממתינות", style: TextStyle(color: Colors.grey, fontSize: 16)),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final w = docs[index].data() as Map<String, dynamic>;
            final wId = docs[index].id;
            final uid = w['userId'] as String? ?? '';
            final amount = (w['amount'] ?? 0.0).toDouble();
            DateTime? requestedAt = (w['requestedAt'] as Timestamp?)?.toDate();
            final formattedDate = requestedAt != null
                ? DateFormat('dd/MM HH:mm').format(requestedAt)
                : '—';

            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.blue.shade100),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Header row: amount + date ──────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("₪${amount.toStringAsFixed(0)}",
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 20)),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.orange[50],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(formattedDate,
                              style: TextStyle(
                                  color: Colors.orange[800], fontSize: 12)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // ── User name (live lookup) ─────────────────────────
                    FutureBuilder<DocumentSnapshot>(
                      future: uid.isNotEmpty
                          ? FirebaseFirestore.instance.collection('users').doc(uid).get()
                          : Future.value(null),
                      builder: (context, userSnap) {
                        String userName = uid.isEmpty ? '—' : 'טוען...';
                        if (userSnap.connectionState == ConnectionState.done) {
                          if (userSnap.hasData && userSnap.data != null && userSnap.data!.exists) {
                            final uData = userSnap.data!.data() as Map<String, dynamic>? ?? {};
                            userName = uData['name'] as String? ?? uid;
                          } else {
                            userName = uid;
                          }
                        }
                        return Row(
                          children: [
                            const Icon(Icons.person_outline, size: 15, color: Colors.blueGrey),
                            const SizedBox(width: 5),
                            Text(userName,
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w600)),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 6),

                    // ── Bank details ────────────────────────────────────
                    _wDetailRow(Icons.account_balance_outlined, "בנק", w['bankName']),
                    _wDetailRow(Icons.tag,                       "חשבון", w['accountNumber']),
                    _wDetailRow(Icons.fork_right,                "סניף", w['branchNumber']),
                    const SizedBox(height: 14),

                    // ── Action buttons ──────────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.red),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.close, color: Colors.red, size: 18),
                            label: const Text("דחה",
                                style: TextStyle(color: Colors.red, fontSize: 13)),
                            onPressed: () async {
                              await FirebaseFirestore.instance.runTransaction((tx) async {
                                tx.update(
                                  FirebaseFirestore.instance.collection('withdrawals').doc(wId),
                                  {'status': 'rejected', 'resolvedAt': FieldValue.serverTimestamp()},
                                );
                                if (uid.isNotEmpty) {
                                  tx.update(
                                    FirebaseFirestore.instance.collection('users').doc(uid),
                                    {'balance': FieldValue.increment(amount)},
                                  );
                                  tx.set(FirebaseFirestore.instance.collection('transactions').doc(), {
                                    'userId': uid,
                                    'amount': amount,
                                    'title': 'בקשת משיכה נדחתה — הסכום הוחזר',
                                    'timestamp': FieldValue.serverTimestamp(),
                                    'type': 'refund',
                                  });
                                }
                              });
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("הבקשה נדחתה והסכום הוחזר")));
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.check, color: Colors.white, size: 18),
                            label: const Text("בוצע — סמן כהושלם",
                                style: TextStyle(color: Colors.white, fontSize: 13)),
                            onPressed: () async {
                              await FirebaseFirestore.instance
                                  .collection('withdrawals')
                                  .doc(wId)
                                  .update({
                                'status': 'completed',
                                'completedAt': FieldValue.serverTimestamp(),
                              });
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    backgroundColor: Colors.green,
                                    content: Text("ההעברה סומנה כהושלמה ✓"),
                                  ));
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── Small helper for a labelled detail row in the withdrawal card ──────────
  Widget _wDetailRow(IconData icon, String label, dynamic value) {
    final str = (value?.toString() ?? '').isNotEmpty ? value.toString() : '—';
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.blueGrey),
          const SizedBox(width: 5),
          Text("$label: ", style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
          Text(str, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildDisputesList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('jobs')
          .where('status', isEqualTo: 'disputed')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
                SizedBox(height: 12),
                Text("אין מחלוקות פתוחות", style: TextStyle(color: Colors.grey, fontSize: 16)),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final job = docs[index].data() as Map<String, dynamic>;
            final jobId = docs[index].id;
            final amount = (job['totalAmount'] ?? job['totalPaidByCustomer'] ?? 0.0).toDouble();
            DateTime? openedAt = (job['disputeOpenedAt'] as Timestamp?)?.toDate();
            final formattedDate = openedAt != null
                ? DateFormat('dd/MM HH:mm').format(openedAt)
                : '—';

            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.red.shade100),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("₪${amount.toStringAsFixed(0)}",
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 18)),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.red[50],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(formattedDate,
                              style: TextStyle(
                                  color: Colors.red[700], fontSize: 12)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text("לקוח: ${job['customerName'] ?? job['customerId'] ?? '—'}",
                        style: const TextStyle(fontSize: 13)),
                    Text("מומחה: ${job['expertName'] ?? job['expertId'] ?? '—'}",
                        style: const TextStyle(fontSize: 13)),
                    if ((job['disputeReason'] ?? '').isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          "\"${job['disputeReason']}\"",
                          style: TextStyle(
                              color: Colors.orange[900],
                              fontSize: 13,
                              fontStyle: FontStyle.italic),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.red),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.undo, color: Colors.red, size: 18),
                            label: const Text("החזר ללקוח",
                                style: TextStyle(color: Colors.red, fontSize: 13)),
                            onPressed: () async {
                              final ok = await PaymentModule.refundDisputedJob(
                                jobId: jobId,
                                customerId: job['customerId'] ?? '',
                                totalAmount: amount,
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  backgroundColor: ok ? Colors.green : Colors.red,
                                  content: Text(ok
                                      ? "הסכום הוחזר ללקוח"
                                      : "שגיאה — נסה שוב"),
                                ));
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.check, color: Colors.white, size: 18),
                            label: const Text("שחרר למומחה",
                                style: TextStyle(color: Colors.white, fontSize: 13)),
                            onPressed: () async {
                              final ok = await PaymentModule.releaseEscrowFunds(
                                jobId: jobId,
                                expertId: job['expertId'] ?? '',
                                expertName: job['expertName'] ?? 'מומחה',
                                customerName: job['customerName'] ?? 'לקוח',
                                totalAmount: amount,
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  backgroundColor: ok ? Colors.green : Colors.red,
                                  content: Text(ok
                                      ? "התשלום שוחרר למומחה"
                                      : "שגיאה — נסה שוב"),
                                ));
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildList(List<QueryDocumentSnapshot> users) {
    var filtered = users.where((doc) {
      var data = doc.data() as Map<String, dynamic>;
      String name = (data['name'] ?? "").toLowerCase();
      String email = (data['email'] ?? "").toLowerCase();
      return name.contains(_searchQuery.toLowerCase()) || email.contains(_searchQuery.toLowerCase());
    }).toList();

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100, top: 10),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        var data = filtered[index].data() as Map<String, dynamic>;
        String uid = filtered[index].id;
        bool isVerified  = data['isVerified']  ?? false;
        bool isPromoted  = data['isPromoted']  ?? false;
        bool isOnline    = data['isOnline']    ?? false;
        DateTime joinDate = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Colors.grey.shade100)),
          child: ListTile(
            onLongPress: () => _showUserActions(uid, data),
            leading: Stack(
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundImage: (data['profileImage'] != null && data['profileImage'] != "") ? NetworkImage(data['profileImage']) : null,
                  child: data['profileImage'] == null ? const Icon(Icons.person) : null,
                ),
                Positioned(right: 0, bottom: 0, child: Container(width: 12, height: 12, decoration: BoxDecoration(color: isOnline ? Colors.green : Colors.grey, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)))),
              ],
            ),
            title: Row(
              children: [
                Text(data['name'] ?? "משתמש", style: const TextStyle(fontWeight: FontWeight.bold)),
                if (isVerified) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.verified, color: Colors.blue, size: 16)),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data['email'] ?? "", style: const TextStyle(fontSize: 12)),
                Text("יתרה: ₪${(data['balance'] ?? 0.0).toStringAsFixed(2)} | וותק: ${_calculateSeniority(joinDate)}", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Verification badge quick-toggle ──────────────────
                GestureDetector(
                  onTap: () {
                    FirebaseFirestore.instance
                        .collection('users')
                        .doc(uid)
                        .update({'isVerified': !isVerified});
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(isVerified
                          ? "אימות הוסר מ-${data['name'] ?? ''}"
                          : "${data['name'] ?? ''} אומת ✓"),
                      backgroundColor:
                          isVerified ? Colors.orange : Colors.blue,
                      duration: const Duration(seconds: 2),
                    ));
                  },
                  child: Tooltip(
                    message: isVerified ? "בטל אימות" : "אמת מומחה",
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 5),
                      decoration: BoxDecoration(
                        color: isVerified
                            ? Colors.blue.shade50
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: isVerified
                                ? Colors.blue.shade300
                                : Colors.grey.shade300),
                      ),
                      child: Icon(
                        isVerified
                            ? Icons.verified
                            : Icons.verified_outlined,
                        color: isVerified ? Colors.blue : Colors.grey,
                        size: 20,
                      ),
                    ),
                  ),
                ),
                // ── Promote toggle ────────────────────────────────────
                GestureDetector(
                  onTap: () {
                    FirebaseFirestore.instance.collection('users').doc(uid)
                        .update({'isPromoted': !isPromoted});
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(isPromoted
                          ? "קידום הוסר מ-${data['name'] ?? ''}"
                          : "${data['name'] ?? ''} קודם ⭐"),
                      backgroundColor: isPromoted ? Colors.grey : Colors.amber[700],
                      duration: const Duration(seconds: 2),
                    ));
                  },
                  child: Tooltip(
                    message: isPromoted ? "בטל קידום" : "קדם ספק",
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                      decoration: BoxDecoration(
                        color: isPromoted ? Colors.amber.shade50 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: isPromoted ? Colors.amber.shade400 : Colors.grey.shade300),
                      ),
                      child: Icon(
                        isPromoted ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: isPromoted ? Colors.amber[700] : Colors.grey,
                        size: 20,
                      ),
                    ),
                  ),
                ),
                // ── Wallet top-up ─────────────────────────────────────
                IconButton(
                  icon: const Icon(Icons.add_card, color: Colors.green),
                  onPressed: () =>
                      _showAddBalanceDialog(uid, data['name'] ?? 'משתמש'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Banners Management ────────────────────────────────────────────────────

  static const _iconOptions = [
    'stars', 'school', 'emoji_events', 'favorite', 'bolt',
    'local_offer', 'rocket_launch', 'workspace_premium', 'celebration', 'trending_up',
  ];
  static const _iconLabels = {
    'stars': Icons.stars_rounded,
    'school': Icons.school_rounded,
    'emoji_events': Icons.emoji_events_rounded,
    'favorite': Icons.favorite_rounded,
    'bolt': Icons.bolt_rounded,
    'local_offer': Icons.local_offer_rounded,
    'rocket_launch': Icons.rocket_launch_rounded,
    'workspace_premium': Icons.workspace_premium_rounded,
    'celebration': Icons.celebration_rounded,
    'trending_up': Icons.trending_up_rounded,
  };

  Widget _buildBannersTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('banners')
          .orderBy('order')
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.add, color: Colors.white),
                      label: const Text("הוסף באנר", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      onPressed: () => _showBannerDialog(existingCount: docs.length),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                    label: const Text("Seed ברירת מחדל"),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: docs.isNotEmpty ? null : _seedDefaultBanners,
                  ),
                ],
              ),
            ),
            if (!snapshot.hasData)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (docs.isEmpty)
              const Expanded(
                child: Center(
                  child: Text("אין באנרים — לחץ 'Seed ברירת מחדל' או 'הוסף באנר'",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 15)),
                ),
              )
            else
              Expanded(
                child: ReorderableListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: docs.length,
                  onReorder: (oldIndex, newIndex) async {
                    if (newIndex > oldIndex) newIndex--;
                    final reordered = [...docs];
                    final moved = reordered.removeAt(oldIndex);
                    reordered.insert(newIndex, moved);
                    final batch = FirebaseFirestore.instance.batch();
                    for (int i = 0; i < reordered.length; i++) {
                      batch.update(reordered[i].reference, {'order': i});
                    }
                    await batch.commit();
                  },
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final isActive = data['isActive'] as bool? ?? true;
                    final iconName = data['iconName'] as String? ?? 'stars';
                    final color1Hex = data['color1'] as String? ?? '667eea';

                    return Card(
                      key: ValueKey(doc.id),
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                _hexToAdminColor(color1Hex),
                                _hexToAdminColor(data['color2'] as String? ?? '764ba2'),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(_iconLabels[iconName] ?? Icons.stars_rounded,
                              color: Colors.white, size: 22),
                        ),
                        title: Text(data['title'] as String? ?? '',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(data['subtitle'] as String? ?? '',
                            style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: isActive,
                              activeColor: Colors.green,
                              onChanged: (val) => doc.reference.update({'isActive': val}),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, color: Colors.blueAccent),
                              onPressed: () => _showBannerDialog(doc: doc, data: data),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                              onPressed: () => _confirmDeleteBanner(doc.id),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  static Color _hexToAdminColor(String hex) {
    final clean = hex.replaceAll('#', '').replaceAll('0x', '');
    final padded = clean.length == 6 ? 'FF$clean' : clean;
    return Color(int.parse(padded, radix: 16));
  }

  Future<void> _seedDefaultBanners() async {
    final defaults = [
      {'title': 'מצא מומחים מובילים', 'subtitle': 'אלפי מומחים מחכים לך',       'color1': '667eea', 'color2': '764ba2', 'iconName': 'stars',         'order': 0, 'isActive': true},
      {'title': 'שיעורים פרטיים',      'subtitle': 'ממש מהמקום שאתה נמצא',     'color1': '11998e', 'color2': '38ef7d', 'iconName': 'school',        'order': 1, 'isActive': true},
      {'title': 'פתח את הפוטנציאל שלך','subtitle': 'עם המומחים הטובים ביותר', 'color1': 'f953c6', 'color2': 'b91d73', 'iconName': 'emoji_events', 'order': 2, 'isActive': true},
    ];
    final batch = FirebaseFirestore.instance.batch();
    for (final b in defaults) {
      batch.set(FirebaseFirestore.instance.collection('banners').doc(), b);
    }
    await batch.commit();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("3 באנרי ברירת מחדל נוצרו")));
  }

  void _showBannerDialog({QueryDocumentSnapshot? doc, Map<String, dynamic>? data, int existingCount = 0}) {
    final titleCtrl    = TextEditingController(text: data?['title']    as String? ?? '');
    final subtitleCtrl = TextEditingController(text: data?['subtitle'] as String? ?? '');
    final color1Ctrl   = TextEditingController(text: data?['color1']   as String? ?? '667eea');
    final color2Ctrl   = TextEditingController(text: data?['color2']   as String? ?? '764ba2');
    String selectedIcon = data?['iconName'] as String? ?? 'stars';
    bool isActive = data?['isActive'] as bool? ?? true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(doc == null ? "באנר חדש" : "עריכת באנר",
              style: const TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                TextField(controller: titleCtrl,    textAlign: TextAlign.right, decoration: const InputDecoration(labelText: "כותרת")),
                const SizedBox(height: 10),
                TextField(controller: subtitleCtrl, textAlign: TextAlign.right, decoration: const InputDecoration(labelText: "תת כותרת")),
                const SizedBox(height: 10),
                TextField(controller: color1Ctrl,   textAlign: TextAlign.right, decoration: const InputDecoration(labelText: "צבע 1 (hex)", hintText: "667eea")),
                const SizedBox(height: 10),
                TextField(controller: color2Ctrl,   textAlign: TextAlign.right, decoration: const InputDecoration(labelText: "צבע 2 (hex)", hintText: "764ba2")),
                const SizedBox(height: 14),
                const Align(alignment: Alignment.centerRight, child: Text("אייקון:", style: TextStyle(fontWeight: FontWeight.bold))),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _iconOptions.map((name) {
                    final selected = name == selectedIcon;
                    return GestureDetector(
                      onTap: () => setDialogState(() => selectedIcon = name),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: selected ? Colors.blueAccent.withValues(alpha: 0.15) : Colors.grey[100],
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: selected ? Colors.blueAccent : Colors.transparent, width: 2),
                        ),
                        child: Icon(_iconLabels[name], size: 22, color: selected ? Colors.blueAccent : Colors.grey[600]),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("פעיל"),
                    Switch(value: isActive, onChanged: (v) => setDialogState(() => isActive = v)),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ביטול")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
              onPressed: () async {
                final payload = {
                  'title':    titleCtrl.text.trim(),
                  'subtitle': subtitleCtrl.text.trim(),
                  'color1':   color1Ctrl.text.trim().replaceAll('#', ''),
                  'color2':   color2Ctrl.text.trim().replaceAll('#', ''),
                  'iconName': selectedIcon,
                  'isActive': isActive,
                  'order':    data?['order'] ?? existingCount,
                };
                if (doc == null) {
                  await FirebaseFirestore.instance.collection('banners').add(payload);
                } else {
                  await doc.reference.update(payload);
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text(doc == null ? "הוסף" : "שמור",
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Monetization Tab ─────────────────────────────────────────────────────

  Widget _buildMonetizationTab(List<QueryDocumentSnapshot> allUsers) {
    final promotedUsers = allUsers
        .where((d) => (d.data() as Map<String, dynamic>)['isPromoted'] == true)
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // ── Commission Controller ──────────────────────────────────────
          _monoCard(
            icon: Icons.percent_rounded,
            color: const Color(0xFF6366F1),
            title: "עמלת פלטפורמה",
            child: _settingsLoaded
                ? Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("${_feePct.toStringAsFixed(0)}%",
                              style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF6366F1))),
                          const Text("מכל עסקה",
                              style: TextStyle(color: Colors.grey, fontSize: 13)),
                        ],
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: const Color(0xFF6366F1),
                          thumbColor: const Color(0xFF6366F1),
                          inactiveTrackColor: Colors.grey[200],
                          overlayColor: const Color(0xFF6366F1).withValues(alpha: 0.1),
                        ),
                        child: Slider(
                          value: _feePct,
                          min: 0,
                          max: 30,
                          divisions: 30,
                          onChanged: (v) => setState(() => _feePct = v),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: const [
                          Text("0%", style: TextStyle(fontSize: 11, color: Colors.grey)),
                          Text("30%", style: TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    ],
                  )
                : const Center(child: CircularProgressIndicator()),
          ),
          const SizedBox(height: 14),

          // ── Urgency Fee ───────────────────────────────────────────────
          _monoCard(
            icon: Icons.local_fire_department_rounded,
            color: const Color(0xFFEA580C),
            title: "תוספת דחיפות (בקשות דחופות)",
            child: _settingsLoaded
                ? Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("+${_urgencyFeePct.toStringAsFixed(0)}%",
                              style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFEA580C))),
                          const Text("על בקשות דחופות",
                              style: TextStyle(color: Colors.grey, fontSize: 13)),
                        ],
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: const Color(0xFFEA580C),
                          thumbColor: const Color(0xFFEA580C),
                          inactiveTrackColor: Colors.grey[200],
                          overlayColor:
                              const Color(0xFFEA580C).withValues(alpha: 0.1),
                        ),
                        child: Slider(
                          value: _urgencyFeePct,
                          min: 0,
                          max: 20,
                          divisions: 20,
                          onChanged: (v) => setState(() => _urgencyFeePct = v),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: const [
                          Text("0%", style: TextStyle(fontSize: 11, color: Colors.grey)),
                          Text("20%", style: TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    ],
                  )
                : const Center(child: CircularProgressIndicator()),
          ),
          const SizedBox(height: 14),

          // ── Save button ───────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.save_rounded, color: Colors.white),
              label: const Text("שמור הגדרות",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              onPressed: _saveAdminSettings,
            ),
          ),
          const SizedBox(height: 22),

          // ── Promoted Providers ────────────────────────────────────────
          _monoCard(
            icon: Icons.star_rounded,
            color: Colors.amber[700]!,
            title: "ספקים מקודמים (${promotedUsers.length})",
            child: promotedUsers.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text("אין ספקים מקודמים כרגע",
                        style: TextStyle(color: Colors.grey, fontSize: 13)),
                  )
                : Column(
                    children: promotedUsers.map((doc) {
                      final d = doc.data() as Map<String, dynamic>;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          radius: 20,
                          backgroundImage: (d['profileImage'] != null &&
                                  d['profileImage'] != '')
                              ? NetworkImage(d['profileImage'])
                              : null,
                          child:
                              d['profileImage'] == null ? const Icon(Icons.person) : null,
                        ),
                        title: Text(d['name'] ?? '—',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(d['serviceType'] ?? d['email'] ?? '',
                            style: const TextStyle(fontSize: 12)),
                        trailing: IconButton(
                          icon: const Icon(Icons.star_rounded,
                              color: Colors.amber, size: 22),
                          tooltip: "בטל קידום",
                          onPressed: () {
                            FirebaseFirestore.instance
                                .collection('users')
                                .doc(doc.id)
                                .update({'isPromoted': false});
                          },
                        ),
                      );
                    }).toList(),
                  ),
          ),
          const SizedBox(height: 22),

          // ── Monthly Earnings Chart ────────────────────────────────────
          _monoCard(
            icon: Icons.bar_chart_rounded,
            color: Colors.green[700]!,
            title: "עמלות החודש",
            child: _buildEarningsChart(),
          ),
          const SizedBox(height: 22),

          // ── CSV Export ────────────────────────────────────────────────
          _monoCard(
            icon: Icons.download_rounded,
            color: Colors.teal[700]!,
            title: "ייצוא לרואה חשבון",
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  "הורד את כל תנועות הארנק כקובץ CSV מוכן לפתיחה ב-Excel.",
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 13, color: Colors.grey[600], height: 1.5),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal[700],
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.table_chart_outlined, size: 18),
                    label: const Text("ייצא עסקאות ל-CSV",
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    onPressed: _exportTransactionsCsv,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _monoCard({
    required IconData icon,
    required Color color,
    required String title,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _buildEarningsChart() {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final daysInMonth = DateUtils.getDaysInMonth(now.year, now.month);

    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('platform_earnings')
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
          .orderBy('timestamp')
          .get(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: Padding(
            padding: EdgeInsets.all(20),
            child: CircularProgressIndicator(),
          ));
        }

        // Group by day-of-month
        final Map<int, double> byDay = {};
        for (final doc in snap.data!.docs) {
          final d = doc.data() as Map<String, dynamic>;
          final ts = (d['timestamp'] as Timestamp?)?.toDate();
          if (ts == null) continue;
          final fee = ((d['platformFee'] ?? d['amount'] ?? 0) as num).toDouble();
          byDay[ts.day] = (byDay[ts.day] ?? 0) + fee;
        }

        final total = byDay.values.fold(0.0, (a, b) => a + b);
        final maxVal = byDay.values.fold(0.0, (a, b) => a > b ? a : b);

        if (byDay.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Text("אין עמלות החודש עדיין",
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Total badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text("סה״כ החודש: ₪${total.toStringAsFixed(0)}",
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green[800],
                      fontSize: 15)),
            ),
            const SizedBox(height: 16),
            // Bar chart
            SizedBox(
              height: 110,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(daysInMonth, (i) {
                  final day = i + 1;
                  final val = byDay[day] ?? 0;
                  final frac = maxVal > 0 ? val / maxVal : 0.0;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (val > 0)
                            Tooltip(
                              message: "יום $day: ₪${val.toStringAsFixed(0)}",
                              child: Container(
                                height: (frac * 85).clamp(3.0, 85.0),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF6366F1),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            )
                          else
                            Container(
                              height: 3,
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          const SizedBox(height: 2),
                          if (day % 7 == 1 || day == daysInMonth)
                            Text("$day",
                                style: TextStyle(
                                    fontSize: 7, color: Colors.grey[500]))
                          else
                            const SizedBox(height: 9),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        );
      },
    );
  }

  void _confirmDeleteBanner(String docId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("מחק באנר"),
        content: const Text("האם אתה בטוח? הפעולה אינה הפיכה."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("ביטול")),
          TextButton(
            onPressed: () async {
              await FirebaseFirestore.instance.collection('banners').doc(docId).delete();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text("מחק", style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}