import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/categories_seeder.dart';
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

  void _showAddBalanceDialog(String uid, String name, double currentBalance) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final TextEditingController amountController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text("הטענת ארנק ל-$name"),
        content: TextField(controller: amountController, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: "סכום להוספה", suffixText: "₪", border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text("ביטול")),
          ElevatedButton(onPressed: () {
            if (amountController.text.isNotEmpty) {
              double val = double.parse(amountController.text);
              FirebaseFirestore.instance.collection('users').doc(uid).update({'balance': currentBalance + val});
              Navigator.pop(dialogContext);
              scaffoldMessenger.showSnackBar(SnackBar(content: Text("נטענו ₪$val לארנק של $name")));
            }
          }, child: const Text("אשר והטען")),
        ],
      ),
    );
  }

  void _confirmDelete(String uid, String name) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("מחיקה סופית"),
        content: Text("האם למחוק את $name? לא ניתן לשחזר מידע זה."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("ביטול")),
          TextButton(onPressed: () {
            FirebaseFirestore.instance.collection('users').doc(uid).delete();
            Navigator.pop(context);
          }, child: const Text("מחק", style: TextStyle(color: Colors.red))),
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
      length: 5,
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          title: const Text("Control Center", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2)),
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          actions: [
            IconButton(
              icon: const Icon(Icons.category_rounded, color: Colors.green, size: 28),
              tooltip: "אתחל קטגוריות ב-Firestore",
              onPressed: () async {
                await CategoriesSeeder.seed();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(backgroundColor: Colors.green, content: Text("קטגוריות נכתבו ל-Firestore בהצלחה!")),
                  );
                }
              },
            ),
            IconButton(icon: const Icon(Icons.campaign_rounded, color: Colors.blueAccent, size: 30), onPressed: _showBroadcastDialog),
            const SizedBox(width: 10),
          ],
          bottom: const TabBar(
            isScrollable: true,
            labelColor: Colors.blueAccent,
            indicatorColor: Colors.blueAccent,
            tabs: [Tab(text: "הכל"), Tab(text: "לקוחות"), Tab(text: "ספקים"), Tab(text: "חסומים"), Tab(text: "מחלוקות 🔴")],
          ),
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('users').snapshots(),
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

  Widget _pulseBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
      child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
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
              onPressed: () => _showAddBalanceDialog(uid, data['name'], (data['balance'] ?? 0.0).toDouble()),
            ),
          ),
        );
      },
    );
  }
}