import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'chat_screen.dart';
import 'my_bookings_screen.dart';
import '../l10n/app_localizations.dart'; // ignore: unused_import — will be used in future i18n pass

class PublicProfileScreen extends StatefulWidget {
  final String userId;
  const PublicProfileScreen({super.key, required this.userId});

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  String? _selectedTimeSlot;
  bool _isProcessing = false;
  int _refreshTrigger = 0;

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('he_IL', null);
  }

  final List<String> _availableSlots = ["08:00", "09:00", "10:00", "11:00", "16:00", "17:00", "18:00", "19:00"];

  Future<void> _processEscrowOrder(BuildContext context, Map<String, dynamic> expertData) async {
    final double price = (expertData['pricePerHour'] ?? 100).toDouble();
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
          padding: const EdgeInsets.fromLTRB(25, 15, 25, 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
              const SizedBox(height: 25),
              const Text("סיכום הזמנה מאובטחת", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Text("אימון עם ${expertData['name']} בתאריך ${_selectedDay?.day}/${_selectedDay?.month} בשעה $_selectedTimeSlot", 
                   textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
              const Divider(height: 40),
              _summaryRow("מחיר השירות", "₪$price"),
              _summaryRow("הגנת AnySkill", "כלול", isGreen: true),
              const Divider(height: 30),
              _summaryRow("סה\"כ לתשלום", "₪$price", isBold: true),
              const SizedBox(height: 30),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.black, minimumSize: const Size(double.infinity, 60), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                onPressed: _isProcessing ? null : () async {
                  setModalState(() => _isProcessing = true);
                  await _executeEscrow(context, price, expertData['name'] ?? "מומחה");
                  if (mounted) setModalState(() => _isProcessing = false);
                },
                child: _isProcessing 
                  ? const CircularProgressIndicator(color: Colors.white) 
                  : const Text("אשר תשלום ושריין מועד", style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _executeEscrow(BuildContext context, double amount, String expertName) async {
    final firestore = FirebaseFirestore.instance;
    final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? "";
    List<String> ids = [currentUserId, widget.userId]; ids.sort(); String chatRoomId = ids.join("_");
    final adminSettingsRef = firestore
        .collection('admin')
        .doc('admin')
        .collection('settings')
        .doc('settings');

    try {
      await firestore.runTransaction((transaction) async {
        // קריאת עמלה דינמית מ-Firestore
        final adminSnap = await transaction.get(adminSettingsRef);
        final double feePercentage =
            ((adminSnap.exists ? adminSnap.get('feePercentage') : null) ?? 0.10)
                .toDouble();
        final double commission = amount * feePercentage;
        final double netToExpert = amount - commission;

        DocumentReference customerRef = firestore.collection('users').doc(currentUserId);
        DocumentSnapshot customerSnap = await transaction.get(customerRef);
        double balance = (customerSnap['balance'] ?? 0.0).toDouble();

        if (balance < amount) throw "אין מספיק יתרה בארנק. טען כסף והמשך.";

        DocumentReference jobRef = firestore.collection('jobs').doc();
        transaction.set(jobRef, {
          'jobId': jobRef.id,
          'chatRoomId': chatRoomId,
          'customerId': currentUserId,
          'customerName': customerSnap['name'] ?? "",
          'expertId': widget.userId,
          'expertName': expertName,
          'totalAmount': amount,
          'commissionAmount': commission,
          'netAmountForExpert': netToExpert,
          'appointmentDate': _selectedDay,
          'appointmentTime': _selectedTimeSlot,
          'status': 'paid_escrow',
          'createdAt': FieldValue.serverTimestamp(),
        });

        // FieldValue.increment מונע race condition
        transaction.update(customerRef, {'balance': FieldValue.increment(-amount)});

        transaction.set(firestore.collection('transactions').doc(), {
          'userId': currentUserId,
          'amount': -amount,
          'title': "שריון תור: $expertName",
          'timestamp': FieldValue.serverTimestamp(),
          'status': 'escrow'
        });
      });

      await firestore.collection('chats').doc(chatRoomId).collection('messages').add({
        'senderId': 'system',
        'message': "🔒 שוריין תור לתאריך ${_selectedDay?.day}/${_selectedDay?.month} בשעה $_selectedTimeSlot. התשלום הופקד בנאמנות.",
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'text'
      });

      if (context.mounted) {
        Navigator.pop(context);
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const MyBookingsScreen()));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: Colors.green, content: Text("התור שוריין בהצלחה!")));
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.red, content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      key: ValueKey(_refreshTrigger),
      future: FirebaseFirestore.instance.collection('users').doc(widget.userId).get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        var data = snapshot.data!.data() as Map<String, dynamic>? ?? {};

        return Scaffold(
          backgroundColor: Colors.white,
          body: Stack(
            children: [
              RefreshIndicator(
                onRefresh: () async => setState(() => _refreshTrigger++),
                child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  _buildSliverAppBar(context, data), // תיקון: הוספת context
                  SliverList(
                    delegate: SliverChildListDelegate([
                      const SizedBox(height: 20),
                      _buildMainInfo(data),
                      const Padding(padding: EdgeInsets.symmetric(horizontal: 25, vertical: 10), child: Divider()),
                      const Padding(padding: EdgeInsets.symmetric(horizontal: 25, vertical: 10), child: Text("בחר מועד לאימון", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
                      _buildCalendar(_parseUnavailableDates(data)),
                      if (_selectedDay != null) _buildTimeSlots(),
                      const Padding(padding: EdgeInsets.symmetric(horizontal: 25, vertical: 25), child: Divider(thickness: 0.8)),
                      _buildSection("אודות המאמן", data['bio'] ?? "אין תיאור זמין"),
                      _buildGallerySection(data['gallery']),
                      const SizedBox(height: 150),
                    ]),
                  ),
                ],
              ),
              ),
              _buildBottomAction(context, data),
            ],
          ),
        );
      },
    );
  }

  Set<DateTime> _parseUnavailableDates(Map<String, dynamic> data) {
    final raw = data['unavailableDates'] as List<dynamic>? ?? [];
    return raw
        .map((d) => DateTime.tryParse(d.toString()))
        .whereType<DateTime>()
        .map((d) => DateTime.utc(d.year, d.month, d.day))
        .toSet();
  }

  Widget _buildCalendar(Set<DateTime> unavailableDates) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey[200]!)),
      child: TableCalendar(
        locale: 'he_IL',
        firstDay: DateTime.now(),
        lastDay: DateTime.now().add(const Duration(days: 30)),
        focusedDay: _focusedDay,
        headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true),
        selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
        enabledDayPredicate: (day) {
          final normalized = DateTime.utc(day.year, day.month, day.day);
          return !unavailableDates.contains(normalized);
        },
        onDaySelected: (selectedDay, focusedDay) {
          setState(() {
            _selectedDay = selectedDay;
            _focusedDay = focusedDay;
            _selectedTimeSlot = null;
          });
        },
        calendarBuilders: CalendarBuilders(
          disabledBuilder: (context, day, focusedDay) {
            final normalized = DateTime.utc(day.year, day.month, day.day);
            if (!unavailableDates.contains(normalized)) return null;
            return Center(
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle),
                child: Center(
                  child: Text('${day.day}',
                    style: TextStyle(color: Colors.red.shade300, fontWeight: FontWeight.bold)),
                ),
              ),
            );
          },
        ),
        calendarStyle: const CalendarStyle(
          selectedDecoration: BoxDecoration(color: Colors.black, shape: BoxShape.circle),
          todayDecoration: BoxDecoration(color: Colors.pinkAccent, shape: BoxShape.circle),
        ),
      ),
    );
  }

  Widget _buildTimeSlots() {
    return Container(
      height: 55,
      margin: const EdgeInsets.only(top: 20),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _availableSlots.length,
        itemBuilder: (context, index) {
          bool isSelected = _selectedTimeSlot == _availableSlots[index];
          return GestureDetector(
            onTap: () => setState(() => _selectedTimeSlot = _availableSlots[index]),
            child: Container(
              margin: const EdgeInsets.only(left: 10),
              padding: const EdgeInsets.symmetric(horizontal: 25),
              decoration: BoxDecoration(color: isSelected ? Colors.black : Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: isSelected ? Colors.black : Colors.grey[300]!)),
              child: Center(child: Text(_availableSlots[index], style: TextStyle(color: isSelected ? Colors.white : Colors.black, fontWeight: FontWeight.bold))),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBottomAction(BuildContext context, Map<String, dynamic> data) {
    bool isReady = _selectedDay != null && _selectedTimeSlot != null;
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(25, 15, 25, 35),
        decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, -5))]),
        child: Row(
          children: [
            Container(decoration: BoxDecoration(border: Border.all(color: Colors.black12), borderRadius: BorderRadius.circular(15)), child: IconButton(icon: const Icon(Icons.chat_bubble_outline), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ChatScreen(receiverId: widget.userId, receiverName: data['name'] ?? "מומחה"))))),
            const SizedBox(width: 15),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: isReady ? Colors.black : Colors.grey[300], minimumSize: const Size(0, 60), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                onPressed: isReady ? () => _processEscrowOrder(context, data) : null,
                child: Text(isReady ? "הזמן ל-$_selectedTimeSlot" : "בחר תאריך וזמן", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliverAppBar(BuildContext context, Map<String, dynamic> data) {
    return SliverAppBar(
      expandedHeight: 350, pinned: true, backgroundColor: Colors.white, elevation: 0,
      leading: Padding(padding: const EdgeInsets.all(10), child: CircleAvatar(backgroundColor: Colors.white.withValues(alpha: 0.8), child: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.black), onPressed: () => Navigator.pop(context)))),
      flexibleSpace: FlexibleSpaceBar(background: Hero(tag: widget.userId, child: Image.network(data['profileImage'] ?? "", fit: BoxFit.cover, errorBuilder: (c, e, s) => Container(color: Colors.blueGrey)))),
    );
  }

  Widget _buildMainInfo(Map<String, dynamic> data) {
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 25), child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text(data['name'] ?? "", style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)), Text(data['serviceType'] ?? "מאמן AnySkill", style: const TextStyle(fontSize: 16, color: Colors.grey))]));
  }

  Widget _buildSection(String title, String content) {
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 25), child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), const SizedBox(height: 12), Text(content, style: const TextStyle(fontSize: 15, color: Colors.black87, height: 1.6), textAlign: TextAlign.right)]));
  }

  Widget _buildGallerySection(List<dynamic>? gallery) {
    if (gallery == null || gallery.isEmpty) return const SizedBox();
    return SizedBox(height: 200, child: ListView.builder(scrollDirection: Axis.horizontal, reverse: true, padding: const EdgeInsets.symmetric(horizontal: 20), itemCount: gallery.length, itemBuilder: (context, index) => Container(width: 280, margin: const EdgeInsets.only(left: 15), decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), image: DecorationImage(image: NetworkImage(gallery[index].toString()), fit: BoxFit.cover)))));
  }

  Widget _summaryRow(String label, String value, {bool isBold = false, bool isGreen = false}) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label), Text(value, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: isGreen ? Colors.green : Colors.black))]));
  }
}