import 'package:cloud_firestore/cloud_firestore.dart';

/// Immutable data model for a Skills Story document.
///
/// Firestore path: `stories/{uid}`
/// Storage path:   `stories/{uid}_{timestamp}.{ext}`
class Story {
  final String uid;
  final String expertName;
  final String videoUrl;
  final String thumbnailUrl;
  final String providerName;
  final String providerAvatar;
  final String serviceType;
  final DateTime? timestamp;
  final DateTime? createdAt;
  final DateTime? expiresAt;
  final bool hasActive;
  final int views;
  final int viewCount;
  final int likeCount;
  final List<String> likedBy;

  const Story({
    required this.uid,
    this.expertName = '',
    this.videoUrl = '',
    this.thumbnailUrl = '',
    this.providerName = '',
    this.providerAvatar = '',
    this.serviceType = '',
    this.timestamp,
    this.createdAt,
    this.expiresAt,
    this.hasActive = false,
    this.views = 0,
    this.viewCount = 0,
    this.likeCount = 0,
    this.likedBy = const [],
  });

  /// Whether this story is still within its 24-hour display window.
  bool get isExpired {
    if (expiresAt != null) return DateTime.now().isAfter(expiresAt!);
    if (timestamp != null) {
      return DateTime.now().difference(timestamp!).inHours >= 24;
    }
    return true;
  }

  bool get isValid => hasActive && !isExpired && videoUrl.isNotEmpty;

  bool isLikedBy(String userId) => likedBy.contains(userId);

  // ── Firestore serialisation ───────────────────────────────────────────

  factory Story.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return Story(
      uid:             doc.id,
      expertName:      d['expertName']     as String? ?? '',
      videoUrl:        d['videoUrl']       as String? ?? '',
      thumbnailUrl:    d['thumbnailUrl']   as String? ?? '',
      providerName:    d['providerName']   as String? ?? '',
      providerAvatar:  d['providerAvatar'] as String? ?? '',
      serviceType:     d['serviceType']    as String? ?? '',
      timestamp:       (d['timestamp']     as Timestamp?)?.toDate(),
      createdAt:       (d['createdAt']     as Timestamp?)?.toDate(),
      expiresAt:       (d['expiresAt']     as Timestamp?)?.toDate(),
      hasActive:       d['hasActive']      as bool?   ?? false,
      views:           (d['views']         as num?)?.toInt() ?? 0,
      viewCount:       (d['viewCount']     as num?)?.toInt() ?? 0,
      likeCount:       (d['likeCount']     as num?)?.toInt() ?? 0,
      likedBy:         (d['likedBy']       as List?)?.cast<String>() ?? const [],
    );
  }

  Map<String, dynamic> toJson() => {
    'uid':            uid,
    'expertId':       uid,
    'expertName':     expertName,
    'videoUrl':       videoUrl,
    'thumbnailUrl':   thumbnailUrl,
    'providerName':   providerName,
    'providerAvatar': providerAvatar,
    'serviceType':    serviceType,
    'timestamp':      timestamp != null ? Timestamp.fromDate(timestamp!) : null,
    'createdAt':      FieldValue.serverTimestamp(),
    'expiresAt':      expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
    'hasActive':      hasActive,
    'views':          views,
    'viewCount':      viewCount,
    'likeCount':      likeCount,
    'likedBy':        likedBy,
  };

  // ── Immutable updates ─────────────────────────────────────────────────

  Story copyWith({
    String? uid,
    String? expertName,
    String? videoUrl,
    String? thumbnailUrl,
    String? providerName,
    String? providerAvatar,
    String? serviceType,
    DateTime? timestamp,
    DateTime? createdAt,
    DateTime? expiresAt,
    bool? hasActive,
    int? views,
    int? viewCount,
    int? likeCount,
    List<String>? likedBy,
  }) {
    return Story(
      uid:             uid             ?? this.uid,
      expertName:      expertName      ?? this.expertName,
      videoUrl:        videoUrl        ?? this.videoUrl,
      thumbnailUrl:    thumbnailUrl    ?? this.thumbnailUrl,
      providerName:    providerName    ?? this.providerName,
      providerAvatar:  providerAvatar  ?? this.providerAvatar,
      serviceType:     serviceType     ?? this.serviceType,
      timestamp:       timestamp       ?? this.timestamp,
      createdAt:       createdAt       ?? this.createdAt,
      expiresAt:       expiresAt       ?? this.expiresAt,
      hasActive:       hasActive       ?? this.hasActive,
      views:           views           ?? this.views,
      viewCount:       viewCount       ?? this.viewCount,
      likeCount:       likeCount       ?? this.likeCount,
      likedBy:         likedBy         ?? this.likedBy,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Story && uid == other.uid && videoUrl == other.videoUrl;

  @override
  int get hashCode => uid.hashCode ^ videoUrl.hashCode;
}
