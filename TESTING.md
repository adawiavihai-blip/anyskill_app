# Testing Guide — AnySkill

This document is the canonical guide for running, writing, and debugging
tests in the AnySkill codebase. Three test suites cover the application:

| Suite | Location | Count | Runtime |
|-------|----------|-------|---------|
| **Flutter unit/widget tests** | `test/unit/` | 524+ | ~5s |
| **Cloud Functions tests** | `functions/__tests__/` | 258 | ~2s |
| **Firestore Rules tests** | `firestore-rules-tests/` | 137 | ~6-8s |
| **E2E tests** | `integration_test/` | 1 | ~30s |

All four are gated in CI (`.github/workflows/ci.yml`) — every PR runs them
in parallel and the deploy job depends on all four passing.

---

## Quick start — run everything locally

```bash
# 1. Flutter analyzer (must be 0 issues)
flutter analyze

# 2. Flutter unit + widget tests
flutter test test/unit/

# 3. Cloud Functions tests (Jest)
cd functions && npx jest __tests__/ && cd ..

# 4. Firestore Rules tests (requires Java 21 + Firebase emulator)
export JAVA_HOME="$PWD/tools/jre21/jdk-21.0.11+10-jre"
export PATH="$JAVA_HOME/bin:$PATH"
firebase emulators:exec --only firestore,storage --project=anyskill-rules-tests \
  "cd firestore-rules-tests && npm test"
```

Expected: all three suites green. Total wall time: ~20 seconds (emulator
boots once for the Rules suite).

---

## 1. Flutter unit/widget tests

**Location:** `test/unit/*.dart`

**Run a specific file:**
```bash
flutter test test/unit/csm_booking_services_test.dart
```

**Run with coverage:**
```bash
flutter test test/unit/ --coverage
genhtml coverage/lcov.info -o coverage/html
```

### What's covered

| File | Focus |
|------|-------|
| `csm_booking_services_test.dart` | Pure-math pricing for all 6 CSMs (babysitter, motorcycle tow, cleaning, delivery, handyman, fitness) |
| `csm_models_serialization_test.dart` | `fromMap`/`toMap` round-trip + `isXCategory` detectors |
| `escrow_payment_test.dart` | Escrow lifecycle |
| `cancellation_service_test.dart` | Cancellation policy + refund math |
| `pro_service_test.dart` | AnySkill Pro badge thresholds |
| `chat_messaging_test.dart` | Chat send/receive + offline queue |
| `business_rules_test.dart` | Cross-cutting business invariants |
| `models_complete_test.dart` | All model serialization |
| `auth_flow_test.dart` | Auth gates + duplicate guard |
| `repository_actions_test.dart` | Repository CRUD |
| `search_repository_test.dart` | Search ranking |
| `category_provider_test.dart` | Category Riverpod providers |
| `payment_service_test.dart` | Payment flows |
| `pro_audit_test.dart` | Pro badge audit log |
| `pro_notifications_test.dart` | Pro tier notifications |
| `ai_analysis_service_test.dart` | AI text analysis service |
| `input_sanitizer_test.dart` | Input sanitization |
| `security_i18n_test.dart` | Locale-aware security checks |
| `story_test.dart` | Stories lifecycle |
| `watchtower_test.dart` | Centralized error logging |

### Adding a new Flutter test

```dart
// test/unit/my_new_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:anyskill_app/services/my_service.dart';

void main() {
  group('MyService — feature group', () {
    test('descriptive test name', () {
      // Arrange
      final input = ...;

      // Act
      final result = MyService.process(input);

      // Assert
      expect(result, equals(expectedValue));
    });
  });
}
```

**Conventions:**
- One file per service / feature group
- Pure-math services don't need mocking — just import and test
- Services with Firestore: use `fake_cloud_firestore` (already in dev deps)
- Avoid `runApp` and full app rendering unless testing a real widget tree
- Group related assertions under `group()` blocks for readability

---

## 2. Cloud Functions tests

**Location:** `functions/__tests__/auth.test.js`

**Run:**
```bash
cd functions && npx jest __tests__/auth.test.js
```

### Mock infrastructure

The CF test suite uses heavy mocking (no emulator dependency). Pre-built
patterns at the top of `auth.test.js`:

| Mock | Purpose |
|------|---------|
| `firebase-admin` | Firestore + Auth + FieldValue + Timestamp |
| `firebase-functions/v2/https` | Unwraps `onCall` handlers so tests can call them directly |
| `firebase-functions/v2/firestore` | Same for `onDocumentCreated/Updated/Written/Deleted` |
| `firebase-functions/v2/scheduler` | Same for `onSchedule` |
| `@anthropic-ai/sdk` | Replaces `Anthropic` class with a mock that has overridable `messages.create` |
| `global.fetch` | Stubbed per-test for Gemini API calls |

### Helper functions

```js
// Build a Firestore mock with seeded docs
mockCollection({ "users/admin1": mockDocSnap(true, { isAdmin: true }) });

// Build Gemini callable mocks (response or thrown error)
buildGeminiCallableMocks({ fetchResponse: mkGeminiResp('{"x":1}') });
```

### What's covered (43 CFs)

Every callable, trigger, and scheduled CF in `functions/index.js` has at
minimum an auth-gate test. Money flows have full happy-path + rejection
coverage. AI callables have graceful-failure coverage.

Categories:
- Money/escrow (4): processPaymentRelease, processCancellation, resolveDisputeAdmin, adminReleaseEscrow
- AnyTasks (4)
- VIP subscriptions (4)
- Admin tools (6)
- Security (1, with `[SECURITY]` regression marker for §50 Vuln 7)
- Triggers (1)
- Flash Auction (3)
- Reviews (1)
- Vault dashboard (3)
- Stories maintenance (1)
- Monetization (2)
- Feedback (2)
- Re-engagement (1)
- Gemini callables (7)
- Banner AI (2)
- AI CEO (1)
- Schema generator (1)

### Adding a new CF test

Find the matching pattern at the top of the file (helpers are reusable):

```js
describe("myNewCf — context", () => {
  const cf = index.myNewCf;

  beforeEach(() => jest.clearAllMocks());

  test("rejects unauthenticated", async () => {
    await expect(cf({ auth: null, data: {} }))
      .rejects.toMatchObject({ code: "unauthenticated" });
  });

  test("happy path", async () => {
    // Set up mocks
    setupMyMocks({...});

    // Call
    const result = await cf({ auth: { uid: "u1" }, data: {} });

    // Assert
    expect(result.success).toBe(true);
  });
});
```

---

## 3. Firestore Rules tests

**Location:** `firestore-rules-tests/*.test.js`

**Setup (one-time):** Java 21 portable JRE is bundled in `tools/jre21/`.

**Run:**
```bash
export JAVA_HOME="$PWD/tools/jre21/jdk-21.0.11+10-jre"
export PATH="$JAVA_HOME/bin:$PATH"
firebase emulators:exec --only firestore,storage --project=anyskill-rules-tests \
  "cd firestore-rules-tests && npm test"
```

**Run a specific file:**
```bash
firebase emulators:exec --only firestore,storage --project=anyskill-rules-tests \
  "cd firestore-rules-tests && npx jest users.test.js"
```

### Test files (12 total)

| File | Coverage |
|------|----------|
| `users.test.js` | self-promote, balance modify, customCommission |
| `jobs.test.js` | escrow lifecycle, self-booking block |
| `reviews.test.js` | review authorship, job participation |
| `volunteer_tasks.test.js` | XP-farm prevention |
| `support_tickets.test.js` | ticket privacy |
| `chats_notifications.test.js` | chat participant gates |
| `job_requests.test.js` | quick-order board |
| `storage.test.js` | Storage path ownership |
| `cf_only_collections.test.js` | platform_earnings, audit logs (no client writes) |
| `admin_only_collections.test.js` | admin-only read collections |
| `misc_collections.test.js` | mixed coverage |
| `additional_collections.test.js` | extras |
| `new_collections.test.js` | flash_auctions, vip_*, app_feedback, monetization_*, dog_walks, demo_bookings (NEW) |

### Adding a new Rules test

```js
const { seedAuthUsers, NON_ADMIN_TOKEN } = require('./_helpers');

describe('my_new_collection — security boundary', () => {
  beforeEach(async () => {
    await testEnv.clearFirestore();
    await seedAuthUsers(testEnv, ['user1', 'attacker']);
  });

  test('owner can read their own doc', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection('my_new_collection').doc('d1').set({
        ownerId: 'user1',
      });
    });
    const db = testEnv
      .authenticatedContext('user1', NON_ADMIN_TOKEN)
      .firestore();
    await assertSucceeds(db.collection('my_new_collection').doc('d1').get());
  });

  test('attacker CANNOT read', async () => {
    // ...
    const db = testEnv
      .authenticatedContext('attacker', NON_ADMIN_TOKEN)
      .firestore();
    await assertFails(db.collection('my_new_collection').doc('d1').get());
  });
});
```

### Important: `isAdmin()` quirk

The `firestore.rules` `isAdmin()` helper does
`get(/users/$(uid)).data.isAdmin`. When the user doc doesn't exist (default
in fresh test env), `get()` returns null and `.data` throws "Null value
error" — even in OR branches. Always seed the auth user via `seedAuthUsers`
helper before running assertions.

---

## 4. E2E tests

**Location:** `integration_test/`

**Run (web):**
```bash
flutter drive --driver=test_driver/integration_test.dart \
              --target=integration_test/login_smoke_test.dart \
              --browser-name=chrome
```

**Status:** Single smoke test as of v15.x. Web-only (Android wrappers blocked
by app_id mismatch — see `tools/notes_e2e.md`). More E2E tests deferred to
post-launch.

---

## CI integration

`.github/workflows/ci.yml` runs all four suites in parallel:

```yaml
jobs:
  test:           # flutter analyze + test/unit/
  cf-tests:       # functions Jest
  rules-tests:    # Firestore emulator + Jest
  lighthouse:     # PWA performance/a11y/SEO/best-practices gates
  build:          # depends on all 4
  deploy:         # depends on build
```

Any test failure blocks deployment.

---

## Troubleshooting

### "Java not found" when running rules tests
The portable JRE is in `tools/jre21/`. Set `JAVA_HOME` and `PATH` per the
"Run" instructions above.

### Flutter tests fail with "Connection refused" to emulator
Flutter unit tests don't need any emulator. If you're seeing this, it's
likely a `fake_cloud_firestore` version mismatch — run `flutter pub get`
to refresh.

### CF tests fail with "Cannot read properties of undefined (reading 'create')"
The Anthropic mock needs runtime override:
```js
const Anthropic = require("@anthropic-ai/sdk").default;
Anthropic.__create.mockResolvedValueOnce({ content: [{ text: "..." }] });
```

### Firestore rules tests show all green but `flutter test` fails
Likely a real bug — the rules tests use the emulator with fresh state
each `beforeEach`. Real Firestore data may break unit tests due to
cached state.

### "Null value error" in rules tests
The user doc isn't seeded. Add the uid to `seedAuthUsers([...uids])`.

---

## Maintaining this guide

When you add a new test category, update the table at the top of this
file with the new count + runtime. When you add a new CF or model that
crosses the 50-LOC threshold, add a corresponding test and a row in
the relevant "What's covered" table.

*Last updated: 2026-05-10 (BONUS 18 sweep — added CSM service tests +
model serialization tests + new_collections rules tests)*
