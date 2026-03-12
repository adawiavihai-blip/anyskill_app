import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart'; 
import 'category_results_screen.dart';
import 'map_screen.dart';
import 'profile_screen.dart';
import 'admin_screen.dart';
import 'chat_list_screen.dart';
import 'system_wallet_screen.dart';
import 'public_profile_screen.dart'; 
import 'my_bookings_screen.dart'; // QA: ייבוא דף ההזמנות החדש
import '../constants.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setOnlineStatus(true);
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
      stream: FirebaseFirestore.instance.collection('users').doc(currentUser?.uid).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        
        var data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
        bool isBanned = data['isBanned'] ?? false;
        if (isBanned && !isAdmin) return _buildBannedScreen();

        bool isOnline = data['isOnline'] ?? false;

        // QA: סידור רשימת הדפים לפי סדר הלשוניות החדש
        List<Widget> pages = [
          const SearchPage(),         // 0. חיפוש
          const MyBookingsScreen(),   // 1. הזמנות (החדש!)
          const ChatListScreen(),     // 2. צ'אט
          _buildUserWallet(data),     // 3. ארנק
          const ProfileScreen(),      // 4. פרופיל
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
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collectionGroup('messages')
          .where('receiverId', isEqualTo: currentUser?.uid)
          .where('isRead', isEqualTo: false)
          .snapshots(),
      builder: (context, snapshot) {
        int unreadCount = snapshot.hasData ? snapshot.data!.docs.length : 0;

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
                const BottomNavigationBarItem(icon: Icon(Icons.admin_panel_settings_outlined), label: 'ניהול'),
                const BottomNavigationBarItem(icon: Icon(Icons.analytics_outlined), label: 'מערכת'),
              ]
            ],
          ),
        );
      },
    );
  }

  // --- שאר הווידג'טים (ארנק, השעיה וכו') נשארים אותו דבר ---
  Widget _buildUserWallet(Map<String, dynamic> data) {
    double balance = (data['balance'] ?? 0.0).toDouble();
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
                    Text("₪${balance.toStringAsFixed(2)}", style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 25),
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
            _buildTransactionsList(),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('transactions')
          .where('userId', isEqualTo: currentUser?.uid)
          .orderBy('timestamp', descending: true).limit(10).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const SizedBox();
        return ListView.builder(
          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            var tx = snapshot.data!.docs[index].data() as Map<String, dynamic>;
            double amt = (tx['amount'] ?? 0.0).toDouble();
            bool isPlus = amt > 0;
            return ListTile(
              leading: CircleAvatar(backgroundColor: isPlus ? Colors.green[50] : Colors.red[50], child: Icon(isPlus ? Icons.add : Icons.remove, color: isPlus ? Colors.green : Colors.red, size: 16)),
              title: Text(tx['title'] ?? "פעולה במערכת", style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              trailing: Text("${isPlus ? '+' : ''}$amt ₪", style: TextStyle(color: isPlus ? Colors.green[700] : Colors.red[700], fontWeight: FontWeight.bold)),
            );
          },
        );
      },
    );
  }

  Widget _buildBannedScreen() {
    return Scaffold(body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.gpp_bad_outlined, color: Colors.redAccent, size: 100), const SizedBox(height: 20), const Text("החשבון הושעה", style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)), const SizedBox(height: 40), ElevatedButton(onPressed: () => FirebaseAuth.instance.signOut(), child: const Text("התנתקות"))])));
  }
}