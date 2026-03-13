import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'profile_screen.dart';
import 'admin_screen.dart';
import 'chat_list_screen.dart';
import 'system_wallet_screen.dart';
import 'my_bookings_screen.dart';
import 'search_screen/search_page.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  final User? currentUser = FirebaseAuth.instance.currentUser;
  final String adminEmail = "adawiavihai@gmail.com";

  // Streams מאוחסנים ב-initState — מניעת subscribe/unsubscribe מחדש בכל rebuild
  late final Stream<DocumentSnapshot> _userStream;
  late final Stream<QuerySnapshot> _chatStream;
  late final Stream<QuerySnapshot> _transactionStream;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setOnlineStatus(true);
    final uid = currentUser?.uid;
    _userStream = FirebaseFirestore.instance.collection('users').doc(uid).snapshots();
    _chatStream = FirebaseFirestore.instance
        .collection('chats')
        .where('users', arrayContains: uid)
        .snapshots();
    _transactionStream = FirebaseFirestore.instance
        .collection('transactions')
        .where('userId', isEqualTo: uid)
        .orderBy('timestamp', descending: true)
        .limit(10)
        .snapshots();
  }

  @override
  void dispose() {
    _setOnlineStatus(false);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _setOnlineStatus(bool isOnline) async {
    if (currentUser != null) {
      await FirebaseFirestore.instance.collection('users').doc(currentUser!.uid).update({
        'isOnline': isOnline,
        'lastSeen': FieldValue.serverTimestamp(),
      }).catchError((e) => debugPrint("Status error: $e"));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _setOnlineStatus(state == AppLifecycleState.resumed);
  }

  @override
  Widget build(BuildContext context) {
    bool isAdmin = currentUser?.email == adminEmail;

    return StreamBuilder<DocumentSnapshot>(
      stream: _userStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Scaffold(body: Center(child: Text("שגיאה בטעינת הפרופיל")));
        if (!snapshot.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));

        var data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
        bool isBanned = data['isBanned'] ?? false;
        if (isBanned && !isAdmin) return _buildBannedScreen();

        bool isOnline = data['isOnline'] ?? false;

        // QA: סידור רשימת הדפים לפי סדר הלשוניות החדש
        void goToSearch() => setState(() => _selectedIndex = 0);

        List<Widget> pages = [
          const SearchPage(),                                         // 0. חיפוש
          MyBookingsScreen(onGoToSearch: goToSearch),                 // 1. הזמנות
          ChatListScreen(onGoToSearch: goToSearch),                   // 2. צ'אט
          _buildUserWallet(data),                                     // 3. ארנק
          const ProfileScreen(),                                      // 4. פרופיל
        ];

        if (isAdmin) {
          pages.add(const AdminScreen());
          pages.add(const SystemWalletScreen());
        }

        return Scaffold(
          body: Stack(
            children: [
              IndexedStack(index: _selectedIndex, children: pages),
              // כפתור אופליין/אונליין צף - מופיע רק בדף החיפוש
              if (_selectedIndex == 0) 
                Positioned(
                  bottom: 25,
                  left: 20,
                  child: FloatingActionButton.extended(
                    elevation: 8,
                    backgroundColor: isOnline ? Colors.green[600] : Colors.grey[900],
                    onPressed: () => FirebaseFirestore.instance.collection('users').doc(currentUser?.uid).update({'isOnline': !isOnline}),
                    label: Text(isOnline ? "אונליין" : "אופליין", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    icon: Icon(isOnline ? Icons.bolt : Icons.power_settings_new, color: Colors.white),
                  ),
                ),
            ],
          ),
          bottomNavigationBar: _buildEliteBottomNav(isAdmin),
        );
      },
    );
  }

  Widget _buildEliteBottomNav(bool isAdmin) {
    // שאילתת chat docs (קטנות) במקום collectionGroup על כל ההודעות
    return StreamBuilder<QuerySnapshot>(
      stream: _chatStream,
      builder: (context, snapshot) {
        int unreadCount = 0;
        if (snapshot.hasData) {
          for (final doc in snapshot.data!.docs) {
            final d = doc.data() as Map<String, dynamic>;
            unreadCount += ((d['unreadCount_${currentUser?.uid}'] ?? 0) as num).toInt();
          }
        }

        return Container(
          decoration: BoxDecoration(boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 15)]),
          child: BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: (i) => setState(() => _selectedIndex = i),
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.white,
            selectedItemColor: Colors.black, // Airbnb Style - שחור כשהוא נבחר
            unselectedItemColor: Colors.grey[400],
            selectedFontSize: 11,
            unselectedFontSize: 11,
            items: [
              const BottomNavigationBarItem(
                icon: Icon(Icons.search_outlined), 
                activeIcon: Icon(Icons.search), 
                label: 'חיפוש'
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.receipt_long_outlined), // אייקון הזמנות
                activeIcon: Icon(Icons.receipt_long), 
                label: 'הזמנות'
              ),
              BottomNavigationBarItem(
                icon: Badge(
                  label: Text(unreadCount.toString()),
                  isLabelVisible: unreadCount > 0,
                  child: const Icon(Icons.chat_bubble_outline),
                ),
                activeIcon: Badge(
                  label: Text(unreadCount.toString()),
                  isLabelVisible: unreadCount > 0,
                  child: const Icon(Icons.chat_bubble),
                ),
                label: 'צ\'אט',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.account_balance_wallet_outlined), 
                activeIcon: Icon(Icons.account_balance_wallet), 
                label: 'ארנק'
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.person_outline), 
                activeIcon: Icon(Icons.person), 
                label: 'פרופיל'
              ),
              if (isAdmin) ...[
                // לאדמין — label ריק כדי לחסוך מקום בסרגל עם 7 פריטים
                const BottomNavigationBarItem(
                  icon: Icon(Icons.admin_panel_settings_outlined),
                  activeIcon: Icon(Icons.admin_panel_settings),
                  label: 'ניהול',
                  tooltip: 'ניהול',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.analytics_outlined),
                  activeIcon: Icon(Icons.analytics),
                  label: 'מערכת',
                  tooltip: 'מערכת',
                ),
              ]
            ],
          ),
        );
      },
    );
  }

  // --- ארנק ---
  Widget _buildUserWallet(Map<String, dynamic> data) {
    double balance = (data['balance'] ?? 0.0).toDouble();
    bool isProvider = data['isProvider'] ?? false;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(title: const Text("הארנק שלי", style: TextStyle(fontWeight: FontWeight.bold)), centerTitle: true, elevation: 0, backgroundColor: Colors.white),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Container(
                width: double.infinity, padding: const EdgeInsets.all(35),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF1A237E), Color(0xFF0D47A1)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(35),
                  boxShadow: [BoxShadow(color: Colors.blue.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 10))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("יתרה זמינה", style: TextStyle(color: Colors.white70, fontSize: 16)),
                    const SizedBox(height: 12),
                    // FittedBox מונע overflow של מספרים ארוכים במסכים צרים
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        "₪${balance.toStringAsFixed(2)}",
                        style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Wrap מונע overflow כשהמסך צר מדי לשני כפתורים בשורה
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        // Top-up button
                        GestureDetector(
                          onTap: () => _showTopUpSheet(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white30),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add, color: Colors.white, size: 18),
                                SizedBox(width: 6),
                                Text("הוסף יתרה", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                              ],
                            ),
                          ),
                        ),
                        if (isProvider && balance > 0)
                          // Withdraw button
                          GestureDetector(
                            onTap: () => _showWithdrawSheet(context, balance),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.green.shade300),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.arrow_upward, color: Colors.white, size: 18),
                                  SizedBox(width: 6),
                                  Text("משיכה", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Divider(color: Colors.white24),
                    const SizedBox(height: 10),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(data['name']?.toUpperCase() ?? "ELITE USER", style: const TextStyle(color: Colors.white, fontSize: 12, letterSpacing: 1.2)),
                      const Icon(Icons.security, color: Colors.white54, size: 22),
                    ]),
                  ],
                ),
              ),
            ),
            _buildTransactionsList(isProvider: isProvider),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionsList({bool isProvider = false}) {
    return StreamBuilder<QuerySnapshot>(
      stream: _transactionStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          if (!isProvider) return const SizedBox();
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: Column(
              children: [
                Icon(Icons.receipt_long_outlined, size: 52, color: Colors.grey[300]),
                const SizedBox(height: 16),
                const Text(
                  "אין עסקאות עדיין",
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                const SizedBox(height: 8),
                Text(
                  "כשתסיים שירות ותקבל תשלום, הרווחים יופיעו כאן",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                ),
              ],
            ),
          );
        }

        final docs = snapshot.data!.docs;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Text(
                "היסטוריית עסקאות",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey[800]),
              ),
            ),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                var tx = docs[index].data() as Map<String, dynamic>;
                double amt = (tx['amount'] ?? 0.0).toDouble();
                bool isPlus = amt > 0;
                String title = tx['title'] ?? "פעולה במערכת";
                String type = tx['type'] ?? '';

                String dateStr = '';
                final ts = tx['timestamp'];
                if (ts is Timestamp) {
                  final dt = ts.toDate();
                  dateStr = '${dt.day.toString().padLeft(2, '0')}/'
                      '${dt.month.toString().padLeft(2, '0')}/'
                      '${dt.year}  '
                      '${dt.hour.toString().padLeft(2, '0')}:'
                      '${dt.minute.toString().padLeft(2, '0')}';
                }

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isPlus ? Colors.green[50] : Colors.red[50],
                    child: Icon(
                      type == 'earning' ? Icons.trending_up : (isPlus ? Icons.add : Icons.remove),
                      color: isPlus ? Colors.green : Colors.red,
                      size: 18,
                    ),
                  ),
                  title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: dateStr.isNotEmpty
                      ? Text(dateStr, style: TextStyle(fontSize: 11, color: Colors.grey[500]))
                      : null,
                  trailing: Text(
                    "${isPlus ? '+' : ''}${amt.toStringAsFixed(2)} ₪",
                    style: TextStyle(
                      color: isPlus ? Colors.green[700] : Colors.red[700],
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  void _showTopUpSheet(BuildContext context) {
    double selectedAmount = 100;
    bool useCustom = false;
    final customController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModal) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text("הוסף יתרה לארנק", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text("בחר סכום לטעינה", style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 20),
                  // Preset chips
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [50, 100, 200, 500].map((amt) {
                      final active = !useCustom && selectedAmount == amt.toDouble();
                      return GestureDetector(
                        onTap: () => setModal(() {
                          selectedAmount = amt.toDouble();
                          useCustom = false;
                          customController.clear();
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                          decoration: BoxDecoration(
                            color: active ? Colors.black : Colors.grey[100],
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text("₪$amt",
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: active ? Colors.white : Colors.black)),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  // Custom amount
                  TextField(
                    controller: customController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.right,
                    onChanged: (v) {
                      final parsed = double.tryParse(v);
                      setModal(() {
                        if (parsed != null && parsed > 0) {
                          selectedAmount = parsed;
                          useCustom = true;
                        } else {
                          useCustom = false;
                        }
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'סכום מותאם אישית...',
                      prefixText: '₪ ',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Icon(Icons.info_outline, size: 14, color: Colors.grey[400]),
                    const SizedBox(width: 6),
                    Text("סביבת הדגמה — לא מחויב כרטיס אמיתי",
                        style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                  ]),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      minimumSize: const Size(double.infinity, 56),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: selectedAmount > 0
                        ? () async {
                            final amount = selectedAmount;
                            final messenger = ScaffoldMessenger.of(context);
                            Navigator.pop(context);
                            await _executeTopUp(amount);
                            if (mounted) {
                              messenger.showSnackBar(SnackBar(
                                backgroundColor: Colors.green,
                                content: Text("₪${amount.toStringAsFixed(0)} נוספו לארנק שלך!"),
                              ));
                            }
                          }
                        : null,
                    child: Text(
                      "הוסף ₪${selectedAmount.toStringAsFixed(0)} לארנק",
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _executeTopUp(double amount) async {
    final uid = currentUser?.uid ?? '';
    if (uid.isEmpty) return;

    final db = FirebaseFirestore.instance;
    await db.runTransaction((tx) async {
      final userRef = db.collection('users').doc(uid);
      tx.update(userRef, {'balance': FieldValue.increment(amount)});
      tx.set(db.collection('transactions').doc(), {
        'userId': uid,
        'amount': amount,
        'title': 'טעינת ארנק',
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'topup',
      });
    });
  }

  void _showWithdrawSheet(BuildContext context, double availableBalance) {
    double selectedAmount = availableBalance < 100 ? availableBalance : 100;
    bool useCustom = false;
    final customController = TextEditingController();
    final bankNameController = TextEditingController();
    final accountNumberController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModal) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40, height: 4,
                        decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text("משיכת כספים", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text("יתרה זמינה: ₪${availableBalance.toStringAsFixed(2)}", style: TextStyle(color: Colors.grey[600])),
                    const SizedBox(height: 20),
                    // Preset chips
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [50, 100, 200, 500].where((amt) => amt.toDouble() <= availableBalance).map((amt) {
                        final active = !useCustom && selectedAmount == amt.toDouble();
                        return GestureDetector(
                          onTap: () => setModal(() {
                            selectedAmount = amt.toDouble();
                            useCustom = false;
                            customController.clear();
                          }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                            decoration: BoxDecoration(
                              color: active ? Colors.black : Colors.grey[100],
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text("₪$amt",
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: active ? Colors.white : Colors.black)),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    // Custom amount
                    TextField(
                      controller: customController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.right,
                      onChanged: (v) {
                        final parsed = double.tryParse(v);
                        setModal(() {
                          if (parsed != null && parsed > 0 && parsed <= availableBalance) {
                            selectedAmount = parsed;
                            useCustom = true;
                          } else {
                            useCustom = false;
                          }
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'סכום אחר (עד ₪${availableBalance.toStringAsFixed(0)})...',
                        prefixText: '₪ ',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text("פרטי חשבון בנק", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 10),
                    TextField(
                      controller: bankNameController,
                      textAlign: TextAlign.right,
                      onChanged: (_) => setModal(() {}),
                      decoration: InputDecoration(
                        hintText: 'שם הבנק (למשל: בנק הפועלים)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: accountNumberController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.right,
                      onChanged: (_) => setModal(() {}),
                      decoration: InputDecoration(
                        hintText: 'מספר חשבון',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(children: [
                      Icon(Icons.info_outline, size: 14, color: Colors.grey[400]),
                      const SizedBox(width: 6),
                      Text("הבקשה תטופל תוך 1–3 ימי עסקים",
                          style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                    ]),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        minimumSize: const Size(double.infinity, 56),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: (selectedAmount > 0 &&
                              bankNameController.text.trim().isNotEmpty &&
                              accountNumberController.text.trim().isNotEmpty)
                          ? () async {
                              final amount = selectedAmount;
                              final bank = bankNameController.text.trim();
                              final account = accountNumberController.text.trim();
                              final messenger = ScaffoldMessenger.of(context);
                              Navigator.pop(context);
                              await _executeWithdrawal(amount, bank, account);
                              if (mounted) {
                                messenger.showSnackBar(SnackBar(
                                  backgroundColor: Colors.green,
                                  content: Text("בקשת משיכה של ₪${amount.toStringAsFixed(0)} נשלחה!"),
                                ));
                              }
                            }
                          : null,
                      child: Text(
                        selectedAmount > 0
                            ? "בקש משיכה של ₪${selectedAmount.toStringAsFixed(0)}"
                            : "הזן פרטים להמשך",
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _executeWithdrawal(double amount, String bankName, String accountNumber) async {
    final uid = currentUser?.uid ?? '';
    if (uid.isEmpty) return;

    final db = FirebaseFirestore.instance;
    await db.runTransaction((tx) async {
      final userRef = db.collection('users').doc(uid);
      tx.update(userRef, {'balance': FieldValue.increment(-amount)});
      tx.set(db.collection('transactions').doc(), {
        'userId': uid,
        'amount': -amount,
        'title': 'בקשת משיכה לבנק',
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'withdrawal',
      });
      tx.set(db.collection('withdrawals').doc(), {
        'userId': uid,
        'amount': amount,
        'bankName': bankName,
        'accountNumber': accountNumber,
        'status': 'pending',
        'requestedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Widget _buildBannedScreen() {
    return Scaffold(body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.gpp_bad_outlined, color: Colors.redAccent, size: 100), const SizedBox(height: 20), const Text("החשבון הושעה", style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)), const SizedBox(height: 40), ElevatedButton(onPressed: () => FirebaseAuth.instance.signOut(), child: const Text("התנתקות"))])));
  }
}