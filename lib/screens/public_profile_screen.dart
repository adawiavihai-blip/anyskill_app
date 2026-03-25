import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'chat_screen.dart';
import 'my_bookings_screen.dart';
import '../models/pricing_model.dart';
import '../widgets/xp_progress_bar.dart';

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

  final List<String> _availableSlots = [
    "08:00", "09:00", "10:00", "11:00",
    "16:00", "17:00", "18:00", "19:00",
  ];

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('he_IL', null);
  }

  // ── Escrow booking flow ────────────────────────────────────────────────────

  Future<void> _processEscrowOrder(
      BuildContext context, Map<String, dynamic> expertData) async {
    final pricing = PricingModel.fromFirestore(expertData);
    final Set<int> selectedAddOns = {};

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final addOnTotal = selectedAddOns.fold<double>(
              0.0,
              (s, i) =>
                  s + (i < pricing.addOns.length ? pricing.addOns[i].price : 0.0));
          final total = pricing.basePrice + addOnTotal;

          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            ),
            padding: const EdgeInsets.fromLTRB(25, 15, 25, 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 20),
                const Text("סיכום הזמנה מאובטחת",
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                  "${expertData['name']} • ${_selectedDay?.day}/${_selectedDay?.month} בשעה $_selectedTimeSlot",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const Divider(height: 32),
                _summaryRow(
                    "מחיר בסיס (${pricing.unitLabel})",
                    "₪${pricing.basePrice.toStringAsFixed(0)}"),
                if (pricing.addOns.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Text("תוספות אופציונליות",
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                  const SizedBox(height: 6),
                  ...pricing.addOns.asMap().entries.map((entry) {
                    final i = entry.key;
                    final ao = entry.value;
                    final checked = selectedAddOns.contains(i);
                    return GestureDetector(
                      onTap: () => setModalState(() {
                        if (checked) {
                          selectedAddOns.remove(i);
                        } else {
                          selectedAddOns.add(i);
                        }
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: checked
                              ? const Color(0xFFF0F0FF)
                              : Colors.grey[50],
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: checked
                                ? const Color(0xFF6366F1)
                                : Colors.grey.shade200,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              checked
                                  ? Icons.check_box_rounded
                                  : Icons.check_box_outline_blank_rounded,
                              color: checked
                                  ? const Color(0xFF6366F1)
                                  : Colors.grey,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '+₪${ao.price.toStringAsFixed(0)}',
                              style: const TextStyle(
                                color: Color(0xFF6366F1),
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                              ),
                            ),
                            const Spacer(),
                            Text(ao.title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 13)),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
                const SizedBox(height: 6),
                _summaryRow("הגנת AnySkill", "כלול", isGreen: true),
                const Divider(height: 24),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: KeyedSubtree(
                    key: ValueKey(total),
                    child: _summaryRow(
                      "סה\"כ לתשלום",
                      "₪${total.toStringAsFixed(0)}",
                      isBold: true,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    minimumSize: const Size(double.infinity, 60),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15)),
                  ),
                  onPressed: _isProcessing
                      ? null
                      : () async {
                          setModalState(() => _isProcessing = true);
                          await _executeEscrow(
                              context, total, expertData['name'] ?? "מומחה");
                          if (mounted) {
                            setModalState(() => _isProcessing = false);
                          }
                        },
                  child: _isProcessing
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text("אשר תשלום ושריין מועד",
                          style: TextStyle(
                              fontSize: 18,
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _executeEscrow(
      BuildContext context, double amount, String expertName) async {
    final firestore = FirebaseFirestore.instance;
    final String currentUserId =
        FirebaseAuth.instance.currentUser?.uid ?? "";
    final List<String> ids = [currentUserId, widget.userId]..sort();
    final String chatRoomId = ids.join("_");
    final adminSettingsRef = firestore
        .collection('admin')
        .doc('admin')
        .collection('settings')
        .doc('settings');

    try {
      await firestore.runTransaction((transaction) async {
        final adminSnap = await transaction.get(adminSettingsRef);
        final double feePercentage =
            ((adminSnap.exists ? adminSnap.get('feePercentage') : null) ??
                    0.10)
                .toDouble();
        final double commission = amount * feePercentage;
        final double netToExpert = amount - commission;

        final customerRef =
            firestore.collection('users').doc(currentUserId);
        final customerSnap = await transaction.get(customerRef);
        final double balance =
            (customerSnap['balance'] ?? 0.0).toDouble();

        if (balance < amount) {
          throw "אין מספיק יתרה בארנק. טען כסף והמשך.";
        }

        final jobRef = firestore.collection('jobs').doc();
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

        transaction.update(
            customerRef, {'balance': FieldValue.increment(-amount)});

        transaction.set(firestore.collection('transactions').doc(), {
          'userId': currentUserId,
          'amount': -amount,
          'title': "שריון תור: $expertName",
          'timestamp': FieldValue.serverTimestamp(),
          'status': 'escrow',
        });
      });

      await firestore
          .collection('chats')
          .doc(chatRoomId)
          .collection('messages')
          .add({
        'senderId': 'system',
        'message':
            "🔒 שוריין תור לתאריך ${_selectedDay?.day}/${_selectedDay?.month} בשעה $_selectedTimeSlot. התשלום הופקד בנאמנות.",
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'text',
      });

      if (context.mounted) {
        Navigator.pop(context);
        Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => const MyBookingsScreen()));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            backgroundColor: Colors.green,
            content: Text("התור שוריין בהצלחה!")));
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: Colors.red,
            content: Text(e.toString())));
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      key: ValueKey(_refreshTrigger),
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final data =
            snapshot.data!.data() as Map<String, dynamic>? ?? {};

        return Scaffold(
          // ── Light grey background matches ProfileScreen ──────────────
          backgroundColor: const Color(0xFFF8F9FA),
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            foregroundColor: Colors.black,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.black),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: Stack(
            children: [
              RefreshIndicator(
                onRefresh: () async =>
                    setState(() => _refreshTrigger++),
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverList(
                      delegate: SliverChildListDelegate([
                        // ── 1. Large white card: avatar + stats + XP ──
                        _buildSpecialistCard(data),
                        const SizedBox(height: 14),
                        // ── 2. Action squares: Gallery | VIP ──────────
                        _buildActionSquares(context, data),
                        const Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 25, vertical: 10),
                          child: Divider(),
                        ),
                        // ── 3. Calendar & time-slot booking ───────────
                        const Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 25, vertical: 10),
                          child: Text("בחר מועד לאימון",
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold)),
                        ),
                        _buildCalendar(_parseUnavailableDates(data)),
                        if (_selectedDay != null) _buildTimeSlots(),
                        // ── 4. About & inline gallery ─────────────────
                        const Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 25, vertical: 25),
                          child: Divider(thickness: 0.8),
                        ),
                        _buildSection("אודות המאמן",
                            data['bio'] ?? "אין תיאור זמין"),
                        _buildGallerySection(
                            data['gallery'] as List<dynamic>?),
                        const SizedBox(height: 150),
                      ]),
                    ),
                  ],
                ),
              ),
              // ── 5. Sticky bottom bar: chat + book ─────────────────
              _buildBottomAction(context, data),
            ],
          ),
        );
      },
    );
  }

  // ── Specialist card (matches ProfileScreen specialist header exactly) ──────

  Widget _buildSpecialistCard(Map<String, dynamic> data) {
    final profileImg = data['profileImage'] as String? ?? '';
    final hasImg = profileImg.isNotEmpty && profileImg.startsWith('http');
    final name = data['name'] as String? ?? '';
    final isVerified = data['isVerified'] == true;
    final isVolunteer = data['isVolunteer'] == true;
    final serviceType = data['serviceType'] as String? ?? '';
    final bio = ((data['aboutMe'] ?? data['bio'] ?? '') as Object).toString();
    final xp = (data['xp'] as num? ?? 0).toInt();
    final rating = data['rating'] ?? '5.0';
    final reviewsCount = (data['reviewsCount'] as num? ?? 0).toInt();
    final jobsCount =
        (data['completedJobsCount'] as num? ?? reviewsCount).toInt();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 20,
            spreadRadius: 0,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── LEFT: name, role, specialty, bio, stats ──────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Name row with badges
                    Row(
                      children: [
                        if (isVerified) ...[
                          const Icon(Icons.verified,
                              color: Colors.blue, size: 18),
                          const SizedBox(width: 5),
                        ],
                        if (isVolunteer) ...[
                          const Icon(Icons.favorite,
                              color: Colors.red, size: 16),
                          const SizedBox(width: 5),
                        ],
                        Flexible(
                          child: Text(
                            name,
                            style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                                color: Colors.black),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'נותן שירות',
                      style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF9CA3AF),
                          fontWeight: FontWeight.w400),
                    ),
                    if (serviceType.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(serviceType,
                          style: const TextStyle(
                              color: Color(0xFF6366F1),
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ],
                    if (bio.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(bio,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12.5,
                              height: 1.4)),
                    ],
                    const SizedBox(height: 14),
                    // Stats
                    _statRow(
                        label: 'עבודות',
                        value: '$jobsCount',
                        icon: Icons.shield_outlined,
                        iconColor: const Color(0xFF6366F1)),
                    const Divider(
                        height: 20,
                        color: Color(0xFFF3F4F6),
                        thickness: 1),
                    _statRow(
                        label: 'דירוג',
                        value: '$rating',
                        icon: Icons.star_rounded,
                        iconColor: Colors.amber),
                    const Divider(
                        height: 20,
                        color: Color(0xFFF3F4F6),
                        thickness: 1),
                    _statRow(
                        label: 'ביקורות',
                        value: '$reviewsCount',
                        icon: Icons.chat_bubble_outline_rounded,
                        iconColor: Colors.teal),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // ── RIGHT: profile photo ──────────────────────────────
              CircleAvatar(
                radius: 52,
                backgroundColor: const Color(0xFFEEEBFF),
                backgroundImage:
                    hasImg ? NetworkImage(profileImg) : null,
                child: hasImg
                    ? null
                    : Icon(Icons.person,
                        size: 44,
                        color: const Color(0xFF6366F1)
                            .withValues(alpha: 0.5)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // ── XP Progress Bar ─────────────────────────────────────
          XpProgressBar(xp: xp),
        ],
      ),
    );
  }

  Widget _statRow({
    required String label,
    required String value,
    required IconData icon,
    required Color iconColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: 6),
        Text(value,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.black87)),
        const SizedBox(width: 5),
        Text(label,
            style: const TextStyle(
                fontSize: 12, color: Color(0xFF9CA3AF))),
      ],
    );
  }

  // ── Action squares ─────────────────────────────────────────────────────────

  Widget _buildActionSquares(
      BuildContext context, Map<String, dynamic> data) {
    final gallery = data['gallery'] as List<dynamic>? ?? [];
    final isPromoted = data['isPromoted'] == true;
    DateTime? expiryDate;
    try {
      final ts = data['promotionExpiryDate'];
      if (ts != null) expiryDate = (ts as dynamic).toDate() as DateTime;
    } catch (_) {}
    final isVipActive = isPromoted &&
        expiryDate != null &&
        expiryDate.isAfter(DateTime.now());

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Gallery square
          Expanded(
            child: InkWell(
              onTap: gallery.isEmpty
                  ? null
                  : () => _showGallerySheet(context, gallery),
              borderRadius: BorderRadius.circular(24),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.07),
                      blurRadius: 20,
                      spreadRadius: 0,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(
                    vertical: 28, horizontal: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.photo_library_outlined,
                        size: 32,
                        color: gallery.isEmpty
                            ? Colors.grey[300]
                            : Colors.black),
                    const SizedBox(height: 10),
                    Text(
                      'גלריית עבודות',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: gallery.isEmpty
                            ? Colors.grey[300]
                            : Colors.black,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          // VIP square
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isVipActive
                    ? const Color(0xFFFBBF24)
                    : Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.07),
                    blurRadius: 20,
                    spreadRadius: 0,
                    offset: const Offset(0, 6),
                  ),
                ],
                border: isVipActive
                    ? null
                    : Border.all(color: Colors.grey.shade200),
              ),
              padding: const EdgeInsets.symmetric(
                  vertical: 28, horizontal: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.workspace_premium_rounded,
                      size: 32,
                      color: isVipActive
                          ? Colors.white
                          : Colors.amber[700]),
                  const SizedBox(height: 10),
                  Text(
                    isVipActive ? 'מומחה VIP' : 'מומחה',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color:
                          isVipActive ? Colors.white : Colors.black,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showGallerySheet(
      BuildContext context, List<dynamic> gallery) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.65,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 16),
            const Text('גלריית עבודות',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 12),
            Expanded(
              child: GridView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12),
                itemCount: gallery.length,
                itemBuilder: (_, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: CachedNetworkImage(
                    imageUrl: gallery[i].toString(),
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) =>
                        Container(color: Colors.grey[200]),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ── Calendar ───────────────────────────────────────────────────────────────

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
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey[200]!)),
      child: TableCalendar(
        locale: 'he_IL',
        firstDay: DateTime.now(),
        lastDay: DateTime.now().add(const Duration(days: 30)),
        focusedDay: _focusedDay,
        headerStyle: const HeaderStyle(
            formatButtonVisible: false, titleCentered: true),
        selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
        enabledDayPredicate: (day) {
          final n = DateTime.utc(day.year, day.month, day.day);
          return !unavailableDates.contains(n);
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
            final n = DateTime.utc(day.year, day.month, day.day);
            if (!unavailableDates.contains(n)) return null;
            return Center(
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    shape: BoxShape.circle),
                child: Center(
                  child: Text('${day.day}',
                      style: TextStyle(
                          color: Colors.red.shade300,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            );
          },
        ),
        calendarStyle: const CalendarStyle(
          selectedDecoration: BoxDecoration(
              color: Colors.black, shape: BoxShape.circle),
          todayDecoration: BoxDecoration(
              color: Colors.pinkAccent, shape: BoxShape.circle),
        ),
      ),
    );
  }

  Widget _buildTimeSlots() {
    return SizedBox(
      height: 55,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _availableSlots.length,
        itemBuilder: (context, index) {
          final slot = _availableSlots[index];
          final isSelected = _selectedTimeSlot == slot;
          return GestureDetector(
            onTap: () =>
                setState(() => _selectedTimeSlot = slot),
            child: Container(
              margin: const EdgeInsets.only(top: 20, left: 10),
              padding:
                  const EdgeInsets.symmetric(horizontal: 25),
              decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.black
                      : Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                      color: isSelected
                          ? Colors.black
                          : Colors.grey[300]!)),
              child: Center(
                child: Text(slot,
                    style: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : Colors.black,
                        fontWeight: FontWeight.bold)),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Bottom sticky bar ──────────────────────────────────────────────────────

  Widget _buildBottomAction(
      BuildContext context, Map<String, dynamic> data) {
    final isReady =
        _selectedDay != null && _selectedTimeSlot != null;
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(25, 15, 25, 35),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
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
                            receiverId: widget.userId,
                            receiverName:
                                data['name'] ?? "מומחה"))),
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      isReady ? Colors.black : Colors.grey[300],
                  minimumSize: const Size(0, 60),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15)),
                ),
                onPressed: isReady
                    ? () => _processEscrowOrder(context, data)
                    : null,
                child: Text(
                  isReady
                      ? "הזמן ל-$_selectedTimeSlot"
                      : "בחר תאריך וזמן",
                  style: const TextStyle(
                      color: Colors.white,
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

  // ── About & inline gallery sections ───────────────────────────────────────

  Widget _buildSection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text(content,
              style: const TextStyle(
                  fontSize: 15, color: Colors.black87, height: 1.6),
              textAlign: TextAlign.right),
        ],
      ),
    );
  }

  Widget _buildGallerySection(List<dynamic>? gallery) {
    if (gallery == null || gallery.isEmpty) return const SizedBox();
    return SizedBox(
      height: 200,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: gallery.length,
        itemBuilder: (context, index) => Container(
          width: 280,
          margin: const EdgeInsets.only(left: 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            image: DecorationImage(
              image: CachedNetworkImageProvider(
                  gallery[index].toString()),
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
    );
  }

  // ── Booking summary helpers ────────────────────────────────────────────────

  Widget _summaryRow(String label, String value,
      {bool isBold = false, bool isGreen = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value,
              style: TextStyle(
                  fontWeight:
                      isBold ? FontWeight.bold : FontWeight.normal,
                  color: isGreen ? Colors.green : Colors.black)),
        ],
      ),
    );
  }
}
