// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:anyskill_app/models/story.dart';
import 'package:anyskill_app/providers/story_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Unit tests: Story Model + StoryProvider
//
// Run:  flutter test test/unit/story_test.dart
//
// Uses fake_cloud_firestore for offline Firestore simulation.
// StoryProvider tests use a mock-friendly approach via direct state inspection.
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // 1. Story MODEL
  // ═══════════════════════════════════════════════════════════════════════════

  group('Story model', () {
    test('fromFirestore parses all fields correctly', () async {
      final db = FakeFirebaseFirestore();
      final now = DateTime(2026, 6, 1, 12, 0);
      final expires = now.add(const Duration(hours: 24));

      await db.collection('stories').doc('user123').set({
        'uid':            'user123',
        'expertId':       'user123',
        'expertName':     'Dana',
        'videoUrl':       'https://storage.example.com/video.mp4',
        'thumbnailUrl':   'https://storage.example.com/thumb.jpg',
        'providerName':   'Dana',
        'providerAvatar': 'https://storage.example.com/avatar.jpg',
        'serviceType':    'ניקיון',
        'timestamp':      Timestamp.fromDate(now),
        'createdAt':      Timestamp.fromDate(now),
        'expiresAt':      Timestamp.fromDate(expires),
        'hasActive':      true,
        'views':          5,
        'viewCount':      10,
        'likeCount':      3,
        'likedBy':        ['a', 'b', 'c'],
      });

      final doc = await db.collection('stories').doc('user123').get();
      final story = Story.fromFirestore(doc);

      expect(story.uid,            'user123');
      expect(story.expertName,     'Dana');
      expect(story.videoUrl,       'https://storage.example.com/video.mp4');
      expect(story.thumbnailUrl,   'https://storage.example.com/thumb.jpg');
      expect(story.providerAvatar, 'https://storage.example.com/avatar.jpg');
      expect(story.serviceType,    'ניקיון');
      expect(story.hasActive,      true);
      expect(story.views,          5);
      expect(story.viewCount,      10);
      expect(story.likeCount,      3);
      expect(story.likedBy,        ['a', 'b', 'c']);
      expect(story.timestamp,      now);
      expect(story.expiresAt,      expires);
    });

    test('fromFirestore handles missing fields gracefully', () async {
      final db = FakeFirebaseFirestore();

      // Minimal document — only the doc ID exists
      await db.collection('stories').doc('sparse').set({
        'hasActive': true,
      });

      final doc = await db.collection('stories').doc('sparse').get();
      final story = Story.fromFirestore(doc);

      expect(story.uid,          'sparse');
      expect(story.expertName,   '');
      expect(story.videoUrl,     '');
      expect(story.hasActive,    true);
      expect(story.viewCount,    0);
      expect(story.likeCount,    0);
      expect(story.likedBy,      isEmpty);
      expect(story.timestamp,    isNull);
    });

    test('toJson produces correct map', () {
      final now = DateTime(2026, 6, 1, 12, 0);
      final story = Story(
        uid:        'u1',
        expertName: 'Test',
        videoUrl:   'https://example.com/v.mp4',
        hasActive:  true,
        timestamp:  now,
        expiresAt:  now.add(const Duration(hours: 24)),
      );

      final json = story.toJson();
      expect(json['uid'],        'u1');
      expect(json['expertId'],   'u1');
      expect(json['expertName'], 'Test');
      expect(json['videoUrl'],   'https://example.com/v.mp4');
      expect(json['hasActive'],  true);
      expect(json['viewCount'],  0);
      expect(json['likeCount'],  0);
      expect(json['likedBy'],    isEmpty);
    });

    test('copyWith creates a new instance with updated fields', () {
      final story = Story(uid: 'u1', expertName: 'Old', likeCount: 5);
      final updated = story.copyWith(expertName: 'New', likeCount: 6);

      expect(updated.uid,        'u1');       // unchanged
      expect(updated.expertName, 'New');      // changed
      expect(updated.likeCount,  6);          // changed
      expect(story.expertName,   'Old');      // original untouched
      expect(story.likeCount,    5);          // original untouched
    });

    test('equality is based on uid + videoUrl', () {
      const a = Story(uid: 'u1', videoUrl: 'v1');
      const b = Story(uid: 'u1', videoUrl: 'v1', likeCount: 99);
      const c = Story(uid: 'u1', videoUrl: 'v2');

      expect(a, equals(b));     // same uid + videoUrl
      expect(a, isNot(equals(c))); // different videoUrl
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. Story EXPIRY logic
  // ═══════════════════════════════════════════════════════════════════════════

  group('Story expiry', () {
    test('story with future expiresAt is not expired', () {
      final story = Story(
        uid:       'u1',
        hasActive: true,
        videoUrl:  'v',
        expiresAt: DateTime.now().add(const Duration(hours: 12)),
      );
      expect(story.isExpired, false);
      expect(story.isValid,   true);
    });

    test('story with past expiresAt is expired', () {
      final story = Story(
        uid:       'u1',
        hasActive: true,
        videoUrl:  'v',
        expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
      );
      expect(story.isExpired, true);
      expect(story.isValid,   false);
    });

    test('story without expiresAt falls back to timestamp (< 24h)', () {
      final story = Story(
        uid:       'u1',
        hasActive: true,
        videoUrl:  'v',
        timestamp: DateTime.now().subtract(const Duration(hours: 10)),
      );
      expect(story.isExpired, false);
    });

    test('story without expiresAt falls back to timestamp (> 24h)', () {
      final story = Story(
        uid:       'u1',
        hasActive: true,
        videoUrl:  'v',
        timestamp: DateTime.now().subtract(const Duration(hours: 25)),
      );
      expect(story.isExpired, true);
    });

    test('story with no timestamp and no expiresAt is expired', () {
      const story = Story(uid: 'u1', hasActive: true, videoUrl: 'v');
      expect(story.isExpired, true);
    });

    test('isValid requires hasActive + not expired + videoUrl', () {
      // Missing videoUrl
      final noVideo = Story(
        uid: 'u1', hasActive: true,
        expiresAt: DateTime.now().add(const Duration(hours: 12)),
      );
      expect(noVideo.isValid, false);

      // hasActive = false
      final inactive = Story(
        uid: 'u1', hasActive: false, videoUrl: 'v',
        expiresAt: DateTime.now().add(const Duration(hours: 12)),
      );
      expect(inactive.isValid, false);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. Story LIKES
  // ═══════════════════════════════════════════════════════════════════════════

  group('Story likes', () {
    test('isLikedBy returns true for UIDs in likedBy', () {
      const story = Story(uid: 'u1', likedBy: ['alice', 'bob']);
      expect(story.isLikedBy('alice'), true);
      expect(story.isLikedBy('bob'),   true);
      expect(story.isLikedBy('carol'), false);
    });

    test('isLikedBy on empty list returns false', () {
      const story = Story(uid: 'u1');
      expect(story.isLikedBy('anyone'), false);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. StoryProvider STATE MANAGEMENT
  // ═══════════════════════════════════════════════════════════════════════════

  group('StoryProvider', () {
    late StoryProvider provider;

    setUp(() {
      provider = StoryProvider.test();
    });

    tearDown(() => provider.dispose());

    test('initial state is clean', () {
      expect(provider.stories,       isEmpty);
      expect(provider.isLoading,     false);
      expect(provider.error,         isNull);
      expect(provider.uploadProgress, 0);
      expect(provider.activeAction,  StoryAction.none);
    });

    test('ownStory returns null on empty list', () {
      expect(provider.ownStory('u1'), isNull);
    });

    test('otherStories returns empty on empty list', () {
      expect(provider.otherStories('u1'), isEmpty);
    });

    test('clearError resets error state', () {
      provider.clearError();
      expect(provider.error, isNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // 5. Firestore ROUND-TRIP (model → Firestore → model)
  // ═══════════════════════════════════════════════════════════════════════════

  group('Firestore round-trip', () {
    test('Story survives write → read cycle', () async {
      final db = FakeFirebaseFirestore();
      final now = DateTime(2026, 6, 1, 14, 30);

      final original = Story(
        uid:            'roundtrip',
        expertName:     'שרה',
        videoUrl:       'https://storage.example.com/vid.mp4',
        thumbnailUrl:   'https://storage.example.com/thumb.jpg',
        providerName:   'שרה',
        providerAvatar: 'https://storage.example.com/av.jpg',
        serviceType:    'אילוף כלבים',
        timestamp:      now,
        expiresAt:      now.add(const Duration(hours: 24)),
        hasActive:      true,
        views:          0,
        viewCount:      7,
        likeCount:      2,
        likedBy:        const ['x', 'y'],
      );

      // Write
      final json = original.toJson();
      // Replace serverTimestamp sentinel with a real timestamp for testing
      json['createdAt'] = Timestamp.fromDate(now);
      await db.collection('stories').doc('roundtrip').set(json);

      // Read back
      final doc = await db.collection('stories').doc('roundtrip').get();
      final loaded = Story.fromFirestore(doc);

      expect(loaded.uid,            original.uid);
      expect(loaded.expertName,     original.expertName);
      expect(loaded.videoUrl,       original.videoUrl);
      expect(loaded.serviceType,    original.serviceType);
      expect(loaded.hasActive,      original.hasActive);
      expect(loaded.viewCount,      original.viewCount);
      expect(loaded.likeCount,      original.likeCount);
      expect(loaded.likedBy,        original.likedBy);
      expect(loaded.timestamp,      original.timestamp);
    });

    test('Multiple stories sort by timestamp descending', () async {
      final db = FakeFirebaseFirestore();

      final older = DateTime(2026, 6, 1, 10, 0);
      final newer = DateTime(2026, 6, 1, 14, 0);

      await db.collection('stories').doc('old').set({
        'hasActive': true,
        'timestamp': Timestamp.fromDate(older),
        'videoUrl':  'v1',
      });
      await db.collection('stories').doc('new').set({
        'hasActive': true,
        'timestamp': Timestamp.fromDate(newer),
        'videoUrl':  'v2',
      });

      final snap = await db
          .collection('stories')
          .where('hasActive', isEqualTo: true)
          .get();

      final stories = snap.docs.map(Story.fromFirestore).toList()
        ..sort((a, b) {
          final ta = a.timestamp?.millisecondsSinceEpoch ?? 0;
          final tb = b.timestamp?.millisecondsSinceEpoch ?? 0;
          return tb.compareTo(ta);
        });

      expect(stories[0].uid, 'new');  // newer first
      expect(stories[1].uid, 'old');
    });

    test('Delete removes story and clears user flags', () async {
      final db = FakeFirebaseFirestore();

      // Setup story + user
      await db.collection('stories').doc('del_user').set({
        'hasActive': true,
        'videoUrl':  'v',
      });
      await db.collection('users').doc('del_user').set({
        'hasActiveStory': true,
        'storyTimestamp':  Timestamp.now(),
        'name':           'Test',
      });

      // Delete story doc
      await db.collection('stories').doc('del_user').delete();

      // Clear user flags
      await db.collection('users').doc('del_user').update({
        'hasActiveStory': false,
        'storyTimestamp':  null,
      });

      // Verify
      final storyDoc = await db.collection('stories').doc('del_user').get();
      expect(storyDoc.exists, false);

      final userDoc = await db.collection('users').doc('del_user').get();
      final userData = userDoc.data()!;
      expect(userData['hasActiveStory'], false);
      expect(userData['storyTimestamp'], isNull);
    });

    test('Like increments count and adds uid to likedBy', () async {
      final db = FakeFirebaseFirestore();

      await db.collection('stories').doc('like_test').set({
        'hasActive': true,
        'likeCount': 0,
        'likedBy':   <String>[],
      });

      await db.collection('stories').doc('like_test').update({
        'likeCount': FieldValue.increment(1),
        'likedBy':   FieldValue.arrayUnion(['voter1']),
      });

      final doc = await db.collection('stories').doc('like_test').get();
      final story = Story.fromFirestore(doc);

      expect(story.likeCount, 1);
      expect(story.likedBy,   ['voter1']);
    });

    test('Duplicate like via arrayUnion is idempotent', () async {
      final db = FakeFirebaseFirestore();

      await db.collection('stories').doc('dup_like').set({
        'hasActive': true,
        'likeCount': 1,
        'likedBy':   ['voter1'],
      });

      // Same voter likes again
      await db.collection('stories').doc('dup_like').update({
        'likedBy': FieldValue.arrayUnion(['voter1']),
      });

      final doc = await db.collection('stories').doc('dup_like').get();
      final data = doc.data()!;
      final likedBy = (data['likedBy'] as List).cast<String>();
      expect(likedBy, ['voter1']); // no duplicate
    });
  });
}
