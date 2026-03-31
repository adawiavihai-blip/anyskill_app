# AnySkill — Clean Architecture Standards

> **Every new domain MUST follow this pattern. No exceptions.**
>
> This document is the binding contract for how code is structured in AnySkill.
> If it's not built in 4 layers with tests, it doesn't ship.

---

## The 4-Layer Rule

```
Layer 1: Model        lib/models/          Immutable data classes
Layer 2: Repository   lib/repositories/    All Firebase operations
Layer 3: Provider     lib/providers/       ChangeNotifier state management
Layer 4: Tests        test/unit/           Offline unit tests (fake_cloud_firestore)
```

**What each layer is allowed to touch:**

| Layer | Can import | Cannot import |
|-------|-----------|---------------|
| Model | `cloud_firestore` (for Timestamp) | Anything else |
| Repository | Model, Firebase SDKs | UI, BuildContext, setState |
| Provider | Model, Repository | Firebase SDKs directly, UI widgets |
| UI (screens/widgets) | Provider (via watch/dispatch) | Repository, Firebase SDKs directly |

---

## Domains Implemented

### 1. Stories System

| Layer | File | Purpose |
|-------|------|---------|
| Model | `lib/models/story.dart` | `Story` with `isExpired`, `isValid`, `isLikedBy()` |
| Repository | `lib/repositories/story_repository.dart` | Upload, delete, like, view, stream |
| Provider | `lib/providers/story_provider.dart` | `StoryAction` enum, `uploadProgress`, error translation |
| Tests | `test/unit/story_test.dart` | **22 tests** |

### 2. Categories & Providers System

| Layer | File | Purpose |
|-------|------|---------|
| Model | `lib/models/category.dart` | `Category` + `SchemaField` with dynamic pricing |
| Model | `lib/models/service_provider.dart` | `ServiceProvider` with `VerificationStatus` lifecycle |
| Repository | `lib/repositories/category_repository.dart` | CRUD, schema loading, image upload, cascade delete |
| Repository | `lib/repositories/provider_repository.dart` | Search, verification lifecycle, admin actions |
| Provider | `lib/providers/category_provider.dart` | Category state with server verification |
| Provider | `lib/providers/service_provider_notifier.dart` | Provider search, approval queue, profile updates |
| Tests | `test/unit/category_provider_test.dart` | **40 tests** |

---

## Dynamic Schema System

Categories can define custom fields that providers fill in during profile setup.
This replaces hardcoded "price per hour" with category-specific pricing and attributes.

### How it works

```
categories/{catId}
  └── serviceSchema: [SchemaField, SchemaField, ...]

users/{uid}
  └── categoryDetails: {fieldId: value, fieldId: value, ...}
```

### SchemaField types

| Type | Dart type | UI widget | Example |
|------|-----------|-----------|---------|
| `number` | `double` | `TextField` (numeric keyboard) | Price per night |
| `text` | `String` | `TextField` | Certification name |
| `bool` | `bool` | `Switch` | "Has fenced yard?" |
| `dropdown` | `String` | `DropdownButton` | Truck size: small/medium/large |

### Primary Price Field

The **first** `number`-type field whose `unit` contains `₪` is the primary price.
Used by search cards to display dynamic pricing (e.g., "150 ₪/ללילה" instead of generic "₪/לשעה").

```dart
// In Category model:
SchemaField? get primaryPriceField =>
    serviceSchema.firstWhere((f) => f.isPriceField);

// In SchemaField:
bool get isPriceField => type == 'number' && unit.contains('₪');
```

### Integration points

| Screen | Widget | Mode |
|--------|--------|------|
| `edit_profile_screen` | `DynamicSchemaForm` | Edit — renders inputs from schema |
| `public_profile_screen` | `CategorySpecsDisplay` | Read-only — shows populated fields |
| `category_results_screen` | `primaryPriceDisplay()` | Compact — price + unit on search cards |

---

## Provider Verification Lifecycle

```
  SIGNUP              PENDING              APPROVED              BANNED
    │                    │                     │                    │
    ▼                    ▼                     ▼                    ▼
┌────────┐      ┌──────────────┐      ┌──────────────┐     ┌──────────┐
│ Form   │─────>│ isPending    │─────>│ isProvider   │────>│ isBanned │
│ Submit │      │ Expert=true  │      │ isVerified   │     │ =true    │
└────────┘      │ isProvider   │      │ isVerified   │     └──────────┘
                │ =false       │      │ Provider=true│
                └──────────────┘      └──────────────┘
                       │                     │
                  Sees: Pending         Sees: HomeScreen
                  Verification          Full access
                  Screen                In search results
```

### VerificationStatus enum

```dart
enum VerificationStatus {
  pending,                // isPendingExpert == true
  verified,              // isProvider + isVerified + isVerifiedProvider
  unverifiedCompliance,  // isProvider + isVerified + !isVerifiedProvider
  banned,                // isBanned == true (overrides all)
}
```

### Computed visibility

```dart
bool get isSearchVisible =>
    isProvider && !isHidden && !isBanned && isVerified;
```

### Admin methods (ProviderRepository)

| Method | What it does | Fields changed |
|--------|-------------|----------------|
| `approveExpert(uid)` | Pending → Live | `isPendingExpert=false, isProvider=true, isVerified=true` |
| `rejectExpert(uid)` | Pending → Rejected | `isPendingExpert=false, isProvider=false` |
| `setVerified(uid, bool)` | Toggle blue checkmark | `isVerified` |
| `setComplianceVerified(uid, bool)` | Toggle compliance | `isVerifiedProvider, compliance.verified` |
| `approveVideo(uid)` | Accept verification video | `videoVerifiedByAdmin=true` |
| `rejectVideo(uid)` | Delete video + reject | `verificationVideoUrl=DELETE, videoVerifiedByAdmin=false` |
| `setBanned(uid, bool)` | Lock/unlock account | `isBanned` |
| `setHidden(uid, bool)` | Hide/show in search | `isHidden` |
| `setOnline(uid, bool)` | Toggle online status | `isOnline` |

---

## Test Suite Coverage (62 tests)

### Stories — 22 tests (`test/unit/story_test.dart`)

| Group | Tests | What's covered |
|-------|-------|----------------|
| Story model | 5 | fromFirestore, missing fields, toJson, copyWith, equality |
| Story expiry | 6 | Future/past expiresAt, timestamp fallback, no-timestamp, isValid |
| Story likes | 2 | isLikedBy with data and empty list |
| StoryProvider state | 4 | Initial state, ownStory, otherStories, clearError |
| Firestore round-trip | 5 | Write-read cycle, sort order, delete+flags, like, idempotent arrayUnion |

### Categories & Providers — 40 tests (`test/unit/category_provider_test.dart`)

| Group | Tests | What's covered |
|-------|-------|----------------|
| Category model | 8 | Full parse, missing fields, top/sub level, schema, primaryPriceField, toJson, copyWith, equality |
| SchemaField | 3 | Dropdown options, isPriceField, toJson omits empty options |
| ServiceProvider model | 3 | Full parse, defaults, phone fallback |
| VerificationStatus | 5 | All 4 states + default |
| isSearchVisible | 5 | Every combination (hidden, banned, unverified, non-provider) |
| Computed properties | 5 | hasLocation, isProfileBoosted, hasUnreviewedVideo, copyWith, equality |
| Provider state | 5 | CategoryProvider + ServiceProviderNotifier initial state and clearError |
| Firestore round-trip | 6 | Category lifecycle, provider approval, click increment, sub-categories, cascade delete, toProfileUpdate |

### Run all tests

```bash
flutter test test/unit/
```

---

## Coding Standard for New Domains

When adding a new domain (Chat, Payments, Bookings, etc.), follow this checklist:

### 1. Model (`lib/models/{domain}.dart`)

- [ ] Immutable class with `const` constructor
- [ ] `factory fromFirestore(DocumentSnapshot doc)` — safe field access with `?? default`
- [ ] `Map<String, dynamic> toJson()` — for Firestore writes
- [ ] `copyWith(...)` — for immutable state updates
- [ ] `operator ==` + `hashCode` — based on document ID
- [ ] Computed properties for business logic (e.g., `isExpired`, `isValid`)

### 2. Repository (`lib/repositories/{domain}_repository.dart`)

- [ ] Constructor accepts injectable Firebase instances for testing
- [ ] `@visibleForTesting` dummy constructor for provider tests
- [ ] `late final` fields (not eagerly initialized)
- [ ] `Stream<List<T>> watch...()` — real-time streams with client-side sort
- [ ] `Future<T?> get...(id)` — one-shot reads
- [ ] Server verification after writes (`Source.server`)
- [ ] Auth token refresh before Storage uploads
- [ ] Fire-and-forget operations use `.ignore()` (not `.catchError(() => null)`)

### 3. Provider (`lib/providers/{domain}_provider.dart`)

- [ ] Extends `ChangeNotifier`
- [ ] Action enum (e.g., `none | loading | saving | deleting`)
- [ ] `String? error` + `bool isLoading` — automatic loading/error state
- [ ] `clearError()` method
- [ ] `startWatching()` to subscribe to repository streams
- [ ] `dispose()` cancels all `StreamSubscription`s
- [ ] Error messages translated to Hebrew
- [ ] `@visibleForTesting` constructor that uses dummy repository

### 4. Tests (`test/unit/{domain}_test.dart`)

- [ ] Uses `fake_cloud_firestore` — runs offline, no Firebase project needed
- [ ] Model parsing tests (full fields + missing fields)
- [ ] Business logic tests (computed properties, validation)
- [ ] State management tests (initial state, clearError, action transitions)
- [ ] Firestore round-trip tests (write → read, update, delete)
- [ ] Minimum 15 tests per domain

### What NOT to do

- Direct `FirebaseFirestore.instance` calls inside widgets
- `setState()` for data that should be global
- Mutable models (always use `copyWith`)
- Showing success before server verification
- Storing `XFile` objects (read bytes immediately, store `Uint8List`)
- Hardcoding fee percentages or configuration values

---

## File Structure

```
lib/
  models/
    story.dart                    # Story + expiry/like logic
    category.dart                 # Category + SchemaField
    service_provider.dart         # ServiceProvider + VerificationStatus
    pricing_model.dart            # (legacy)
    quote.dart                    # (legacy)
    review.dart                   # (legacy)
  repositories/
    story_repository.dart         # Stories Firebase ops
    category_repository.dart      # Categories Firebase ops
    provider_repository.dart      # Provider/expert Firebase ops
  providers/
    story_provider.dart           # Stories state (ChangeNotifier)
    category_provider.dart        # Categories state (ChangeNotifier)
    service_provider_notifier.dart # Providers state (ChangeNotifier)
test/
  unit/
    story_test.dart               # 22 tests
    category_provider_test.dart   # 40 tests
    payment_service_test.dart     # (legacy)
    auth_flow_test.dart           # (legacy)
    ai_analysis_service_test.dart # (legacy)
```

---

*62 tests. 0 errors. 3 domains. Ship it.*

*Last updated: 2026-05-31*
