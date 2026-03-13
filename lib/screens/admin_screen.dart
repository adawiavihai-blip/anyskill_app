import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart';
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
    bool isBanned = data['isBanned'] ?? false;
    bool isVerified = data['isVerified'] ?? false;
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
      length: 7,
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
            tabs: [Tab(text: "הכל"), Tab(text: "לקוחות"), Tab(text: "ספקים"), Tab(text: "חסומים"), Tab(text: "מחלוקות 🔴"), Tab(text: "משיכות 💸"), Tab(text: "קטגוריות 🏷️")],
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
                    const SizedBox(height: 8),
                    Text("בנק: ${w['bankName'] ?? '—'}",
                        style: const TextStyle(fontSize: 13)),
                    Text("מספר חשבון: ${w['accountNumber'] ?? '—'}",
                        style: const TextStyle(fontSize: 13)),
                    Text("מזהה משתמש: ${w['userId'] ?? '—'}",
                        style: TextStyle(fontSize: 11, color: Colors.grey[500])),
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
                            icon: const Icon(Icons.close, color: Colors.red, size: 18),
                            label: const Text("דחה",
                                style: TextStyle(color: Colors.red, fontSize: 13)),
                            onPressed: () async {
                              // Reject: refund balance back to user
                              final uid = w['userId'] ?? '';
                              await FirebaseFirestore.instance.runTransaction((tx) async {
                                tx.update(FirebaseFirestore.instance.collection('withdrawals').doc(wId),
                                    {'status': 'rejected', 'resolvedAt': FieldValue.serverTimestamp()});
                                if (uid.isNotEmpty) {
                                  tx.update(FirebaseFirestore.instance.collection('users').doc(uid),
                                      {'balance': FieldValue.increment(amount)});
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
                            label: const Text("אשר העברה",
                                style: TextStyle(color: Colors.white, fontSize: 13)),
                            onPressed: () async {
                              await FirebaseFirestore.instance
                                  .collection('withdrawals')
                                  .doc(wId)
                                  .update({
                                'status': 'approved',
                                'resolvedAt': FieldValue.serverTimestamp(),
                              });
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    backgroundColor: Colors.green,
                                    content: Text("הועברה אושרה — יש לבצע העברה ידנית"),
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
        bool isVerified = data['isVerified'] ?? false;
        bool isOnline = data['isOnline'] ?? false;
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
            trailing: IconButton(
              icon: const Icon(Icons.add_card, color: Colors.green),
              onPressed: () => _showAddBalanceDialog(uid, data['name'] ?? 'משתמש'),
            ),
          ),
        );
      },
    );
  }
}