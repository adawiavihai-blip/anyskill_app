import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:table_calendar/table_calendar.dart';
import 'chat_screen.dart';

class ExpertProfileScreen extends StatefulWidget {
  final String expertId;
  final String expertName;

  const ExpertProfileScreen(
      {super.key, required this.expertId, required this.expertName});

  @override
  State<ExpertProfileScreen> createState() => _ExpertProfileScreenState();
}

class _ExpertProfileScreenState extends State<ExpertProfileScreen> {
  bool _isProcessing = false;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  String? _selectedTimeSlot;

  final List<String> _timeSlots = [
    "08:00", "09:00", "10:00", "11:00",
    "14:00", "15:00", "16:00", "17:00", "18:00", "19:00",
  ];

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('he_IL', null);
  }

  String _getChatRoomId(String uid1, String uid2) {
    final ids = [uid1, uid2]..sort();
    return ids.join("_");
  }

  Future<void> _processEscrowPayment(BuildContext context, double totalPrice) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    final firestore = FirebaseFirestore.instance;
    final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? "";
    final String chatRoomId = _getChatRoomId(currentUserId, widget.expertId);
    final adminSettingsRef = firestore
        .collection('admin')
        .doc('admin')
        .collection('settings')
        .doc('settings');

    // יוגדרו בתוך הטרנזקציה ויישמרו כאן כדי להיות נגישים לאחר מכן
    double expertNetEarnings = totalPrice * 0.90;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await firestore.runTransaction((transaction) async {
        // קריאת הגדרות עמלה מ-Firestore (מונע אי-התאמה בין הזמנה לשחרור)
        final adminSnap = await transaction.get(adminSettingsRef);
        final double feePercentage =
            ((adminSnap.exists ? adminSnap.get('feePercentage') : null) ?? 0.10)
                .toDouble();
        final double commission = totalPrice * feePercentage;
        expertNetEarnings = totalPrice - commission;

        final customerRef = firestore.collection('users').doc(currentUserId);
        final customerSnap = await transaction.get(customerRef);
        final double currentBalance = (customerSnap['balance'] ?? 0.0).toDouble();

        if (currentBalance < totalPrice) {
          throw "אין מספיק יתרה בארנק לביצוע ההזמנה";
        }

        final jobRef = firestore.collection('jobs').doc();
        transaction.set(jobRef, {
          'jobId': jobRef.id,
          'chatRoomId': chatRoomId,
          'customerId': currentUserId,
          'customerName': customerSnap['name'] ?? "",
          'expertId': widget.expertId,
          'expertName': widget.expertName,
          'totalPaidByCustomer': totalPrice,
          'commissionAmount': commission,
          'netAmountForExpert': expertNetEarnings,
          'appointmentDate': _selectedDay,
          'appointmentTime': _selectedTimeSlot,
          'status': 'paid_escrow',
          'createdAt': FieldValue.serverTimestamp(),
        });

        transaction.update(customerRef, {'balance': FieldValue.increment(-totalPrice)});

        transaction.set(firestore.collection('platform_earnings').doc(), {
          'jobId': jobRef.id,
          'amount': commission,
          'sourceExpertId': widget.expertId,
          'timestamp': FieldValue.serverTimestamp(),
          'status': 'pending_escrow',
        });

        transaction.set(firestore.collection('transactions').doc(), {
          'userId': currentUserId,
          'amount': -totalPrice,
          'title': "תשלום מאובטח: ${widget.expertName}",
          'timestamp': FieldValue.serverTimestamp(),
          'status': 'escrow',
        });
      });

      await _sendSystemNotification(chatRoomId, totalPrice, expertNetEarnings, currentUserId);

      if (mounted) {
        navigator.pop(); // close summary sheet
        messenger.showSnackBar(const SnackBar(
          backgroundColor: Colors.green,
          content: Text("התור שוריין והתשלום הופקד בנאמנות!"),
        ));
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(backgroundColor: Colors.red, content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _sendSystemNotification(
      String chatRoomId, double total, double net, String currentUserId) async {
    final chatRef = FirebaseFirestore.instance.collection('chats').doc(chatRoomId);
    final dateStr = _selectedDay != null
        ? "${_selectedDay!.day}/${_selectedDay!.month}"
        : "";

    await chatRef.collection('messages').add({
      'senderId': 'system',
      'message':
          "🔒 הזמנה חדשה לתאריך $dateStr בשעה $_selectedTimeSlot!\nסכום שיעבור אליך: ₪$net",
      'type': 'text',
      'timestamp': FieldValue.serverTimestamp(),
    });

    await chatRef.set({
      'lastMessage': "🔒 הזמנה חדשה על סך ₪$total",
      'lastMessageTime': FieldValue.serverTimestamp(),
      'users': [currentUserId, widget.expertId],
      'unreadCount_${widget.expertId}': FieldValue.increment(1),
    }, SetOptions(merge: true));
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance
            .collection('users')
            .doc(widget.expertId)
            .get(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!.data() as Map<String, dynamic>;

          return Stack(
            children: [
              CustomScrollView(
                slivers: [
                  SliverAppBar(
                    expandedHeight: 250,
                    pinned: true,
                    flexibleSpace: FlexibleSpaceBar(
                      title: Text(widget.expertName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              shadows: [Shadow(blurRadius: 10, color: Colors.black)])),
                      background: (data['profileImage'] != null &&
                              data['profileImage'] != "")
                          ? Image.network(data['profileImage'], fit: BoxFit.cover)
                          : Container(color: Colors.blueGrey),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildInfoRow(data),
                          const SizedBox(height: 25),
                          const Text("על המומחה",
                              style: TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 10),
                          Text(
                            data['aboutMe'] ?? "מומחה מוסמך בקהילת AnySkill.",
                            style: const TextStyle(fontSize: 16, height: 1.5),
                          ),
                          const SizedBox(height: 30),
                          const Divider(),
                          const SizedBox(height: 16),
                          const Text("בחר מועד לשירות",
                              style: TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 16),
                          _buildCalendar(_parseUnavailableDates(data)),
                          if (_selectedDay != null) ...[
                            const SizedBox(height: 16),
                            _buildTimeSlots(),
                          ],
                          const SizedBox(height: 30),
                          const Divider(),
                          const SizedBox(height: 16),
                          _buildReviewsSection(),
                          const SizedBox(height: 120), // space for bottom bar
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              _buildBottomBar(context, data),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInfoRow(Map<String, dynamic> data) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.star, color: Colors.amber, size: 20),
              Text(" ${data['rating'] ?? '5.0'}",
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ]),
            Text(data['serviceType'] ?? "נותן שירות",
                style: const TextStyle(color: Colors.grey)),
          ],
        ),
        Text("₪${data['pricePerHour'] ?? '250'} / שעה",
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
      ],
    );
  }

  // ── Calendar ──────────────────────────────────────────────────────────────
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
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: TableCalendar(
        locale: 'he_IL',
        firstDay: DateTime.now(),
        lastDay: DateTime.now().add(const Duration(days: 60)),
        focusedDay: _focusedDay,
        headerStyle: const HeaderStyle(
            formatButtonVisible: false, titleCentered: true),
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
          selectedDecoration:
              BoxDecoration(color: Colors.black, shape: BoxShape.circle),
          todayDecoration:
              BoxDecoration(color: Colors.pinkAccent, shape: BoxShape.circle),
        ),
      ),
    );
  }

  // ── Time slots ────────────────────────────────────────────────────────────
  Widget _buildTimeSlots() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("בחר שעה",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        SizedBox(
          height: 48,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            reverse: true,
            itemCount: _timeSlots.length,
            itemBuilder: (context, index) {
              final slot = _timeSlots[index];
              final isSelected = _selectedTimeSlot == slot;
              return GestureDetector(
                onTap: () => setState(() => _selectedTimeSlot = slot),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(left: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.black : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: isSelected ? Colors.black : Colors.grey.shade300),
                  ),
                  child: Center(
                    child: Text(slot,
                        style: TextStyle(
                            color: isSelected ? Colors.white : Colors.black,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Sticky bottom bar ─────────────────────────────────────────────────────
  Widget _buildBottomBar(BuildContext context, Map<String, dynamic> data) {
    final bool isReady = _selectedDay != null && _selectedTimeSlot != null;
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 20,
                offset: const Offset(0, -5))
          ],
        ),
        child: Row(
          children: [
            Container(
              decoration: BoxDecoration(
                  border: Border.all(color: Colors.black12),
                  borderRadius: BorderRadius.circular(15)),
              child: IconButton(
                icon: const Icon(Icons.chat_bubble_outline),
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => ChatScreen(
                            receiverId: widget.expertId,
                            receiverName: widget.expertName))),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isReady ? Colors.black : Colors.grey[300],
                  minimumSize: const Size(0, 58),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15)),
                ),
                onPressed: isReady ? () => _showBookingSummary(context, data) : null,
                child: _isProcessing
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        isReady
                            ? "הזמן ל-$_selectedTimeSlot"
                            : "בחר תאריך וזמן",
                        style: TextStyle(
                            color: isReady ? Colors.white : Colors.grey[600],
                            fontWeight: FontWeight.bold,
                            fontSize: 16),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Booking summary bottom sheet ──────────────────────────────────────────
  void _showBookingSummary(BuildContext context, Map<String, dynamic> data) {
    final double price = (data['pricePerHour'] ?? 250).toDouble();
    final dateStr = _selectedDay != null
        ? "${_selectedDay!.day}/${_selectedDay!.month}/${_selectedDay!.year}"
        : "";

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(25, 20, 25, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 20),
            const Text("סיכום הזמנה מאובטחת",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text("$dateStr בשעה $_selectedTimeSlot",
                style: const TextStyle(color: Colors.grey)),
            const Divider(height: 30),
            _summaryRow("מחיר השירות", "₪$price"),
            _summaryRow("הגנת הקונה AnySkill", "כלול במחיר", isGreen: true),
            const Divider(height: 20),
            _summaryRow("סה\"כ לתשלום (נאמנות)", "₪$price", isBold: true),
            const SizedBox(height: 25),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  minimumSize: const Size(double.infinity, 55),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14))),
              onPressed: () => _processEscrowPayment(context, price),
              child: const Text("אשר תשלום ושריין מועד",
                  style: TextStyle(
                      fontSize: 17,
                      color: Colors.white,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value,
      {bool isBold = false, bool isGreen = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text(value,
              style: TextStyle(
                  fontSize: 15,
                  color: isGreen ? Colors.green : Colors.black,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }

  // ── Reviews section ───────────────────────────────────────────────────────
  Widget _buildReviewsSection() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('reviews')
          .where('expertId', isEqualTo: widget.expertId)
          .orderBy('timestamp', descending: true)
          .limit(20)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              docs.isEmpty ? 'ביקורות' : 'ביקורות (${docs.length})',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (docs.isEmpty)
              const Text('אין ביקורות עדיין',
                  style: TextStyle(color: Colors.grey))
            else
              ...docs.map((doc) {
                final r = doc.data() as Map<String, dynamic>;
                final rating = (r['rating'] ?? 5).toDouble();
                final name = r['reviewerName'] ?? 'לקוח';
                final comment = (r['comment'] ?? '').toString().trim();
                final ts = r['timestamp'] as Timestamp?;
                final date = ts != null
                    ? DateFormat('dd/MM/yyyy').format(ts.toDate())
                    : '';

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          Row(
                            children: List.generate(
                                5,
                                (i) => Icon(
                                      i < rating
                                          ? Icons.star
                                          : Icons.star_border,
                                      color: Colors.amber,
                                      size: 16,
                                    )),
                          ),
                        ],
                      ),
                      if (comment.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(comment,
                            style:
                                const TextStyle(fontSize: 14, height: 1.4)),
                      ],
                      if (date.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(date,
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 11)),
                      ],
                    ],
                  ),
                );
              }),
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }
}
