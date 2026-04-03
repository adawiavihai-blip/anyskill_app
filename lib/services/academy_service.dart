import 'package:cloud_firestore/cloud_firestore.dart';

// ── Data models ────────────────────────────────────────────────────────────────

class AcademyCourse {
  final String id;
  final String title;
  final String description;
  final String videoUrl;
  final String category;
  final String duration;
  final int order;
  final int xpReward;
  final List<Map<String, dynamic>> quizQuestions;
  final String? thumbnailUrl;

  const AcademyCourse({
    required this.id,
    required this.title,
    required this.description,
    required this.videoUrl,
    required this.category,
    required this.duration,
    required this.order,
    this.xpReward = 200,
    required this.quizQuestions,
    this.thumbnailUrl,
  });

  factory AcademyCourse.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return AcademyCourse(
      id:             doc.id,
      title:          d['title']       as String? ?? '',
      description:    d['description'] as String? ?? '',
      videoUrl:       d['videoUrl']    as String? ?? '',
      category:       d['category']    as String? ?? '',
      duration:       d['duration']    as String? ?? '',
      order:          (d['order']      as num?    ?? 0).toInt(),
      xpReward:       (d['xpReward']   as num?    ?? 200).toInt(),
      quizQuestions:  List<Map<String, dynamic>>.from(
                        (d['quizQuestions'] as List?)?.map(
                          (e) => Map<String, dynamic>.from(e as Map)) ?? []),
      thumbnailUrl:   d['thumbnailUrl'] as String?,
    );
  }
}

class CourseProgress {
  final double watchedPercent;
  final bool   passed;
  final bool   xpAwarded;

  const CourseProgress({
    this.watchedPercent = 0,
    this.passed         = false,
    this.xpAwarded      = false,
  });

  factory CourseProgress.fromMap(Map<String, dynamic> d) => CourseProgress(
    watchedPercent: (d['watchedPercent'] as num? ?? 0).toDouble(),
    passed:         d['passed']    as bool? ?? false,
    xpAwarded:      d['xpAwarded'] as bool? ?? false,
  );
}

// ── Service ─────────────────────────────────────────────────────────────────────

class AcademyService {
  AcademyService._();

  static final _db = FirebaseFirestore.instance;

  // Stream all courses ordered by the `order` field
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamCourses() =>
      _db.collection('courses').orderBy('order').limit(100).snapshots();

  // Stream all progress docs for a given user
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamProgress(
          String uid) =>
      uid.isEmpty
          ? const Stream.empty()
          : _db
              .collection('user_progress')
              .doc(uid)
              .collection('courses')
              .limit(100)
              .snapshots();

  // Save how far the user has watched (called every ~5 s while playing)
  static Future<void> saveWatchProgress(
    String uid,
    String courseId,
    double percent,
  ) async {
    if (uid.isEmpty) return;
    await _db
        .collection('user_progress')
        .doc(uid)
        .collection('courses')
        .doc(courseId)
        .set({'watchedPercent': percent}, SetOptions(merge: true));
  }

  // Award XP + certification badge + notification on course completion
  static Future<void> completeCourse({
    required String uid,
    required String courseId,
    required String courseTitle,
    required String category,
    int xpReward = 200,
  }) async {
    if (uid.isEmpty) return;

    final batch = _db.batch();

    // Mark progress as passed
    final progressRef = _db
        .collection('user_progress')
        .doc(uid)
        .collection('courses')
        .doc(courseId);
    batch.set(progressRef, {
      'passed':         true,
      'xpAwarded':      true,
      'watchedPercent': 100,
      'completedAt':    FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Award XP + add certified category to user profile
    final userRef = _db.collection('users').doc(uid);
    batch.update(userRef, {
      'xp':                  FieldValue.increment(xpReward),
      'certifiedCategories': FieldValue.arrayUnion([category]),
    });

    // Write an in-app notification
    final notifRef = _db.collection('notifications').doc();
    batch.set(notifRef, {
      'userId':    uid,
      'title':     '🎓 השלמת קורס!',
      'body':      'סיימת את "$courseTitle" וקיבלת $xpReward XP ותעודת הסמכה!',
      'isRead':    false,
      'type':      'certification',
      'createdAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  // ── URL helpers ─────────────────────────────────────────────────────────────

  /// Extracts the YouTube video ID from a URL or returns the raw ID.
  static String extractVideoId(String urlOrId) {
    final uri = Uri.tryParse(urlOrId);
    if (uri == null || !uri.hasScheme) return urlOrId;
    if (uri.host.contains('youtu.be')) {
      return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : urlOrId;
    }
    if (uri.queryParameters.containsKey('v')) {
      return uri.queryParameters['v']!;
    }
    return urlOrId;
  }

  /// Returns the hqdefault thumbnail URL for a YouTube video.
  static String thumbnailUrl(String videoId) =>
      'https://img.youtube.com/vi/$videoId/hqdefault.jpg';
}
