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
  String _searchQuery    = '';
  bool   _filterUnder100 = false;
  int    _refreshTrigger = 0;
  Future<List<Map<String, dynamic>>>? _expertsFuture;

  @override
  void initState() {
    super.initState();
    _expertsFuture = _fetchExperts();
  }

  /// חד-פעמי — מונע את באג ה-Firestore web SDK שמתרחש כאשר
  /// מאזין real-time מתבטל באמצע עדכון (assertion ve:-1).
  Future<List<Map<String, dynamic>>> _fetchExperts() async {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .where('isProvider', isEqualTo: true)
        .where('serviceType', isEqualTo: widget.categoryName)
        .limit(50)
        .get();
    return snap.docs.map((d) {
      final map = d.data();
      map['uid'] = d.id;
      return map;
    }).toList();
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
    // בדיקות מזריקות Stream; ייצור משתמש ב-Future (מונע באג Firestore web SDK)
    if (widget.testStream != null) {
      return StreamBuilder<List<Map<String, dynamic>>>(
        stream: widget.testStream,
        builder: (context, snapshot) => _buildContent(context, snapshot),
      );
    }
    return FutureBuilder<List<Map<String, dynamic>>>(
      key: ValueKey(_refreshTrigger),
      future: _expertsFuture,
      builder: (context, snapshot) => _buildContent(context, snapshot),
    );
  }

  Widget _buildContent(
      BuildContext context, AsyncSnapshot<List<Map<String, dynamic>>> snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }

    if (snapshot.hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('שגיאה בטעינת המומחים',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('נסה שוב'),
              onPressed: () => setState(() {
                _refreshTrigger++;
                _expertsFuture = _fetchExperts();
              }),
            ),
          ],
        ),
      );
    }

    final all = snapshot.data ?? [];
        final experts = filterExperts(
          all,
          query: _searchQuery,
          underHundred: _filterUnder100,
        );

        if (experts.isEmpty) {
          final hasFilters = _searchQuery.isNotEmpty || _filterUnder100;
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.person_search_outlined,
                        size: 56, color: Colors.grey[400]),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    hasFilters ? "לא נמצאו תוצאות" : 'אין מומחים ב${widget.categoryName} עדיין',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    hasFilters
                        ? "נסה לשנות את החיפוש או לבטל את הפילטר"
                        : "היה הראשון להצטרף לקטגוריה זו!",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  ),
                  if (hasFilters) ...[
                    const SizedBox(height: 28),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.filter_alt_off),
                      label: const Text("נקה פילטרים"),
                      onPressed: () => setState(() {
                        _searchQuery = '';
                        _filterUnder100 = false;
                      }),
                    ),
                  ],
                ],
              ),
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
  }
}
