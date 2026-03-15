import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'profile_screen.dart';
import 'admin_screen.dart';
import 'chat_list_screen.dart';
import 'system_wallet_screen.dart';
import 'my_bookings_screen.dart';
import 'search_screen/search_page.dart';
import 'opportunities_screen.dart';
import 'my_requests_screen.dart';
import '../services/location_service.dart';
import '../services/ai_analysis_service.dart';

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
    if (uid != null) LocationService.init(uid);
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

        bool isProvider = data['isProvider'] ?? false;
        String serviceType = (data['serviceType'] ?? '') as String;
        String userName = (data['name'] ?? '') as String;

        List<Widget> pages = [
          const SearchPage(),                                         // 0. חיפוש
          MyBookingsScreen(onGoToSearch: goToSearch),                 // 1. הזמנות
          ChatListScreen(onGoToSearch: goToSearch),                   // 2. צ'אט
          _buildUserWallet(data),                                     // 3. ארנק
          const ProfileScreen(),                                      // 4. פרופיל
        ];

        if (isProvider) {
          pages.add(OpportunitiesScreen(
            serviceType: serviceType,
            providerName: userName,
          ));                                                         // 5. הזדמנויות
        }

        if (isAdmin) {
          pages.add(const AdminScreen());
          pages.add(const SystemWalletScreen());
        }

        return Scaffold(
          body: Stack(
            children: [
              IndexedStack(index: _selectedIndex, children: pages),
              // כפתור אופליין/אונליין צף - מופיע רק בדף החיפוש
              if (_selectedIndex == 0) ...[
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
                Positioned(
                  bottom: 25,
                  right: 20,
                  child: FloatingActionButton.extended(
                    elevation: 8,
                    backgroundColor: const Color(0xFF6366F1),
                    onPressed: () => _showQuickRequestSheet(context, data),
                    label: const Text('בקשה מהירה', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    icon: const Icon(Icons.campaign_rounded, color: Colors.white),
                  ),
                ),
              ],
            ],
          ),
          bottomNavigationBar: _buildEliteBottomNav(isAdmin, isProvider),
        );
      },
    );
  }

  Widget _buildEliteBottomNav(bool isAdmin, bool isProvider) {
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
              if (isProvider) ...[
                const BottomNavigationBarItem(
                  icon: Icon(Icons.work_outline_rounded),
                  activeIcon: Icon(Icons.work_rounded),
                  label: 'הזדמנויות',
                ),
              ],
              if (isAdmin) ...[
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

  void _showQuickRequestSheet(
      BuildContext context, Map<String, dynamic> userData) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _QuickRequestSheet(
        clientUid: currentUser?.uid ?? '',
        clientName: (userData['name'] ?? 'לקוח') as String,
      ),
    );
  }

  Widget _buildBannedScreen() {
    return Scaffold(body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.gpp_bad_outlined, color: Colors.redAccent, size: 100), const SizedBox(height: 20), const Text("החשבון הושעה", style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)), const SizedBox(height: 40), ElevatedButton(onPressed: () => FirebaseAuth.instance.signOut(), child: const Text("התנתקות"))])));
  }
}

// ─── Quick Request Sheet (with AI analysis) ───────────────────────────────────

class _QuickRequestSheet extends StatefulWidget {
  final String clientUid;
  final String clientName;

  const _QuickRequestSheet(
      {required this.clientUid, required this.clientName});

  @override
  State<_QuickRequestSheet> createState() => _QuickRequestSheetState();
}

class _QuickRequestSheetState extends State<_QuickRequestSheet> {
  final _descCtrl = TextEditingController();
  final _locCtrl = TextEditingController();

  RequestAnalysis _analysis = const RequestAnalysis();
  bool _isBroadcasting = false;
  // Confirmed category — set by user tapping the suggestion chip
  String? _confirmedCategory;
  int _activeRequestCount = 0;

  @override
  void initState() {
    super.initState();
    _descCtrl.addListener(_onTextChanged);
    _loadActiveRequestCount();
  }

  @override
  void dispose() {
    _descCtrl.removeListener(_onTextChanged);
    _descCtrl.dispose();
    _locCtrl.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final analysis = AiAnalysisService.analyze(_descCtrl.text);
    if (mounted) setState(() => _analysis = analysis);
  }

  Future<void> _loadActiveRequestCount() async {
    if (widget.clientUid.isEmpty) return;
    final snap = await FirebaseFirestore.instance
        .collection('job_requests')
        .where('clientId', isEqualTo: widget.clientUid)
        .where('status', isEqualTo: 'open')
        .limit(10)
        .get();
    if (mounted) setState(() => _activeRequestCount = snap.docs.length);
  }

  Future<void> _broadcast() async {
    final desc = _descCtrl.text.trim();
    if (desc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('נא לתאר את הבקשה'),
        backgroundColor: Colors.orange,
      ));
      return;
    }
    setState(() => _isBroadcasting = true);
    try {
      final pos = await LocationService.getIfGranted();
      final category = _confirmedCategory ??
          (_analysis.suggestedCategory ?? '');
      final isUrgent = _analysis.urgency == 'urgent';

      // Read urgency fee % from admin settings (only when needed)
      double urgencyFeePct = 0;
      if (isUrgent) {
        final settingsDoc = await FirebaseFirestore.instance
            .collection('admin').doc('admin')
            .collection('settings').doc('settings').get();
        final sd = settingsDoc.data() as Map<String, dynamic>? ?? {};
        urgencyFeePct = ((sd['urgencyFeePercentage'] as num?) ?? 5).toDouble();
      }

      await FirebaseFirestore.instance.collection('job_requests').add({
        'clientId': widget.clientUid,
        'clientName': widget.clientName,
        'description': desc,
        'location': _locCtrl.text.trim(),
        'category': category,
        'status': 'open',
        'urgency': _analysis.urgency ?? 'normal',
        if (isUrgent) 'urgencyFeePercentage': urgencyFeePct,
        'interestedProviders': [],
        'interestedProviderNames': [],
        'interestedCount': 0,
        'createdAt': FieldValue.serverTimestamp(),
        if (pos != null) 'clientLat': pos.latitude,
        if (pos != null) 'clientLng': pos.longitude,
      });
      if (mounted) {
        Navigator.pop(context);
        final msg = isUrgent && urgencyFeePct > 0
            ? 'הבקשה הדחופה פורסמה! תוספת דחיפות ${urgencyFeePct.toStringAsFixed(0)}% תחול על הסכום הסופי 🔥'
            : 'הבקשה פורסמה! ספקים יפנו אליך בקרוב 🚀';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: isUrgent ? const Color(0xFFEA580C) : Colors.green,
          content: Text(msg),
          duration: const Duration(seconds: 4),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              backgroundColor: Colors.red,
              content: Text('שגיאה: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isBroadcasting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 36),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Active requests banner
              if (_activeRequestCount > 0)
                GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const MyRequestsScreen()),
                    );
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFF0F0FF), Color(0xFFE8E8FF)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: const Color(0xFF6366F1)
                              .withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.arrow_forward_ios_rounded,
                            size: 14, color: Color(0xFF6366F1)),
                        const Spacer(),
                        Text(
                          'יש לך $_activeRequestCount בקשות פעילות',
                          style: const TextStyle(
                            color: Color(0xFF6366F1),
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.campaign_rounded,
                            size: 16, color: Color(0xFF6366F1)),
                      ],
                    ),
                  ),
                ),

              // Sheet header
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('פרסם בקשה מהירה',
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold)),
                      SizedBox(height: 2),
                      Text('תאר מה אתה צריך — ספקים יפנו אליך',
                          style:
                              TextStyle(color: Colors.grey, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)]),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.campaign_rounded,
                        color: Colors.white, size: 22),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Description field
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F6FA),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: TextField(
                  controller: _descCtrl,
                  maxLines: 4,
                  textAlign: TextAlign.right,
                  textDirection: TextDirection.rtl,
                  decoration: const InputDecoration(
                    hintText:
                        'תאר מה אתה צריך...\nלמשל: "צריך שרברב מחר ב-10:00 לתיקון ברז דולף"',
                    hintStyle: TextStyle(
                        color: Colors.grey, fontSize: 13, height: 1.5),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(16),
                  ),
                ),
              ),

              // ── AI analysis panel ──────────────────────────────────────
              AnimatedSize(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeInOut,
                child: _analysis.hasInsights
                    ? _buildAiInsights()
                    : const SizedBox.shrink(),
              ),

              const SizedBox(height: 12),

              // Location field
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F6FA),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: TextField(
                  controller: _locCtrl,
                  textAlign: TextAlign.right,
                  textDirection: TextDirection.rtl,
                  decoration: const InputDecoration(
                    hintText: 'אזור כללי (אופציונלי) — למשל: תל אביב',
                    hintStyle:
                        TextStyle(color: Colors.grey, fontSize: 13),
                    prefixIcon: Icon(Icons.location_on_outlined,
                        color: Colors.grey),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Broadcast button
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 58),
                  backgroundColor: const Color(0xFF6366F1),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                onPressed: _isBroadcasting ? null : _broadcast,
                child: _isBroadcasting
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.campaign_rounded,
                              color: Colors.white, size: 20),
                          SizedBox(width: 8),
                          Text('שדר לכל הספקים!',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAiInsights() {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Category suggestion
          if (_analysis.suggestedCategory != null)
            _aiChip(
              icon: '🏷️',
              label: 'נראה שמדובר ב: ${_analysis.suggestedCategory}',
              color: const Color(0xFF6366F1),
              bg: const Color(0xFFF0F0FF),
              onConfirm: () => setState(
                  () => _confirmedCategory = _analysis.suggestedCategory),
              confirmed: _confirmedCategory == _analysis.suggestedCategory,
            ),

          // Urgency signal
          if (_analysis.urgency == 'urgent') ...[
            const SizedBox(height: 6),
            _aiChip(
              icon: '🔥',
              label: 'דחוף — ספקים זמינים יקבלו עדיפות',
              color: const Color(0xFFEA580C),
              bg: const Color(0xFFFFF7ED),
            ),
          ],

          // Smart prompts for missing info
          if (_analysis.missingDate) ...[
            const SizedBox(height: 6),
            _suggestionChip(
              icon: '📅',
              label: 'מתי תרצה את השירות?',
              onTap: () {
                _descCtrl.text = '${_descCtrl.text.trimRight()} מחר בבוקר';
                _descCtrl.selection = TextSelection.fromPosition(
                    TextPosition(offset: _descCtrl.text.length));
              },
            ),
          ],
          if (_analysis.missingLocation) ...[
            const SizedBox(height: 6),
            _suggestionChip(
              icon: '📍',
              label: 'באיזה אזור?',
              onTap: () {
                _locCtrl.text = '';
                FocusScope.of(context).requestFocus(FocusNode());
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _aiChip({
    required String icon,
    required String label,
    required Color color,
    required Color bg,
    VoidCallback? onConfirm,
    bool confirmed = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (onConfirm != null && !confirmed)
            GestureDetector(
              onTap: onConfirm,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('✓ אמת',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ),
            ),
          if (confirmed)
            const Icon(Icons.check_circle_rounded,
                size: 16, color: Colors.green),
          const SizedBox(width: 8),
          Flexible(
            child: Text(label,
                textAlign: TextAlign.right,
                style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 6),
          Text(icon, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }

  Widget _suggestionChip({
    required String icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.amber[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: Colors.amber.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.amber[600],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('+ הוסף',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(label,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      color: Colors.amber[800],
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 6),
            Text(icon, style: const TextStyle(fontSize: 14)),
          ],
        ),
      ),
    );
  }
}