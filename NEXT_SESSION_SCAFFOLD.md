# Next Session Scaffold — Top-3 Customer Screen Widget Tests

> **Goal**: enable widget testing of the 3 highest-traffic customer screens
> (`home_tab`, `category_results_screen`, `expert_profile_screen`) by
> building the Firebase mocking infrastructure they need.
>
> **Estimated effort**: 2 sessions of ~3 hours each (this scaffold gets
> session 1 to a running baseline; session 2 ships full coverage of one
> of the three).

---

## Why these 3 screens

The launch readiness audit (§58-era) called out:
> "the three highest-traffic screens... 0 widget tests"

| Screen | LOC | Streams | Services | Why critical |
|--------|----:|---------|----------|--------------|
| `home_tab.dart` | 2,882 | 6 | 4+ | First screen every user sees |
| `category_results_screen.dart` | 4,433 | 4 | 5+ | Search funnel — entire conversion path |
| `expert_profile_screen.dart` | 4,370 | 8 | 6+ | The 1 booking screen — only revenue path |

A regression in any of them silently breaks the whole funnel. The
§71 testability hook proved one piece of the puzzle (Firestore can
be faked); but auth, services, and stream-builders need similar hooks.

---

## What's already in place (after §58→§75 + post-audit)

✅ `fake_cloud_firestore: ^4.0.2` in pubspec
✅ `CacheService.getDoc/getDocs` accept `db: FirebaseFirestore?` (§71/§74)
✅ `CachedReaders.providerProfile/providerProfiles` accept `db:` (§71/§74)
✅ Empty-uid guard in cache layer (post-audit fix)
✅ 9 unit tests + 5 widget tests already exercise the cache layer
✅ Conditional-import bridges (§65) — `dart:html` etc. don't block test VM

## What's MISSING (this scaffold's scope)

❌ FirebaseAuth mocking — `FirebaseAuth.instance.currentUser` is a
   singleton. No test infrastructure exists.
❌ `LocaleProvider.instance` — singleton; no override.
❌ `ViewModeService.instance` — singleton; no override.
❌ Service-locator pattern is missing for service singletons used by
   the top-3 screens.

---

## Session 1 — Mocking infrastructure (3 hours)

### Step 1.1 — Add `firebase_auth_mocks` to dev_dependencies (10 min)

```yaml
# pubspec.yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  fake_cloud_firestore: ^4.0.2
  firebase_auth_mocks: ^0.14.1  # <-- NEW
```

Run `flutter pub get`.

### Step 1.2 — Build `test/helpers/fake_firebase.dart` (30 min)

A reusable helper that wires:
- `FakeFirebaseFirestore` instance
- `MockFirebaseAuth` with a configurable signed-in user
- A test-time `FirebaseFirestore.instance` shim (advanced — see notes)

```dart
// test/helpers/fake_firebase.dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;

class FakeFirebase {
  final FakeFirebaseFirestore firestore;
  final MockFirebaseAuth auth;
  final User? user;

  FakeFirebase._({required this.firestore, required this.auth, this.user});

  /// Builds a fake Firebase environment with optional auth + Firestore seed.
  static FakeFirebase create({
    String? uid,
    Map<String, dynamic>? userData,
    Map<String, Map<String, dynamic>>? seedJobs,
  }) {
    final auth = uid == null
        ? MockFirebaseAuth()
        : MockFirebaseAuth(
            signedIn: true,
            mockUser: MockUser(uid: uid, displayName: userData?['name'] as String?),
          );
    final firestore = FakeFirebaseFirestore();
    if (uid != null && userData != null) {
      firestore.collection('users').doc(uid).set(userData);
    }
    if (seedJobs != null) {
      seedJobs.forEach((id, data) {
        firestore.collection('jobs').doc(id).set(data);
      });
    }
    return FakeFirebase._(
      firestore: firestore,
      auth: auth,
      user: auth.currentUser,
    );
  }
}
```

### Step 1.3 — Refactor `LocaleProvider` + `ViewModeService` to accept overrides (45 min)

Both are `ChangeNotifier.instance` singletons. Add a `static set instance(LocaleProvider override)` for tests, plus a reset hook.

```dart
// lib/services/locale_provider.dart
class LocaleProvider extends ChangeNotifier {
  static LocaleProvider _instance = LocaleProvider._();
  static LocaleProvider get instance => _instance;

  /// **Test-only** — override the singleton for widget tests.
  @visibleForTesting
  static void overrideInstance(LocaleProvider fake) => _instance = fake;

  @visibleForTesting
  static void resetForTesting() => _instance = LocaleProvider._();
  // ... rest unchanged
}
```

Repeat for `ViewModeService.instance`.

### Step 1.4 — Build `test/helpers/test_app_wrapper.dart` (30 min)

A reusable function that wraps any widget with:
- `MaterialApp` with l10n delegates
- `Directionality(rtl)` (Hebrew default)
- An `InheritedWidget` carrying the `FakeFirebase` instance so deep
  widgets can inject the fake firestore.

### Step 1.5 — Smoke test for ONE simple screen (45 min)

Pick the simplest of the top-3: `category_results_screen.dart`. Write:

```dart
// test/widget/screens/category_results_smoke_test.dart
testWidgets('renders without crashing for an empty category', (tester) async {
  final fake = FakeFirebase.create(uid: 'tester');
  // Seed empty `users` collection so search returns 0 providers.

  LocaleProvider.overrideInstance(LocaleProvider());

  await tester.pumpWidget(buildTestApp(
    child: const CategoryResultsScreen(categoryName: 'אינסטלציה'),
    fake: fake,
  ));

  await tester.pump(); // First frame
  await tester.pump(const Duration(milliseconds: 500)); // Let streams settle

  // Just verify it didn't throw + a key UI element rendered
  expect(find.text('אינסטלציה'), findsOneWidget); // AppBar title
});
```

This single passing test is the GOAL of session 1. If it passes, the
infrastructure works.

---

## Session 2 — Real coverage on one screen (3 hours)

Pick `category_results_screen.dart` (lowest-coupling of the three).

### Coverage targets

| Test | What it verifies |
|------|------------------|
| Empty results state | Renders "no providers found" message |
| 5 providers rendered | List shows 5 cards with names + prices |
| Filter chip tap | Filtering by rating reduces visible cards |
| Map toggle | Switching to map view doesn't crash |
| Map back to list | Switching back preserves scroll position |
| `SearchCardPricePill` integration | Cards with `priceLocked` show lock badge |
| Tap a card | Navigates to ExpertProfileScreen |

7 tests × ~20 min each = ~2.5 hours. The remaining 30 min is for the
final analyze pass + CI integration.

---

## What NOT to do in this scope

- ❌ Don't try to test ALL 3 screens in one session — pick one, ship,
  validate, then carry forward.
- ❌ Don't refactor `home_tab.dart` (2,882 LOC) just to make it
  testable. Treat it as "too big to test" until we split it (separate
  refactor PR).
- ❌ Don't mock Sentry / Crashlytics / Watchtower — they're already
  fire-and-forget. Tests that don't care can ignore them.
- ❌ Don't hit real network in tests — every external call must be
  via the FakeFirebase helper.

---

## Risks (in priority order)

| Risk | Likelihood | Mitigation |
|------|-----------:|------------|
| `FirebaseFirestore.instance` shim breaks production callers | Medium | Use `firebase_core_platform_interface.delegateFor` if needed; otherwise keep injection-based and skip the shim |
| Service singletons resist override (e.g. const-construction) | Medium | Wrap each as `static late` and add `resetForTesting()` |
| Stream-based widget tests time out waiting for `.snapshots()` | High | Use `await tester.pump(...)` with explicit durations, never `pumpAndSettle` |
| Hebrew RTL renders differently in test VM than browser | Low | Always wrap in `Directionality(rtl)` — already standard pattern |
| `flutter test test/widget/screens/` glob breaks CI runtime | Low | Set timeout-minutes to 10 in the workflow YAML |

---

## Reference patterns

- `test/widget/booking_profile_avatar_test.dart` (§75) — pre-populating
  cache to avoid Firestore.instance access. Use as template for any
  cache-dependent widget test.
- `test/unit/cached_readers_test.dart` (§71/§74) — direct injection
  via `db:` parameter. Use as template for service-level tests.

---

## Done criteria for Session 1

- ✅ `firebase_auth_mocks` added + `flutter pub get` clean
- ✅ `test/helpers/fake_firebase.dart` exists + compiles
- ✅ `test/helpers/test_app_wrapper.dart` exists + compiles
- ✅ `LocaleProvider` + `ViewModeService` have `overrideInstance` + `resetForTesting`
- ✅ One smoke test passes against `category_results_screen.dart`
- ✅ `flutter analyze` → 0 issues
- ✅ CI doesn't regress on existing tests (still 80+ pass)

## Done criteria for Session 2

- ✅ 7 widget tests on `category_results_screen.dart` pass
- ✅ Add `test/widget/screens/` to the CI glob
- ✅ Document the new patterns in CLAUDE.md as §76 (or §77)

---

*Generated 2026-05-10 by Claude Code. Read alongside CLAUDE.md §71/§74
+ DEPLOY_CHECKLIST_2026-05-10.md.*
