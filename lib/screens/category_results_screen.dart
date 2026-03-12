import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'expert_profile_screen.dart';
import '../utils/expert_filter.dart';

class CategoryResultsScreen extends StatefulWidget {
  final String categoryName;

  /// זרם אופציונלי — מוזרק בבדיקות במקום Firestore האמיתי.
  /// בסביבת ייצור תמיד null (נשתמש ב-Firestore).
  final Stream<List<Map<String, dynamic>>>? testStream;

  const CategoryResultsScreen({
    super.key,
    required this.categoryName,
    this.testStream,
  });

  @override
  State<CategoryResultsScreen> createState() => _CategoryResultsScreenState();
}

class _CategoryResultsScreenState extends State<CategoryResultsScreen> {
  String _searchQuery   = '';
  bool   _filterUnder100 = false;

  /// מחזיר את זרם המומחים — Firestore בייצור, testStream בבדיקות.
  Stream<List<Map<String, dynamic>>> get _expertsStream {
    if (widget.testStream != null) return widget.testStream!;

    return FirebaseFirestore.instance
        .collection('users')
        .where('isProvider', isEqualTo: true)
        .where('serviceType', isEqualTo: widget.categoryName)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => d.data() as Map<String, dynamic>).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text("מומחי ${widget.categoryName}",
            style: const TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: Column(
        children: [
          _buildSearchAndFilter(),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilter() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        children: [
          // שורת חיפוש
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              textAlign: TextAlign.right,
              decoration: const InputDecoration(
                hintText: 'חפש לפי שם...',
                hintStyle: TextStyle(color: Colors.grey, fontSize: 13),
                prefixIcon: Icon(Icons.search, color: Colors.grey, size: 20),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // פילטר מחיר
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () => setState(() => _filterUnder100 = !_filterUnder100),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: _filterUnder100
                      ? Colors.pinkAccent
                      : Colors.white,
                  borderRadius: BorderRadius.circular(50),
                  border: Border.all(
                    color: _filterUnder100
                        ? Colors.pinkAccent
                        : Colors.grey.shade300,
                  ),
                  boxShadow: _filterUnder100
                      ? [
                          BoxShadow(
                            color: Colors.pinkAccent.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          )
                        ]
                      : [],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.attach_money,
                        size: 14,
                        color: _filterUnder100
                            ? Colors.white
                            : Colors.grey[600]),
                    const SizedBox(width: 6),
                    Text(
                      'עד 100 ₪',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: _filterUnder100
                            ? Colors.white
                            : Colors.grey[800],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _expertsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final all = snapshot.data ?? [];
        final experts = filterExperts(
          all,
          query: _searchQuery,
          underHundred: _filterUnder100,
        );

        if (experts.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.person_search_outlined,
                    size: 80, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text(
                  'לא נמצאו מומחים ב${widget.categoryName}',
                  style:
                      const TextStyle(fontSize: 18, color: Colors.grey),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: experts.length,
          itemBuilder: (context, index) {
            final data      = experts[index];
            final isVerified = data['isVerified'] ?? false;
            final isOnline   = data['isOnline']   ?? false;
            final expertId   = data['uid']         ?? '';

            return GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ExpertProfileScreen(
                    expertId: expertId,
                    expertName: data['name'] ?? 'מומחה',
                  ),
                ),
              ),
              child: Container(
                margin: const EdgeInsets.only(bottom: 15),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    )
                  ],
                ),
                child: Row(
                  children: [
                    Stack(children: [
                      CircleAvatar(
                        radius: 35,
                        backgroundColor: Colors.blue[50],
                        backgroundImage: (data['profileImage'] != null &&
                                data['profileImage'] != '')
                            ? NetworkImage(data['profileImage'])
                            : null,
                        child:
                            (data['profileImage'] == null ||
                                    data['profileImage'] == '')
                                ? const Icon(Icons.person, size: 35)
                                : null,
                      ),
                      if (isOnline)
                        Positioned(
                          right: 0,
                          bottom: 2,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                    ]),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Text(data['name'] ?? 'מומחה',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 17)),
                            if (isVerified)
                              const Padding(
                                padding: EdgeInsets.only(right: 5),
                                child: Icon(Icons.verified,
                                    color: Colors.blue, size: 18),
                              ),
                          ]),
                          Text(
                            data['aboutMe'] ?? 'לחץ לצפייה בפרטים...',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: Colors.grey[600], fontSize: 13),
                          ),
                          const SizedBox(height: 5),
                          Row(children: [
                            const Icon(Icons.star,
                                color: Colors.amber, size: 16),
                            Text(' ${data['rating'] ?? '5.0'} ',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            Text('(${data['reviewsCount'] ?? '0'})',
                                style: const TextStyle(
                                    color: Colors.grey, fontSize: 11)),
                            const Spacer(),
                            Text(
                              '₪${data['pricePerHour'] ?? '100'}',
                              style: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const Text(' / שעה',
                                style: TextStyle(
                                    color: Colors.grey, fontSize: 11)),
                          ]),
                        ],
                      ),
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
}
