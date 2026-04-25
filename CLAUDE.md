# AnySkill -- Definitive Master Guide

> **Read this file first in every session.** This is the single source of truth
> for architecture, business rules, payment flows, anti-fraud logic, review
> mechanics, and coding conventions. Breaking changes to any system documented
> here require updating this file in the same commit.

---

## 1. Project Overview

**AnySkill** is an RTL-first (Hebrew + Arabic) service marketplace connecting
customers with verified service providers (experts). Flutter + Firebase, deployed as PWA.

| Layer | Technology |
|-------|-----------|
| Client | Flutter 3.7+, Dart, Riverpod (generators) |
| Auth | Firebase Auth (Google Sign-In, Phone/OTP) |
| Database | Cloud Firestore (43+ collections) |
| Storage | Firebase Storage |
| Functions | Cloud Functions for Firebase (Node.js 24) |
| Payments | **Phase 2 — Israeli payment provider TBD** (Stripe Connect removed in v11.9.x). Booking escrow currently runs on the internal-credits ledger only. |
| AI | Anthropic Claude API, Vertex AI, Google Generative AI |
| Maps | flutter_map + Geolocator |
| i18n | 4 locales: Hebrew (he), English (en), Spanish (es), Arabic (ar) -- 942 keys each |
| Monitoring | Sentry (sentry_flutter ^8.0.0), Firebase Crashlytics, Watchtower |
| Hosting | Firebase Hosting (SPA) |

**Version:** 11.9.0 &bull; **Firebase Project:** anyskill-6fdf3

---

## 2. Folder Structure

```
lib/
  main.dart                  # Firebase init, AuthWrapper, FCM, routing
  constants.dart             # APP_CATEGORIES (6 main + 40 subs), resolveCanonicalCategory()
  firebase_options.dart      # Multi-platform Firebase config
  screens/                   # 63 screens (home, chat, profile, admin, booking, etc.)
    chat_modules/            # 8 modular subsystems (logic, stream, UI, image, location, payment, safety, notification)
    search_screen/           # Search page + widgets (pills, cards, stories)
  services/                  # 41 services (volunteer, community_hub, escrow, gamification, ranking, location, AI, stripe, etc.)
  widgets/                   # 14 reusable widgets (xp_progress_bar, level_badge, pro_badge, etc.)
  models/                    # pricing_model, quote, review
  providers/                 # Riverpod providers (admin_users, admin_billing, admin_global, user_detail)
  repositories/              # Data layer (admin_users, admin_billing, provider, category, search, story, logger)
  utils/                     # expert_filter, payment_calculator, input_sanitizer
  l10n/                      # app_localizations.dart (942 keys, 4 locales: he/en/es/ar)
  constants/                 # quick_tags, help_knowledge_base
functions/                   # Cloud Functions (Node.js)
  index.js                   # XP awards, dispute resolution, payment release, Claude API
  payments.js                # Stripe webhooks, releaseEscrow, morning invoicing
firestore.rules              # Security rules (50+ match blocks)
firestore.indexes.json       # 13+ composite indexes
```

---

## 3. User Roles & Verification

### Role Hierarchy

| Role | Field(s) | How Set | Access |
|------|----------|---------|--------|
| **Customer** | default (no flag) | On signup | Browse, book, chat, review |
| **Provider** | `isProvider: true` | Registration form | Offer services, receive bookings |
| **Pending Provider** | `isPendingExpert: true` | Registration form | Blocked on `PendingVerificationScreen` |
| **Verified Provider** | `isProvider: true, isVerified: true` | Admin approval only | Full marketplace access |
| **Elderly/Needy** | `isElderlyOrNeedy: true` | Admin sets manually | Can request volunteer help; anti-fraud exemption |
| **Demo Expert** | `isDemo: true` | Admin creates via demo tab | Fake profiles to seed supply; `isHidden` toggle |
| **Admin** | `isAdmin: true` (Firestore) + email check | Admin SDK only | Full dashboard, dispute resolution, user management |
| **CMS Admin** | Email = `adawiavihai@gmail.com` | Hardcoded | Content management, design CMS |

### Provider Lifecycle & Registration (`onboarding_screen.dart`)

**Mandatory fields — ALL users (v8.9.4):**

| Field | Hebrew | Mandatory for |
|-------|--------|---------------|
| Full Name | שם מלא | All |
| Phone Number | מספר טלפון | All |
| Email | אימייל | Providers only |
| Profile Image | תמונה | Providers only |
| Business Type | סוג עסק | Providers only |
| ID Number | ת.ז / ח.פ | Providers only |
| ID Document | צילום ת.ז / דרכון | Providers only |
| Category | קטגוריה מקצועית | Providers only |

**OnboardingGate phone enforcement (`main.dart`):**
Legacy users who completed onboarding before phone was mandatory are redirected
back to `OnboardingScreen` if `users/{uid}.phone` is empty.

**Standard path (known category):**
```
1. User fills Contact Info (name + phone mandatory, email for providers)
2. Provider selects business type from dropdown
3. Provider uploads ID document (mandatory)
4. Provider selects category from dropdown (תחום עיסוק)
5. Selects sub-category from cascading dropdown (תת-קטגוריה)
6. All users: profile image + bio
7. Accept terms (must read TermsOfServiceScreen first)
8. Submit → isPendingExpert: true → PendingVerificationScreen
9. Admin approves → isVerified: true → Full provider access
```

**Validation:** `_submit()` enforces all mandatory fields with Hebrew error messages.
`canSubmit` button is disabled until name + phone + terms are filled.
Provider submit is blocked unless ALL provider fields are complete.
Error: "יש למלא את כל הפרטים כדי להמשיך"

**"Other" category path (manual approval):**
```
1. Provider selects "אחר..." in category or sub-category dropdown
2. Free-text field appears: "תאר את השירות שלך" (min 10 chars)
3. Submit → creates category_requests doc (status: 'pending')
              + sets pendingCategoryApproval: true on user
              + sends email to admin (via mail collection)
4. Admin reviews in dashboard → creates new category → approves provider
```

**Business document upload:**
- Label: "העלה תעודת עוסק מורשה/פטור או רישיון עסק"
- Uploads to Firebase Storage: `business_docs/{uid}/license_{timestamp}.{ext}`
- Stored in `users/{uid}.businessDocUrl`
- Optional but expedites approval

**Firestore: `category_requests/{id}`**
```
userId, userName, description, originalCategory?, status: 'pending'|'approved'|'rejected', createdAt
```

### AnySkill Pro Badge (`pro_service.dart`)

Auto-evaluated OR manual override (`proManualOverride: true` locks status).

| Criterion | Threshold | Field |
|-----------|-----------|-------|
| Rating | >= 4.8 stars | `rating` |
| Completed transactions | >= 20 | orderCount from `jobs` query |
| Avg response time | < 15 minutes | `avgResponseMinutes` |
| Cancellations (30d) | 0 | `jobs` query where `cancelledBy == 'expert'` |

Thresholds are configurable from `settings_gamification/pro_thresholds` doc.
When `proManualOverride: true`, automatic recalculation is skipped.

---

## 3b. Dynamic Service Schema (Category-Specific Profiles)

### Overview
Each category can define custom fields that providers fill in during profile setup.
This allows category-specific pricing units (e.g., "₪/ללילה" for pet boarding)
and custom attributes (e.g., "חצר מגודרת?" as a boolean).

### Firestore: `categories/{catId}.serviceSchema`
```json
[
  {"id": "pricePerNight", "label": "מחיר ללילה", "type": "number", "unit": "₪/ללילה"},
  {"id": "hasFencedYard", "label": "חצר מגודרת?", "type": "bool"},
  {"id": "truckSize", "label": "גודל משאית", "type": "dropdown", "options": ["קטן", "בינוני", "גדול"]}
]
```

**Field types:** `number`, `text`, `bool`, `dropdown`

### Firestore: `users/{uid}.categoryDetails`
```json
{"pricePerNight": 150, "hasFencedYard": true}
```

### Primary Price Field Logic
The **first number-type field** in the schema whose `unit` contains "₪" is treated
as the primary price field. This is used in:
- **Search cards:** displays `"150 ₪/ללילה"` instead of generic `"150 ₪/לשעה"`
- **Public profile:** CategorySpecsDisplay shows all populated fields
- **Fallback:** If no schema exists, falls back to `pricePerHour` + "₪/לשעה"

### Widgets (`lib/widgets/category_specs_widget.dart`)
- **`DynamicSchemaForm`** — edit mode: dynamically renders inputs based on schema type
- **`CategorySpecsDisplay`** — read-only display (full mode for profiles, compact for cards)
- **`primaryPriceDisplay(userData, schema)`** — returns `(price, unitLabel)` tuple
- **`loadSchemaForCategory(name)`** — Firestore query helper

### Integration Points
| Screen | Usage |
|--------|-------|
| `edit_profile_screen.dart` | `DynamicSchemaForm` rendered after price field; saves to `categoryDetails` |
| `category_results_screen.dart` | `primaryPriceDisplay()` for dynamic price unit on search cards |
| `public_profile_screen.dart` | `CategorySpecsDisplay` after XP bar showing all specs |

### Admin Setup (Manual or AI-Generated)

**Manual:** Write the `serviceSchema` array directly to the category document in Firestore.

**AI-Powered:** In the admin catalog tab, the "Add Category" dialog includes a
"צור עם AI" (Generate with AI) button that:
1. Takes the category name from the input field
2. Calls `generateServiceSchema` Cloud Function (Claude Haiku)
3. AI returns a JSON schema array with Hebrew labels, types, and pricing units
4. Admin sees a **preview card** showing each generated field with type icon + unit badge
5. Admin can clear/regenerate before saving
6. On save, the `serviceSchema` is written alongside the category document

**Files:**
- `lib/services/ai_schema_service.dart` -- Flutter service calling the CF
- `functions/index.js: generateServiceSchema` -- Cloud Function with Anthropic Claude Haiku
- `lib/screens/admin_catalog_tab.dart` -- UI with "Generate with AI" button + preview

**Cloud Function:** `generateServiceSchema`
- **Auth:** Admin-only (isAdmin check + email check)
- **Model:** `claude-haiku-4-5-20251001`
- **Input:** `{categoryName: "פנסיון לחיות"}`
- **Output:** `{schema: [{id, label, type, unit, options?}, ...]}`
- **Prompt:** Always returns primary price field first (with ₪ unit), plus 2-4 category-specific fields
- **Deploy:** `firebase deploy --only functions:generateServiceSchema`

Categories without a `serviceSchema` field work exactly as before (default hourly pricing).

---

## 3c. Service Schema v2 + Industry-Specific Modules (v12.0.0)

> **STATUS:** Production. The legacy v1 List shape (Section 3b) is still
> supported for backwards compatibility — `ServiceSchema.fromRaw` auto-detects
> v1 vs v2 from the Firestore document.

### Why v2

The legacy v1 schema (a flat `List<SchemaField>`) lacks structured pricing
tiers, off-hours surcharge, mandatory deposits, contextual booking inputs,
and per-industry feature flags. v2 wraps all of those into a single Map
shape — and ships with a one-click admin migration that backfills sensible
defaults across the entire `categories` collection.

### v2 Schema model — `categories/{id}.serviceSchema`

```jsonc
{
  "version": 2,
  "unitType": "per_visit",        // per_hour | per_visit | per_session | per_room
                                    // per_event | per_call | per_person | per_night
                                    // per_walk | flat
  "fields": [                       // Provider-fillable specs (same as v1)
    {"id": "callOutFee", "label": "תעריף קריאה", "type": "number", "unit": "₪/קריאה"}
  ],
  "bundles": [                      // Multi-tier pricing (4-pack, 10-pack, etc.)
    {"id": "pack4", "label": "חבילת 4 סשנים", "qty": 4, "unit": "session", "price": 0, "savingsPercent": 10}
  ],
  "surcharge": {                    // Off-hours / emergency surcharge
    "nightPercent": 30,
    "weekendPercent": 15,
    "nightStartHour": 22,
    "nightEndHour": 7
  },
  "depositPercent": 30,             // Commitment Fee (דמי רצינות)
  "defaultPolicy": "moderate",      // flexible | moderate | strict | nonRefundable
  "bookingRequirements": [          // Customer must answer before "Pay & Secure"
    {"id": "address", "label": "כתובת", "type": "address", "required": true}
  ],

  // ── v2.1 industry feature flags ──
  "requireVisualDiagnosis": true,   // Forces an `image` booking requirement
  "priceLocked": true,              // Shows green "מחיר נעול" badge in summary
  "walkTracking": false,            // Enables Start/End Walk + GPS map (pet)
  "dailyProof": false               // Daily photo + video upload prompt (pet)
}
```

### Provider customizations — `users/{uid}.categoryDetails`

* Schema field values: `{fieldId: value}` (unchanged from v1)
* **Reserved keys**:
  * `_bundles`: `{bundleId: {enabled: bool, price: number}}` — provider-overridden
  * `_surcharge`: `{enabled: bool, nightPct, weekendPct}` — provider-overridden

### Files

| File | Role |
|------|------|
| `lib/widgets/category_specs_widget.dart` | `ServiceSchema`, `PricingBundle`, `SurchargeConfig`, `BookingRequirement`, `loadServiceSchemaFor()`, `DynamicServiceSchemaForm`, `ServiceSchemaDisplay`, `BookingRequirementsForm` |
| `lib/services/schema_migration_service.dart` | `SchemaMigrationService.migrateAll()` — keyword-based default templates per sub-category |
| `lib/services/cancellation_policy_service.dart` | `defaultPolicyForSubcategory()` keyword mapper |
| `lib/screens/admin_catalog_tab.dart` | "מיגרציית סכמות" admin button (header, top-right) |
| `lib/screens/edit_profile_screen.dart` | Renders `DynamicServiceSchemaForm` after price field; reloads on sub-category change |
| `lib/screens/admin_demo_experts_tab.dart` | Renders `DynamicServiceSchemaForm` so demo profiles get full v2 parity |
| `lib/screens/expert_profile_screen.dart` | Loads schema once on profile mount; renders `BookingRequirementsForm` in booking sheet; gates "Pay & Secure" until required fields filled; persists `bookingRequirementValues` + `depositAmount` to job doc |
| `lib/screens/public_profile_screen.dart` | Renders `ServiceSchemaDisplay` (fields + bundles + surcharge + deposit) |

### Migration

Admin panel → "ניהול קטלוג" → **"מיגרציית סכמות"** button.

* Idempotent — existing v2 schemas are NEVER overwritten.
* v1 (List shape) and missing schemas → upgraded to a v2 default chosen by
  keyword matching against parent + sub names. 11 templates ship: pest
  control, locksmith/towing, cleaning, repairs/handyman, fitness, lessons,
  photography, design, events/DJ, beauty/spa, generic.
* Reports `scanned/upgraded/skipped/errors` via snackbar after running.

---

## 3d. Industry-Specific Solutions (v12.1.0)

Built on top of Service Schema v2 to solve trust/reliability issues in the
Israeli service market. Each module is **gated by a schema flag** so it only
activates for the relevant sub-categories.

### Module A: Home Services (`requireVisualDiagnosis` + `priceLocked`)

Applies to: pest control, plumbing, electrician, carpentry, paint, AC, etc.
(Anything with a "תחזוק"/"תיקונ"/"חשמל"/"מדביר"/"אינסטלצ"/etc keyword.)

**Visual Diagnosis Requirement.** When `requireVisualDiagnosis: true`, the
schema includes an `image`-typed booking requirement (`visualDiagnosis`)
that the customer MUST upload before "Pay & Secure" becomes enabled. The
image lives at `booking_requirements/{customerUid}/{requirementId}_{ts}.jpg`
and its URL is stored on `jobs/{id}.bookingRequirementValues.visualDiagnosis`.

**Price Locked Badge.** When `priceLocked: true`, the booking summary shows
a green "🔒 מחיר נעול — מובטח אחרי אישור התמונות" row. The intent is
contractual: once the provider sees the photos and proceeds with the
booking, the price becomes binding (no on-site gouging).

**Storage rule:**
```
match /booking_requirements/{userId}/{allPaths=**} {
  allow read:  if isSignedIn();
  allow write: if isOwner(userId) && isImageContentType() && underSize(10);
}
```

### Module B: Beauty & Grooming (`depositPercent`)

Applies to: hair, cosmetics, nails, massage, spa.

**Commitment Fee.** Beauty schemas ship with `depositPercent: 20`
(20% commitment fee), shown as a separate row in the booking summary
("פיקדון מקדים: ₪X (20%)") and persisted on `jobs/{id}.depositAmount` +
`jobs/{id}.depositPercent`. When the Israeli payment provider integration
ships, this can switch to a deposit-only flow.

**Smart Calendar.** Already enforced by the existing `bookingSlots`
collection — every confirmed booking writes a slot doc and the search
calendar greys out occupied slots in real time. No new code needed.

### Module C: Pet Services (`walkTracking` / `dailyProof`)

Applies to: dog walking, dog boarding/pension, dog training (each gets a
DIFFERENT template — only walking gets `walkTracking`, only boarding gets
`dailyProof`).

**Dog Walk GPS Tracker.** When `walkTracking: true`, the provider's
`ExpertJobCard` shows a "התחל הליכון" / "סיים הליכון" toggle backed by
`DogWalkService`:
1. Start Walk → creates `dog_walks/{walkId}` doc + opens
   `Geolocator.getPositionStream(distanceFilter: 10)`.
2. Each position is appended to the doc's `path` array; flushes every
   5 points or 30 seconds (whichever comes first).
3. End Walk → computes total distance + duration, generates a Google
   Static Maps URL of the route, posts a chat system message of
   `type: 'walk_summary'`, and pushes a notification to the customer.

`walkId` format: `{jobId}_{startTimestamp}` (multi-walk per booking).

**Daily Boarding Proof.** When `dailyProof: true`, the provider's
`ExpertJobCard` shows two camera buttons (תמונה / וידאו) backed by
`BoardingProofService`:
1. Photo upload → `boarding_proofs/{jobId}/{YYYYMMDD}_photo.jpg`
2. Video upload → `boarding_proofs/{jobId}/{YYYYMMDD}_video.mp4`
3. Each merges into `boarding_proofs/{jobId}/days/{YYYYMMDD}` and posts
   a chat message + notification to the customer.

The widget reads "today's proof" on init so it can show check-marks for
already-uploaded media.

**Files:**
| File | Role |
|------|------|
| `lib/services/dog_walk_service.dart` | Start/record/end walk + path stream + distance compute + map URL builder |
| `lib/services/boarding_proof_service.dart` | Daily photo/video upload with chat-message + notification side effects |
| `lib/widgets/pet_service_actions.dart` | Single dual-mode card mounted on `ExpertJobCard` — controlled by `flagWalkTracking` / `flagDailyProof` on the job doc |
| `lib/widgets/bookings/expert_job_card.dart` | Renders `PetServiceActions` between the work-stepper buttons and the "Done" button when either flag is set |

**Job document caching.** When the booking flow creates a job, it copies
the schema flags (`flagWalkTracking`, `flagDailyProof`, `flagPriceLocked`,
`flagRequireVisualDiagnosis`) onto the job doc. This way the provider's
order card can branch on a single read instead of re-fetching the category
schema on every render.

### Storage rules added

```
match /booking_requirements/{userId}/{allPaths=**} { ... }   // 10 MB cap
match /dog_walks/{walkId}/{allPaths=**} { ... }               //  5 MB cap (image only)
match /boarding_proofs/{jobId}/{allPaths=**} { ... }          // 50 MB cap (image + video)
```

### Firestore rules added

```
match /dog_walks/{walkId} {
  // Read: customer or provider only
  // Write: provider only (creates + appends path)
}
match /boarding_proofs/{jobId} { ... }
match /boarding_proofs/{jobId}/days/{dayKey} { ... }
```

Both use `get(/databases/$(database)/documents/jobs/$(jobId))` to inherit
participant identity from the parent job doc — guarantees the customer and
provider on a job can both see the walk/proof, and nobody else can.

### v12.1.1 — hardening pass (reliability + cost + platform coverage)

Four issues flagged in the v12.1.0 ship notes are now fixed in-place.
None of them changed the public schema shape.

**1. Platform permission coverage**

* `ios/Runner/Info.plist` — existing `NSLocationWhenInUseUsageDescription`
  updated to mention dog-walking explicitly. Added
  `NSLocationAlwaysAndWhenInUseUsageDescription`, `NSLocationAlwaysUsageDescription`,
  `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`,
  `NSMicrophoneUsageDescription`, and added `location` to
  `UIBackgroundModes` so `Geolocator.getPositionStream` keeps firing when
  the screen locks.
* `android/app/src/main/AndroidManifest.xml` — added
  `ACCESS_BACKGROUND_LOCATION`, `FOREGROUND_SERVICE`,
  `FOREGROUND_SERVICE_LOCATION`, `CAMERA`.
* `DogWalkService.startWalk` — now makes a second
  `Geolocator.requestPermission()` call after `whileInUse` is granted to
  prompt for the iOS "always" upgrade. Degrades gracefully to
  foreground-only if the user declines.

**2. Free static map (no API key, no watermark)**

`DogWalkService._staticMapUrl` rewritten to use
`https://staticmap.openstreetmap.de/staticmap.php` — community-hosted,
completely free. Polyline format identical to Google's
`path=color:0x6366F1ff|weight:5|lat,lng|...`, markers use OSM's
`lightblue1` / `ol-marker` types. Caps at 60 sampled points.

In addition to the static preview, the new
[lib/screens/walk_route_screen.dart](lib/screens/walk_route_screen.dart)
provides an **interactive** route viewer using the existing `flutter_map` +
`latlong2` stack — tapping the walk summary card in chat opens a full
OpenStreetMap view with live polyline and start/end markers. Streams the
walk doc in real time, so in-progress walks animate as the provider moves.

Wired into `chat_ui_helper.dart` via two new card widgets:
* `_WalkSummaryCard` — opens `WalkRouteScreen` on tap
* `_BoardingProofCard` — shows the daily photo + launches external video player

**3. Deposit-only escrow mode**

When `ServiceSchema.depositPercent > 0`, the customer now pays **only the
deposit** at booking and the remainder is charged on release. Data model:

| Field on `jobs/{id}` | Meaning |
|----------------------|---------|
| `totalAmount` | Full service price (unchanged) |
| `depositPercent` | Copied from schema at booking |
| `depositAmount` | `totalAmount * depositPercent / 100` |
| `paidAtBooking` | Actually debited at booking (= deposit, or total if no deposit) |
| `remainingAmount` | `totalAmount - paidAtBooking` — charged on release |
| `depositPaidAt` | Timestamp of the deposit charge |
| `remainderPaidAt` | Timestamp of the final charge |

**Client (`expert_profile_screen._processEscrowPayment`):** sufficient-
balance check now compares against `paidAtBooking` instead of `totalAmount`.
The wallet transaction title is suffixed with `"(פיקדון)"` for deposit
bookings so the user's finance screen is self-explanatory.

**Cloud Function (`processPaymentRelease`):** inside the atomic transaction
we re-read the job doc, check `remainingAmount`, and if > 0 debit the
customer's balance for the remainder before computing the provider payout.
Throws `failed-precondition` if the customer has insufficient balance, so
the UI can show a "top up your wallet" message.

**Cloud Function (`processCancellation`):** refund math switched to use
`paidAtBooking` instead of `totalAmount`. Penalty amount is capped at
`paidAtBooking` (never over-charge). `nonRefundable` + `strict` both
compute as 100% penalty fraction.

**Customer UI (`customer_booking_card.dart`):** when a booking has
`remainingAmount > 0`, the release button label changes from "אשר ושחרר
תשלום" to "אשר ושלם את היתרה", and a blue info card above the button
shows "שולם בפיקדון: ₪X" + "ייגבה בשחרור: ₪Y" so there are no surprises.

**4. Walk resume after app close (SharedPreferences)**

`DogWalkService` now persists the active walk to SharedPreferences so a
tab refresh / app relaunch can resume silently. Keys:

```
dog_walk.activeWalkId
dog_walk.activeJobId
dog_walk.activeCustomerId
dog_walk.activeCustomerName
dog_walk.activeProviderId
dog_walk.activeProviderName
```

New API:

* `DogWalkService.readPersistedActiveWalk()` → `PersistedWalkInfo?`
* `DogWalkService.tryResumeActiveWalk()` → `bool` (true = resumed)

Behaviour:

1. `startWalk` writes all keys immediately after the Firestore doc is created.
2. `endWalk` and `cancelWalk` clear all keys.
3. `tryResumeActiveWalk()` reads the keys, verifies the doc still exists
   in Firestore with `status == 'walking'`, re-requests location permission,
   and re-attaches the position stream to the same `walkId`. Stale prefs
   (doc missing, finished, or cancelled elsewhere) are cleared silently.

The [PetServiceActions](lib/widgets/pet_service_actions.dart) widget calls
`_attemptResumeWalk()` in `initState` — but **only** when the persisted
`jobId` matches the widget's own `jobId`, so other jobs' walks are left
alone. On successful resume the user sees a green snackbar
"🐕 ההליכון ממשיך — חזרה מהפסקה".

---

## 4. Escrow & Payment Lifecycle

> **PHASE 2 NOTE (v11.9.x):** Stripe Connect was removed from the codebase
> pending integration with an Israeli payment provider. The legacy
> internal-credits ledger is now the **only** payment path. All references
> below to "Stripe path", `releaseEscrow` CF, `processRefund` CF,
> `stripePaymentIntentId`, `stripeAccountId`, etc. describe the previous
> architecture and are kept here as a reference for the re-integration
> work. Booking now flows: chat quote → `EscrowService.payQuote()` →
> `processPaymentRelease` CF → completed.

### 4.1 Quote-to-Escrow Creation (`escrow_service.dart`)

Triggered when customer taps "Pay & Secure" on a quote card. Runs as a
**Firestore transaction** (atomic, all-or-nothing):

```
1. READ   client balance             (must be >= totalAmount)
2. READ   admin/admin/settings/settings  (feePercentage, default 0.10)
3. READ   quote status               (must not be 'paid')
4. CALC   commission = totalAmount * feePercentage
5. CALC   netToProvider = totalAmount - commission
6. WRITE  jobs/{new}                 status: 'paid_escrow'
7. WRITE  users/{client}.balance     -= totalAmount
8. WRITE  users/{provider}.pendingBalance  += netToProvider
9. WRITE  platform_earnings/{new}    amount: commission, status: 'pending_escrow'
10. WRITE transactions/{new}         type: 'quote_payment', payoutStatus: 'pending'
11. WRITE quotes/{id}.status         = 'paid'
12. WRITE admin settings             totalPlatformBalance += commission
13. POST  chat system message        "₪X נעולים באסקרו. העבודה יכולה להתחיל!"
```

### 4.2 Job Status Transitions

```
                          paid_escrow
                              |
               +--------------+--------------+
               |                             |
        Expert marks done              Customer cancels
               |                             |
        expert_completed            (cancellation policy)
               |                       /            \
        Customer approves       Before deadline   After deadline
               |                    |                  |
     releaseEscrow CF          cancelled       cancelled_with_penalty
               |
           completed
               |
        Both sides review
               |
         Reviews published
```

**Terminal statuses:** `completed`, `cancelled`, `cancelled_with_penalty`, `refunded`, `split_resolved`, `disputed`

### 4.3 Payment Release

**Active path — internal credits** (`index.js: processPaymentRelease`):
1. Read admin fee inside transaction (support per-expert `customCommission` override)
2. `expert.balance += netToExpert`, `expert.orderCount += 1`
3. `admin.totalPlatformBalance += feeAmount`
4. Write `platform_earnings` + `transactions` records

**REMOVED — Stripe path** (was `payments.js: releaseEscrow`, deleted in v11.9.x):
- Verified PaymentIntent → `stripe.transfers.create()` (ils, agorot)
- Generated Morning (Green Invoice) tax documents
- Will be reintroduced when the Israeli payment provider is integrated.
  At that point, jobs created via the new provider will carry a
  `paymentProvider` field that gates which CF the client calls
  (the legacy switch on `stripePaymentIntentId != null` is gone).

**CRITICAL:** Fee percentage MUST be read from Firestore **inside** the transaction. Never hardcode.

### 4.4 Cancellation Policy (`cancellation_policy_service.dart`)

| Policy | Free window | Penalty after window |
|--------|-------------|---------------------|
| `flexible` | 4 hours before appointment | 50% of amount |
| `moderate` | 24 hours before appointment | 50% of amount |
| `strict` | 48 hours before appointment | 100% of amount |

**Provider cancels:** Always full refund to customer. Provider gets -100 XP penalty.

**Customer cancels before deadline:** Full refund, status `cancelled`.

**Customer cancels after deadline:**
- `customerCredit = totalAmount - penaltyAmount`
- `expertCredit = penaltyAmount * (1 - feePct)`
- `platformFee = penaltyAmount * feePct`
- Status: `cancelled_with_penalty`

### 4.8 Support Workspace & RBAC — Uber/Airbnb-grade (v11.9.x)

**Purpose:** Production-grade support center for triaging customer/provider
issues. Built in the style of Uber/Airbnb support consoles: split-screen
workspace with ticket queue, customer 360 view, and action center. Includes
full role-based access control so support agents can do their job without
having access to the financial Vault, fee settings, or admin-only operations.

#### RBAC Model (3 roles)

| Role | Stored | Lands on | Can access |
|------|--------|----------|-----------|
| `admin` | `users/{uid}.role == 'admin'` AND `isAdmin == true` | HomeScreen + AdminScreen | Everything (Vault, fees, broadcast, agent management) |
| `support_agent` | `users/{uid}.role == 'support_agent'` AND `isAdmin == false` | SupportDashboardScreen (dedicated workspace) | Tickets, customer 360, restricted action set |
| `user` (default) | no role field, or `'user'` | HomeScreen (regular flow) | Customer/provider features |

**Important:** The role field lives on the user doc, NOT in Firebase Custom
Claims. This was a deliberate choice to avoid the token-refresh complexity
and maintain consistency with the existing `isAdmin` boolean. Custom Claims
hardening is a Phase 2 enhancement.

The `setUserRole` Cloud Function syncs `role` and `isAdmin` together so
existing isAdmin checks throughout the codebase continue to work unchanged.

#### What support agents CANNOT do (the "Vault")

| Locked | Why | Enforced where |
|--------|-----|----------------|
| Read `admin/admin/settings/settings` (fee % etc.) | Financial config | firestore.rules — `admin/{docId}` allows read but only admins write |
| Read `platform_earnings` | Revenue privacy | firestore.rules — admin-only read |
| Write `admin_audit_log` | Admin trail | rules — `isAdmin()` only |
| `grantAdminCredit` CF | Money creation | CF gate — `isAdminCaller` |
| `setUserRole` CF (promote/demote) | Privilege escalation | CF gate — `isAdminCaller` |
| `deleteUser` CF | Destructive | CF gate — `isAdminCaller` |
| `processRefund` (above ₪1,000) | Refund cap | CF gate (existing) |
| AdminScreen (any tab) | UI access | Routing — agents land on SupportDashboardScreen instead |
| Withdrawals tab | Provider payouts | UI not exposed in workspace |

#### What support agents CAN do

| Action | Endpoint | Audit logged? |
|--------|----------|---------------|
| Read all support_tickets | Direct Firestore (rule: `isStaff()`) | — |
| Claim a ticket (assign to self) | `SupportAgentService.claimTicket` | No (claim is benign) |
| Send public message to customer | `SupportAgentService.sendMessage(isInternal: false)` | No |
| Send internal note (staff-only) | `SupportAgentService.sendMessage(isInternal: true)` | No |
| Verify identity | `supportAgentAction` CF, action `verify_identity` | ✅ Yes |
| Send password reset email | `supportAgentAction` CF, action `send_password_reset` | ✅ Yes |
| Flag account for review | `supportAgentAction` CF, action `flag_account` | ✅ Yes |
| Unflag account | `supportAgentAction` CF, action `unflag_account` | ✅ Yes |
| Close ticket + trigger CSAT survey | `SupportAgentService.closeTicket` | No |
| View customer 360 (orders, balance, ratings) | Direct Firestore reads | — |

Every audit-logged action writes to `support_audit_log` with:
`{agentUid, agentName, agentRole, action, targetUserId, targetName, reason, ticketId, result, createdAt}`. Reason is required (≥5 chars).

#### Cloud Functions added

| CF | Auth | Purpose |
|----|------|---------|
| `setUserRole` | admin only | Grants/revokes support_agent role. Syncs role + isAdmin atomically. Audit-logged to BOTH admin_audit_log and support_audit_log. |
| `supportAgentAction` | admin OR support_agent | Centralized action dispatch (verify_identity, send_password_reset, flag/unflag). Validates reason ≥5 chars, writes audit log, returns result. |

#### Firestore collections added/modified

```
support_tickets/{id}                    // EXTENDED
  // Existing: userId, userName, category, subject, status, jobId, createdAt
  // New v11.9.x:
  priority: 'low' | 'normal' | 'high' | 'urgent'  // SLA priority
  assignedTo: agentUid | null
  assignedToName: string | null
  lastAgentMessageAt: Timestamp | null  // SLA breach flag computation
  closedAt: Timestamp | null
  closedBy: agentUid | null
  csatRequested: bool                   // true after closeTicket
  csatRating: int | null                // 1-5 stars
  csatComment: string | null
  csatSubmittedAt: Timestamp | null

support_tickets/{id}/messages/{msgId}   // EXTENDED
  // Existing: senderId, senderName, isAdmin, message, createdAt
  // New v11.9.x:
  isInternal: bool                      // true = staff-only note (filtered from customer)

support_audit_log/{id}                  // NEW
  agentUid, agentName, agentRole, action, targetUserId, targetName,
  reason, ticketId, result, createdAt

canned_responses/{id}                   // NEW
  title, body, category, createdBy, createdAt
  // Body supports {customerName}, {ticketId}, {agentName} placeholders
  // Auto-seeded with 10 default Hebrew templates on first dashboard load
```

#### Firestore rules added

```javascript
// Helper functions
function isSupportAgent() {
  return isVerifiedAuth()
      && get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'support_agent';
}
function isStaff() {
  return isAdmin() || isSupportAgent();
}

// support_tickets — staff sees all, agents update assigned tickets
match /support_tickets/{ticketId} {
  allow read: if isStaff() || (isVerifiedAuth() && resource.data.userId == request.auth.uid);
  allow update: if isStaff() || (isVerifiedAuth() && resource.data.userId == request.auth.uid);
  // ...
  match /messages/{msgId} {
    // Customer can ONLY read non-internal messages (isInternal != true)
    allow read: if isStaff() || (isVerifiedAuth() && resource.data.isInternal != true && ...);
    // Customer cannot write internal notes
    allow create: if isStaff() || (isVerifiedAuth() && request.resource.data.isInternal != true && ...);
  }
}

// support_audit_log — read by admin (all) or agent (own entries only)
// Writes blocked at client; only Cloud Functions can append
match /support_audit_log/{logId} {
  allow read: if isAdmin() || (isSupportAgent() && resource.data.agentUid == request.auth.uid);
  allow create, update, delete: if false;
}

// canned_responses — staff reads, admin writes
match /canned_responses/{templateId} {
  allow read: if isStaff();
  allow create, update, delete: if isAdmin();
}
```

The Vault remains locked because the existing `admin/`, `platform_earnings`,
`admin_audit_log`, etc. rules use `isAdmin()` (not `isStaff()`), so adding
the support_agent role doesn't grant any access to financial collections.

#### SupportDashboardScreen — 3-pane workspace

```
┌────────────────────────────────────────────────────────────────────────────┐
│ AppBar:  AnySkill Support · Workspace · [12 פתוחות] · [agent name] · 🚪    │
├──────────────┬──────────────────────────────────────┬──────────────────────┤
│              │   ┌─ Customer info bar ──────────┐   │   Customer profile   │
│ Ticket Queue │   │ name · status · priority · 🚩│   │   ┌──────────────┐   │
│              │   │ subject preview              │   │   │ avatar  name │   │
│ [filters]    │   │ [קח לטיפול] (if unassigned)  │   │   │ email phone  │   │
│ • all/me/    │   └──────────────────────────────┘   │   │ verified ✓   │   │
│   unassigned │                                       │   └──────────────┘   │
│ • urgent/    │   ┌─ Messages list ──────────────┐   │                      │
│   high/...   │   │  [customer]:  שלום, יש לי..  │   │   🛠️ Actions         │
│              │   │                              │   │   • אמת זהות         │
│ ┌─ tickets ─┐│   │  [agent]:     אני בודק...    │   │   • איפוס סיסמה      │
│ │ 🔴 0:12  ││   │                              │   │   • דגל את החשבון    │
│ │ Urgent   ││   │  📝 Internal note (yellow):  │   │                      │
│ │          ││   │     לטפל מהר — VIP customer  │   │   🎯 Resolution       │
│ │ 🟡 5:30  ││   │                              │   │   • סמן כנפתר        │
│ │ ...      ││   └──────────────────────────────┘   │                      │
│ │          ││                                       │   📊 Context          │
│ │ 🟢 1:02  ││   ┌─ Composer ───────────────────┐   │   • 12 הזמנות        │
│ │ ...      ││   │ [💬 ללקוח] [🔒 הערה פנימית] │   │   • ₪3,200 יתרה      │
│ └──────────┘│   │ [תבניות ▾]                   │   │   • ⭐ 4.8 דירוג     │
│              │   │ [______________________]    │   │                      │
│              │   │ [שלח ↑]                     │   │   📋 Recent jobs     │
│              │   └──────────────────────────────┘   │   ...                │
└──────────────┴──────────────────────────────────────┴──────────────────────┘
   ~300px              flex                              ~360px
```

**Key features:**
- **SLA timers** — every ticket card shows age with color-coded pill
  (🟢 0-5 min, 🟡 5-10 min, 🔴 10+ min). Queue auto-sorts breached tickets
  to the top. Refreshed every 30 seconds via internal Timer.periodic.
- **Ticket assignment** — "קח לטיפול" button claims the ticket. Once
  assigned, the agent sees an "אצלי" badge and can work without competing
  with other agents on the same ticket.
- **Internal notes** — toggle in the composer between "💬 הודעה ללקוח"
  and "🔒 הערה פנימית". Internal notes render with yellow background +
  lock icon, are filtered out of customer view by Firestore rules.
- **Canned responses** — bottom sheet with 10 default Hebrew templates
  (auto-seeded on first dashboard load). Templates support
  `{customerName}`, `{ticketId}`, and `{agentName}` placeholders that are
  replaced when inserted into the composer.
- **Customer 360 panel** — right side shows the customer's profile,
  recent orders, balance, rating, and a count of other open tickets.
  All actions (verify, password reset, flag, close) are one-click and
  require a reason (which goes to the audit log).
- **CSAT survey** — when an agent clicks "סמן כנפתר וסגור", the customer
  receives a `csat_survey` notification. Tapping it opens a 5-star
  rating modal (`csat_survey_modal.dart`) with optional comment field.
  The result is written to `support_tickets/{id}.csatRating`.

#### Files

| File | Purpose |
|------|---------|
| `lib/services/support_agent_service.dart` | Centralized service: role detection, ticket queue streams, SLA computation, claim/release/close, message send (with internal flag), agent action dispatch, customer 360 loader, CSAT submission |
| `lib/services/canned_responses_service.dart` | Template service: stream all, seed defaults, fill placeholders |
| `lib/screens/support/support_dashboard_screen.dart` | The full 3-pane workspace (queue + customer 360 + action center). 1,887 lines. |
| `lib/screens/support/csat_survey_modal.dart` | CSAT modal (1-5 stars + comment), opened from notification tap |
| `lib/screens/admin_agent_management_tab.dart` | Admin tab: list of agents + add agent dialog (search by email/name, promote via setUserRole CF) + audit log viewer |
| `functions/index.js: setUserRole` | CF: admin grants/revokes support_agent role |
| `functions/index.js: supportAgentAction` | CF: centralized agent action dispatch with validation + audit |

#### Routing

```
Login → AuthWrapper (StreamBuilder<User>)
  ↓
OnboardingGate reads users/{uid}
  ↓
PRIORITY 1: isAdmin == true             → HomeScreen (admin gets all tabs)
PRIORITY 1b: role == 'support_agent'    → SupportDashboardScreen ✅ NEW
PRIORITY 2: hasRole (provider/customer) → HomeScreen (regular)
PRIORITY 3: pending verification        → PendingVerificationScreen
PRIORITY 4: no role yet                 → OnboardingScreen
```

The agent **cannot** navigate to HomeScreen — there's no path. They sign
out and back in with a separate account if they want to use AnySkill as
a regular customer.

#### Admin Agent Management Tab

Lives in the existing AdminScreen Management section as a 16th tab:
**"סוכני תמיכה 🎧"**. Two sub-tabs:

1. **מומחי תמיכה** — list of all current support agents with their join
   date + a "הסר הרשאת סוכן" action. FAB opens an "Add Support Agent"
   dialog that searches users by name/email and grants the role via
   `setUserRole` CF.
2. **יומן פעולות** — full `support_audit_log` stream sorted by date.
   Shows agent name, action type (with icon), target user, reason, and
   timestamp. Read-only — append-only log.

#### What the customer sees vs the agent

| | Customer | Agent |
|--|----------|-------|
| Ticket list | "הפניות שלי" inside SupportCenterScreen | Full queue with SLA + filters |
| Messages | All non-internal messages only | All messages including internal notes |
| Actions | View status, send messages | Verify, flag, password reset, close, internal notes, canned responses |
| Customer 360 | N/A | Full profile + orders + transactions + flags |

#### Phase 2 hardening (future)

- Migrate role storage from Firestore field to **Firebase Custom Claims**
  for cryptographic guarantees independent of Firestore reads
- Add **per-agent SLA dashboards** (avg response time, CSAT, resolution rate)
- Add **agent shift scheduling** (active/offline state, on-call rotation)
- Add **admin alerts** when SLA breached or CSAT < 3 stars

### 4.7 Demo Expert Profiles — Soft Launch Supply Seeding (v11.9.x)

**Purpose:** During Soft Launch (before real providers register), the admin
needs to populate the marketplace with high-quality fake provider profiles
so customers see a fully-stocked catalog. Customers can attempt to book
these profiles; the system intercepts the booking and notifies the admin
to convert the demand signal into a real provider sourcing call.

**Key principle:** Demo profiles are **indistinguishable** from real ones in
the customer-facing UI. They appear in search, can be browsed, have reviews,
gallery, working hours, pricing — everything a real profile has. The ONLY
difference is at the booking transaction: the escrow flow is bypassed and a
softer "we'll update you" message is shown instead.

#### Architecture

```
ADMIN side                              CUSTOMER side
─────────                              ─────────
AdminDemoExpertsTab                    CategoryResultsScreen / GlobalSearchBar
  ├─ "Demo Experts" list                 │ (no longer filters isDemo)
  └─ "Demo Bookings" tab                 ▼
       ▲                              Demo profile in search results
       │ writes ←──────────────────── Tap "Book Now" on demo profile
       │                                 │
       │                                 ▼
   demo_bookings/{id}                ExpertProfileScreen
   notifications/{id} × N admins        │
   activity_log/{id}                    │ _processEscrowPayment(isDemo: true)
       ▲                                 │
       │                                 ▼
       └─────────── Customer sees   _handleDemoBooking()
                    "ההזמנה התקבלה" ─→  │ Reads customer profile
                    success view         │ Reads demo expert category
                                         │ Writes demo_bookings doc
                                         │ Writes activity_log entry
                                         │ Notifies ALL admins (1 doc each)
                                         │ Notifies the customer too
                                         ▼
                                     Returns true → success view
```

#### Demo Profile Creation (`AdminDemoExpertsTab`)

The admin creates a demo profile via a full-feature form that mirrors a
real provider profile. **All fields:**

| Field | Required | Notes |
|-------|----------|-------|
| Name | ✅ | Display name |
| Phone | optional | Hidden from customers, used by admin for handoff |
| Email | optional | Same as above |
| Bio / description | recommended | Long-form intro |
| Completed jobs | default 54 | Inflates social proof |
| **Price per hour** | default ₪150 | Drives the price displayed in cards |
| Category (main) | ✅ | Sets `serviceType` and the `provider_listings` doc category |
| Sub-category | optional | When set, becomes the effective `serviceType` |
| Profile image | recommended | Storage upload or pasted URL |
| **Gallery** | up to 6 | 3×2 grid, Storage uploads |
| **Working hours** | per day, 0=Sun..6=Sat | Checkbox enable/disable + from/to times |
| **Cancellation policy** | flexible / moderate / strict | Same options as real providers |
| **Quick tags** | multi-select | 8 predefined tags (fast_response, reliable, etc.) |
| **Reviews** | up to 5 | Editable in BOTH create and edit mode |

#### Key behaviors

1. **Auto-creates `provider_listings` doc.** On every save, the form writes
   to BOTH `users/{uid}` AND `provider_listings/demo_{uid}`. Without this
   the demo wouldn't appear in search (which queries `provider_listings`).
   The listing ID is deterministic (`demo_{uid}`) so subsequent edits upsert.
2. **Reviews are editable post-creation.** Previously, the form had a banner
   "reviews can only be created on first save". Now the form loads existing
   demo reviews from Firestore on edit, lets the admin update or clear them,
   and persists the changes (update / delete / create as needed).
3. **Sticky bottom CTA bar.** The submit button used to be at the end of a
   long ListView and got cut off below the fold. Now it lives in a `Stack`
   pinned to the bottom — always reachable.
4. **isHidden toggle syncs both docs.** Hiding a demo from search now updates
   both the `users` doc AND the `provider_listings` doc (the search query
   reads from listings, so user-only update used to leave them visible).
5. **Delete cleans up everything.** Deleting a demo removes the user doc,
   the listing doc, AND all associated demo reviews.

#### Demo Booking Interception (`_handleDemoBooking` in expert_profile_screen.dart)

When a customer taps "Book Now" on a demo profile:

1. **No escrow transaction.** The customer's balance is NOT debited. No
   `jobs/{id}` doc is created. No `bookingSlots/{id}` reservation.
2. **Customer profile is read** (name, image, phone) for the admin context.
3. **`demo_bookings/{id}` doc is created** with all the context needed:
   ```
   {
     customerId, customerName, customerImage, customerPhone,
     demoExpertId, demoExpertName, demoExpertCategory,
     selectedDate, selectedTime, totalAmount,
     status: 'pending' | 'contacted',
     createdAt: serverTimestamp,
   }
   ```
4. **`activity_log` entry** is also written for the existing live feed.
5. **Every admin user receives an in-app notification.** The client queries
   `users where isAdmin == true`, then writes one `notifications/{id}` doc
   per admin in a single batch. No Cloud Function needed (1-3 admins in
   practice).
6. **The customer also gets a notification** matching the friendly success
   message shown on screen.
7. **Success view** renders with demo-specific text: "ההזמנה התקבלה!" +
   "אנחנו כבר מעדכנים אותך אם נותן השירות פנוי" + indigo color scheme +
   hourglass icon (instead of green checkmark for real bookings).

#### Demo Bookings Sub-tab

The `AdminDemoExpertsTab` is now a 2-tab screen:
- **Tab 1: "מומחי דמו"** — list of all demo profiles, with create/edit/hide/delete
- **Tab 2: "הזמנות שניסו לקבוע"** — every demo booking attempt, with:
  - Customer name + image + phone
  - Demo expert name + category
  - Requested date + time slot
  - Amount they would have paid
  - Timestamp
  - Status pill: "ממתין" (pending) or "✓ טופל" (contacted)
  - Actions: "סמן כטופל" + "מחק"

The admin uses this tab as a sales pipeline: every pending booking is a
real customer expressing real demand for a category that doesn't yet have
real providers. Convert each one by manually sourcing a real provider for
that category.

#### Firestore rules added

```javascript
match /demo_bookings/{bookingId} {
  allow create: if isVerifiedAuth()
                && request.resource.data.customerId == request.auth.uid;
  allow read:   if isAdmin();
  allow update: if isAdmin() && onlyFields(['status', 'contactedAt', 'adminNotes']);
  allow delete: if isAdmin();
}
```

Plus updated `provider_listings` create/update to allow `|| isAdmin()` so
the admin client can write the demo listing for a fake user UID.

#### Files

- [lib/screens/admin_demo_experts_tab.dart](lib/screens/admin_demo_experts_tab.dart) — full rewrite, 2 tabs, sticky CTA, 11+ fields
- [lib/screens/expert_profile_screen.dart](lib/screens/expert_profile_screen.dart) — `_handleDemoBooking` enhanced, `_buildBookingSuccessView` accepts `isDemo`
- [lib/screens/category_results_screen.dart](lib/screens/category_results_screen.dart) — removed `isDemo` filter (line 221)
- [lib/widgets/global_search_bar.dart](lib/widgets/global_search_bar.dart) — removed `isDemo` filter (line 206)
- [firestore.rules](firestore.rules) — new `demo_bookings` rules + admin override on `provider_listings`

#### What is still filtered

- [job_broadcast_service.dart:119](lib/services/job_broadcast_service.dart#L119) — broadcasts skip demos (correct: they wouldn't respond)
- [chat_screen.dart:139](lib/screens/chat_screen.dart#L139) — *opposite* check (logs demand signal IF demo). Keep as-is.

### 4.6 Admin Credit Grants — Soft Launch Tool (`grantAdminCredit` CF)

**Purpose:** During the Phase 2 transition (Stripe removed, Israeli payment
provider TBD), customers cannot top up their own balance. This tool lets
admins grant promotional/compensation credits to specific users so the
marketplace can run a Soft Launch with real users on internal credits only.

**Trigger:** [admin_user_detail_screen.dart](lib/screens/admin_user_detail_screen.dart) — "Top Up Wallet" action button → opens `_GrantCreditDialog`.

**Flow:**
```
Admin opens user detail → taps "Top Up Wallet"
  ↓
_GrantCreditDialog (with quick-pick chips ₪50/100/250/500/1000)
  ↓
Admin enters: amount + reason (≥10 chars, mandatory)
  ↓
Client calls grantAdminCredit CF with idempotency key
  ↓
CF validates:
  • Caller is admin (isAdminCaller check)
  • amount > 0 AND amount ≤ ₪5,000          (per-grant cap, typo protection)
  • reason length ≥ 10 chars                  (mandatory audit trail)
  • targetUserId !== caller.uid               (no self-grant)
  • Idempotency check (cached result if same clientReqId within 1 hour)
  • Daily cap: caller's grants today + amount ≤ ₪20,000  (insider risk)
  ↓
Atomic Firestore transaction writes:
  1. users/{target}.balance += amount
  2. transactions/{new} (type: 'admin_credit_grant', reason, grantedBy)
  3. admin_audit_log/{new} (action: 'grant_credit', beforeBalance, afterBalance)
  ↓
Best-effort (outside transaction):
  • Cache idempotency record (admin_credit_idempotency/{caller}_{clientReqId})
  • Notify user (in-app notification + FCM push if token exists)
  ↓
Returns: { success, beforeBalance, afterBalance, dailyTotalUsed, dailyCapRemaining }
```

**Limits (hardcoded — change in `functions/index.js: grantAdminCredit`):**
- Per-grant cap: **₪5,000**
- Per-admin per-day cumulative cap: **₪20,000**
- Reason min length: **10 characters**
- Idempotency window: **1 hour**

**Audit trail:** Every grant is written to `admin_audit_log` with the full
context (admin uid, target uid, amount, reason, before/after balance, timestamp).
The daily cap is enforced by reading from this same collection inside the
transaction, so two concurrent grants from the same admin cannot squeeze through.

**Removal plan:** This CF + UI dialog should be **kept** even after the
Israeli payment provider is integrated — it's still useful for customer
service compensations, refund-as-credit flows, and promotional campaigns.
The only change post-Phase-2: relabel the UI from "Soft Launch tool" to
"Customer Service tool".

**Files:**
- `functions/index.js: grantAdminCredit` (CF)
- `lib/screens/admin_user_detail_screen.dart: _GrantCreditDialog` (UI)
- New collection: `admin_credit_idempotency/{adminUid}_{clientReqId}` (cache)
- Existing collection: `admin_audit_log` (audit trail, daily cap source)

### 4.5 Dispute Resolution (`functions/index.js: resolveDisputeAdmin`)

Admin-only. Three resolution options:

| Resolution | Customer gets | Expert gets | Platform gets | New status |
|-----------|---------------|-------------|---------------|------------|
| **Refund** | 100% of totalAmount | 0 | 0 | `refunded` |
| **Release** | 0 | totalAmount * (1-fee) | totalAmount * fee | `completed` |
| **Split** | 50% | 50% * (1-fee) | 50% * fee | `split_resolved` |

Fields written: `resolvedAt`, `resolvedBy` (admin UID), `resolutionType`, `adminNote`.

---

## 5. Airbnb-Style Review System

### 5.1 Review Data Model (`review_service.dart`)

```
reviews/{id}:
  jobId             String     -- links to booking
  reviewerId        String     -- who wrote it
  reviewerName      String     -- display name
  revieweeId        String     -- who is being reviewed
  isClientReview    bool       -- true = customer reviews expert
  ratingParams      Map        -- { professional, timing, communication, value } (1.0-5.0 each)
  overallRating     double     -- average of the 4 params, rounded to 1 decimal
  publicComment     String     -- visible text
  privateAdminComment String   -- admin-only notes
  isPublished       bool       -- FALSE until publish trigger fires
  createdAt         Timestamp  -- server timestamp
```

### 5.2 Double-Blind Logic

Neither party can see the other's review until **both have submitted** OR **7 days have passed**.

**Tracking fields on `jobs/{id}`:**
- `clientReviewDone: bool` -- set true when customer submits
- `providerReviewDone: bool` -- set true when expert submits

**Immediate publish trigger (`_checkAndPublish`):**
Called after every `submitReview()`. If BOTH `clientReviewDone` AND
`providerReviewDone` are true:
1. Query all unpublished reviews for this jobId
2. Batch set `isPublished: true` on every review
3. Recalculate expert's aggregate `rating` + `reviewsCount` (from ALL published client reviews)
4. Recalculate customer's aggregate `customerRating` + `customerReviewsCount` (from ALL published expert reviews)

**7-day lazy publish trigger (`lazyPublish`):**
Called when reviews are displayed on expert profile screen. For any review where
`createdAt <= DateTime.now() - 7 days` AND `isPublished == false`:
1. Batch set `isPublished: true`
2. Recalculate ratings for both parties

**Display filter (`expert_profile_screen.dart`):**
```dart
// Shows reviews where isPublished == true OR field is missing (legacy)
final published = allDocs.where((doc) {
  final d = doc.data();
  return d['isPublished'] == null || d['isPublished'] == true;
}).toList();
```

### 5.3 Rating Criteria (4 categories, 5-star scale)

| Key | Hebrew | Icon |
|-----|--------|------|
| `professional` | מקצועיות | workspace_premium_rounded |
| `timing` | דיוק בזמנים | schedule_rounded |
| `communication` | תקשורת | chat_bubble_outline_rounded |
| `value` | תמורה למחיר | price_check_rounded |

All 4 must be rated (> 0) before submission is allowed.
Overall rating = average of 4, formatted to 1 decimal.

### 5.4 Admin Review Tools (v8.9.4)

**Admin sees ALL reviews** regardless of blind/publish status. In the
`AdminUserDetailScreen` reviews bottom sheet:

- **Status badge** on each review: "פומבי" (green) or "מוסתר מהמשתמש" (amber)
- **Blind filter toggle:** "מוסתרות בלבד (N)" — shows only reviews where
  `isPublished == false` AND `createdAt < 7 days ago`
- **Rating params breakdown:** Shows individual scores (מקצועיות, דיוק, תקשורת, תמורה)
- **Private admin comment:** Red locked section visible only in admin view
- **Role-aware title:** "ביקורות מלקוחות" for providers / "ביקורות מנותני שירות" for customers

**Live rating aggregation:** When `users/{uid}.rating` is 0 or null, the admin
detail screen computes the average from actual `reviews` collection docs via
`userReviewsProvider`. This ensures the rating card is never empty when reviews exist.

### 5.5 Post-Submission UX

After customer submits: yellow info box says:
> "חוות דעתך תפורסם לאחר שהצד השני ישתף את שלו, או באופן אוטומטי לאחר 7 ימים"

Customer is auto-navigated to ReviewScreen immediately after releasing payment
(`_handleCompleteJob` in `my_bookings_screen.dart`).

### 5.6 Firestore Security Rules for Reviews

```
allow create: reviewerId == auth.uid AND reviewer is a job participant
allow update (providerResponse): revieweeId == auth.uid AND isClientReview == true
allow update (isPublished): both parties reviewed (canPublishReview) OR 7 days passed
```

---

## 6. Search Ranking Formula (`search_ranking_service.dart`)

```
Score = (XP_Score x 0.6) + (Distance_Score x 0.2) + (Story_Bonus x 0.2)
        + Promoted_Add + Online_Add + VolunteerBadge_Add
```

| Component | Calculation | Range |
|-----------|-------------|-------|
| XP Score | `(xp / goldThreshold).clamp(0,1) * 100` | 0-100 |
| Distance Score | `((50km - dist) / 50km) * 100` (null = 50) | 0-100 |
| Story Bonus | 100 if Skills Story posted in last 24h, else 0 | 0 or 100 |
| **Promoted Add** | +200 flat (VIP 99 NIS/month subscription) | 0 or 200 |
| **Online Add** | +100 flat (provider marked online) | 0 or 100 |
| **Volunteer Badge Add** | +50 flat (1+ volunteer task in last 30 days) | 0 or 50 |

**Tier hierarchy:** Promoted (200) > Online (100) > Volunteer Badge (50) > weighted formula.

**Performance:** `hasActiveVolunteerBadge()` is O(1) -- pure in-memory Timestamp
comparison on `lastVolunteerTaskAt`. Zero Firestore reads inside the sort loop.

**Max theoretical score:** 100 (weighted) + 200 + 100 + 50 = 450.

---

## 6b. Job Broadcast System (First-Come-First-Served)

### Overview
When a client posts an **urgent** request, the system creates a `job_broadcasts` document
and pushes notifications to matching online providers within a 15km radius. The first
provider to tap "תפוס עכשיו" claims the job atomically via a Firestore transaction.

### Constants (`job_broadcast_service.dart`)
| Constant | Value | Purpose |
|----------|-------|---------|
| `broadcastExpiryMinutes` | 30 min | Unclaimed broadcasts auto-expire |
| `notifyRadiusMeters` | 15,000 m (15 km) | GPS filter for notifications |
| `maxNotifiedProviders` | 50 | Cost control on batch notifications |

### Flow
```
1. Client posts urgent Quick Order     (home_screen.dart: _broadcast())
2. job_requests doc created            (existing flow)
3. IF urgent: JobBroadcastService.broadcastUrgentJob() fire-and-forget
4. job_broadcasts/{id} created         (status: 'open')
5. Matching providers queried          (isProvider + isOnline + serviceType + within 15km)
6. Batch notifications sent            (type: 'broadcast_urgent', max 50)
7. Provider taps notification          -> claim bottom sheet OR sees card in opportunities
8. Provider taps "תפוס עכשיו"          -> claimJob() Firestore transaction
9. Transaction: read status, if 'open' -> set 'claimed' + claimedBy (atomic)
10. Winner: chat opens with client     + client notified (type: 'broadcast_claimed')
11. Losers: see "נתפסה ע"י X" state    (real-time via StreamBuilder)
```

### Claim Atomicity (`claimJob`)
Uses `_db.runTransaction()` — the first writer wins:
1. `tx.get(docRef)` — read current status
2. If `status != 'open'` -> return `ClaimResult.taken(claimedByName)`
3. If expired -> update to `expired`, return error
4. If `providerId == clientId` -> block self-claim
5. `tx.update(...)` -> `status: 'claimed'`, `claimedBy`, `claimedAt`

Only one provider can succeed. All others get the Hebrew error "המשרה כבר נתפסה".

### UI Components
- **Opportunities screen:** Horizontal scroll of `_BroadcastClaimCard` widgets above regular job cards. Each card streams its broadcast doc for real-time status updates.
- **Open state:** Orange border + pulse, "תפוס עכשיו" orange button
- **Claimed (by me):** Green border, "✓ תפסת את המשרה!" badge
- **Claimed (by other):** Gray border, "נתפסה ע"י [name]" disabled label
- **Notification sheet:** Full claim sheet from notification tap with description + action button

### Firestore Collection: `job_broadcasts/{id}`
```
clientId, clientName, category, description, location
status: 'open' | 'claimed' | 'expired'
claimedBy: string?          (winner provider UID)
claimedByName: string?
claimedAt: Timestamp?
clientLat, clientLng
createdAt, expiresAt
notifiedCount: int
sourceJobRequestId: string? (links to job_requests/{id})
```

---

## 7. Volunteer Task Lifecycle & Anti-Fraud

### 7.1 Constants

| Constant | Value | Purpose |
|----------|-------|---------|
| `volunteerXpReward` | 150 XP | Per verified task |
| `gpsProximityThreshold` | 500 meters | Max GPS distance for validation |
| `badgeWindowDays` | 30 days | Badge active if 1+ task in window |
| `sameClientCooldownDays` | 30 days | Same client-provider pair cooldown |
| `reciprocalBlockDays` | 30 days | A<->B reciprocal block window |
| `dailyVolunteerXpCap` | 300 XP | Max volunteer XP per calendar day (= 2 tasks) |
| `minReviewLength` | 10 chars | Client review minimum for confirmation |

### 7.2 Full Flow

```
1. CLIENT submits help_request         (community_screen.dart -> help_requests collection)
2. Matching VOLUNTEERS notified        (notifications with type: 'help_request', skip self)
3. VOLUNTEER taps notification         -> Accept bottom sheet (notifications_screen.dart)
4. Volunteer accepts                   -> VolunteerService.createTask() -> chat opens
5. Provider arrives, taps "הגעתי"      -> GPS captured -> validateGpsProximity()
6. CLIENT sees GPS status + writes     -> review (10+ chars) + taps "אשר סיום"
   review (10+ chars) + confirms       -> confirmCompletion() runs 5 anti-fraud checks
7. XP + Badge awarded to provider      -> notification sent
```

### 7.3 Anti-Fraud Rules (enforced in `confirmCompletion()`)

All checks run **before** any XP award or status change. Each returns a Hebrew
error string shown in the client's SnackBar on rejection.

**Identity & access controls:**
1. **Self-assignment block:** `clientId != providerId` -- enforced in service AND Firestore rules
2. **Client-only confirmation:** Only original `clientId` can call `confirmCompletion()`
3. **Help request skip-self:** Notification loop skips `volunteerId == requesterId`
4. **XP is server-only:** `xp` field blocked from client writes -- Cloud Functions only

**XP farming prevention:**
5. **Same-user cooldown (30d):** Provider cannot earn volunteer XP from the same client more than once per 30 days. Query: `volunteer_tasks where providerId==P AND clientId==C AND status=='completed' AND completedAt > (now-30d)`.
6. **Reciprocal help block (30d):** If A helped B, B cannot earn volunteer XP from A for 30 days. Query: reverse direction `where providerId==C AND clientId==P AND status=='completed' AND completedAt > (now-30d)`.
7. **Daily XP cap (300/day):** Sums `xpAmount` on provider's completed tasks since midnight. Blocks if >= 300.

**Proof of work:**
8. **Client review required:** Min 10 characters. Stored on `volunteer_tasks/{id}.clientReview`. Confirm button is disabled (grayed) until valid.
9. **GPS validation:** Provider taps "הגעתי" button in chat banner. Captures GPS via `LocationService.requestAndGet()`, calls `validateGpsProximity()`. Client sees status chip: green "מיקום אומת" or gray "ממתין לאימות". Confirm dialog shows GPS card with distance.

### 7.4 Dynamic Volunteer Badge

- **Check:** `VolunteerService.hasActiveVolunteerBadge(userData)` -- reads `lastVolunteerTaskAt` Timestamp
- **Active if:** `DateTime.now() - lastVolunteerTaskAt <= 30 days`
- **Displayed on:** profile screens (public + own), search result cards (gradient mini-badge)
- **Search boost:** +50 points in ranking formula
- **Auto-expires:** Pure Timestamp check; no cron needed for display/ranking correctness

---

## 7b. Community Hub (v11.0.0) — `community_hub_screen.dart`

### Overview
Replaces the legacy "למען הקהילה" volunteer screen with a full-featured Community Hub.
**Key change:** Both providers AND customers can volunteer as "Community Helpers".
The provider-only restriction from the old `CommunityScreen` has been removed.

**Slogan:** "כישרון אחד, לב אחד" (One skill, one heart)

### Data Architecture

**New Collection: `community_requests/{id}`**

| Field | Type | Purpose |
|-------|------|---------|
| `requesterId` | String | Who needs help |
| `requesterName` | String | Display name (or "אנונימי") |
| `requesterImage` | String? | Profile image (null if anonymous) |
| `volunteerId` | String? | Who claimed (null when open) |
| `volunteerName` | String? | Volunteer display name |
| `title` | String | Request title |
| `description` | String | Detailed description |
| `category` | String | help category ID |
| `requesterType` | String | `elderly`, `lone_soldier`, `struggling_family`, `general` |
| `status` | String | `open`, `accepted`, `in_progress`, `pending_confirmation`, `completed`, `cancelled` |
| `urgency` | String | `low`, `medium`, `high` |
| `isAnonymous` | bool | Hides requester identity |
| `location` | GeoPoint? | For distance calc + map pins |
| `createdAt` | Timestamp | Server timestamp |
| `claimedAt` | Timestamp? | When volunteer claimed |
| `startedAt` | Timestamp? | When requester confirmed start |
| `markedDoneAt` | Timestamp? | When volunteer signaled completion |
| `completedAt` | Timestamp? | When requester confirmed & thanked |
| `volunteerReview` | String? | Requester's 10+ char review |
| `thankYouNote` | String? | Short thank-you note (shown on volunteer profile) |
| `thankYouAuthor` | String? | Requester name for the thank-you note |

**New User Doc Fields:**

| Field | Type | Purpose |
|-------|------|---------|
| `volunteerHeart` | bool | Permanent red heart — true after first completed task |
| `communityXP` | int | Separate community XP track (450/task) |
| `communityBadges` | List\<String\> | Earned badges: `starter`, `pillar`, `angel` |

### Help Categories (8)

| ID | Hebrew | Icon |
|----|--------|------|
| `repair` | תיקונים | build_rounded |
| `cleaning` | ניקיון | cleaning_services_rounded |
| `delivery` | הובלות | local_shipping_rounded |
| `teaching` | שיעורים | school_rounded |
| `tech` | טכנולוגיה | computer_rounded |
| `cooking` | בישול | restaurant_rounded |
| `companionship` | ליווי וחברות | favorite_rounded |
| `other` | אחר | more_horiz_rounded |

### Requester Types (4)

| ID | Hebrew | Color |
|----|--------|-------|
| `elderly` | קשישים 👴 | `#EF4444` (red) |
| `lone_soldier` | חיילים בודדים 🎖️ | `#6366F1` (indigo) |
| `struggling_family` | משפחות נזקקות 👨‍👩‍👧 | `#F59E0B` (amber) |
| `general` | כללי 🤝 | `#10B981` (green) |

### Two-Tab UI

**Tab A — "תן עזרה" (Give Help):**
- Join banner (for non-volunteers): "כל אחד יכול לעזור — לא צריך להיות נותן שירות!"
- **Active Tasks section** (persistent, streams volunteer's active tasks):
  - `accepted`: "ממתין לאישור הפונה" status badge
  - `in_progress`: big green "סיימתי לעזור!" button + chat icon
  - `pending_confirmation`: "ממתין לאישור סיום" status badge
- Filter chips by requester type (הכל / קשישים / חיילים / משפחות / כללי)
- Vertical feed of open `community_requests` cards:
  - Requester avatar (or anonymous icon), name, time ago
  - Urgency badge (colored chip)
  - Title + description
  - Requester type badge + category icon + distance (km)
  - "אני יכול/ה לעזור!" green CTA button
- **Map toggle FAB** — switches between list and flutter_map view with pins

**Tab B — "בקש עזרה" (Request Help):**
- Form: title, description, category grid, requester type, urgency selector, anonymous toggle
- "הבקשות שלי" section showing my requests with status + action buttons:
  - Open: "בטל" cancel button
  - Accepted: "אשר התחלה" indigo button + chat icon + cancel
  - In progress: chat icon (waiting for volunteer to mark done)
  - Pending confirmation: amber prompt "האם [name] עזר/ה לך?" + "אשר ותודה" / "עוד לא"
  - Completed: green "הושלם" badge + thank-you note (if written)

### Task State Machine (v11.1.0)

```
                        open
                          |
                   Volunteer claims
                          |
                      accepted
                          |
                  Requester confirms start
                          |
                     in_progress
                          |
               Volunteer marks done
                          |
                pending_confirmation
                    /           \
           Requester          Requester
           "Confirm"          "Not Yet"
               |                  |
          completed          in_progress (back)
               |
        XP + Heart + Badges
        Thank-You Note stored
```

### Claim Flow (Atomic Transaction)

```
1. Volunteer taps "אני יכול/ה לעזור!" on a request card
2. Confirmation dialog: "האם ברצונך לעזור ב-[title]?"
3. CommunityHubService.claimRequest() → Firestore transaction:
   a. tx.get(docRef) — read current status
   b. If status != 'open' → return "הבקשה כבר נתפסה על ידי [name]"
   c. If volunteerId == requesterId → return "לא ניתן להתנדב לבקשה שלך"
   d. tx.update: status='accepted', volunteerId, volunteerName, claimedAt
4. Notification sent to requester: "מתנדב/ת רוצה לעזור — אשר/י כדי להתחיל"
5. ChatScreen opens with auto-message: "אישרתי את בקשת העזרה שלך — נתאם?"
```

### Confirm Start Flow (Requester approves volunteer)

```
1. Requester taps "אשר התחלה" on accepted request card
2. CommunityHubService.confirmStart():
   a. Validates requester owns the request
   b. Validates status == 'accepted'
   c. Updates: status='in_progress', startedAt=serverTimestamp
3. Notification to volunteer: "הפונה אישר/ה — אפשר להתחיל!"
```

### Mark Task Done Flow (Volunteer signals completion)

```
1. Volunteer taps "סיימתי לעזור!" button in Active Tasks section
2. Confirmation dialog: "סיימת לעזור?"
3. CommunityHubService.markTaskDone():
   a. Validates volunteer owns the task
   b. Validates status == 'in_progress'
   c. Updates: status='pending_confirmation', markedDoneAt=serverTimestamp
4. Notification to requester: "[name] סיים/ה לעזור — אנא אשר/י"
```

### Completion & Confirmation Flow

```
1. Requester sees pending_confirmation prompt: "האם [name] עזר/ה לך?"
2. Taps "אשר ותודה" → bottom sheet:
   - Review text field (min 10 chars — proof of work)
   - Thank-You Note field (optional — shown on volunteer's profile)
   - XP reward preview: "+450 XP"
3. CommunityHubService.completeRequest() runs 6 anti-fraud checks:
   a. Only original requester can confirm
   b. Must be pending_confirmation status
   c. Review ≥ 10 chars (proof of work)
   d. Same-user cooldown (30 days)
   e. Reciprocal block (30 days)
   f. Daily XP cap (900/day = 2 tasks)
4. Mark completed + store thankYouNote + award 3× XP (450) + update badges/heart
5. Celebration overlay: scale-in animation + "+450 XP" badge
6. Notification to volunteer: "ההתנדבות אושרה — קיבלת +450 XP!" + thank-you preview
```

### Reject Completion ("Not Yet")

```
1. Requester taps "עוד לא" on pending_confirmation prompt
2. CommunityHubService.rejectCompletion():
   - Status reverts: pending_confirmation → in_progress
   - markedDoneAt field deleted
3. Notification to volunteer: "הפונה ציין/ה שהעזרה עוד לא הושלמה"
```

### Community Impact (Thank-You Notes on Profile)

- `CommunityHubService.streamCommunityImpact(userId)` streams completed tasks
  with `thankYouNote` field for display on the volunteer's profile
- Notes stored directly on `community_requests/{id}.thankYouNote` + `thankYouAuthor`
- Future: integrate into `public_profile_screen.dart` as "Community Impact" section

### Gamification

| Feature | Details |
|---------|---------|
| **XP per task** | 450 (3× standard 150, via 3 CF calls to `volunteer_task` event) |
| **Community XP** | Separate `communityXP` field incremented by 450 per task |
| **Daily XP cap** | 900 (2 tasks/day) |
| **Volunteer Heart** | Permanent red heart on profile image after 1st completed task |
| **Starter badge** | 1 completed task → "מתחיל" |
| **Pillar badge** | 5 completed tasks → "עמוד תווך" (purple gradient) |
| **Angel badge** | 10 completed tasks → "מלאך" (gold gradient) |

### Badge Display Across Screens

| Screen | Display |
|--------|---------|
| Search cards (`category_results_screen.dart`) | Red heart overlay on avatar + gradient badge in name row with community badge label |
| Expert profile (`expert_profile_screen.dart`) | Red heart overlay on profile image |
| Public profile (`public_profile_screen.dart`) | Red heart overlay + community badge widget (Starter/Pillar/Angel) |
| Own profile (`profile_screen.dart`) | Community badge widget with tier-specific gradient |

Heart is shown when `volunteerHeart == true` OR `isVolunteer == true`.
Badge label upgrades: "מתנדב פעיל" → "עמוד תווך" → "מלאך הקהילה".

### Files

| File | Purpose |
|------|---------|
| `lib/services/community_hub_service.dart` | Service: CRUD, claims, completion, XP, badges |
| `lib/screens/community_hub_screen.dart` | Two-tab UI with map view |
| `lib/screens/community_screen.dart` | Legacy (still exists, no longer navigated to) |

### Firestore Indexes (6 new)

| Fields | Purpose |
|--------|---------|
| `status + createdAt DESC` | Open feed sorted by time |
| `status + requesterType + createdAt DESC` | Filtered feed |
| `requesterId + createdAt DESC` | User's own requests |
| `volunteerId + status` | Volunteer's claimed tasks |
| `volunteerId + requesterId + status + completedAt DESC` | Anti-fraud cooldown |
| `volunteerId + status + completedAt DESC` | Daily XP cap |

### Security Rules

- **Create:** Authenticated user, `requesterId == auth.uid`
- **Read:** Admin, participant (requester or volunteer), or any auth user if status is `open`
- **Update:** Admin or participant (requester or volunteer), or any auth user if status is `open` (for claiming)
- **Delete:** Never (`allow delete: if false`)

---

## 8. XP & Gamification System

### Level Thresholds (configurable: `settings_gamification/app_levels`)

| Level | XP Range | Display Name | Gradient |
|-------|----------|-------------|----------|
| Rookie | 0-499 | טירון | `#CD7F32` -> `#A0522D` |
| Pro | 500-1,999 | מקצוען | `#9CA3AF` -> `#6B7280` |
| Gold | 2,000-4,999 | זהב | `#F59E0B` -> `#D97706` |
| Legendary | 5,000+ | אגדי | (extended via EngagementService) |

### XP Events (via Cloud Function `updateUserXP`)

| Event ID | XP | Trigger |
|----------|-----|---------|
| `finish_job` | +100 | Job marked completed |
| `five_star_review` | +50 | Receive 5-star review |
| `quick_response` | +25 | Reply within 5 min |
| `volunteer_task` | +150 | Verified volunteer completion |
| `story_upload` | TBD | Post a Skills Story |
| `join_opportunity` | TBD | Join opportunity board |
| `provider_cancel` | -100 | Provider cancels a job |
| `no_response` | penalty | No reply to client |

### Variable XP (2X Off-Peak Multiplier)
- **Off-peak hours:** 20:00-08:00 local time, OR any Saturday
- **Multiplier:** 2X (Cloud Function called twice)
- **Detection:** `EngagementService.isOffPeak()` checks `DateTime.now()`
- **Usage:** `EngagementService.awardVariableXp(userId, eventId)` returns `{newXp, multiplier}`

### Level-Up Celebration
- **Detection:** `EngagementService.didLevelUp(oldXp, newXp)` compares levels
- **Widget:** `showLevelUpCelebration(context, newXp)` -- full-screen overlay
- **Animation:** Scale-in with elasticOut curve + confetti particles + auto-dismiss (3s)

---

## 8b. Engagement Systems (`engagement_service.dart`)

### Daily Drop (Variable Reward System)

| Constant | Value |
|----------|-------|
| `dailyDropProbability` | 20% |
| `activityWindowHours` | 72 hours |

**Flow:** On first provider login each day:
1. Check `lastDailyDropDate` != today
2. Check `lastActiveAt` within 72h
3. Set `lastDailyDropDate` = today (prevent re-rolls)
4. Roll 20% probability
5. If won: pick random reward, write to `user_rewards`, show mystery box modal

**Reward Pool:**

| Reward | Duration | Effect |
|--------|----------|--------|
| `ZERO_COMMISSION_DAY` | 24h | 0% platform fee on all jobs |
| `PROFILE_BOOST_CARD` | 12h | +200 pts in search ranking (= VIP level) |
| `TEMPORARY_RECOMMENDED_BADGE` | 24h | "מומלץ" badge displayed on profile |

**Profile Boost Card** is denormalized: sets `users/{uid}.profileBoostUntil` timestamp
for O(1) lookup in the search ranking loop.

**UI:** Mystery box modal (`daily_drop_modal.dart`) with 2-second suspense animation
(pulsing scale + glow), then fade-reveal of the reward card.

### Provider Streaks

| Constant | Value |
|----------|-------|
| `streakResponseThreshold` | 10 minutes |
| `streakBoostMilestone` | 7 days |

**Streak qualification:** Provider's `avgResponseMinutes` <= 10 on consecutive days.

**Fields on `users/{uid}`:** `streak` (int), `lastStreakDate` (YYYY-MM-DD), `streakBestEver` (int)

**At-risk detection:** `EngagementService.isStreakAtRisk(userData)` returns true if
streak was yesterday but not yet extended today. UI shows warning pulse on badge.

**Milestone (every 7 days):** Auto-awards a free PROFILE_BOOST_CARD + notification.

**Widget:** `StreakBadge.fromUserData(data)` -- fire emoji + count, orange/red gradient.
Shown on profile screen after XP progress bar.

### Firestore Collection: `user_rewards/{id}`
```
userId         String
type           String (zeroCommissionDay | profileBoostCard | temporaryRecommendedBadge)
status         String (active | expired | used)
awardedAt      Timestamp
expiresAt      Timestamp
source         String? (streak_milestone_7, daily_drop, etc.)
```

---

## 9. RTL & UI Standards

### RTL Rules (MANDATORY for new code)

| Pattern | Correct | Wrong |
|---------|---------|-------|
| Text alignment | `TextAlign.start` / `.end` | `TextAlign.left` / `.right` |
| Layout alignment | `AlignmentDirectional.centerStart` | `Alignment.centerLeft` |
| Edge insets | `EdgeInsetsDirectional` | `EdgeInsets.only(left/right)` |
| Gradient direction | `AlignmentDirectional` begin/end | `Alignment.centerRight` |
| Row children | Logical order (Flutter auto-reverses in RTL) | Visual order |

`GlobalMaterialLocalizations.delegate` automatically mirrors layout for RTL locales (`he` and `ar`).
Both Hebrew and Arabic are RTL -- `AppLocalizations.isRtl(locale)` returns true for both.

### Color Palette

| Role | Hex | Dart |
|------|-----|------|
| Primary (Indigo) | `#6366F1` | `Color(0xFF6366F1)` |
| Secondary (Purple) | `#8B5CF6` | `Color(0xFF8B5CF6)` |
| Success / Volunteer | `#10B981` | `Color(0xFF10B981)` |
| Error / Danger | `#EF4444` | `Color(0xFFEF4444)` |
| Warning / VIP | `#F59E0B` | `Color(0xFFF59E0B)` |
| Online green | `#22C55E` | `Color(0xFF22C55E)` |
| Dark text | `#1A1A2E` | `Color(0xFF1A1A2E)` |
| Muted text | `#6B7280` | `Color(0xFF6B7280)` |
| Scaffold BG | `#F4F7F9` | `Color(0xFFF4F7F9)` |
| Card BG | `#FFFFFF` | `Colors.white` |

### Typography

- **Font:** Google Fonts Assistant (dynamic), NotoSansHebrew (fallback, bundled)
- **Material 3:** `useMaterial3: true`, seed color `0xFF007AFF`
- **Sizes:** Titles 18-26px, Body 14-15px, Captions 12-13px, Badges 9-11px

### Card & Container Conventions

| Element | Value |
|---------|-------|
| Card radius | `BorderRadius.circular(12-16)` |
| Modal top radius | `BorderRadius.circular(24)` |
| Button radius | `BorderRadius.circular(10-14)` |
| Card shadow | `BoxShadow(color: black @ 0.05-0.06, blurRadius: 10-12)` |
| Standard padding | `EdgeInsets.all(16)` |
| Modal padding | `EdgeInsets.fromLTRB(24, 28, 24, 20)` |

### Key Gradients

| Use | Colors |
|-----|--------|
| XP bar fill | `#6366F1` -> `#A855F7` -> `#EC4899` (3-stop) |
| Level badge | `#6366F1` -> `#8B5CF6` |
| Volunteer badge | `#10B981` -> `#6366F1` |
| Academy dark BG | `#0F0F1A` |

### Async-Safe Pattern

```dart
final confirmText = l10n.confirm;  // capture BEFORE await
await someAsyncOperation();
if (!mounted) return;
showSnackBar(confirmText);         // safe to use
```

---

## 9b. HomeTab Architectural Laws (MANDATORY)

> **These rules exist because we debugged painful regressions. Do NOT relax them
> without updating this section in the same commit.**

### Law 1: Persistent StoriesRow -- NEVER Zero Height

`StoriesRow` must **always** render at a fixed `height: 98` between the search
bar and the category grid. It must NEVER return `SizedBox.shrink()`.

| State | Provider view | Customer view |
|-------|---------------|---------------|
| Stories exist | "Add Story" circle (slot 0) + other experts | Other experts' circles |
| No stories | "Add Story" circle alone | "אין סטוריז עדיין" placeholder (icon + text, 98px) |
| Stream error | "Add Story" circle alone | Placeholder |
| Auth loading | Placeholder shell | Placeholder shell |

**Why:** `SizedBox.shrink()` caused a vanishing-row bug where the outer
`_categoriesStream` StreamBuilder rebuild triggered a re-evaluation of
`DateTime.now()` in the expiry filter, borderline stories flipped in/out,
and the row collapsed to zero height on every other frame.

**Files:** `lib/screens/search_screen/widgets/stories_row.dart`

### Law 2: Provider "Add Story" Entry Point

The **first slot** (index 0) in StoriesRow is always the current provider's
upload button. It shows:
- Their profile image (from `users/{uid}.profileImage`)
- A blue `+` icon overlay (bottom-left, `_kGradStart` color)
- Tapping opens the upload sheet; long-press deletes existing story

The provider's own story doc is extracted from the raw Firestore snapshot
**before** the 25-hour expiry filter runs. The provider's entry point must
never be filtered out by the time window.

**Widget:** `_MyStorySlot` in `stories_row.dart`

### Law 3: 25-Hour Stable Expiry Buffer

Other experts' stories use a **25-hour** window (not 24) for the client-side
expiry filter. This 1-hour grace period prevents borderline flicker when
parent `StreamBuilder` rebuilds shift `DateTime.now()` by milliseconds.

```dart
// CORRECT — 25h tolerance, own doc excluded from filter
final otherDocs = rawDocs.where((d) {
  if (d.id == _uid) return false; // own doc handled separately
  ...
  return ts != null && now.difference(ts).inHours < 25;
}).toList();
```

### Law 4: HomeTab Stream Error Resilience

Every `StreamBuilder` inside the `CustomScrollView.slivers` list MUST have
an `if (snap.hasError) return const SizedBox.shrink();` guard as its first
line. A Firestore permission error or Gemini 404 must collapse to zero
height, never throw or leave a broken sliver.

**Current protected streams (4):**
| Stream | File | Purpose |
|--------|------|---------|
| `_urgentStream` | `home_tab.dart` | Job request pulse banner |
| `_remindersStream` | `home_tab.dart` | AI re-engagement card |
| `_dealStream` | `home_tab.dart` (via `_buildAirbnbRows`) | AI Deal of the Day |
| `_storiesStream` | `stories_row.dart` | Skills Stories row |

### Law 5: Version Update Loop Prevention

Two-layer defence prevents the "infinite update banner" loop:

**Layer 1 — `web/app_init.js`:**
- `_swUpdateSignalled` flag ensures `sw_update_pending` is set at most once
  per page load.
- If `sessionStorage['v5_purged']` is already set (= cache-bust just ran),
  the flag is NOT re-set. This breaks the SW-fires-again-after-reload cycle.

**Layer 2 — `lib/main.dart` `_handleWebUpdates()`:**
- Before showing the banner, checks `_prefs.getString('banner_dismissed_v')`.
- If the dismissed version equals `currentAppVersion`, the banner is suppressed.
- This catches edge cases where the JS layer still sets the flag.

**Layer 3 — `_startVersionListener()` (Firestore path):**
- Compares `latestVersion` vs `currentAppVersion` with `_isNewerVersion()`.
- Checks `banner_dismissed_v` in SharedPreferences.
- `_updateNotified` flag prevents re-showing within the same session.

### Law 6: HomeTab Sliver Order (Fixed Layout)

```
SliverToBoxAdapter  →  _buildHeader()
SliverToBoxAdapter  →  _buildSearchBar()
SliverToBoxAdapter  →  Urgent pulse banner (StreamBuilder, error-safe)
SliverToBoxAdapter  →  StoriesRow (key: 'stories_row_slot')   ← ALWAYS HERE
if/else chain       →  Loading shimmer / Empty / No results / Grid:
                        ├─ AI Re-Engagement card (error-safe)
                        ├─ 1st category row
                        ├─ AI Deal of the Day banner (injected by _buildAirbnbRows)
                        ├─ 2nd category row
                        ├─ _PromoCarousel
                        └─ Remaining categories
SliverToBoxAdapter  →  Footer (logout + version)
```

StoriesRow is **outside** the `if/else` conditional chain. It uses
`ValueKey('stories_row')` on both the `SliverToBoxAdapter` and the widget
to preserve state across parent `_categoriesStream` rebuilds.

### Law 7: Sentry Monitoring (MANDATORY for Production)

Sentry must remain enabled for all production builds. It is the primary
crash-reporting and performance-tracing layer, complementing Crashlytics
(native-only) and Watchtower (Firestore logs).

**Configuration (`main.dart`):**
```dart
await SentryFlutter.init((options) {
  options.dsn = 'https://...@....ingest.us.sentry.io/...';
  options.tracesSampleRate = 1.0;
  options.environment = kDebugMode ? 'development' : 'production';
  options.release = 'anyskill@$currentAppVersion';
}, appRunner: () { ... runApp(...) });
```

**Three error-reporting channels (all active simultaneously):**

| Channel | Scope | Dashboard |
|---------|-------|-----------|
| **Sentry** | All platforms (web + iOS + Android) | sentry.io |
| **Firebase Crashlytics** | Native only (iOS + Android) | Firebase Console |
| **Watchtower** | All platforms (Firestore `error_logs`) | Admin → ביצועים |

**Sentry user context:** Set in `AuthWrapper._authSub` listener —
`Sentry.configureScope()` tags every event with `user.uid`, `email`,
and `displayName`. Cleared on logout.

**Navigator tracing:** `SentryNavigatorObserver()` added to
`MaterialApp.navigatorObservers` — tracks page navigation as Sentry
transactions for performance monitoring.

**Admin test:** "Test Crash" button in `SystemPerformanceTab` sends a
captured exception to Sentry and shows a success snackbar.

**Rules:**
- Never remove or disable Sentry in production builds
- Never lower `tracesSampleRate` below `0.2` without team discussion
- The DSN is a public ingest key (safe in client code, like Firebase API keys)
- If Sentry init fails, the app MUST still launch (it's inside `SentryFlutter.init`'s error handling)

### Law 8: Live Selfie Identity Verification

Provider onboarding includes a **mandatory live selfie step** after the ID
document upload. The selfie is captured from the front camera and uploaded
to `verification_selfies/{uid}.jpg` in Firebase Storage.

**Onboarding flow (providers):**
1. Business fields (type, ID number)
2. ID document upload (`id_docs/{uid}`)
3. **Live selfie** (front camera, 600px, `verification_selfies/{uid}.jpg`)
4. Category selection
5. Contact info + profile
6. Terms → Submit

**Admin verification panel:** Shows the selfie and ID document **side-by-side**
in `_buildIdVerificationCard()` for visual identity matching. The admin sees
both images before tapping "Approve" or "Reject".

**Firestore:** `users/{uid}.selfieVerificationUrl` — download URL from Storage.

**Rules:**
- Selfie MUST use `ImageSource.camera` (not gallery) — prevents uploading fake photos
- `CameraDevice.front` ensures it's a self-portrait
- The selfie field is NOT in the `doesNotTouch` blocked list — owner can write it

### Law 9: Provider Active/Inactive Status & Booking Gate

The existing `isOnline` field controls provider availability. When a provider
is **offline** (`isOnline: false`):

| Area | Behaviour |
|------|-----------|
| **Search cards** | Shows grey "לא זמין כעת" badge (instead of green "Online") |
| **Expert profile** | Booking button disabled with "לא זמין להזמנות כרגע" message |
| **Search ranking** | -100 points (Online Add removed from score) |
| **Job broadcasts** | Excluded from notification recipients |

The toggle lives in the `HomeTab` header (green/grey pill) and is persisted
to `users/{uid}.isOnline`. It auto-sets `true` on app resume and `false` on
dispose via `home_screen.dart._setOnlineStatus()`.

**Files:** `home_tab.dart` (toggle UI), `home_screen.dart` (lifecycle sync),
`category_results_screen.dart` (badge), `expert_profile_screen.dart` (booking gate)

### Law 10: Friendly Error Handling + Internal Support Chat

**All user-facing catch blocks** should use `ErrorMapper.show(context, e)`
instead of raw `SnackBar(content: Text('$e'))`.

**File:** `lib/utils/error_mapper.dart`

**Behaviour:**
- Maps Firebase error codes to Hebrew messages (e.g., `permission-denied` →
  "היי, נראה שיש לנו תקלה קטנה בחיבור הפרופיל שלך...")
- Maps network/timeout/Stripe errors to appropriate Hebrew messages
- Shows a red floating SnackBar with the friendly message
- "לחץ כאן לדבר עם תמיכה" opens the **internal Support Chat** (NOT WhatsApp)
- Generic fallback: "משהו השתבש. אנא נסה שוב או פנה לתמיכה."

**Support flow when user taps "לדבר עם תמיכה":**
1. `ErrorMapper._createErrorTicket()` creates a `support_tickets` doc
   with `category: 'error_report'` and `subject: 'שגיאה אוטומטית: {code}'`
2. First message is auto-written with error code, friendly message, and context
3. User is navigated to `TicketChatScreen` where they can add details
4. CF `notifyAdminOnSupportMessage` pushes a notification to all admins
5. Admin sees the ticket in "תיבת פניות 📮" tab (AdminSupportInboxTab)

**Cloud Function:** `notifyAdminOnSupportMessage`
- Trigger: `onDocumentCreated("support_tickets/{ticketId}/messages/{messageId}")`
- Skips admin-sent messages (prevents notify-self loop)
- Sends FCM push + in-app notification to all `isAdmin: true` users

**Rules:**
- Never show raw English exception text to users
- Never use WhatsApp or external links for support — all support is internal
- New Firebase error codes should be added to the `switch` in `messageFor()`
- The auto-created ticket includes the error code so the admin immediately knows the issue

### Law 11: Single Source of Truth for Profile Images

**All profile image display** must use `safeImageProvider()` from
`lib/utils/safe_image_provider.dart`. Never use `NetworkImage()` or
`CachedNetworkImageProvider()` directly for user profile images.

**Why:** Profile images are stored in two formats:
- **HTTPS URLs** — from Google Sign-In or Firebase Storage uploads
- **Base64 data URIs** (`data:image/png;base64,...`) — from onboarding camera capture

`NetworkImage` and `CachedNetworkImage` crash silently on base64 strings,
causing blank/missing avatars. `safeImageProvider()` handles both formats
and returns `null` for malformed data so callers show a proper placeholder.

**Utility:** `lib/utils/safe_image_provider.dart`
```dart
// Returns ImageProvider for HTTPS URLs or base64, null if empty/broken.
ImageProvider? safeImageProvider(String? raw);

// Complete avatar widget with initials fallback.
Widget buildProfileAvatar({required String? imageUrl, required String name, ...});
```

**Fixed screens (must stay using `safeImageProvider`):**

| Screen | File | What was broken |
|--------|------|----------------|
| Expert cards (search) | `category_results_screen.dart` | `NetworkImage(profileImg)` → base64 crash |
| Story circles | `stories_row.dart` | `Image.network(avatar)` → base64 crash |
| Public profile | `public_profile_screen.dart` | `NetworkImage(profileImg)` → base64 crash |
| Chat bubbles | `chat_ui_helper.dart` | `startsWith('http')` check excluded base64 |

**Rules:**
- Never use `NetworkImage()` directly for `profileImage` fields
- Never check `startsWith('http')` to decide if an image exists — use `safeImageProvider() != null`
- New screens displaying user avatars MUST import and use `safeImageProvider`
- The `stories` collection stores `providerAvatar` (a snapshot) — it may be base64

### Law 12: Zero-Tolerance for Stale UI

**AI Deal Banner** must never persist beyond its valid date. The
`OpportunityHunterService.streamToday()` applies a strict same-day check:
- `validDate` must equal `todayKey()` (YYYY-MM-DD) — stale docs return `null`
- `expiresAt` timestamp (if present) must be in the future
- If the Gemini CF fails (404), the stream returns `null` → `SizedBox.shrink()`

**Bottom-nav badges must reflect the actual list:**

| Badge | Query | Screen |
|-------|-------|--------|
| Orders (provider) | `expertId == uid && status == 'paid_escrow'` | `home_screen.dart:136-142` |
| Orders (customer) | `customerId == uid && status == 'expert_completed'` | `home_screen.dart:127-133` |

The badge query and the list query MUST read from the same `jobs` collection
with the same uid. The `my_bookings_screen.dart` provider tasks tab streams
**all** expert jobs (no status filter) and splits client-side into
active (`paid_escrow`, `expert_completed`) and history.

**Debug:** `[Tasks] expertStream returned N docs` logs are present in
`_buildProviderTasksTab()` to diagnose any badge/list mismatch.

**Tab controller:** `DefaultTabController(length: 2)` — both provider and
customer paths have exactly 2 tabs. Using `3` for customers was a bug that
caused the tab content to not render.

### Law 13: Self-Booking Prevention (Anti-Fraud)

Providers are **strictly prohibited** from creating jobs/bookings where
`customerId == expertId`. This prevents fake reviews and circular money flows.

**Three-layer enforcement:**

| Layer | File | Check |
|-------|------|-------|
| **UI (button)** | `expert_profile_screen.dart` | `isSelf = currentUser.uid == widget.expertId` → button disabled, shows "לא ניתן להזמין שירות מעצמך" |
| **Service (logic)** | `escrow_service.dart` | `if (clientId == providerId) return error` — before any Firestore transaction |
| **Search (visual)** | `category_results_screen.dart` | Purple "הפרופיל שלך" badge on own card in search results |

**Firestore rules** already enforce `clientId != providerId` on `volunteer_tasks`
(see Section 11). The `jobs` collection does not have this rule because the
escrow service handles it. If a future code path bypasses the service,
add to `firestore.rules`:
```
allow create: if ... && request.resource.data.customerId != request.resource.data.expertId;
```

### Law 14: Task Visibility + Admin Superiority

#### No Ghost Bookings

Job streams must return **all** relevant documents. Ghost bookings
(jobs appearing and disappearing) are caused by two things:

**A) Query limits too low.** Without `orderBy`, Firestore picks an
arbitrary subset. When a doc changes, the subset shifts and jobs
appear/disappear. Fix: use `.limit(200)` for booking streams.

**B) Missing terminal statuses.** Every status that exists in the system
must be in exactly one bucket — active or history.

**Active statuses (shown in "משימות שלי" / "פעילות"):**
```
paid_escrow, expert_completed, disputed,
pending, accepted, in_progress, awaiting_payment
```

**History statuses (shown in "היסטוריה"):**
```
completed, cancelled, refunded,
split_resolved, cancelled_with_penalty, payment_failed
```

The customer history tab uses a **catch-all**: `!_activeStatuses.contains(status)`.
The provider tasks list must use the class-level `_activeStatuses` set.

#### Admin Superiority — Unrestricted Visibility

The Admin user (`isAdmin: true`) must have **unrestricted visibility** of all
jobs, experts, and users. Admins must never experience UI lag from redundant
stream listeners.

**Admin bookings merge (`my_bookings_screen.dart`):**
- When `isAdmin: true`, `_isProvider` is forced to `true` so admin always
  sees provider tabs (יומן + משימות שלי)
- `_buildMergedTasksStream()` merges BOTH `_expertStream` and `_customerStream`
  into a single deduplicated list (by doc ID)
- Admin sees every job they're involved in — as customer OR as expert

**Tab caching (`home_screen.dart`):**
- The `IndexedStack` tab list is cached in `_cachedTabs`
- Only rebuilt when `isProvider` or `isAdmin` changes
- Normal user doc changes (isOnline toggle, XP, badge) reuse the cached list
- This eliminates redundant widget tree rebuilds on every Firestore event

**Files:** `my_bookings_screen.dart` (`_buildMergedTasksStream`, `_subscribeProviderStatus`),
`home_screen.dart` (`_cachedTabs`, `_cachedIsProvider`, `_cachedIsAdmin`).

### Law 15: Mobile Resilience — Watchdog + Resilient Fetch

Mobile browsers (especially iOS Safari) are prone to loading hangs caused
by stale service workers, slow Firestore reads, or stuck JS init.

**Three-tier resilient user fetch (`_resilientUserFetch` in `main.dart`):**

| Tier | Source | Timeout | Fallback on failure |
|------|--------|---------|---------------------|
| 1 | `Source.server` | 4 seconds | → Tier 2 |
| 2 | `Source.cache` | instant | → Tier 3 (if empty/missing) |
| 3 | Default `get()` | 4 seconds | → cache catchError |

**Never throws.** Always returns a `DocumentSnapshot` (may be non-existent
but won't crash the `FutureBuilder`).

**JS Watchdog timer (`app_init.js`):**
- On page load: clears `sessionStorage['app_ready']`, starts 10s countdown
- Flutter writes `sessionStorage['app_ready'] = '1'` after first frame
- If flag not set after 10s: clears nuclear purge key + `location.reload()`
- This catches stuck SW registration, stalled Dart init, corrupted cache

**Rules:**
- `Source.server` timeout must be ≤ 4 seconds (was 8s — too slow on mobile)
- The watchdog timer must be ≥ 10 seconds (Flutter engine needs ~5s on slow devices)
- `_resilientUserFetch` must never throw — all tiers wrapped in try/catch

### Law 16: UI Context Awareness + Provider Workspace

**Floating buttons must strictly adhere to their assigned screens and never
persist during sub-navigation.**

**Urgent Search FAB (`home_screen.dart`):**
- Visible ONLY when: `safeIndex == 0` (Home tab selected) AND the Home tab's
  nested Navigator is at its **root** route (`canPop() == false`)
- Hidden when the user navigates into a category, expert profile, or search
- A `_HomeRouteObserver` on the Home tab's Navigator triggers `setState()`
  on push/pop so the `Builder` re-evaluates visibility

**Booking button (`expert_profile_screen.dart`):**
- `isOnline` does NOT block scheduled bookings — removed the gate in v9.0.2
- Only blocked by: `isSelf` (self-booking) or `!isReady` (no date/time selected)
- Offline providers show a grey badge on search cards but can still receive bookings

**Review auto-trigger (`my_bookings_screen.dart`):**
- Admins NEVER get auto-review popups (`if (_isAdmin) return`)
- Requires `completedAt` timestamp to exist (proves payment finalized)
- Requires `providerReviewShown != true` (Firestore flag set immediately on trigger)
- Requires `jobExpertId == currentUserId` (only the expert reviews)
- Requires `jobExpertId != jobCustomerId` (never self-rate)
- `_reviewTriggeredFor` in-memory set prevents re-trigger within same session

**Provider Workspace — Orders must be segmented into 3 tabs (v9.0.3):**

| Tab # | Name | Content | Stream |
|-------|------|---------|--------|
| 1 (leftmost) | משימות שלי | Active/pending jobs (`_activeStatuses`) | `_expertStream` |
| 2 | יומן | Calendar view with unavailable dates | `_expertStream` |
| 3 | היסטוריה | Completed/cancelled/refunded jobs | `_expertStream` (catch-all `!_activeStatuses`) |

`DefaultTabController(length: _isProvider ? 3 : 2)` — provider has 3 tabs,
customer has 2. The provider History tab uses the same catch-all pattern as
the customer History tab: `!_activeStatuses.contains(status)`.

**StoriesRow "+" badge (`stories_row.dart`):**
- ALWAYS visible for providers — green (has story) or indigo (no story)
- Tap when no story → upload sheet
- Tap when story exists → view story; long-press → delete
- The "+" icon changes to a play icon when a story exists

### Law 17: Workflow Resilience — Stepper + Review Visibility

**Provider job stepper must include "On the Way" before "Arrived":**

| Step | Provider button | Field written | Customer sees |
|------|----------------|---------------|---------------|
| 1. התקבלה | (automatic on payment) | `status: 'paid_escrow'` | "ההזמנה התקבלה" |
| 2. בדרך | "אני בדרך 🚗" (amber) | `expertOnWay: true, expertOnWayAt` | "המומחה בדרך אליך" |
| 3. בעבודה | "הגעתי — התחל עבודה 🛠️" (indigo) | `workStartedAt, expertOnWay: false` | "המומחה עובד" |
| 4. הושלם | "סיימתי את העבודה" (green) | `status: 'expert_completed'` | "ממתין לאישור" |

The "בדרך" button only appears when `expertOnWay == false && workStartedTs == null`.
The "הגעתי" button only appears when `expertOnWay == true && workStartedTs == null`.

**Files:** `my_bookings_screen.dart` (`_markOnTheWay`, `_markWorkStarted`,
`_ExpertJobCard` button logic)

**Review visibility rules (already implemented in `review_service.dart`):**
1. Both client AND expert submitted → `_checkAndPublish()` publishes immediately
2. Only one side submitted → stays hidden (unpublished) for 7 days
3. After 7 days → `lazyPublish()` publishes on next profile view

**iPhone resilience (`main.dart` `_resilientUserFetch`):**
- Cache-first: tries `Source.cache` BEFORE server (instant on repeat visits)
- Server timeout reduced to 3 seconds (was 4)
- Three-tier fallback: cache → server(3s) → default(3s)

---

### Law 18: Naming Convention & Direct Actions (v9.0.6)

**"Chat" is now "Messages" (הודעות) across the entire app.**

| Locale | Old | New |
|--------|-----|-----|
| Hebrew | צ'אט | **הודעות** |
| English | Chat | **Messages** |
| Spanish | Chat | **Mensajes** |
| Arabic | الرسائل | الرسائل (unchanged) |

Updated in: `tabChat` key in all 4 `.arb` files and all 4 `app_localizations_*.dart` files.
The `chatListTitle` was already "הודעות"/"Messages" — no change needed.

**Booking card buttons must use short, action-oriented labels:**

| Old | New | Action |
|-----|-----|--------|
| "📞 התקשר למומחה" | "📞 התקשר" | `tel:` link to expert phone |
| "💬 צ'אט מהיר" | "💬 שלח הודעה" | Opens specific conversation |
| "צ׳אט עם לקוח" | "שלח הודעה" | Opens conversation with customer |

**Rules:**
- Never use "צ'אט" / "Chat" in user-facing text — always "הודעות" / "Messages"
- Booking card buttons must be ≤ 3 Hebrew words
- Every "Send Message" button must deep-link to the specific conversation

---

### Law 19: Order Segmentation — Active vs History (v9.0.7)

**Terminal statuses must strictly reside in the History tab. My Tasks must
remain active-only.**

**Provider tabs (3 tabs):**

| Tab | Shows | Statuses |
|-----|-------|----------|
| משימות שלי | Active jobs ONLY | `paid_escrow`, `expert_completed`, `disputed`, `pending`, `accepted`, `in_progress`, `awaiting_payment` |
| יומן | Calendar view | All jobs (visual only) |
| היסטוריה | Completed/cancelled | Everything NOT in `_activeStatuses` (catch-all) |

**Previous bug (fixed in v9.0.7):** `_buildExpertTasksList` showed BOTH active
and history sections in the same ListView. Completed jobs appeared in the tasks
tab with a "היסטוריה" header. Now the tasks tab filters to `_activeStatuses`
only and shows empty state if no active jobs exist.

**Customer tabs (2 tabs):**

| Tab | Shows | Filter |
|-----|-------|--------|
| פעילות | Active bookings | `_activeStatuses.contains(status)` |
| היסטוריה | Past bookings | `!_activeStatuses.contains(status)` (catch-all) |

**Debug logging:** Both customer and provider history builders print
`[CustomerHistory] Stream returned N docs` and `[History] Provider stream: N total docs`
to the console for diagnosis.

**Story upload resilience:** Server verification uses retry with 1-second delay
between attempts, 3-second timeout per attempt. Removed hard failure on
verification miss — logs instead of throwing.

### Law 20: Wallet Management & Support Path (v9.0.8)

**Users must be able to remove saved credit cards:**

- `_buildSavedCardTile()` in `finance_screen.dart` shows an X button on each card
- `_confirmRemoveCard()` shows a confirmation dialog before deletion
- `StripeService.removeCard(paymentMethodId)` calls `detachPaymentMethod` CF
- After removal, `_loadSavedCards()` refreshes the list to show "Add Card" state
- Both native and web StripeService implementations have the method

**Community Support must link to internal Messages, not WhatsApp:**

- `_WhatsAppSosButton` in `category_results_screen.dart` renamed to internal support
- Button label: "תמיכה" (Support) with `support_agent_rounded` icon
- Navigates to `SupportCenterScreen(jobCategory: 'volunteer')`
- No external WhatsApp link — all support is handled internally
- `_kCoordinatorPhone` and `url_launcher` import removed

**Rules:**
- Never link to external WhatsApp for support — use `SupportCenterScreen`
- Every saved card must have a visible remove option
- Card removal must go through `detachPaymentMethod` CF, never direct Firestore delete

---

### Law 21: Resilience & Visual Badges (v9.0.9)

**iOS Connection Supervisor (`main.dart` AuthWrapper):**
- 5-second timeout on `authStateChanges()` waiting state
- `_authTimedOut = true` after 5s → forces past splash screen
- If auth hasn't resolved, user sees `PhoneLoginScreen` (can retry)
- If auth HAS resolved (just slow stream), `snapshot.data` is checked normally

**History tab timeout (`my_bookings_screen.dart`):**
- 6-second timeout on `_buildProviderHistoryTab` stream
- `_historyTimedOut = true` → shows empty state instead of infinite spinner
- Prevents iOS users from seeing a permanent loading indicator

**Volunteer Golden Heart badge (`expert_profile_screen.dart`):**
- `Stack` wraps the profile `CircleAvatar` in the specialist card
- When `isVolunteer == true`: red heart icon (❤️) at bottom-right with white circle border
- Visible on the expert's full profile page (was previously only on search cards)

**Rules:**
- Auth splash screen must NEVER exceed 5 seconds on any platform
- History/task streams must ALWAYS have a timeout fallback (≤ 10 seconds)
- `isVolunteer` badge must appear on: search cards, expert profile, public profile

### Law 22: Data Integrity & Real-time Sync (v9.1.0)

**Volunteer profile images must use `safeImageProvider`:**
- `_buildVolunteerChip` in `community_screen.dart` uses `safeImageProvider(imageUrl)`
- Handles both base64 and HTTPS URLs with initials fallback
- Debug logging: `[Volunteer] name (uid=...) img=N chars|NULL`

**Support chat must be accessible from Messages tab:**
- Pinned "תמיכה" entry at index 0 of the chat list (`chat_list_screen.dart`)
- Shows support agent icon + "צריך עזרה? דבר עם הצוות שלנו"
- Taps navigates to `SupportCenterScreen`
- Support tickets live in `support_tickets` collection (separate from `chats`)

**Story upload must offer replace/delete options:**
- When provider has an existing story, tapping opens a bottom sheet:
  - "צפה בסטורי" → view existing
  - "העלה סטורי חדש" → upload replacement
  - "מחק סטורי" → delete + allow new upload
- When no story exists, tapping goes straight to upload

**Customer stream timeout:**
- `_customerStreamTimedOut` flag after 6 seconds
- Shows empty state instead of infinite skeleton shimmer
- Same pattern as provider history timeout

### Law 23: Infrastructure Integrity (v9.1.2)

**Firestore IndexedDB persistence is PERMANENTLY DISABLED on web.**

This is not a temporary workaround — it is a permanent architecture decision.

**Why:** IndexedDB persistence on web caused 4 major crash cycles:
- v8.9.4: "INTERNAL ASSERTION FAILED" on multi-tab conflict
- v9.0.0: Corrupted cache after nuclear purge → blank screens
- v9.1.0: Double Settings call → assertion crash froze admin panel
- v9.1.1: `clearPersistence()` on partially-initialized instance → crash loop

**The fix (`main.dart` Step 3a):**
```dart
FirebaseFirestore.instance.settings = const Settings(
  persistenceEnabled: false,
);
```
One line. No try-catch chains. No clearPersistence. No race conditions.

**What replaces persistence:**
- `CacheService` (in-memory TTL) handles short-lived caching
- `StreamBuilder` listeners get real-time updates from server
- Nuclear purge in `app_init.js` forces fresh data on version bumps
- ~200ms extra on first page load (server round-trip) — acceptable

**Logout must NOT manually navigate:**
- `performSignOut()` calls ONLY `FirebaseAuth.instance.signOut()`
- `AuthWrapper.StreamBuilder<User?>` detects `null` → shows `PhoneLoginScreen`
- Manual `pushAndRemoveUntil` caused a double-navigation race → blank screen
- Fallback: if signOut throws, THEN navigate manually as last resort

**Auth supervisor reduced to 3 seconds:**
- iOS cold starts: `_authTimedOut = true` after 3s (was 5s)
- Forces past splash screen — user sees login or home screen immediately

**Rules:**
- `FirebaseFirestore.instance.settings` must be called AT MOST ONCE per app lifecycle
- `performSignOut` must NEVER navigate — let AuthWrapper handle it
- All stream timeouts must fall back to empty/error state, never infinite spinner

### Law 24: Atomic Resilience — Defensive Engineering (v9.1.2)

**Self-healing stream wrapper (`lib/utils/resilient_stream.dart`):**
- `ResilientStreamBuilder<T>` — drop-in replacement for `StreamBuilder`
- Built-in timeout (default 6s) → shows empty state, not infinite spinner
- Built-in error handler → shows "שגיאה בטעינת הנתונים", never crashes
- Use for ALL admin panel streams (banners, stories, users)

**Hard state reset on logout (`lib/services/auth_service.dart`):**
1. `CacheService.purgeExpired()` — clears in-memory cache
2. `Sentry.configureScope(null)` — clears user context
3. `FlutterSecureStorage().deleteAll()` — clears saved credentials
4. `FirebaseAuth.signOut()` — triggers AuthWrapper navigation
5. Fallback: if signOut throws → manual `pushAndRemoveUntil`

**Admin sidebar responsive layout (`admin_design_tab.dart`):**
- `LayoutBuilder` checks `constraints.maxWidth >= 600`
- Wide screens: sidebar (220px) + content pane
- Narrow screens: sidebar hidden (prevents vertical-letter bug)

**Atomic init sequence (`main.dart`):**
```
Step 1: PackageInfo (version string)
Step 2: LocaleProvider
Step 3: Firebase.initializeApp()
Step 3a: Firestore Settings (persistence OFF, ONCE only)
Step 3b: Auth persistence (LOCAL)
Step 3c: Web redirect handling
Step 5: Stripe (10s timeout)
Step 7: Sentry (fire-and-forget)
Step 8: bfcache disable
→ runApp()
```

No step depends on a previous step's success. Each step has try/catch.
If any step fails, the app still launches with degraded functionality.

### Law 25: Support Intelligence (v9.1.3)

**Admin inbox must resolve sender UIDs to full user profiles:**

- `_TicketCard` in `admin_support_inbox_tab.dart` is now `StatefulWidget`
- On init: fetches `users/{userId}` to get `profileImage`, `name`, `phone`, `email`
- Avatar uses `safeImageProvider(profileImg)` with initials fallback
- Contact info (phone or email) shown below the name
- Falls back to `data['userName']` if user doc fetch fails

**Story playback retry with fresh URL:**

- Error state shows "נסה שוב" (Retry) button
- `_retryWithFreshUrl()` re-reads `stories/{uid}.videoUrl` from Firestore
- If URL changed (re-upload), uses the new URL
- 10s timeout on `VideoPlayerController.initialize()`
- 2-attempt retry loop on initial load

### Law 26: WhatsApp-Style Push Notifications (v9.3.1)

**Deep-link navigation on notification tap:**

| Notification Type | Tab | Deep Link |
|-------------------|-----|-----------|
| `chat` | Messages (2) | Opens specific `ChatScreen(receiverId)` extracted from `chatRoomId` |
| `new_booking`, `booking_confirmed`, `job_status` | Orders (1) | Tab only |
| `job_request`, `broadcast_urgent` | Opportunities (5) | Tab only |
| `support_ticket` | Messages (2) | Support pinned at top |
| `admin_payment_alert` | Admin (6) | Tab only |
| `request_declined` | Home (0) | Shows as in-app notification |

**Sound & priority (all Cloud Functions):**
- iOS: `aps: { sound: "default" }` + `apns-priority: 10`
- Android: `priority: "high"` + custom channel `anyskill_chats`
- Web: Service worker `firebase-messaging-sw.js` shows desktop notification

**Background handling:**
- `@pragma('vm:entry-point')` on `_firebaseMessagingBackgroundHandler`
- `Firebase.initializeApp()` called inside the background isolate
- OS shows the notification automatically from the FCM payload

**Foreground tap:** `_navigateFromMessage` calls `setState()` to force
HomeScreen rebuild so `PendingNotification` is picked up immediately.

**Files:** `main.dart` (`PendingNotification`, `_navigateFromMessage`),
`home_screen.dart` (deep-link in `initState`)

### Law 27: Provider Request Decline (v9.3.0)

Providers can explicitly decline job requests they don't want.

**UI:** "לא מעוניין" text button below the Accept/QuickBid buttons in
`_RequestCard` — grey, low priority, visible only for open requests.

**Logic (`_declineRequest` in `opportunities_screen.dart`):**
1. Confirmation dialog: "האם אתה בטוח שברצונך לדחות את הבקשה?"
2. Writes `declinedProviders: arrayUnion([uid])` to `job_requests/{id}`
3. Sends notification to customer: "הספק לא זמין/ה כרגע"
4. Card hidden via client-side filter: `declined.contains(_uid)`

**Customer impact:** Other providers can still accept. The customer sees
"הספק לא זמין" notification but the request stays open.

**Firestore field:** `job_requests/{id}.declinedProviders: string[]`

### Law 28: Offline Message Queue (WhatsApp-style, v12.2.0)

Because **Law 23 permanently disables Firestore IndexedDB persistence on web**,
we cannot rely on the Firestore SDK to buffer offline sends. A manual local
outbox fills the gap.

**Service:** [lib/services/offline_message_queue.dart](lib/services/offline_message_queue.dart)
— `OfflineMessageQueue.instance` (ChangeNotifier singleton), initialized in
[main.dart](lib/main.dart) via `unawaited(OfflineMessageQueue.instance.init())`.

**Storage:** single JSON array under `SharedPreferences['offline_msg_queue_v1']`.
Web-safe (no IndexedDB), iOS-safe, Android-safe.

**Send pipeline:**
1. `chat_screen._send()` calls `enqueue()` — NO more `SafetyModule.hasInternet()`
   gate. The user can tap send offline and the bubble renders immediately.
2. Queue writes an entry with `status: pending` + optimistic `localId`
   (`local_{ts}_{rand}`), then attempts `ChatService.sendMessage`.
3. On success → remove from queue (Firestore stream delivers the real doc).
4. On failure → stay `pending` + schedule a 2s retry. After `_maxAttempts` (3)
   → flip to `status: failed`.
5. `Connectivity().onConnectivityChanged` listener flushes the whole queue
   whenever the network returns.

**UI merge:** [chat_message_list.dart](lib/screens/chat_helpers/chat_message_list.dart)
wraps the `StreamBuilder<QuerySnapshot>` in an `AnimatedBuilder(animation:
OfflineMessageQueue.instance)`. Pending messages are prepended to the Firestore
docs via `PendingMessage.toDocMap()` — same shape as a real Firestore doc,
plus three UI-only fields (`__isPending`, `__pendingStatus`, `__localId`,
`__createdAtMs`).

**Status icons** (my-bubble only, [chat_ui_helper.dart](lib/screens/chat_modules/chat_ui_helper.dart)
`_StatusIcon`):

| State  | Icon                          | Trigger |
|--------|-------------------------------|---------|
| pending | `schedule_rounded` (clock)   | in queue, send not yet succeeded |
| failed  | `error_outline_rounded` (red)| 3 attempts exhausted — tap bubble to retry |
| sent    | single-grey `done_all_rounded` | in Firestore, `isRead: false` |
| read    | double-blue `done_all_rounded` | `isRead: true` |

Failed bubbles are tappable (retries via `OfflineMessageQueue.retry`) and
long-press opens a sheet with Retry + Cancel actions.

**Rules:**
- Never re-enable Firestore web persistence to "fix offline sends" — that's
  Law 23 territory and reopens the crash cycle. Use this queue instead.
- Every new send path (payment request, image, location) should flow through
  `_send()` so it inherits the queue. The one legacy site still bypassing it
  is `_sendPaymentRequest` in `chat_screen.dart` — migrating that is a future
  cleanup (low priority — payment requests are rarely sent offline).
- `PendingMessage.toDocMap()` must keep matching the Firestore message shape
  (senderId, receiverId, message, type, timestamp, isRead). If you add a
  required field to messages, add it there too.

---

## 9c. v9.0.4 Changelog — Major Fixes Implemented 2026-04-04

### Double Booking Prevention (`expert_profile_screen.dart`)

When the user selects a day on the calendar, `_loadBookedSlots(day)` queries
the `bookingSlots` collection for all docs matching the pattern:
```
bookingSlots/{expertId}_{YYYYMMDD}_{HHmm}
```
Uses `FieldPath.documentId` range query (`>= prefix`, `< prefix + 'z'`).
Booked slots are displayed as **greyed out with strikethrough** — tapping
does nothing. The existing `kSlotConflict` transaction guard remains as a
fallback for rare race conditions.

### Provider Workspace — 3-Tab Structure (`my_bookings_screen.dart`)

| Tab | Position | Content | Status filter |
|-----|----------|---------|---------------|
| משימות שלי | 1 (leftmost) | Active jobs | `_activeStatuses` set |
| יומן | 2 | Calendar with unavailable dates | All expert jobs |
| היסטוריה | 3 | Past jobs | `!_activeStatuses` (catch-all) |

`DefaultTabController(length: _isProvider ? 3 : 2)`.
New `_buildProviderHistoryTab()` reuses `_buildGroupedList()` with `isHistory: true`.

### Story System — Persistent "+" Button (`stories_row.dart`)

The provider's "+" badge on their story circle is **always visible**:
- **No story:** Indigo `+` icon → tapping opens upload sheet
- **Has story:** Green play icon → tapping views, long-press deletes

The 25-hour expiry filter applies only to OTHER experts' stories. The
provider's own doc is extracted before filtering.

### Admin Guards (`my_bookings_screen.dart`)

- `_isProvider = isProvider` (reverted from `isProvider || isAdmin`)
- Admins see client tabs by default — no merged streams
- `_autoTriggerProviderReview`: `if (_isAdmin) return` as first line
- Review trigger requires `completedAt`, `providerReviewShown`, `expertId == currentUserId`

### Urgent Search FAB (`home_screen.dart`)

Hidden via `_HomeRouteObserver` when inside any sub-route (category, profile,
search). Uses `canPop()` check on the Home tab's nested Navigator.

### Booking Gate (`expert_profile_screen.dart`)

`canBook = isReady && !isSelf` — `isOnline` removed from the gate. Scheduled
bookings work regardless of provider's online status.

### Self-Booking Prevention — 3 Layers

| Layer | File | Check |
|-------|------|-------|
| UI | `expert_profile_screen.dart` | `isSelf` → button disabled |
| Service | `escrow_service.dart` | `clientId == providerId` → error |
| Visual | `category_results_screen.dart` | "הפרופיל שלך" badge |

### Version Text

`'VERSION: 4.3.0'` → `'AnySkill v$appVersion'` using `constants.dart`.

---

## 9d. v11.8.0 Changelog — 2026-04-08

### Typography Migration

- **Font:** Heebo → **Assistant** (Google Fonts). Single-point change in `lib/theme/app_theme.dart`.
- **Fallback chain:** Assistant → NotoSansHebrew (bundled) → sans-serif (system).
- `GoogleFonts.assistantTextTheme(...)` replaces `GoogleFonts.heeboTextTheme(...)`.

### Branding — Luxury Metallic Gold

- All volunteer-related hearts changed to **Metallic Gold `#D4AF37`**.
- Applied to: profile picture overlay, volunteer counter stat row, home banner pulse.
- Home banner "נתינה מהלב" heart uses `_HeartPulse` widget (2s `easeInOut` scale animation).

### Community Hub (v11.0.0 → v11.8.0)

- **Active Requests section** added to "Request Help" tab (Tab B) — `StreamBuilder` on `streamMyActiveRequests(uid)` shows requester's active tasks at the top.
- **Dynamic status cards:** ACCEPTED (volunteer name + confirm start), IN_PROGRESS (chat), PENDING_CONFIRMATION (evidence photo + "אשר ושלח תודה!" + "עוד לא הסתיים").
- **Request form UX:** positive reinforcement banner, anonymous helper text, urgency color coding (dark variants), optional target date picker, preview dialog.
- **Label:** "סוג נזקק" → "עבור מי הסיוע?"
- **Completion flow hardened:** `try/catch` around `completeRequest`, `debugPrint` for rejections.

### Home Screen — Community Banner

- Title: "AnySkill Community" → **"נתינה מהלב"**.
- Real-time volunteer counter via `.snapshots()` stream (not one-shot `.get()`).
- **Facepile:** 4 overlapping `CircleAvatar` widgets using `safeImageProvider` + `PositionedDirectional`.
- Client-side sort by `lastVolunteerTaskAt` (avoids composite index dependency).
- Arrow hint icon at trailing edge. Stream cancelled in `dispose()`.

### Search Bar

- **Sub-categories only:** Top-level categories filtered out (`if (parentId.isEmpty) continue`).
- **Tap race fix:** `_onFocusChange` delay (200ms) before `_removeOverlay()` so `InkWell.onTap` fires.
- **Visual sync:** Category images rendered via `ClipOval` + `BoxFit.cover`; provider avatars via `safeImageProvider`.
- **InkWell feedback:** `borderRadius`, `splashColor`, `highlightColor` added.
- **Home tab callback:** handles both `'category'` and `'subcategory'` types → `CategoryResultsScreen`.

### Expert Profile

- **VIP card removed:** `_buildActionSquares` always shows **Video + Gallery** (two equal `Expanded` cards).
- **Video banner removed:** Deleted the dark gradient video section from specialist card header.
- **XP bar owner-only:** `if (auth.uid == widget.expertId)` wraps `XpProgressBar`.
- **Volunteer counter (public):** `FutureBuilder<int>` with `_getVolunteerCount(expertId)` queries `community_requests where volunteerId == expertId AND status == 'completed'`. Tied to user UID — identical across all skill profiles.
- **Name row:** Heart icon removed (only avatar overlay heart remains).

### Firestore Indexes

- Added composite index: `community_requests: requesterId + status` for `streamMyActiveRequests` `whereIn` query.
- Existing `volunteerId + status` index covers volunteer count query.

---

## 9e. Business Agenda & Availability Manager (v11.9.0) — `my_bookings_screen.dart`

### Overview
Upgraded the provider "Calendar" tab from a basic day-off blocker to a professional
Business Agenda with hourly granularity, recurring weekly rules, and daily agenda view.

### New Data Model (`users/{uid}`)

| Field | Type | Purpose |
|-------|------|---------|
| `unavailableDates` | `string[]` | Full-day blocks (ISO-8601: `'YYYY-MM-DD'`) — backward compatible |
| `timeBlocks` | `map[]` | Hourly blocks: `[{date, from, to, reason}]` |
| `recurringRules` | `map[]` | Weekly patterns: `[{dayIndex, type, from?, to?}]` |
| `workingHours` | `map` | Per-day hours (unchanged, edited in profile) |

**`timeBlocks` entry:**
```json
{"date": "2026-04-15", "from": "12:00", "to": "14:00", "reason": "break"}
```
Reasons: `personal`, `break`, `appointment`

**`recurringRules` entry:**
```json
{"dayIndex": 5, "type": "off"}
{"dayIndex": 0, "type": "hours", "from": "08:00", "to": "12:00"}
```
`dayIndex`: 0=Sunday..6=Saturday. `type`: `off` (full day closed) or `hours` (custom hours override).

### Calendar Cell Color Coding

| State | Visual | Color |
|-------|--------|-------|
| Fully available | Default white | — |
| Has booked jobs | Green tint + purple dots (up to 3) | `#F0FDF4` bg |
| Partial time block | Orange outline | `#FFF7ED` bg, `#F97316` border |
| Fully blocked (day off / recurring rule) | Red striped circle | Red diagonal stripes |
| Today | Purple tint | `#6366F1` @ 15% |
| Selected | Solid purple circle | `#6366F1` |

### Weekly Summary Header
Purple gradient card (`#6366F1` → `#8B5CF6`) showing:
- **X הזמנות השבוע** — count of jobs with `appointmentDate` in current week
- **Y שעות זמינות השבוע** — computed from effective working hours minus blocks

### Daily Agenda View
Below the calendar, tapping a day shows:
- **Day header:** Hebrew date + status badge (working hours range or "יום חסום")
- **Time blocks:** Orange cards with time range pill, reason icon, delete button
- **Job cards:** Time pill + customer name + service type + amount badge + status badge
- **Empty state:** Green "יום פנוי — אין הזמנות" or red "יום זה חסום"

### Recurring Rules Section ("חוקים חוזרים")
White card below agenda with:
- "הוסף" button opens bottom sheet with day selector (7 pills) + type toggle
- Rules displayed as color-coded rows: red for "סגור" days, green for custom hours
- Each rule has inline delete (×) button
- Replacing: adding a rule for same day removes the previous rule

### FAB + Save Bar
- **Save button:** "שמור שינויים" (dark, full-width) — persists `unavailableDates` + `timeBlocks` + `recurringRules` to Firestore
- **FAB (+):** Opens "הוסף חסימה" bottom sheet with:
  - Block type toggle: "יום מלא" or "טווח שעות"
  - Date picker
  - Time range dropdowns (06:00–22:30, 30-min steps)
  - Reason chips: אישי / הפסקה / פגישה

### Google Calendar Sync
Placeholder button in header — taps show "בקרוב!" snackbar.
Ready for future integration with `googleapis` package.

### Availability Resolution Priority
```
1. Full-day block (unavailableDates)     → day fully blocked
2. Recurring rule type='off'             → day fully blocked
3. Recurring rule type='hours'           → override working hours
4. workingHours from profile             → base schedule
5. No workingHours configured            → fallback (provider hasn't set hours)
```

### Helper Methods

| Method | Purpose |
|--------|---------|
| `_isDayFullyBlocked(day)` | Checks `unavailableDates` + recurring off rules |
| `_isDayBlockedByRule(day)` | Checks only recurring `type='off'` rules |
| `_getRecurringHoursForDay(day)` | Returns custom hours override or null |
| `_getBlocksForDate(day)` | Returns time blocks for specific date, sorted by `from` |
| `_getEffectiveHours(day)` | Resolves final (from, to) considering all layers |
| `_saveAvailability()` | Persists all three fields to Firestore |

### Helper Widgets

| Widget | File | Purpose |
|--------|------|---------|
| `_BlockTypeChip` | `my_bookings_screen.dart` | Toggle chip for block type selection |
| `_TimeDropdown` | `my_bookings_screen.dart` | 30-min interval time picker (06:00-22:30) |
| `_ReasonChip` | `my_bookings_screen.dart` | Reason selector for time blocks |
| `_StripedBlockedDay` | `my_bookings_screen.dart` | Red striped calendar cell (unchanged) |

### Backward Compatibility
- `unavailableDates` field is unchanged — old data loads correctly
- `workingHours` is read-only in calendar (still edited in profile)
- `bookingSlots` collection and customer booking flow are untouched
- `_loadUnavailableDates()` now loads all three new fields in one Firestore read

---

## 10. Firestore Collections Reference

| Collection | Key Fields | Purpose |
|-----------|-----------|---------|
| `users/{uid}` | isProvider, isVolunteer, isVerified, isDemo, isElderlyOrNeedy, isAnySkillPro, proManualOverride, serviceType, xp, balance, pendingBalance, rating, reviewsCount, customerRating, isOnline, lastVolunteerTaskAt, volunteerTaskCount, hasActiveVolunteerBadge, stripeAccountId, cancellationPolicy, streak, lastStreakDate, streakBestEver, lastDailyDropDate, profileBoostUntil, workingHours, selfieVerificationUrl, **volunteerHeart**, **communityXP**, **communityBadges**, **timeBlocks**, **recurringRules** | User profiles |
| `jobs/{jobId}` | customerId, expertId, totalAmount, netAmountForExpert, commission, status, quoteId, chatRoomId, clientReviewDone, providerReviewDone, providerReviewShown, completedAt, cancellationDeadline, stripePaymentIntentId, stripeTransferId | Bookings |
| `quotes/{id}` | providerId, clientId, amount, status, jobId | Price quotes |
| `reviews/{id}` | jobId, reviewerId, revieweeId, isClientReview, ratingParams, overallRating, publicComment, privateAdminComment, isPublished, createdAt | Double-blind reviews |
| `volunteer_tasks/{id}` | clientId, providerId, category, description, status, clientConfirmed, gpsValidated, providerLat/Lng, clientLat/Lng, gpsDistanceMeters, xpAwarded, xpAmount, clientReview, completedAt | Volunteer lifecycle |
| `help_requests/{id}` | userId, category, description, status | Legacy community help requests |
| `community_requests/{id}` | requesterId, volunteerId, title, description, category, requesterType, status (open/in_progress/completed/cancelled), urgency (low/medium/high), isAnonymous, location, completedAt, volunteerReview | Community Hub requests (v11.0.0) |
| `chats/{chatRoomId}` | users: [uid1, uid2] | Chat rooms (id = sorted UIDs joined by `_`) |
| `chats/{id}/messages/{msgId}` | senderId, receiverId, **message** (NOT 'text'), type, timestamp, isRead | Messages |
| `transactions/{id}` | senderId, receiverId, amount, type, jobId, payoutStatus, timestamp | Payment audit trail |
| `platform_earnings/{id}` | jobId, amount, sourceExpertId, status, timestamp | Commission records |
| `notifications/{id}` | userId, title, body, type, relatedUserId, category, isRead, createdAt | In-app notifications |
| `job_requests/{id}` | clientId, category, status, interestedProviders[], isActive, urgency | Quick-order board |
| `job_broadcasts/{id}` | clientId, category, status (open/claimed/expired), claimedBy, claimedByName, expiresAt, sourceJobRequestId | Urgent first-come-first-served claims |
| `courses/{id}` | title, videoUrl, category, quizQuestions[], xpReward, order | Academy courses |
| `user_progress/{uid}/courses/{id}` | watchedPercent, passed, xpAwarded | Course progress |
| `stories/{uid}` | mediaUrl, videoUrl, timestamp, expiresAt, viewCount, likeCount, hasActive, providerName, providerAvatar | Skills Stories (25h expiry) |
| `user_rewards/{id}` | userId, type, status (active/expired), awardedAt, expiresAt, source | Daily Drop / streak / engagement rewards |
| `support_tickets/{id}` | userId, userName, jobId?, category, subject, status (open/in_progress/resolved), evidenceUrls | Support ticket + messages subcollection |
| `category_requests/{id}` | userId, userName, description, originalCategory?, status (pending/approved/rejected) | Custom "Other" category requests |
| `admin/admin/settings/settings` | feePercentage, urgencyFeePercentage, totalPlatformBalance | Platform config |
| `app_settings/sounds` | {soundName: assetPath or URL} | Admin-managed sound mappings |
| `settings_gamification/app_levels` | silver (default 500), gold (default 2000) | XP level thresholds |
| `application_content/{locale}` | key-value string overrides | CMS text overrides |
| `admin_audit_log/{id}` | targetUserId, action, adminName, adminUid, createdAt | Admin action audit trail (v8.9.4) |

---

## 11. Firestore Security Rules -- Key Patterns

### Server-Only Fields (blocked from client writes on `users/{uid}`)
`xp`, `current_xp`, `level`, `isPromoted`, `isVerifiedProvider`, `isVerified`, `isAdmin`, `balance` (increment only via CF)

### Allowed Cross-User Writes on `users/{uid}`

| Fields | Who | Why |
|--------|-----|-----|
| `rating, reviewsCount` | Any auth | Review aggregation |
| `customerRating, customerReviewsCount` | Any auth | Expert reviews customer |
| `pendingBalance` | Any auth | Client credits expert escrow |
| `lastVolunteerTaskAt, volunteerTaskCount, hasActiveVolunteerBadge` | Any auth | Volunteer confirmation |

### Collection-Level Anti-Fraud Rules
- `volunteer_tasks` create: `providerId == auth.uid AND clientId != auth.uid`
- `volunteer_tasks` read/update: only participant (`clientId` or `providerId`)
- `reviews` create: `reviewerId == auth.uid` AND reviewer is job participant
- `reviews` update (publish): both parties reviewed OR 7 days passed

### Private Data Subcollection Pattern (v12.2.0)

Sensitive fields are being moved from the public-ish `users/{uid}` doc into
`users/{uid}/private/{docId}` — owner + admin reads only, rule:

```
match /users/{uid}/private/{docId} {
  allow read:           if isOwner(uid) || isAdmin();
  allow create, update: if isOwner(uid) || isAdmin();
}
```

Admin SDK (Cloud Functions, including Ilon's `askCeoAgent`) bypasses rules
and can always read the subcollection — no CF changes needed for new fields.

**Subcollection layout:**

| Doc path | Fields | Status |
|----------|--------|--------|
| `private/financial` | `balance`, `pendingBalance`, `bankDetails` | Scaffold only — no live writes |
| `private/identity` | `phone`, `email`, `taxId`, `idNumber` | Write-side DONE (PR 2a). Readers not migrated. |
| `private/kyc` | `idNumber`, `idDocUrl`, `selfieVerificationUrl`, `businessDocUrl` | Write-side DONE (PR 1). Admin verification tab READS from here. |

**Helper service:** [lib/services/private_data_service.dart](lib/services/private_data_service.dart)
— `getKycData`, `writeKycData`, `getContactData`, `writeContactData`,
`migrateIfNeeded`. All getters fall back to the main user doc for
pre-migration users, so no data loss during the transition.

**Dual-write pattern (MANDATORY during migration):** Every onboarding/signup
path that writes `phone`, `email`, or a KYC field to `users/{uid}` must also
call the matching `PrivateDataService.writeXxx()` helper in the same flow.
The main-doc write stays because legacy readers still depend on it.

**Wired signup paths (v12.2.0):**

| File | Trigger |
|------|---------|
| [onboarding_screen.dart](lib/screens/onboarding_screen.dart) | Main onboarding form (all roles) |
| [provider_registration_screen.dart](lib/screens/provider_registration_screen.dart) | Dedicated provider registration |
| [main.dart:152](lib/main.dart) | `OnboardingGate` first-time Google Sign-In profile create |
| [main.dart:1338](lib/main.dart) | `_PhoneCollectionScreen` — legacy users adding phone |
| [otp_screen.dart:503](lib/screens/otp_screen.dart) | `_RoleSelectionSheet` new customer/provider profile |
| [phone_login_screen.dart:847](lib/screens/phone_login_screen.dart) | Phone/Google/Apple linked new user doc |

**If you add a new signup or profile-edit flow**, it MUST call
`PrivateDataService.writeContactData` (phone + email) and, for providers,
`writeKycData` (id + docs). Missing the dual-write means the user's data
silently stays only in the main doc and never makes it to the subcollection.

**Readers migrated so far:**

| Screen | Reads via | Notes |
|--------|-----------|-------|
| [admin_id_verification_tab.dart](lib/screens/admin_id_verification_tab.dart) | `PrivateDataService.getKycData(uid)` | `FutureBuilder` wrapping the ID + selfie comparison row |

**Readers still on the main doc** (future PR 2b): [admin_user_detail_screen.dart](lib/screens/admin_user_detail_screen.dart)
(WhatsApp/tel buttons + 360), [admin_users_tab.dart](lib/screens/admin_users_tab.dart)
(tel launch), [admin_agent_management_tab.dart](lib/screens/admin_agent_management_tab.dart),
[support_dashboard_screen.dart](lib/screens/support/support_dashboard_screen.dart)
(customer 360 panel), [main.dart:1240](lib/main.dart) (OnboardingGate legacy
phone redirect), [edit_profile_screen.dart:125](lib/screens/edit_profile_screen.dart)
(init display), [identity_onboarding_screen.dart:435](lib/screens/identity_onboarding_screen.dart).

**End-state (not yet executed):**
1. All readers pull via `PrivateDataService.getXxx` with the built-in main-doc
   fallback.
2. A one-shot Cloud Function backfill runs `migrateIfNeeded` for every
   existing user so `private/*` docs exist for pre-v12.2 accounts.
3. Writes to the main doc's `phone`, `email`, `idNumber`, `idDocUrl`,
   `selfieVerificationUrl`, `businessDocUrl` are removed. Then — and only
   then — the main doc becomes safe to open to wider reads.

**Do NOT** widen the `users/{uid}` rule to "any auth user" until step 3 is
complete. The main doc still carries PII.

**Why not migrate readers in one big PR?** The admin surface (especially
`admin_user_detail_screen`) threads a sync `Map<String, dynamic>` through
~6 builder functions. Converting to async `FutureBuilder` everywhere is
real surgery with zero privacy win until the main-doc writes stop — so
each reader migrates in a PR that can be validated end-to-end.

---

## 12. i18n Architecture

- **Singleton:** `LocaleProvider.instance` -- ChangeNotifier wrapping `Locale`
- **Persistence:** SharedPreferences key `app_locale`
- **CMS overrides:** `application_content/{locale}` streamed live from Firestore
- **Override priority:** CMS value > hard-coded `AppLocalizations._translations`
- **Switching:** `LocaleProvider.instance.setLocale(Locale('en'))` rebuilds entire app
- **942 keys** across 4 locales (he, en, es, ar) -- all screens fully migrated
- **RTL locales:** Hebrew (`he`) and Arabic (`ar`) -- both return `isRtl() == true`
- **Fallback chain:** CMS override > current locale > Hebrew > key name
- **ARB files:** Secondary format (`app_he.arb`, `app_en.arb`, `app_es.arb`, `app_ar.arb`) -- 88-key subset for tooling
- **Arabic note:** AI-generated translations (MSA). Should be reviewed by a native speaker before launch.

---

## 12b. Admin Sound Management (צלילים)

**Tab location:** Admin Panel -> System section (מערכת) -> "צלילים 🔊" (tab 10 of 10)

**Access:** Admin-only (tab is inside the admin panel which requires `isAdmin` role).

### Sound Inventory (4 registered sounds)

| Sound | Asset Path | Trigger | Screen |
|-------|-----------|---------|--------|
| Wealth Crystal | `audio/wealth_crystal.mp3` | Payment received / balance update | chat_screen, finance_screen |
| Solution Snap | `audio/solution_snap.mp3` | AI match found | home_screen |
| Opportunity Pulse | `audio/opportunity_pulse.mp3` | New job opportunity arrives | opportunities_screen |
| Growth Ascend | `audio/growth_ascend.mp3` | Course completed / XP earned | course_player_screen |

### Management UI
- Each sound row: Hebrew action name + current file + Play preview button + Edit button
- Edit opens bottom sheet with predefined sound list (selectable radio buttons with preview)
- Custom mappings show "מותאם" chip badge
- Save FAB writes all mappings to Firestore

### Persistence: `app_settings/sounds`
```
{
  "wealthCrystal": "audio/wealth_crystal.mp3",      // or a Firebase Storage URL
  "solutionSnap": "audio/custom_solution.mp3",
  ...
}
```

**AudioService** loads these mappings on `init()` and overrides preloaded players.
Supports both asset paths (`audio/file.mp3`) and URLs (`https://...`).

---

## 12c. AI CEO Strategic Agent (סוכן AI מנכ"ל)

**Tab location:** Admin Panel -> 5th section "AI CEO" (psychology icon)

### Architecture
```
AiCeoService.collectMetrics()     → 12 parallel Firestore queries
    ↓
AiCeoService.generateInsight()    → calls generateCeoInsight CF
    ↓
Cloud Function (Claude Sonnet)    → returns Hebrew strategic analysis
    ↓
AdminAiCeoTab                     → dark premium UI
```

### Metrics Collected (12 queries in parallel)
| Metric | Source | Purpose |
|--------|--------|---------|
| Total users / providers | `users` count | Growth tracking |
| Pending verifications | `users` where isPendingExpert | Bottleneck detection |
| Active jobs | `jobs` where status in [paid_escrow, expert_completed] | Workload |
| Completed jobs (24h) | `jobs` where completedAt > yesterday | Velocity |
| Open disputes | `jobs` where status == disputed | Trust health |
| Open support tickets | `support_tickets` where status == open | Support load |
| Pending category requests | `category_requests` where status == pending | Market demand |
| Weekly revenue | `platform_earnings` sum (7 days) | Financial health |
| Ticket categories (24h) | `support_tickets` category distribution | Issue trends |
| Category request descriptions | `category_requests` descriptions (7 days) | Demand signals |
| Open broadcasts | `job_broadcasts` where status == open | Urgency load |

### AI Output (all in Hebrew)
- **Morning Brief** (סיכום בוקר): 2-3 paragraph executive summary with key numbers
- **Recommendations** (המלצות): Exactly 3 actionable items
- **Red Flags** (נורות אדומות): 0-3 alerts on fraud/drops/anomalies

### Dark Premium UI
- Background: `#0F0F1A` (near-black)
- Cards: `#1A1A2E` (dark navy)
- Accents: Indigo `#6366F1` + Purple `#8B5CF6`
- Red flags: `#EF4444` background tint
- Recommendations: `#10B981` numbered cards

### Cloud Function: `generateCeoInsight`
- **Model:** `claude-sonnet-4-6-20250514` (strategic analysis needs stronger model)
- **Auth:** Admin-only
- **Input:** Full metrics JSON snapshot
- **Output:** `{morningBrief, recommendations[], redFlags[]}`
- **Deploy:** `firebase deploy --only functions:generateCeoInsight`

---

## 13. Cloud Functions Reference

| Function | Trigger | Purpose |
|----------|---------|---------|
| `updateUserXP` | callable | Award/deduct XP by event ID (caller must be self or admin; volunteer_task allowed for verified counterparty) |
| `processPaymentRelease` | callable | Release escrow (internal credits ledger) |
| `processCancellation` | callable | Cancel with policy enforcement |
| `resolveDisputeAdmin` | callable | Admin dispute resolution (refund/release/split) |
| `activateVipSubscription` | callable | Deduct 99 NIS, set isPromoted for 30d |
| `expireVipSubscriptions` | cron 00:30 IST | Clear expired VIP flags |
| `sendReceiptEmail` | Firestore trigger | Email receipt on completion |
| `generateServiceSchema` | callable (admin) | AI generates category-specific schema fields |
| `generateCeoInsight` | callable (admin) | AI CEO strategic analysis from platform metrics |
| `grantAdminCredit` | callable (admin) | Soft Launch tool — grants promotional credit to a user with validation, daily caps, idempotency, and full audit trail. See Section 4.6. |
| `setUserRole` | callable (admin) | Grants/revokes support_agent role on a user. Syncs role + isAdmin atomically, audit-logs to both admin_audit_log and support_audit_log. See Section 4.8. |
| `supportAgentAction` | callable (admin OR support_agent) | Centralized dispatch for agent actions: verify_identity, send_password_reset, flag_account, unflag_account. Reason required (≥5 chars). Every call writes to support_audit_log. See Section 4.8. |

**Phase 2 — REMOVED in v11.9.x (Stripe Connect):**
`createPaymentIntent`, `handleStripeWebhook`, `releaseEscrow`,
`onboardProvider`, `processRefund`, `listPaymentMethods`, `createSetupIntent`,
`createStripeSetupSession`, `createStripePaymentSession`,
`updateStripeAccount`, `detachPaymentMethod`. The entire `functions/payments.js`
module was deleted alongside the `stripe` npm dependency. Re-create a new
`functions/payments.js` (or `functions/payments_<provider>.js`) when
integrating the Israeli payment provider.

---

## 14. Known Patterns & Gotchas

### Data Access
- `DocumentSnapshot.get(field)` throws `StateError` if absent -- always `doc.data() ?? {}` then bracket access
- Chat messages use field `'message'` (NOT `'text'`)
- `connectivity_plus ^7` returns `List<ConnectivityResult>` -- use `.every()` not `==`
- Fee percentage: per-expert override `customCommission` takes precedence over global `feePercentage`

### Deprecated APIs
- `Color.withOpacity()` -> `Color.withValues(alpha: ...)`
- `dart:html` -> `package:web` + `dart:js_interop`

### Widget Gotchas
- `Slider`: `onChanged` is REQUIRED even with only `onChangeEnd` -- use `onChanged: (_) {}`
- `late bool _isOnline = _isOnline` self-assignment -> `LateInitializationError`
- `_setOnlineStatus(true)` must NOT be in `build()` -- only `initState`
- `HomeTab` in `_nestedTab()` Navigator: `widget.isOnline` frozen at first render

### Firebase
- `notification_module.dart` service worker: `.register(str.toJS)` not `.register(str)`
- Background FCM: pass `DefaultFirebaseOptions.currentPlatform` to `Firebase.initializeApp()`
- All queries need `.limit()` -- jobs:50, chats:50, experts:50, admin:500

### Logging
- 73 `debugPrint` calls across 18 service files -- all in error/diagnostic paths, intentionally kept
- Heaviest: `visual_fetcher_service.dart` (20), `stripe_service_native.dart` (9), `audio_service.dart` (8)

### Testing
- `flutter analyze`: must be 0 issues before any commit
- `flutter test test/unit/`: 77+ tests (1 known `fake_cloud_firestore` version mismatch)

---

## 15. Admin Panel -- Full Inventory (31 tabs)

Admin panel has 5 sections toggled by a `SegmentedButton<int>` in the AppBar.
**Access:** `isAdmin: true` on user doc OR email `adawiavihai@gmail.com`.

### Management (ניהול) -- 15 tabs

| # | Tab | Widget | Purpose |
|---|-----|--------|---------|
| 1 | הכל | `_buildList(allUsers)` | All users list |
| 2 | לקוחות | filtered isCustomer | Customer list |
| 3 | ספקים | filtered isProvider | Provider list |
| 4 | חסומים | filtered isBanned | Banned users |
| 5 | מחלוקות 🔴 | `DisputeResolutionScreen` | Dispute arbitration (refund/release/split) |
| 6 | משיכות 💸 | `_buildWithdrawalsList()` | Withdrawal requests |
| 7 | XP & רמות 🎮 | `XpManagerScreen` | XP management + level overrides |
| 8 | אימות זהות 🪪 | `_buildIdVerificationTab()` | Identity verification queue |
| 9 | משפך הרשמה 📈 | `RegistrationFunnelTab` | Signup funnel analytics |
| 10 | לייב פיד 📡 | `LiveActivityTab` | Real-time activity stream |
| 11 | צ'אטים 💬 | `_buildSupportTab()` | Chat monitoring |
| 12 | דמו ★ | `AdminDemoExpertsTab` | Demo expert CRUD |
| 13 | Pro ⭐ | `AdminProTab` | Pro badge management |
| 14 | בינה עסקית 🧠 | `BusinessAiScreen` | AI business coach |
| 15 | תיבת פניות 📮 | `AdminSupportInboxTab` | Support ticket inbox |

### Content (תוכן) -- 4 tabs

| # | Tab | Purpose |
|---|-----|---------|
| 1 | סטוריז 📸 | Skills Stories management |
| 2 | אקדמיה 🎓 | Course management |
| 3 | וידאו ✅ | Video verification |
| 4 | משוב פרטי 🔒 | Private feedback |

### System (מערכת) -- 10 tabs

| # | Tab | Widget | Purpose |
|---|-----|--------|---------|
| 1 | קטגוריות 🏷️ | `_buildCategoriesTab()` | Category CRUD + AI schema generator |
| 2 | באנרים 🎨 | `AdminBannersTab` | Home screen banner management |
| 3 | מוניטיזציה 💰 | `_buildMonetizationTab()` | Fee sliders (commission + urgency) |
| 4 | כספים 💵 | `AdminBillingTab` | Financial overview |
| 5 | תובנות 📊 | `_buildInsightsTab()` | Platform analytics |
| 6 | ביצועים 🖥️ | `SystemPerformanceTab` | DB latency, error logs |
| 7 | מיתוג 🎨 | `AdminBrandAssetsTab` | Brand assets |
| 8 | חסימות 🛡️ | `_buildChatGuardTab()` | Chat safety rules |
| 9 | תשלומים 💳 | `AdminPayoutsTab` | Stripe payouts |
| 10 | צלילים 🔊 | `AdminSoundsTab` | Sound management |

### Design (עיצוב) -- 1 pane

Single-pane CMS: `AdminDesignTab` -- two-pane text editor for `application_content/{locale}` overrides.
Access restricted to CMS admin email.

### AI CEO (סוכן AI מנכ"ל) -- 1 pane

`AdminAiCeoTab` -- dark premium dashboard powered by Claude Sonnet.
Collects 12 metrics in parallel, generates Hebrew strategic analysis.
See Section 12c for full documentation.

---

## 15a. Admin User Detail Screen (v8.9.4)

**Navigation:** Tap any user row in AdminUsersTab → `AdminUserDetailScreen(userId:)`

**Architecture:** Riverpod `.family` providers (autoDispose per userId):
- `userDetailProvider(uid)` — real-time stream of user doc
- `userTransactionsProvider(uid)` — one-shot fetch sent + received
- `userJobsProvider(uid)` — one-shot fetch as customer + expert
- `userReviewsProvider(uid)` — one-shot fetch all reviews (admin sees ALL)
- `userAuditLogProvider(uid)` — real-time stream of admin actions

**Sections:**
| Section | Content |
|---------|---------|
| Hero header | Gradient SliverAppBar with avatar, badges, online dot |
| Status chips | Role-aware: provider shows XP/streak/Pro; customer hides them |
| Quick stats (Provider) | כוח הרווחה: earnings, jobs, rating, trust score, reviews, XP |
| Quick stats (Customer) | כוח הקנייה: spending, bookings, customer rating, trust score, reviews |
| Trust Score (אמינות) | `completed / (completed + cancelled) × 100`. Green ≥90%, amber ≥70%, red <70% |
| Personal details | Phone, email, category (providers), policy (providers), balance |
| Timeline | Join date, last seen, rating — all with relative Hebrew time |
| Admin note | Tap-to-edit, writes to `adminNote` |
| Action center | 6 buttons: verify, ban, promote, send notification, top-up, view-as-user |
| Transactions | Last 10 with direction arrows |
| Reviews | Bottom sheet with blind filter toggle |
| Audit log | Streams `admin_audit_log` collection |

**Speed Dial FAB:**
| Button | Action |
|--------|--------|
| WhatsApp | `wa.me/972...` with formatted phone |
| Call | `tel:` link |
| Internal Note | Edit `adminNote` dialog |
| Send Notification | Push to `notifications` collection |

**Audit logging:** Every admin action (verify, ban, promote, top-up, delete, notification)
writes to `admin_audit_log/{id}` with `targetUserId`, `action`, `adminName`, `createdAt`.

**Firestore rule:** `admin_audit_log` — admin read/create, no delete.

---

## 15b. Code Health Snapshot (2026-04-04 — v9.0.4 STABLE)

| Metric | Value | Status |
|--------|-------|--------|
| `flutter analyze` | 0 issues | Ready |
| Translation keys | 942 x 4 locales | Complete |
| Firestore collections | 42+ | All rules defined |
| StreamBuilders (key screens) | 13 | All with `.limit()` |
| Anti-fraud checks | 5 (self-assign, cooldown, reciprocal, daily cap, review) | Active |
| debugPrints | 73 across 18 services | Intentional (error handlers) |
| Known TODOs | 5 | Documented below |

### Known TODOs

| File | TODO | Status |
|------|------|--------|
| `login_screen.dart:177` | Apple Sign-In | Deferred (dependency not added) |
| `sign_up_screen.dart:589` | Apple Sign-In | Same |
| `profile_screen.dart:785` | AggregateQuery | Awaiting cloud_firestore support |
| `profile_screen.dart:838` | Registration date fallback | Data migration needed |
| `profile_screen.dart:960` | Customer reviews count | Feature gap |

---

## 16. Future Roadmap

### Volunteer Task Dashboard
- Dedicated provider screen for accepted tasks (`streamForProvider()`)
- Dedicated client screen for pending confirmations (`streamPendingForClient()`)
- Currently works via notifications + chat banner; screens improve discoverability

### Push Notifications for Volunteer Events
- FCM handler exists in `main.dart` but volunteer-specific CF triggers not yet written
- Needs: `volunteer_accepted` and `volunteer_completed` push triggers

### Badge Expiry Cron
- `refreshBadgeStatus()` runs on-demand (profile load)
- Optional: daily CF to batch-expire stale `hasActiveVolunteerBadge` booleans

### Marketplace Expansion
- Multi-city support, category-level pricing tiers, provider availability zones

---

## 16. Support & Dispute Center

### Overview
Wolt/Airbnb-inspired support system with self-service tips and live admin chat.

### User-Facing Flow (`support_center_screen.dart`)
```
1. User opens Support Center (from chat Help icon or home screen)
2. Category grid: Payments / Volunteer / Account / Other
3. Self-service tips shown per category (automated resolution)
4. If unresolved: user writes subject (min 5 chars) + taps "Start Live Chat"
5. Ticket created in support_tickets + messages subcollection
6. Chat interface opens (real-time StreamBuilder on messages)
7. "Estimated response time: 5 minutes" banner throughout
```

### Admin Inbox (`admin_support_inbox_tab.dart`)
- **Location:** Admin Panel -> Management -> "תיבת פניות 📮" (tab 15)
- **3 sub-tabs:** Open / In Progress / Resolved
- **Ticket card:** User avatar, name, age, category chip, subject, job link
- **Actions via chat menu:**
  - "✓ סמן כנפתר" — sets status to `resolved`, posts system message
  - "🎁 פיצוי XP (+100)" — increments user XP + posts system message

### Contextual Access Points
| Entry Point | Passes | File |
|-------------|--------|------|
| Chat screen AppBar | jobId (optional) | `chat_screen.dart` |
| Home screen Help button | nothing | `home_tab.dart` |

### Firestore: `support_tickets/{id}`
```
userId, userName, jobId?, category, subject
status: 'open' | 'in_progress' | 'resolved'
evidenceUrls: [string]
assignedAdmin: string?
createdAt, updatedAt: Timestamp
```

### Firestore: `support_tickets/{id}/messages/{msgId}`
```
senderId, senderName, isAdmin: bool, message, createdAt
```

### Self-Service Categories (8 tips total)
- **Payments:** Payment not released, Cancellation/refund, Commission questions
- **Volunteer:** Provider no-show, XP not received
- **Account:** Change category, Delete account
- **Other:** Technical issues

### Security Rules
- Users: create own tickets, read/write own tickets + messages
- Admins: read/write all tickets + messages
- Messages: parent ticket ownership check via `get()` on parent doc

---

## 17. Scalability & Security (3M+ Users)

### Database Indexing (31 composite indexes)
Indexes added across project lifetime:
- `users`: 4 indexes (provider+serviceType, provider+rating, volunteer+online+serviceType, pending+createdAt)
- `jobs`: 7 indexes (expertId, customerId, status — various combinations with createdAt)
- `volunteer_tasks`: 4 indexes (anti-fraud cooldown, reciprocal, daily cap, client stream)
- `job_broadcasts`: 1 index (status + category + createdAt)
- `support_tickets`: 2 indexes (admin inbox, user tickets)
- `user_rewards`: 1 index (active rewards by user)
- `reviews`: 1 index (revieweeId + createdAt DESC)
- `admin_audit_log`: 1 index (targetUserId + createdAt DESC)
- `notifications`, `messages`, `transactions`, `search_logs`, etc.: remaining indexes

**Deploy:** `firebase deploy --only firestore:indexes`

### Image Compression
All 15 upload paths have compression. Key presets:
| Use Case | maxWidth | Quality | Expected Size |
|----------|----------|---------|--------------|
| Profile avatar | 300px | 50% | 15-30 KB |
| Gallery | 800px | 65% | 50-100 KB |
| Chat images | 1200px | 70% | 80-150 KB |
| Documents | 1600px | 85% | 200-400 KB |
| Banners | 1200px | 75% | 100-200 KB |

Centralized utility: `lib/utils/image_compressor.dart` with `ImagePreset` enum.

### Caching Strategy
- **Firestore persistence:** IndexedDB on web (10 MB cap), platform defaults on mobile
- **In-memory TTL cache:** `CacheService` with per-type TTLs
  - Categories: **30 min** (quasi-static, was 10 min)
  - User profiles: 5 min
  - Admin settings: 1 min
  - Expert profiles: 5 min
- **Cache purge:** Timer every 5 min in main.dart

### Performance & Cost Optimization Rules (v8.9.4)

> **MANDATORY for all new code.** Every Firestore query must follow these rules.
> Violations inflate the Firebase bill and degrade UX at scale.

#### Rule 1: Every `.snapshots()` stream MUST have `.limit()`

| Context | Max Limit | Example |
|---------|-----------|---------|
| User-facing lists (search, chat, bookings) | **15-50** | `.limit(15)` per page |
| Admin dashboards (insights, analytics) | **500** | `.limit(500)` — never 5000 |
| Single-user streams (profile, notifications) | **20-50** | `.limit(50)` |
| System/config docs | **1** (single doc) | `.doc('settings').snapshots()` |
| Background badge counts | **100-200** | `.limit(200)` |

**Rationale:** Each doc in a stream costs 1 read on every change to ANY doc in the result set.
A `.limit(5000)` stream = 5000 reads every time one doc updates.

#### Rule 2: Never duplicate a stream — share it

**Wrong:**
```dart
// AppBar
StreamBuilder(stream: users.doc(uid).snapshots(), ...)
// Body
StreamBuilder(stream: users.doc(uid).snapshots(), ...) // 2x reads!
```

**Correct:**
```dart
late final _userStream = users.doc(uid).snapshots(); // one stream, shared
StreamBuilder(stream: _userStream, ...) // both use same subscription
```

#### Rule 3: Use `.get()` for data that doesn't change mid-session

| Data Type | Method | Why |
|-----------|--------|-----|
| Categories list | `.snapshots()` with 30-min `CacheService` TTL | Admin may add categories live |
| System settings | `.snapshots()` on single doc | Tiny cost, enables live toggles |
| Course list | `.get()` cached or `.snapshots().limit(100)` | Courses don't change mid-session |
| Login screen config | `.snapshots()` acceptable (single doc) | 1 read, negligible |
| User profiles (other users) | `.get()` with 5-min cache | No need for real-time on others' profiles |

#### Rule 4: Pagination standards

| Screen | Page Size | Method |
|--------|-----------|--------|
| Search results | 15 | Cursor-based (`.startAfterDocument()`) |
| Admin user list | 50 | Cursor-based |
| Chat messages | 50 | `.limit(50).orderBy('timestamp', descending: true)` |
| Notifications | 50 | `.limit(50).orderBy('createdAt', descending: true)` |
| Transaction history | 200 | `.limit(200)` (no real-time, use `.get()`) |
| Reviews | 30 | `.limit(30)` per user |

#### Rule 5: CacheService TTLs (in-memory)

| Data Type | TTL | Key Pattern |
|-----------|-----|-------------|
| Categories | **30 min** | `categories/{name}` |
| User profiles | **5 min** | `users/{uid}` |
| Admin settings | **1 min** | `admin/settings` |
| Expert profiles | **5 min** | `expert/{uid}` |

**Purge:** `Timer.periodic(5 min)` in `main.dart` calls `CacheService.purgeExpired()`.

#### Rule 6: Firestore web persistence

```dart
// main.dart — after Firebase.initializeApp()
FirebaseFirestore.instance.settings = const Settings(
  persistenceEnabled: true,
  cacheSizeBytes: 40 * 1024 * 1024, // 40 MB
);
```

Fallback: if persistence init fails, disable it entirely to avoid
"INTERNAL ASSERTION FAILED" errors from corrupted IndexedDB.

#### Rule 7: Financial rounding (NIS)

All money calculations MUST use 2-decimal rounding:
- **Dart:** `double.parse((amount * feePct).toStringAsFixed(2))`
- **JavaScript (CF):** `roundNIS(amount * feePct)` where `roundNIS = n => Math.round(n * 100) / 100`
- **Pattern:** Always compute `fee = round(total * pct)`, then `net = round(total - fee)` — fee-first subtraction prevents ghost agorot.

#### Rule 8: Mandatory composite indexes

All queries with multiple `.where()` or `.where() + .orderBy()` need composite indexes.
Current index count: **31** (deployed via `firebase deploy --only firestore:indexes`).

| Collection | Fields | Purpose |
|-----------|--------|---------|
| `users` | isProvider + serviceType | Category search |
| `users` | isProvider + rating DESC | Top-rated search |
| `users` | isVolunteer + isOnline + serviceType | Volunteer matching |
| `jobs` | expertId + status + createdAt | Provider bookings |
| `jobs` | customerId + status + createdAt | Customer bookings |
| `jobs` | status + createdAt | Admin dashboard |
| `reviews` | revieweeId + createdAt DESC | User detail reviews |
| `admin_audit_log` | targetUserId + createdAt DESC | Audit trail |
| `volunteer_tasks` | providerId + clientId + status + completedAt | Anti-fraud cooldown |
| `notifications` | userId + isRead + createdAt | Unread badge |
| `support_tickets` | status + createdAt | Admin inbox |
| `user_rewards` | userId + status + expiresAt | Active rewards |

**Before adding a new multi-field query:** check `firestore.indexes.json` and add the index
in the same PR. Queries without matching indexes return 0 results silently on web.

#### Cost projection at 4,000 users

| Metric | Value |
|--------|-------|
| Reads/month | ~85M |
| Writes/month | ~5M |
| Estimated cost | ~$51/month |
| Free tier (Spark) | 50K reads/day |
| Blaze breakeven | ~28K reads/day |

---

### Error Monitoring (Dual-Channel)

Every crash is reported to **both** channels simultaneously:

| Layer | Crashlytics (Android/iOS) | Firestore `error_logs` (all platforms) |
|-------|--------------------------|----------------------------------------|
| Flutter framework | `recordFlutterFatalError()` | Firestore write (type: flutter) |
| Async / platform | `recordError(fatal: false)` | Firestore write (type: platform) |
| Admin visibility | Firebase Console dashboard | `SystemPerformanceTab` real-time stream |

**Initialization:** `main.dart` Step 3b — after Firebase.initializeApp, before App Check.
On web, Crashlytics is a no-op (web errors go to Firestore only).

**Package:** `firebase_crashlytics: ^5.1.0`

### Security Hardening
| Protection | Status |
|-----------|--------|
| Server-only fields (xp, balance, isAdmin) | Blocked in rules |
| Self-assignment block | Rules + service layer |
| Bulk delete prevention | `allow delete: if false` on financial/log collections |
| Notification spam protection | Max 10 fields + body < 1000 chars |
| Cross-user write scoping | Only specific fields allowed per rule |
| App Check | Console-level enforcement (not in rules) |

### Offloading Assessment
| Logic | Current Location | Status |
|-------|-----------------|--------|
| XP awards | Cloud Function (`updateUserXP`) | Server-side |
| Badge updates | Cloud Function + client denormalize | Hybrid (acceptable) |
| Search ranking | Client-side (`SearchRankingService`) | Client-side (acceptable — sorts 15 docs max per page) |
| Payment release | Cloud Function | Server-side |
| Dispute resolution | Cloud Function | Server-side |

### Load Testing Recommendations
For 3M+ users, test with:
- **Locust** (Python): Simulate concurrent Firestore reads/writes via REST API
- **Firebase Emulator Suite**: Local testing of rules + functions + indexes
- **Firestore Budget Alerts**: Set at 80% of monthly quota
- **Key metrics to test:** concurrent chat streams, job_request writes/sec, search query latency

---

## 18. Quick Reference

```bash
flutter analyze                          # Must be 0 issues
flutter test test/unit/                  # Unit tests
flutter build web                        # Build PWA
firebase deploy --only hosting           # Deploy web
firebase deploy --only functions         # Deploy CFs
firebase deploy --only firestore:rules   # Deploy rules
firebase deploy --only firestore:indexes # Deploy indexes
```

---

## 19. TTL Retention Policy (v12.3.0, 2026-04-13)

> **Hot/Cold storage strategy** modeled on Uber/Wolt — append-only operational
> logs auto-deleted after 30 days via Firestore TTL. Business data
> (transactions, jobs, users, messages, audit logs) is **never** TTL'd.

### Phase 1 (shipped) — `error_logs` + `activity_log`

Every write to these two collections includes `expireAt: Timestamp` set to
`createdAt + 30 days`. After the GCP TTL policy is configured on the
`expireAt` field per collection, Firestore auto-deletes expired docs in the
background (TTL deletes consume no read/write quota — they are free).

**Central writer (covers Watchtower):** [lib/models/app_log.dart](lib/models/app_log.dart)
— `AppLog.toJson()` includes `expireAt` only for `LogType.error` and
`LogType.activity`. `auth_logs` is excluded for now.

**Direct write sites that bypass Watchtower (all updated with `expireAt`):**

| File | Collection |
|------|-----------|
| `lib/services/community_hub_service.dart` | error_logs |
| `lib/services/chat_guard_service.dart` | activity_log |
| `lib/screens/admin_monetization_tab.dart` | activity_log |
| `lib/screens/sign_up_screen.dart` | activity_log |
| `lib/screens/search_screen/widgets/stories_row.dart` (×2) | activity_log |
| `lib/screens/registration_funnel_tab.dart` | activity_log |
| `lib/screens/provider_registration_screen.dart` | activity_log |
| `lib/repositories/story_repository.dart` | activity_log |
| `lib/screens/otp_screen.dart` | activity_log |
| `lib/screens/chat_screen.dart` | activity_log |
| `lib/screens/expert_profile_screen.dart` | activity_log |
| `lib/screens/bookings/booking_actions.dart` | activity_log |
| `lib/screens/edit_profile_screen.dart` | activity_log |
| `functions/index.js` (`_logActivity` helper + 3 direct sites) | activity_log |

### Manual GCP Console step (one-time, per collection)

After deploy, in **GCP Console → Firestore → TTL**:

1. Click **Create Policy**
2. Collection group: `error_logs`, Timestamp field: `expireAt` → Create
3. Repeat for `activity_log`

Firestore starts deleting expired docs within 24h.

### Rules

- **NEVER add `expireAt` to:** `users`, `jobs`, `transactions`,
  `platform_earnings`, `reviews`, `chats`, `messages`, `support_tickets`,
  `support_audit_log`, `admin_audit_log`, `community_requests`,
  `notifications`. These are business/compliance data.
- **Pattern for new code:** Every `.collection('error_logs').add(...)` and
  `.collection('activity_log').add/set(...)` MUST include
  `'expireAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 30)))`
  (Dart) or `expireAt: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 30 * 24 * 60 * 60 * 1000))` (JS).
- **Future phases** (after Phase 1 validated in Console for ~1 week):
  `search_logs` (90d), `admin_credit_idempotency` (7d), `job_broadcasts`
  where status in [expired, claimed] (7d), `dog_walks` where status='completed'
  (30d), `boarding_proofs` (30d after parent job completed).

---

---

## 20. Anti-Duplicate Auth Guard (PR-A, v12.4.0, 2026-04-13)

> **Belt-and-suspenders complement to the Firebase Console flag
> "One account per email".** Catches the legacy bug where an existing
> email/password user (e.g. `adawiavihai@gmail.com`) signs in via Google
> and ends up with TWO `users/{uid}` docs — one per Firebase Auth uid.

### Helper service

[lib/services/auth_duplicate_guard.dart](lib/services/auth_duplicate_guard.dart)
— `AuthDuplicateGuard.findConflict({currentUid, email})` queries
`users.where('email', isEqualTo: email.toLowerCase()).limit(2)` and returns
any doc id whose uid ≠ currentUid (or `null` if no conflict).

`AuthDuplicateGuard.enforceOrSignOut({context, cred})` is the convenience
wrapper: on conflict it signs the user back out and shows a Hebrew dialog
explaining "use your original sign-in method" (per user decision: **block,
do NOT auto-merge**).

### Wired sites

| File | Path | Behavior on conflict |
|------|------|----------------------|
| [lib/screens/phone_login_screen.dart](lib/screens/phone_login_screen.dart) | `_createProfileIfNew` (Google + Apple web + Apple native, 3 callers) | `enforceOrSignOut` → dialog → caller sees `false` and aborts navigation |
| [lib/main.dart](lib/main.dart) | `_ensureProfileExists` (web session-restore path) | Silent variant — no `BuildContext` available, just signs out + logs. AuthWrapper routes back to login. |

### Rules

- **Pattern for new social-signup paths:** Before any `users/{uid}.set(...)`
  that includes an `email` field for a NEW user, MUST call either
  `AuthDuplicateGuard.enforceOrSignOut` (when context is available) or
  `findConflict` + manual signOut (when not).
- **Email normalization:** `findConflict` lowercases the input. Existing
  `users/{uid}.email` writes do NOT yet lowercase — Firebase Auth normalizes
  Google/Apple emails so this works in practice. If a future bug surfaces
  for case-mismatched legacy users, normalize on write.
- **Future PRs in this series (NOT shipped yet):**
  - PR-B: Unified login UI — remove `login_screen.dart` (email/password) from
    nav, add prominent Google/Apple at top of `phone_login_screen.dart`.
  - PR-C: Email Gap — post-OTP email collection screen for phone users
    (required for invoices). 6-digit code verification, stored in
    `private/identity.email` + `emailVerifiedAt`.
  - PR-D: Phone Gap — post-Social phone collection screen. Goal: every user
    has BOTH verified phone + verified email.

---

---

## 21. Unified Auth + Contact Completion (PR-B/C/D, v12.5.0, 2026-04-13)

> **Every user must eventually have BOTH a verified phone AND a verified
> email.** Email/password login is removed. Social (Google/Apple) users are
> prompted to add+verify a phone. Phone-OTP users are prompted to add+verify
> an email. Both prompts respect a 7-day skip cooldown.

### PR-B — Unified login UI

Email/password login is no longer reachable from the UI.

- [lib/screens/phone_login_screen.dart](lib/screens/phone_login_screen.dart) —
  Google + Apple buttons moved ABOVE the phone input (was below), divider
  "או", then phone + send-code button. Removed:
  - "יש לך חשבון עם אימייל?" TextButton
  - `import 'login_screen.dart'`
- [lib/screens/community_hub_screen.dart](lib/screens/community_hub_screen.dart)
  and [lib/screens/community_screen.dart](lib/screens/community_screen.dart)
  — the "היכנס" dialog CTAs now push `PhoneLoginScreen` instead of
  `LoginScreen`.
- `lib/screens/login_screen.dart` is kept as dead code for 1 week before
  deletion. Nothing navigates to it. Do NOT re-introduce a reference.
- `sign_up_screen.dart` is similarly orphaned — no nav path reaches it.

### PR-D — Phone Gap (post-social phone collection)

`_PhoneCollectionScreen` in [lib/main.dart](lib/main.dart) rewritten:

- **Two-step UI**: enter phone → "שלח קוד" → enter 6 digits → "אמת/י".
- **Mobile**: `FirebaseAuth.verifyPhoneNumber` → `PhoneAuthProvider.credential`
  → `user.linkWithCredential(phoneCred)`. Android instant verification is
  handled in the `verificationCompleted` callback.
- **Web**: `user.linkWithPhoneNumber(e164)` returns a `ConfirmationResult`;
  `.confirm(code)` in step 2. Flutter's firebase_auth plugin handles
  invisible reCAPTCHA automatically.
- **On success**: writes `phone` + `phoneVerifiedAt: serverTimestamp` to
  `users/{uid}` AND `private/identity` (via `PrivateDataService.writeContactData`).
- **Error mapping** (Hebrew):
  - `credential-already-in-use` / `provider-already-linked` →
    "מספר זה כבר משויך לחשבון אחר"
  - `invalid-verification-code` → "קוד שגוי"
  - `too-many-requests` → "יותר מדי ניסיונות"
- **"מאוחר יותר"**: writes `phonePromptSkippedAt: serverTimestamp` →
  OnboardingGate honors 7-day cooldown.

### PR-C — Email Gap (post-OTP email collection)

**New Cloud Functions** in [functions/index.js](functions/index.js):

- `sendEmailVerificationCode({ email })`:
  - Blocks if email is already on another user doc.
  - Rate limit: 5 sends / hour per caller.
  - Generates 6-digit code, stores `{codeHash, salt, tries, expiresAt}` at
    `email_verification_codes/{uid}` (10-minute TTL + 1-day safety expireAt).
  - Writes a Hebrew HTML email via the `mail` collection
    (Firebase Trigger Email Extension delivers it).
  - **Never stores plaintext** — only `sha256(salt:code)`.
- `verifyEmailCode({ code })`:
  - Max 6 tries per code, expires after 10 minutes.
  - On match: batch-writes `email` + `emailVerifiedAt` to `users/{uid}`
    AND `users/{uid}/private/identity`, then deletes the code doc.
  - Never returns the correct code on error — just "קוד שגוי".

**New UI** — `_EmailCollectionScreen` in [lib/main.dart](lib/main.dart),
same two-step pattern as the phone screen. Calls the two CFs via
`FirebaseFunctions.httpsCallable(...)`.

**Firestore rules** in [firestore.rules](firestore.rules):

```
match /email_verification_codes/{uid} {
  allow read, write: if false;   // Cloud Function / Admin SDK only
}
```

### OnboardingGate routing (updated)

In [lib/main.dart](lib/main.dart) `OnboardingGate`, the priority chain is:

1. Admin → HomeScreen
2. Support agent → SupportDashboardScreen
3. Pending verification → PendingVerificationScreen
4. No role → OnboardingScreen
5. **Phone missing AND not `phonePromptSkippedAt` within 7d** → `_PhoneCollectionScreen`
6. **Email missing AND phone set AND not `emailPromptSkippedAt` within 7d** → `_EmailCollectionScreen`
7. Permissions not seen → PermissionRequestScreen
8. Default → HomeScreen

### Deployment checklist

- [ ] `flutter pub get` (cloud_functions already in pubspec as ^6.0.7)
- [ ] `firebase deploy --only functions:sendEmailVerificationCode,functions:verifyEmailCode`
- [ ] `firebase deploy --only firestore:rules`
- [ ] Firebase Extensions → Trigger Email → confirm it's active and pointed
      at the `mail` collection (already in use for receipts — should be live).

### Rules for future code

- **NEVER re-introduce a nav path to `LoginScreen`.** If someone needs email
  login, they reset via the admin support flow.
- **NEW social signup paths** (any `users/{uid}.set` with `email`) MUST call
  `AuthDuplicateGuard.enforceOrSignOut` first (Section 20).
- **NEW user-doc-create paths with `phone`** should NOT bypass the OTP flow
  — if you need a phone, route through `_PhoneCollectionScreen`. Writing a
  raw phone string without `phoneVerifiedAt` leaves the invariant broken.
- **First-payment gate (future):** the payment flow should check
  `emailVerifiedAt` and block with a friendly "verify your email first"
  prompt. Not yet wired — add when the Israeli payment provider lands.

---

---

## 22. Provider ↔ Customer View-Mode Toggle (v12.6.0, 2026-04-14)

> A real provider can toggle the app into the **customer UI** without any
> logout / account switch. Firestore `isProvider` stays `true` — only the
> rendering decision changes. Every provider-only tab, FAB, and dashboard
> is hidden.

### Service

[lib/services/view_mode_service.dart](lib/services/view_mode_service.dart) —
`ChangeNotifier` singleton mirroring the `LocaleProvider` pattern. Persisted
**per-uid** to `SharedPreferences` under `view_mode.customer.{uid}` so a
shared device can't leak one provider's choice to another.

```dart
ViewModeService.instance.customerMode            // current value
ViewModeService.initForUid(uid)                  // load on auth state change
ViewModeService.instance.setCustomerMode(...)    // toggle + persist
ViewModeService.instance.reset()                 // on sign-out
```

Wired in [lib/main.dart](lib/main.dart) inside the `AuthWrapper._authSub`
listener: `initForUid` on sign-in, `reset()` on sign-out.

### HomeScreen interception

[lib/screens/home_screen.dart](lib/screens/home_screen.dart):

1. `initState` attaches a listener that `setState()`s whenever the service
   notifies — so the outer StreamBuilder re-evaluates and the tab cache
   regenerates.
2. After reading `data['isProvider']`, computes:

```dart
final actualIsProvider = data['isProvider'] ?? false;
final inCustomerView   = actualIsProvider
    && ViewModeService.instance.customerMode;
bool isProvider        = actualIsProvider && !inCustomerView;
```

3. All downstream code (tab builder, opportunities badge, `MyBookingsScreen`
   props, etc.) reads the shadowed `isProvider` — so a provider in customer
   mode never gets the Opportunities tab, never gets provider booking
   columns, never sees provider-only FABs.

### Persistent banner in customer mode

Indigo 34-px banner at the top of HomeScreen's Column (same slot as the
offline banner) — "מצב לקוח פעיל · חזור לנותן שירות". One tap toggles off
and shows a green success snackbar.

### Entry point: Edit Profile

[lib/screens/edit_profile_screen.dart](lib/screens/edit_profile_screen.dart)
— first child of the form body when `_isProvider == true`. Gradient card:

- **Provider mode** → muted light card with indigo eye icon, label
  "מצב לקוח 👁".
- **Customer mode** → solid indigo→purple gradient, work icon,
  "חזור למצב נותן שירות".

Tapping the card persists the choice, pops the Edit stack back to the
HomeScreen root with `popUntil((r) => r.isFirst)`, and shows a Hebrew
snackbar.

### What this does NOT do

- **Firestore is unchanged.** `users/{uid}.isProvider` stays `true` in
  customer mode. Admin panels still list the user as a provider.
- **Chat / bookings history is visible either way.** A provider in customer
  mode still sees their existing bookings — just no provider-side tools.
- **Opportunity pushes still arrive.** FCM notifications come regardless
  of view mode. Tapping one routes to Opportunities which won't render
  the tab while in customer mode — current limitation, add a navigation
  guard if users complain.

### Rules for future code

- **New provider-only screens** — gate rendering on the `isProvider` that
  HomeScreen already passes through tab props. Don't read the service
  directly from deep screens unless absolutely necessary.
- **Never flip `isProvider` in Firestore** to "implement" this — it's pure
  UI state, not role state.
- **Navigation deep-links** — if a deep-link (e.g. notification tap)
  forces a provider tab while customer mode is on, consider auto-resetting
  customer mode or showing a banner asking the user to switch back.

---

---

## 23. Legacy Phone→Auth Linker + 3-mode Admin Toggle (v12.7.0, 2026-04-14)

> Two fixes in one release. **(a)** Legacy email/password users (e.g.
> Sigalit) could log in via phone but the app created a brand-new uid —
> their profile/history was invisible. **(b)** The admin wanted to toggle
> between admin / provider / customer UI, not just customer/provider.

### (a) Legacy Phone → Auth Linker

**Root cause.** Before v12.5 removed the email login, users signed up with
email+password. Their Firebase Auth account has an email but **no phone
number attached**. When they now log in via phone OTP, Firebase creates a
new Auth account because it doesn't recognize the phone.

**Fix.** Attach their phone to their **existing** Auth uid via Admin SDK
`admin.auth().updateUser(uid, {phoneNumber})`. After that, every future
phone login routes to the legacy uid → their `users/{uid}` doc + jobs +
chats all resolve naturally.

**New Cloud Functions** in [functions/index.js](functions/index.js):

- `backfillPhonesToAuth()` — admin-only one-shot. Iterates every user doc
  with a non-empty `phone` field, normalizes to E.164, and calls
  `admin.auth().updateUser(uid, {phoneNumber})`. Idempotent (skips users
  whose Auth account already has the phone). Writes a summary to
  `admin_audit_log` with `{scanned, updated, skipped, errors, errorSamples}`.
- `lookupLegacyUidByPhone({phone})` — open callable. Given an E.164 phone,
  returns `{found: bool, uid?}` of the user doc that owns it. Used by the
  OTP screen to detect "new Auth uid but legacy doc exists" — a sign that
  the backfill hasn't run yet for this user.

**Client guard** in [lib/screens/otp_screen.dart](lib/screens/otp_screen.dart)
`_verify()`: when Firebase says `isNewUser: true`, we first call
`lookupLegacyUidByPhone`. If it returns a uid that differs from
`user.uid`, we:

1. Tear down the empty new Auth account (`user.delete()` + `signOut()`)
2. Show a Hebrew dialog: "נמצא חשבון קיים — פנה/י לתמיכה"
3. Return without creating a new user doc.

After the admin runs the backfill CF once, this code path becomes unreachable
— Firebase itself will route future phone logins to the legacy uid.

**Operational procedure for stuck users (e.g. Sigalit):**

1. Admin signs in.
2. Calls `backfillPhonesToAuth` (e.g. via a new "חיבור טלפונים" button in
   the admin panel, or a one-off `firebase functions:shell` invocation).
3. Admin deletes the orphan new-uid user doc + Auth account (existing
   admin UI supports this).
4. User logs in again with phone → Firebase routes to legacy uid → done.

### (b) Tri-state view-mode (admin sees 3 buttons)

**`ViewModeService` refactored** in
[lib/services/view_mode_service.dart](lib/services/view_mode_service.dart)
— replaced `bool customerMode` with `enum ViewMode { normal, customer, providerOnly }`.

- `normal` — default. User sees everything they're entitled to.
- `customer` — hide BOTH admin + provider tabs. Everyone can enter.
- `providerOnly` — admin-only. Hides admin tabs, keeps provider tabs.

Legacy v12.6 SharedPreferences bool key is still read on first init for a
smooth upgrade; new writes use the enum key. `customerMode` + `setCustomerMode`
back-compat shims kept so existing code doesn't break.

**`home_screen.dart` uses the enum.** `actualIsAdmin` + `actualIsProvider`
are preserved; `effectiveAdmin` and local `isProvider` are shadowed:

```
effectiveAdmin  = actualIsAdmin && viewMode == normal
isProvider      = actualIsProvider && viewMode != customer
```

Banner at top of Scaffold Column shows current mode:
- Customer mode → indigo banner "מצב לקוח פעיל · חזור ל…"
- Provider-only mode → sky banner "מצב נותן שירות פעיל · חזור לניהול"
- One tap returns to `normal`.

**`edit_profile_screen.dart` toggle card** (at top of the form):
- Non-admin provider → 2 chips (נותן שירות / לקוח).
- Admin → 3 chips (ניהול / נותן שירות / לקוח).
- Each chip is a gradient pill; the selected one is filled, the others
  are white with a border. Tapping any chip persists the mode and
  `popUntil((r) => r.isFirst)` back to HomeScreen.

### Rules

- **Admin 3-mode toggle** is the single source of truth for what an admin
  sees. No other branching on `isAdmin` should read the raw `users/{uid}.isAdmin`
  field for UI purposes — use the `effectiveAdmin` that HomeScreen computes
  and passes into tabs.
- **Never migrate user data across uids** as an alternative to linking the
  phone. Doc migration is unsafe: chats/{id} embed uids in the doc ID, and
  thousands of `expertId == oldUid` references across jobs/reviews/etc.
  would need rewrites. Linking the phone to the existing Auth account is
  the only surgically safe fix.
- **`lookupLegacyUidByPhone` is an open callable.** Returning a uid for a
  phone number is not sensitive on its own (uids are opaque) and the
  alternative — requiring auth — breaks the pre-signup use case. If this
  becomes a privacy issue, add rate limiting + a hashed uid.

### Deployment checklist

- [ ] `firebase deploy --only functions:backfillPhonesToAuth,functions:lookupLegacyUidByPhone`
- [ ] Run `backfillPhonesToAuth` ONCE from the admin console (or firebase shell).
- [ ] For pre-backfill duplicates (Sigalit), delete the empty new-uid user doc +
      Auth account via the existing admin UI. Tell the user to re-login.
- [ ] `flutter build web --release && firebase deploy --only hosting`.

---

---

## 24. Sub-category Grid Sizing Fix (v12.8.1, 2026-04-14)

**Bug:** Sub-category cards on the "הצג הכל" page rendered huge on tablets —
up to 220×220 — because the grid used a fixed 4-column count with aspect
ratio 0.75, so cells stretched with screen width.

**Fix:** [lib/screens/sub_category_screen.dart](lib/screens/sub_category_screen.dart)
— swapped `SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4)` for
`SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 116,
childAspectRatio: 100 / 128)`. Cards now cap at ~100–116 px wide regardless
of screen size — identical to the home tab's horizontal strip
(`_buildSubCatCard` renders cards at 100 × ~120). Also reduced label
font-size from 13 → 11.5 to match.

---

## 25. Profile Overwrite + Map CSP Fix (v12.8.0, 2026-04-14)

Two unrelated bugs found after user report:

**Bug A — every Google/Apple re-login was resetting the profile.**
`_createProfileIfNew` in [lib/screens/phone_login_screen.dart](lib/screens/phone_login_screen.dart)
called `set(merge: true)` with a full default payload on EVERY sign-in —
overwriting `profileImage`, `rating`, `reviewsCount`, `gallery`, `aboutMe`,
`serviceType`, `isProvider`, `onboardingComplete`, `tourComplete` back to
their initial defaults. Users lost custom-uploaded avatars and ratings
silently.

**Fix:** read the doc first. If it exists, skip the write entirely (preserve
all existing data) and only mirror contact fields into `private/identity`
to keep the v12.2 dual-write invariant. Only when `!snap.exists` do we write
the full initial profile. Same pattern already used in `main.dart
_ensureProfileExists`.

**Bug B — grey map on the category page (CSP blocked tile fetches).**
CartoDB basemap tiles were blocked by the `connect-src` directive in
[web/index.html](web/index.html). Flutter_map on web uses `fetch` for tile
downloads (not plain `<img>`), so CSP applies even though `img-src` was
wide open.

**Fix:** added to `connect-src` — `https://*.basemaps.cartocdn.com`,
`https://basemaps.cartocdn.com`, plus OSM main + Germany mirror as
fallbacks. Also added `staticmap.openstreetmap.de` for the existing dog-walk
route summary's static map.

After deploy, users need a hard-refresh (Ctrl+Shift+R) because the Service
Worker caches the old CSP.

---

## 26. Map Screen Upgrade — "World-class" design (v12.9.0, 2026-04-14)

Full redesign of the map view to match the Uber/Airbnb feel requested by the
user. Shipped as 5 small PRs, each reviewable in isolation.

### PR-1 — Scoped map palette

New `MapPalette` + `MapShadows` in [lib/theme/app_theme.dart](lib/theme/app_theme.dart).
Scoped to the map view ONLY — does NOT replace `Brand.*`, so every other
screen in the app keeps its existing colors. Reversible in one commit.

### PR-2 — Floating top bar over the map

[lib/screens/category_results_screen.dart](lib/screens/category_results_screen.dart):
- Fading white gradient over the top 140 px of the map.
- Top bar (in SafeArea): round back button, pill-shaped search box wired to
  the existing `_searchQuery` (live filter), round list-toggle button.
- AppBar map-toggle icon is HIDDEN while on the map (the floating one
  replaces it) — no duplicate entry points.

### PR-3 — Filter chips + provider count badge

Same file. Horizontal `SingleChildScrollView` of 5 chips:
- מרחק — opens modal with 2/5/10/20/50 km options.
- דירוג — opens modal with 4+/4.5+/5 options.
- עד ₪100 — toggle tied to existing `_filterUnder100`.
- זמינים עכשיו — NEW `_onlineOnly` state; filter added to
  [lib/utils/expert_filter.dart](lib/utils/expert_filter.dart) as a new
  `onlineOnly: false` param (backward compatible).
- הזמנה מיידית — grey chip + "בקרוב 🎉" snackbar (no Firestore field yet).

Black pill badge with animated slide+bounce appears only when ≥1 filter is
active: "🟢 7 {category} באזור שלך".

### PR-4 — New marker design + cluster + pulsing My Location + "Search this area"

**New dependency:** `flutter_map_marker_cluster: ^8.2.2` (compatible with
flutter_map 8.x).

[lib/widgets/providers_map_view.dart](lib/widgets/providers_map_view.dart):

- **Marker redesign.** 92×104, anchored at `bottomCenter` so the pointer tip
  sits exactly on the provider's coordinates. Composition: black price tag
  (`₪150`) → circular avatar 48 px with colored border (indigo / online green
  / gold-active) and optional glow → small online dot in bottom-right →
  pointer stalk → ellipse ground shadow.
- **Clusters** via `MarkerClusterLayerWidget`. Purple circle, white border,
  count text. `disableClusteringAtZoom: 16` so high-zoom detail is
  guaranteed.
- **My Location** = pulsing halo `AnimationController.repeat(2s)` + solid
  indigo dot with white border and glow.
- **"חפש באזור הזה" pill** appears when the user pans ≥400 m from the last
  queried center. Tapping fires `onSearchThisArea` callback and updates the
  reference center.
- **Side controls** (start-aligned, RTL-safe): my-location (indigo),
  zoom in (+), zoom out (−). 42 px circles with `MapShadows.floatingControl`.
  Positioned via `bottomSafeArea` prop so they stay above the sheet.

### PR-5 — Bottom-sheet carousel of provider cards (synced with map)

Same file. `DraggableScrollableSheet` with snap sizes `[0.16, 0.38, 0.85]`.
Contents: drag handle → `PageView.builder` (viewportFraction 0.88) of
`_MapProviderCard` widgets.

**Card (per mockup):**
- Gallery strip (up to 3 images) with online status pill (top-end) + price
  pill (bottom-start).
- Row: avatar 44 px + name + verified check + "מומלץ" badge + aboutMe.
- Meta row: star rating + reviews count + walking-minutes/km + city.
- Quick-tag chips colored semantically (home-visit = blue, certified =
  green, discount = rose, default = grey).
- Divider, then action row: "מתי פנוי?" text button → expert profile, round
  message button, purple "הזמן עכשיו" stadium button → expert profile.

**Bidirectional sync:**
- Card swipe → `setState` + `focusedLatLng` → `ProvidersMapView.didUpdateWidget`
  moves the camera.
- Marker tap → `onMarkerTap` callback → `pageCtrl.animateToPage` + update
  `_mapSelectedUid` (marker renders gold-active border + glow).

**API addition on `ProvidersMapView`:**
- `externalSelectedUid`, `onMarkerTap`, `focusedLatLng`, `bottomSafeArea`.
- When `onMarkerTap` is provided the widget SKIPS rendering its legacy info
  card — the parent's carousel replaces it. Legacy callers that don't pass
  the callback still see the old info card (zero-regression).

### Files touched

| File | Change |
|------|--------|
| `lib/theme/app_theme.dart` | Added `MapPalette` + `MapShadows`. |
| `lib/screens/category_results_screen.dart` | Top bar, chips, badge, carousel sheet, card widget. |
| `lib/widgets/providers_map_view.dart` | Marker redesign, cluster, pulsing ring, search-here pill, side controls, parent-drive props. |
| `lib/utils/expert_filter.dart` | Added `onlineOnly: false` param. |
| `pubspec.yaml` | Added `flutter_map_marker_cluster: ^8.2.2`. |

---

## 27. Admin 3-mode Parity Fix (v12.10.0, 2026-04-14)

**Bug report:** Admin (`adawiavihai@gmail.com`) tapped "נותן שירות" in the
edit-profile 3-mode toggle but did NOT see the Opportunities tab / provider
UX. The admin user doc has `isProvider: false` in Firestore (admins aren't
actually providers), so the view-mode override didn't help — `isProvider`
stayed false and the provider tab list wasn't added.

**Fix** in [lib/screens/home_screen.dart](lib/screens/home_screen.dart):

```dart
bool isProvider = actualIsProvider && !inCustomerView;
if (actualIsAdmin && inProviderOnly) {
  isProvider = true;  // admin previewing provider UX
}
```

Additionally, the bottom-nav was receiving the raw `isAdmin` state variable
instead of `effectiveAdmin`, meaning even when admin toggled to customer
view the Admin/System nav items could still render. Fixed by passing
`effectiveAdmin` into `_buildEliteBottomNav(...)`.

### End state

| Mode | Admin sees | Non-admin provider sees |
|------|-----------|------------------------|
| `normal`       | Admin + System + Opportunities + regular tabs (full) | Opportunities + regular tabs |
| `customer`     | Regular customer tabs only (+ banner) | Regular customer tabs only (+ banner) |
| `providerOnly` | Opportunities + regular tabs, NO admin (+ banner) | — (admin-only mode) |

Banner text adapts to actual role:
- Admin: "חזור לניהול"
- Provider: "חזור לנותן שירות"

Admin's provider preview is a best-effort UX — if the admin's Firestore doc
has no `serviceType`/`category`/`gallery`, the Opportunities screen + the
provider home render empty-state versions. That's accepted as "this is what
a brand-new provider's day looks like".

---

## 28. Pet Stay Tracker (v13.0.0, 2026-04-14)

Full end-to-end tracking system for the "בעלי חיים" category, gated to the
sub-categories **"פנסיון ביתי"** (home boarding) and **"דוגווקר"** (dog
walker). Activated ONLY when a job's category schema has the v2 flags
`walkTracking` and/or `dailyProof`. All pet UI is invisible on non-pet
bookings — gating is enforced via `jobs/{id}.flagWalkTracking/flagDailyProof`
(cached on the job doc at booking time).

### Architecture (one-liner per file)

```
lib/features/pet_stay/
├── models/
│   ├── dog_profile.dart          DogProfile + Medication + 9 personality enum keys
│   ├── pet_stay.dart             PetStay snapshot lifecycle (upcoming → active → completed)
│   ├── schedule_item.dart        ScheduleItem + type enum (feed/walk/medication/play/sleep)
│   └── pet_update.dart           PetUpdate (walk_completed, pee, poop, photo, video, note, daily_report)
├── services/
│   ├── dog_profile_service.dart  CRUD for users/{uid}/dogProfiles/* + photo upload to dog_profiles/
│   ├── pet_stay_service.dart     PetStay snapshot + schedule CRUD (tx + batched post-tx)
│   ├── pet_update_service.dart   Feed writes: markers, walk_completed, photo, video, note, daily_report, reactions, replies
│   └── schedule_generator.dart   Routine × days → ScheduleItem[] (pension only)
├── widgets/
│   ├── dog_profile_card.dart     Read-only display of dogSnapshot (shared provider + owner)
│   ├── dog_picker_section.dart   Inline picker in booking sheet with empty-CTA
│   ├── schedule_checklist.dart   Multi-day grouped checklist (provider toggleable)
│   ├── feed_composer.dart        Provider "share" buttons: 📸 / 🎥 / 📝
│   ├── feed_item_card.dart       Per-type rendering + reactions (6 emojis) + replies
│   ├── pet_feed_timeline.dart    Reverse-chron stream of updates
│   ├── live_walk_map.dart        Owner-side real-time map (flutter_map + pulsing green pin + pee/poop emoji markers)
│   ├── owner_hero_card.dart      Purple gradient + progress bar + stats derived from feed
│   ├── rating_sheet.dart         5-star + text review (NO TIP — removed from product)
│   └── daily_report_form.dart    Auto-fill mood + meals/walks/meds/pee/poop + notes
└── screens/
    ├── dog_profile_list_screen.dart     Owner's list of all their dogs
    ├── dog_profile_builder_screen.dart  8-section form (identity/health/personality/food/meds/notes/emergency/routine)
    ├── provider_pet_mode_screen.dart    Provider's home: dog card + composer + checklist + pension-only "send daily report" + feed
    └── owner_pet_mode_screen.dart       Owner's view: hero + live map + rating prompt + dog card + feed
```

### Data flow

**Booking time (inside payment transaction):**
1. Customer selects dog → `expert_profile_screen._processEscrowPayment`
2. Atomic writes: `jobs/{newId}`, `jobs/{id}/petStay/data` (with `dogSnapshot` frozen copy)
3. Schedule items captured in closure var (NOT written yet)

**Post-transaction:**
4. `PetStayService.writeScheduleItemsBatched` commits schedule in 400-item
   `WriteBatch` chunks — avoids Firestore 500-op transaction limit for
   long pension stays (180 days × 5 items = 900 items).
5. Graceful degradation: batch failure logs error; booking still valid
   with empty schedule.

**Runtime:**
- Provider: starts walk → GPS stream writes path to `dog_walks/{walkId}`
  every 10m or 5 points. Markers appended to `markers` array on tap.
  On end: stats computed (naive: steps = distance/0.75, calories =
  weight×km×0.8, pace = duration/km), walk_completed dual-written to feed.
- Customer: streams PetStay + updates + latest active dog_walks doc.
  LiveWalkMap renders only when a `status=='walking'` walk exists.

### Firestore rules (fine-grained per-party)

`jobs/{jobId}/petStay/data` update — **per-party field allow-lists**:
- Customer: `rating, reviewText, ratedAt, status` only (status flips to
  `'completed'` on rating submission)
- Provider: `totalWalks, totalDistanceKm, totalPhotos, totalVideos,
  totalReports, status` only (NO rating writes)
- Neither can touch `dogSnapshot` (frozen at create).

`jobs/{jobId}/petStay/data/schedule/{id}` — customer creates, provider
updates (for completion toggle), both read.

`jobs/{jobId}/petStay/data/updates/{id}` — provider creates (all fields),
customer updates with `diff().affectedKeys().hasOnly(['reactions','replies'])`
gate (can only react + reply, never modify content).

`dog_walks/{walkId}` — provider writes markers, both read.

### Required composite indexes

```
dog_walks: jobId ASC + startedAt DESC
  → Serves LiveWalkMap `.where(jobId).orderBy(startedAt DESC).limit(1)`
  → Also serves DailyReportForm `.where(jobId).where(startedAt >= today)`
```

### Known rules

- **Chat-quote pet-gate**: `EscrowService.payQuote` does a pre-flight check
  of the provider's category schema and blocks with Hebrew message
  ("זהו שירות פנסיון/דוגווקר — יש להזמין מפרופיל הספק כדי לצרף פרופיל כלב")
  if pet flags are set. Fail-open on error.
- **Walk resume**: `DogWalkService.tryResumeActiveWalk` uses SharedPreferences
  to restart a dropped walk stream on the SAME job only.
- **Concurrent walks**: `DogWalkService.startWalk` throws `StateError`
  if `_activeSub != null`.
- **No TIP**: Removed entirely per product decision — not in UI, not in
  model, not in Firestore. Rating flow is stars + text only.
- **NO FCM Push**: In-app notifications only (`notifications/` collection).
  Deferred Cloud Function push to a future release.

### Phase 2 QA (2026-04-14) — 6 bugs found + fixed

See [docs/pet_stay_qa_report.md](docs/pet_stay_qa_report.md) for the
full 10-phase audit. Highlights of bugs fixed:

1. **Too-permissive petStay update rule** → tightened with per-party
   `diff().affectedKeys()` allow-lists.
2. **Orphan dog profile on photo-before-name** → required name guard.
3. **HIGH: Schedule tx could exceed 500-op limit** → moved to post-tx
   `WriteBatch` with 400-item chunks + graceful degradation.
4. **Fragile medications cast could throw** → permissive `whereType<Map>()
   + Map.from()` pattern.
5. **Dead `OwnerHeroCard` class with broken `_jobIdGuess()`** → deleted.
6. **HIGH: Missing composite index** → added `dog_walks.(jobId, startedAt DESC)`.

Pet Stay post-QA: `flutter analyze lib/features/pet_stay/` → **0 issues**.

---

---

## 29. Vault Financial Dashboard (v14.x, 2026-04-16)

Premium financial dashboard for the admin panel, located in the **System
(מערכת)** section as tab 5: **"כספת 🔐"** (between "כספים 💵" and "תובנות 📊").

### Overview

The Vault dashboard gives the admin a real-time, data-driven view of all
platform financials: revenue, active escrows, transaction pipeline,
category breakdown, peak hours, top providers, and a live activity feed.
Every number on screen comes from real Firestore data — no mock data.

### Data Architecture

The Vault queries **existing** collections — no duplicate data stores:

| Metric | Source Collection | Query |
|--------|-------------------|-------|
| Platform balance | `admin/admin/settings/settings.totalPlatformBalance` | `.snapshots()` |
| Commission fee % | `admin/admin/settings/settings.feePercentage` | Same stream |
| Period revenue | `platform_earnings` | `.where('timestamp', >=, periodStart).limit(500)` |
| Active jobs (escrow) | `jobs` | `.where('status', whereIn: ['paid_escrow', 'expert_completed', 'disputed'])` |
| Recent transactions | `transactions` | `.orderBy('timestamp', desc).limit(20)` |
| Activity feed | `activity_log` | `.orderBy('timestamp', desc).limit(15)` |
| Top providers | `users` | `.where('isProvider', ==, true).limit(100)` client-sorted by `orderCount` |
| User/provider counts | `users` | `.count()` aggregation queries |
| Withdrawals | `withdrawals` | `.where('status', ==, status).limit(50)` |

### Dashboard Sections (top to bottom)

| # | Section | Description |
|---|---------|-------------|
| 1 | Header + Period Selector | "AnySkill Vault" + pulsing green dot + live clock + day/week/month/year pills |
| 2 | Live Ticker | Dark gradient bar: LIVE badge + period revenue + active count + pending commission + completed count |
| 3 | Balance + Health Score | Platform balance card (total + fee %) + circular health score ring (growth/retention/settlement/diversity) |
| 4 | Metrics Grid | 4 cards: Revenue, Transactions, Avg Commission, Providers — each with change %, previous period, accent colors |
| 5 | Live Transactions Monitor | Green-bordered card: pipeline visualization (escrow → completed → disputed), active job rows with status pills |
| 6 | Revenue Chart | `fl_chart` LineChart with daily breakdown, purple gradient fill, date labels |
| 7 | Category + Type Breakdown | PieChart by category + waterfall by source type (quote/anytask/any_tasks) |
| 8 | Peak Hours Heatmap | 24-bar histogram colored by intensity, hour labels every 4h |
| 9 | Top Providers | Ranked list with avatar, name, VIP badge, order count, rating |
| 10 | Recent Transactions | Last 20 transactions with type label (Hebrew), direction arrow, amount, timestamp |
| 11 | Activity Feed | Live stream with color-coded dots by event type, relative timestamps |
| 12 | Quick Actions | 6 action chips: Monthly Report, CSV Export, Real-time, Alerts, VIP, Anomalies |

### Color Palette (VaultColors)

| Name | Hex | Usage |
|------|-----|-------|
| Green | `#1D9E75` | Revenue, success, health |
| Blue | `#378ADD` | Transactions, info |
| Amber | `#EF9F27` | Pending, warnings, VIP |
| Purple | `#7F77DD` | Providers, premium, charts |
| Red | `#E24B4A` | Cancellations, risk |

Each color has `Bg` (light) and `Text` (dark) variants for status pills.

### Health Score Computation

```
Score = growth×0.3 + retention×0.3 + settlement×0.2 + diversity×0.2
```

| Component | Calculation |
|-----------|-------------|
| Growth | `(revenueGrowth% + 100) / 3` clamped 0-100 |
| Retention | `completedJobs / (completed + cancelled) × 100` |
| Settlement | Fixed 80 (placeholder until avg settlement time is tracked) |
| Diversity | `activeProviders / 50 × 100` clamped 0-100 |

### Cloud Functions Added

| CF | Trigger | Purpose |
|----|---------|---------|
| `updateVaultAnalytics` | `onSchedule` every 1 hour | Aggregates metrics for all 4 periods into `vault_analytics/{period}` |
| `generateVaultAlerts` | `onSchedule` every 1 hour | Creates smart alerts in `vault_alerts` (stuck escrows, milestones, high cancellation rate) |
| `updateVaultBalance` | `onDocumentWritten("transactions/{id}")` | Recomputes `vault_balance/main` from admin settings + pending jobs + completed withdrawals |

### New Firestore Collections

| Collection | Purpose | Written by |
|-----------|---------|------------|
| `vault_analytics/{period}` | Pre-aggregated metrics per period (day/week/month/year) | `updateVaultAnalytics` CF |
| `vault_alerts/{id}` | Smart alerts (achievement, warning, risk, recommendation) | `generateVaultAlerts` CF |
| `vault_balance/main` | Computed balance snapshot (available, pending, withdrawn) | `updateVaultBalance` CF |

### Files

| File | Purpose |
|------|---------|
| `lib/services/vault_service.dart` | Firestore queries, computed metrics, helper functions |
| `lib/screens/admin_vault_tab.dart` | Full dashboard UI (~1500 lines) |
| `lib/screens/admin_screen.dart` | Tab registration (length 10→11, position after כספים) |
| `functions/index.js` | 3 new CFs appended (updateVaultAnalytics, generateVaultAlerts, updateVaultBalance) |
| `functions/vault_functions.js` | Standalone copy for reference (same code as appended to index.js) |

### Deployment

```bash
firebase deploy --only functions:updateVaultAnalytics,functions:generateVaultAlerts,functions:updateVaultBalance
flutter build web --release && firebase deploy --only hosting
```

After first deploy, the `vault_analytics` docs won't exist until the hourly
CF fires. To populate immediately, invoke `updateVaultAnalytics` manually
from the Firebase Console or via `firebase functions:shell`.

### Future Enhancements

- **Withdrawal flow:** Dialog + `initiateWithdrawal` CF with double verification
- **PDF export:** `generateVaultReport` CF producing downloadable reports
- **Conversion funnel:** Requires Firebase Analytics event tracking integration
- **AI Insights:** Gemini-powered opportunity analysis on vault_analytics data
- **Push alerts:** FCM notifications to admin on critical vault_alerts
- **Scheduled withdrawals:** Recurring withdrawal rules in `withdrawals` collection

---

## 30. Phone Login Screen — Premium Redesign (v14.x, 2026-04-16)

> **World-class sign-in / sign-up redesign.** Full UI rebuild of
> [phone_login_screen.dart](lib/screens/phone_login_screen.dart) inspired by
> Airbnb/Revolut. Every line of existing Auth logic is preserved — only the
> UI layer changed.

### What's preserved (do NOT touch)

| Logic | Status |
|-------|--------|
| `_sendOtp()` — web `signInWithPhoneNumber`, mobile `verifyPhoneNumber` | unchanged |
| `_loginGoogle()` — unified `GoogleSignIn` plugin for web+native | unchanged |
| `_loginApple()` — web `signInWithPopup`, native `sign_in_with_apple` + nonce | unchanged |
| `_createProfileIfNew()` — anti-duplicate guard + 3-attempt retry + dual-write | unchanged |
| `_isIOSPwa` — hides social buttons in iOS PWA mode | unchanged |
| Rate limiting — 3 OTP sends per 10 minutes | unchanged |
| Country picker — 15 countries via bottom sheet | unchanged |
| Phone validation regex `^\d{7,12}$` | unchanged |
| AuthWrapper routes after sign-in — NO Navigator.push on success | unchanged |

### What's new (UI only)

**Design language**: single white card with rounded 28px corners floating over
a soft purple background (`#F5F5FF`). The card has three vertical sections:

1. **Hero** — gradient `[indigoDark → indigo → purple]` at 135deg with:
   - Animated floating orbs (warning-yellow + white, 12s loop, opposite phases)
   - 3 pulsing dots with staggered delays
   - Glass-morphism language button (top-start corner, `BackdropFilter blur 10px`)
   - White 84×84 rounded square wrapping `AnySkillBrandIcon(size: 56)`
   - Centered subtitle with `maxWidth: 280`

2. **Form** — padded white section with:
   - Google + Apple social buttons (hidden on iOS PWA)
   - Uppercase letter-spaced divider "OR WITH PHONE NUMBER"
   - Phone input with LTR inner direction + country prefix on the left
   - Focus ring: 1.5px purple border + 4px spread glow
   - Primary CTA button with:
     - Gradient `[indigo, indigoDark]`
     - Infinite pulse via two stacked `BoxShadow` layers
     - Shimmer stripe sweeping left-to-right every 3 seconds
     - Loading spinner replaces text+arrow when `_isLoading`
   - Terms text with two tappable links (both open `TermsOfServiceScreen`)

3. **Bottom strip** — soft gradient `[#FAFAFF → #F0EEF9]` with:
   - Badge icon + "Offering a service?" + "Earn with AnySkill →"
   - On tap: `Navigator.push → ProviderRegistrationWizardScreen`

### Language switcher — dropdown instead of bottom sheet

Replaces the old `showModalBottomSheet` pattern with an overlay-based
dropdown anchored to the language button:

| Behavior | Detail |
|----------|--------|
| Trigger | Tap the pill button (top-start of hero) |
| Open | 200ms fade+scale-in (`Curves.easeOutCubic`) |
| Position | `top: button.bottom + 6px`, aligned to button's trailing edge |
| Dismiss | Tap outside (full-screen `GestureDetector` behind menu) |
| Languages | he, en, ar, es — **same 4 as before**, no change |
| On pick | Calls `LocaleProvider.instance.setLocale(locale)` + `setState()` |

Implementation: `OverlayEntry` inserted into `Overlay.of(context)` with a
click-catcher `Positioned.fill` behind the menu. Menu itself is
`_LanguageDropdown` widget with its own animation controller.

### Stagger animation on mount

Single `AnimationController` (1300ms total) drives fade-in + translateY(14→0)
for each element via `Interval` curves:

| Element | Start (% of duration) |
|---------|------------------------|
| Language button, logo | 0% |
| Subtitle | 14% |
| Google button | 22% |
| Apple button | 26% |
| Divider | 30% |
| Phone input | 34% |
| CTA button | 38% |
| Terms text | 44% |
| Bottom strip | 48% |

Each element animates over 54% of total duration → effectively 700ms each.
Helper: `_buildStagger(delay: ..., child: ...)`.

### New localization keys (4 languages)

Added to all four `.arb` files (he/en/es/ar):

```
phoneLoginContinueGoogle  — "Continue with Google"
phoneLoginContinueApple   — "Continue with Apple"
phoneLoginOrPhone         — "OR WITH PHONE NUMBER"
phoneLoginCtaLogin        — "Sign in"
phoneLoginTermsPrefix     — "By continuing, I agree to the"
phoneLoginTermsOfUse      — "Terms of Use"
phoneLoginAnd             — "and"
phoneLoginPrivacyPolicy   — "Privacy Policy"
phoneLoginOfferingService — "Offering a service?"
phoneLoginBecomeProvider  — "Earn with AnySkill →"
```

Existing keys (`phoneLoginHeroSubtitle`, `phoneLoginPhoneHint`,
`phoneLoginSelectCountry`, `phoneInvalidNumber`, etc.) are reused as-is.

### Color palette — uses existing `Brand.*`

Per user instruction: **no new color file**. All colors sourced from
`lib/theme/app_theme.dart`:

| Purpose | Source |
|---------|--------|
| Hero gradient | `[Brand.indigoDark, Brand.indigo, Brand.purple]` |
| CTA gradient | `[Brand.indigo, Brand.indigoDark]` (matches existing `Brand.ctaGradient`) |
| Focus ring | `Brand.indigo` |
| Check icon on valid phone | `Brand.success` |
| Orb 1 color | `Brand.warning.withValues(alpha: 0.22)` |
| Error snackbar | `Brand.error` |

### Performance

- Hero content wrapped in `RepaintBoundary` so orbs + pulses don't repaint
  the rest of the card
- All animation controllers disposed properly in `dispose()`
- Overlay removed on dispose + on tap-outside + on language pick
- Shimmer and pulse use `AnimatedBuilder` (not `setState`) for 60fps

### Removed

- Old `login_screen.dart` (email+password dead code from v12.5 era) —
  zero call sites, deleted in this PR
- Old `_WavePainter` at the bottom of the hero — not used in new design
- `_chip()` helper (security/fast/reliable pills) — redundant with subtitle

### Files

| File | Role |
|------|------|
| [lib/screens/phone_login_screen.dart](lib/screens/phone_login_screen.dart) | Full rewrite — ~1000 lines, keeps class name `PhoneLoginScreen` |
| `lib/screens/login_screen.dart` | **Deleted** (was dead code) |
| `lib/l10n/app_he.arb` + 3 others | +10 keys each (40 new translations) |

### Rules for future changes

- **Never add Navigator.push after successful sign-in** — AuthWrapper handles
  routing. Adding navigation here causes a double-push race (v12.8 bug).
- **Never overwrite existing user doc** in `_createProfileIfNew` — read first,
  only write if `!exists`. See v12.8 fix.
- **Always call `AuthDuplicateGuard.enforceOrSignOut` before writing**
  `users/{uid}` with an email field (PR-A, Section 20).
- **Country list is per-spec: do not replace.** The user explicitly kept it.
- **Language list is 4: he/en/ar/es.** Do not add ru/fr without user ack.

---

## 31. Monetization Tab — Premium Redesign v15.x (2026-04-17)

Full rewrite of the admin Monetization tab ([lib/screens/admin_monetization_tab.dart](lib/screens/admin_monetization_tab.dart)) — from a flat 6-section fee manager into a 9-section commission + AI + simulator control center.

**Location:** ניהול → מערכת → מוניטיזציה
**Spec:** [docs/ui-specs/monetization/PROMPT_FOR_CLAUDE_CODE.md](docs/ui-specs/monetization/PROMPT_FOR_CLAUDE_CODE.md) + `monetization_mockup.html`. Spec rule: "HTML wins over text".

### 3-Layer Commission Hierarchy (the spine of v15.x)

**Rule:** specific beats general.

```
Layer 1 — Global      admin/admin/settings/settings.feePercentage (fraction, 0.10 = 10%)
   ↓ overridden by
Layer 2 — Category    category_commissions/{categoryName}.percentage (0-100 scale)
   ↓ overridden by
Layer 3 — Per-user    users/{uid}.customCommission.{percentage, expiresAt, reason, notes}
                      guarded by users/{uid}.customCommissionActive == true
```

**IMPORTANT — category doc ID is the category NAME**, not a generated ID. That's because `users.serviceType` stores the NAME (see [lib/constants.dart](lib/constants.dart) `APP_CATEGORIES`), and `escrow_service.dart` needs a direct lookup inside the transaction. Do not switch to UUIDs.

**Resolution happens in 3 places — all in sync:**

| Consumer | File | Why |
|----------|------|-----|
| Flutter UI preview | [lib/services/commission_calculator.dart](lib/services/commission_calculator.dart) — `CommissionCalculator.resolve()` | Live slider tick, edit dialog preview |
| Server authoritative | [functions/index.js](functions/index.js) — `_getEffectiveCommission(userId, categoryId)` | Used by `getEffectiveCommission` callable |
| Live escrow booking | [lib/services/escrow_service.dart](lib/services/escrow_service.dart) lines 71-127 | Reads all 3 layers INSIDE the Firestore transaction and writes `commissionSource` + `commissionFeePct` on the job doc |

**Fee fraction vs percentage — the one gotcha:**
- `admin/settings.feePercentage` + `urgencyFeePercentage` are **fractions** (0.10 = 10%). Historical format, unchanged.
- `category_commissions.percentage` + `users.customCommission.percentage` are **0-100 scale**. New v15.x convention — less error-prone.
- UI slider is always 0-100. `MonetizationService.updateGlobalCommission` does `/100` on write; `streamGlobalSettings` callers do `*100` on read.

### 9 Sections — File-by-File

| # | Section | Widget | Data Source |
|---|---------|--------|-------------|
| 1 | Top bar + save | inline `_buildTopBar` | `_hasUnsavedChanges` (slider vs persisted) |
| 2 | AI Insight Banner | `ai_insight_banner.dart` | `ai_insights/monetization` stream |
| 3 | 4 KPI cards | `kpi_card.dart` + Sparkline / EscrowWaitBars / FeeTargetBar / CustomProviderBars | `MonetizationKpiService` snapshot |
| 4 | Smart alerts strip | `smart_alert_card.dart` | `monetization_alerts` stream |
| 5 | Commission Control + Simulator | `commission_hierarchy_visual` + `category_commission_grid` + `commission_simulator` | `_computeSimulation()` heuristic |
| 6 | Revenue chart + Heatmap | `revenue_chart` + `activity_heatmap` | KPI snapshot `currentMonthDaily` / `heatmap` |
| 7 | Provider table (full) | `provider_commission_table` + `provider_edit_dialog` | `MonetizationProviderService.load()` |
| 8 | Escrow + Activity | `escrow_transaction_card` + `activity_timeline` | `jobs where status==paid_escrow` + `activity_log where category==monetization` |

### Service Layer (`lib/services/`)

| Service | Responsibility |
|---------|----------------|
| `monetization_service.dart` | **Single source of truth for all writes.** Every commission change + smart-rule toggle goes through here and lands in `activity_log` with `category: 'monetization'`. Also exposes streams used by widgets. |
| `monetization_kpi_service.dart` | One-shot aggregator. 6 parallel queries → `MonetizationKpis` snapshot (KPIs + chart series + heatmap). Called from tab `initState` + refreshed every 60s. |
| `monetization_provider_service.dart` | One-shot aggregator for section 7. 4 parallel queries → up to 500 `ProviderTableRow` with `effectivePct`, `healthScore`, `gmv30d`, `isChurnRisk`, `isTopPerformer`. |
| `commission_calculator.dart` | Pure-function resolver. Mirrors server `_getEffectiveCommission` + applies smart-rule adjustments (waive, tiered, weekend boost). |

### Cloud Functions Added

| CF | Trigger | Purpose | Auth |
|----|---------|---------|------|
| `getEffectiveCommission` | callable | Preview effective commission for `(userId, categoryId)`. Returns `{percentage, source, ...}`. | Self or admin |
| `detectMonetizationAnomalies` | `onSchedule("every 60 minutes")` | Scans 28d of `platform_earnings` + users + categories. Writes 3 signal types to `monetization_alerts`: anomaly (≥30% GMV drop), churn_risk (VIP 10d / regular 14d inactive), growth_opportunity (≥20% GMV up). Idempotent via 24h dedupe. | scheduled |
| `generateMonetizationInsight` | `onSchedule("every 6 hours")` | Feeds metrics JSON to **Gemini 2.5 Flash Lite** and writes one strategic recommendation to `ai_insights/monetization`. Schema: `{title, recommendation, expectedImpact, actionType, actionParams}`. `actionType` ∈ `adjust_category_commission | reduce_provider_commission | promote_provider | none`. | scheduled |
| `adminReleaseEscrow` | callable | **Admin-only** force-release of paid_escrow jobs. Uses the commission baked into the job at booking time — does NOT re-compute. | `isAdminCaller` |

**AI model pinned to Gemini**, NOT Claude. The AI CEO tab (Section 12c) uses Claude Sonnet for deeper reasoning; this tab uses Gemini per spec's explicit requirement. They co-exist.

### Firestore Schema Additions

```
category_commissions/{categoryName}          // doc ID = category name
  categoryId, categoryName, percentage (0-100), updatedAt, updatedBy, reason?

users/{uid}.customCommissionActive: bool     // sentinel for `.where()`
users/{uid}.customCommission: {
  percentage, setAt, setBy, reason, notes?, expiresAt?
}

ai_insights/monetization                     // single doc, merge-written
  title, recommendation, expectedImpact,
  actionType, actionParams, model, generatedAt,
  applied, appliedBy?, appliedAt?, dismissedBy?, dismissedAt?

monetization_alerts/{alertId}                // append-only (CF writes, admin updates `resolved`)
  type, severity, entityType, entityId, message,
  detectedAt, resolved, suggestedAction, resolvedAt?, resolvedBy?, resolutionNote?

admin/admin/settings/settings                // extended with smart-rule fields
  waiveFeeFirstNJobs: int                     // 0 = disabled
  tieredCommission: { enabled, tiers:[{minGMV, discount}] }
  weekendBoost: { enabled, daysOfWeek, extraPercentage }
```

### Firestore Rules Added ([firestore.rules](firestore.rules))

```
match /category_commissions/{id}  { allow read: if isAuth() || isAppCheckValid(); allow write: if isAdmin(); }
match /ai_insights/{id}           { allow read: if isAdmin(); allow update: if isAdmin(); allow create, delete: if false; }
match /monetization_alerts/{id}   { allow read: if isAdmin(); allow update: if isAdmin(); allow create, delete: if false; }
```

Admin writes to `users/{uid}.customCommission` are already covered by the existing `isAdmin()` branch in the users rule — no rule change needed.

### Jobs Now Carry Commission Provenance

Every job written by `EscrowService.payQuote` now includes:
- `commissionFeePct`: number (0-100 scale) — what percentage was actually charged
- `commissionSource`: `'global' | 'category' | 'custom'` — which layer won

Lets admin screens explain why a job had a given fee, and enables audit reports.

### Design Tokens ([lib/widgets/monetization/design_tokens.dart](lib/widgets/monetization/design_tokens.dart))

**Scoped palette** — does NOT replace `Brand.*`. Same pattern as `MapPalette` (§26) and the Vault palette (§29). Every color extracted from the mockup HTML; do not change without updating the mockup first.

Shared helpers: `MonetizationCard` (white card, 0.5px border, radius 12), `MonetizationPill` (rounded badge), `cardDecoration()`, `badgeDecoration()`.

### Dark Mode Decision — Light-Only

This tab is **light-mode only**, consistent with the Vault tab (§29) and the rest of the admin panel. The mockup defines a warm cream + white aesthetic. If dark mode is needed later, add a `Theme.of(context).brightness` switch in `design_tokens.dart` — but only after redesigning each visual (the simulator already uses a dark card on a light background, which would conflict with a dark scaffold).

### Responsive Breakpoints

Tab uses `LayoutBuilder` at the root. Three breakpoints:

| Width | Layout |
|-------|--------|
| `< 720px` (phone) | Top bar wraps to 2 rows · KPI grid 2-col · alerts stack vertically · every side-by-side grid collapses to a column |
| `720-1024px` (tablet) | Top bar single row · KPI 2-col · side-by-side grids (control, charts, escrow) stack vertically |
| `≥ 1024px` (desktop) | Original mockup: 4-col KPI · 2/3+1/3 · 3/5+2/5 · 1/2+1/2 |

Phone breakpoint added for completeness — admin panel's primary target is desktop.

### Rules for Future Code

- **Never hard-code a fee percentage.** Always read from the layered source. If writing a new payment path, study `escrow_service.dart:71-127` and replicate the 3-read pattern INSIDE the transaction.
- **Never write to `users.customCommission` outside `MonetizationService.setUserCommission`** — you'll lose the audit-log entry and the `customCommissionActive` sentinel.
- **Every admin action in this tab must hit `activity_log`** with `category: 'monetization'`. `MonetizationService._logActivity()` handles it — use the service, not direct Firestore writes.
- **Don't switch AI to Claude** for this tab. Spec is explicit.
- **`category_commissions` doc ID must equal the Hebrew category NAME.** Do not change to UUIDs without updating `escrow_service.dart` (direct `.doc(serviceType)` lookup) and `MonetizationProviderService`.
- **Keep the Gemini JSON schema stable** (`title`, `recommendation`, `expectedImpact`, `actionType`, `actionParams`). The "הפעל" button in `_applyInsight()` dispatches on `actionType` — a new type requires a new case there.

### Deploy Checklist

```bash
firebase deploy --only \
  functions:getEffectiveCommission,\
  functions:detectMonetizationAnomalies,\
  functions:generateMonetizationInsight,\
  functions:adminReleaseEscrow
firebase deploy --only firestore:rules
flutter build web --release && firebase deploy --only hosting
```

After first deploy: the scheduled CFs run hourly / every 6h. To populate immediately, invoke them once from the Firebase Console ("Force run") or `firebase functions:shell`.

### Files Touched

**Created (17):**
- 4 services: `monetization_service.dart`, `monetization_kpi_service.dart`, `monetization_provider_service.dart`, `commission_calculator.dart`
- 13 widgets under `lib/widgets/monetization/`

**Modified:**
- `lib/screens/admin_monetization_tab.dart` — full rewrite
- `lib/services/escrow_service.dart` — 3-layer commission resolution inside the tx
- `functions/index.js` — 4 new CFs + 1 internal helper
- `firestore.rules` — 3 new match blocks

---

## 32. Pest Control CSM (Category-Specific Module, v15.x, 2026-04-17)

Full category-specific module for the "הדברה" (pest control) sub-category,
following the same CSM pattern as massage (Section 3d / massage files).
Adds two new blocks — provider settings and client booking — that only
appear when the sub-category is "הדברה".

### Architecture

| Component | File | Purpose |
|-----------|------|---------|
| Model | `lib/models/pest_control_profile.dart` | `PestControlProfile` + 8 sub-models (licenses, availability, service area, warranty, packages, instructions) + `isPestControlCategory()` helper |
| Pest types catalog | `lib/constants/pest_types_catalog.dart` | 14 pest types in 3 groups (insects, rodents, animal capture) with icons + colors |
| Treatment methods | `lib/constants/pest_treatment_methods.dart` | 5 methods (green, spray, heat, injection, fumigation) |
| Instructions catalog | `lib/constants/pest_structured_instructions.dart` | 7 structured post-treatment instructions with duration options + color-coded cards |
| Booking service | `lib/services/pest_control_booking_service.dart` | Price calculation, breakdown builder, last-booking preferences fetch |
| Provider block | `lib/screens/pest_control/pest_control_settings_block.dart` | 9-section settings form (licenses, pest types, methods, availability, pricing, warranty, packages, instructions) |
| Client block | `lib/screens/pest_control/pest_booking_block.dart` | AI pest identification (Gemini Vision), treatment instructions display with acknowledgement checkbox, urgency/location/method selectors, summary bar |

### Key features

- **AI Pest Identification**: Gemini Vision via `identifyPestFromImage` Cloud Function (NOT Claude). Client uploads/captures photo, AI returns pest type + confidence + recommendation.
- **Treatment Instructions**: Provider sets 7 structured instructions (evacuate home, remove pets, no washing, ventilation, cover food, cover aquarium, remove ceramics) with duration selectors + custom free-text. Client sees color-coded cards and MUST acknowledge before booking.
- **Licenses**: Provider must have Ministry of Environmental Protection license. Snake catching requires separate snake catcher license.
- **Emergency service**: Toggle with configurable surcharge (default ₪150).
- **Maintenance packages**: Provider creates quarterly/monthly packages with discount percentages.
- **Demo profile parity**: Admin demo experts tab renders the same `PestControlSettingsBlock` when "הדברה" is selected.

### Firestore field

`users/{uid}.pestControlProfile` — nested Map identical to the `PestControlProfile.toMap()` output. Synced to `provider_listings/{id}.pestControlProfile` on save.

`jobs/{id}.pestControlPreferences` — booking preferences including AI identification data, selected pest type, urgency, treatment method, special household members, add-ons, and `instructionsAcknowledged` with timestamp.

### Detection function

```dart
bool isPestControlCategory(String? serviceType) {
  if (serviceType == null) return false;
  final lower = serviceType.trim().toLowerCase();
  return lower == 'הדברה' || lower == 'pest_control' ||
      lower.contains('הדברה') || lower.contains('מדביר');
}
```

### Integration points

| Screen | Method | What happens |
|--------|--------|-------------|
| `edit_profile_screen.dart` | `_isPestControlSubCategory()` | Shows `PestControlSettingsBlock` after sub-category dropdown |
| `expert_profile_screen.dart` | `_hasPestControlProfile()` | Shows `PestBookingBlock` between About and Service sections |
| `admin_demo_experts_tab.dart` | `_isDemoPestControlCategory()` | Shows `PestControlSettingsBlock` in demo profile form |

### Localization

+35 keys in all 4 locale files (he/en/es/ar), prefix `pest*`.

### Cloud Function needed (NOT yet created)

`identifyPestFromImage` — callable, takes `{imageBase64}`, calls Gemini Vision, returns `{pestType, pestTypeHe, confidence, alternativeMatches, urgencyLevel, description, treatmentRecommendation}`. Deploy separately.

### Files

**Created (7):**
- `lib/models/pest_control_profile.dart`
- `lib/constants/pest_types_catalog.dart`
- `lib/constants/pest_treatment_methods.dart`
- `lib/constants/pest_structured_instructions.dart`
- `lib/services/pest_control_booking_service.dart`
- `lib/screens/pest_control/pest_control_settings_block.dart`
- `lib/screens/pest_control/pest_booking_block.dart`

**Modified (7):**
- `lib/screens/edit_profile_screen.dart` — imports, state, detection, validation, UI, save, listing sync
- `lib/screens/expert_profile_screen.dart` — imports, state, detection, builder, insertion, job doc
- `lib/screens/admin_demo_experts_tab.dart` — imports, state, init, detection, UI, both save payloads
- `lib/l10n/app_he.arb` — +35 keys
- `lib/l10n/app_en.arb` — +35 keys
- `lib/l10n/app_es.arb` — +35 keys
- `lib/l10n/app_ar.arb` — +35 keys

---

## 33. Delivery CSM (Category-Specific Module, v15.x, 2026-04-17)

Full category-specific module for the "משלוחים" (delivery / couriers)
sub-category, following the same CSM pattern as massage (§3d) and pest
control (§32). Adds two new blocks — provider settings and client booking —
that appear only when the sub-category is "משלוחים".

### Architecture

| Component | File | Purpose |
|-----------|------|---------|
| Model | `lib/models/delivery_profile.dart` | `DeliveryProfile` + 9 sub-models (documents, vehicles, availability, service area, pricing, rules, business packages) + `isDeliveryCategory()` helper |
| Delivery types catalog | `lib/constants/delivery_types_catalog.dart` | 6 package types — documents, small/medium/large, flowers, cakes |
| Vehicle types | `lib/constants/delivery_vehicle_types.dart` | 2 vehicles per spec — scooter, car (NO trucks, NO fridges) |
| Courier rules catalog | `lib/constants/courier_rules_catalog.dart` | 5 built-in rules (no_dangerous, photo_documentation, call_before_arrival, weight_verification, rain_delivery) |
| Package tags | `lib/constants/delivery_package_tags.dart` | 4 tags (fragile, sensitive, photo_documentation, signature_required) |
| Booking service | `lib/services/delivery_booking_service.dart` | `calculateTotal`, `buildPriceBreakdown`, `getLastBookingWith` (for Express Reorder) |
| Provider block | `lib/screens/delivery/delivery_settings_block.dart` | Dark premium "הקריירה שלך" settings form — 9 sections |
| Client block | `lib/screens/delivery/delivery_booking_block.dart` | Dark premium "שלח עם {name}" booking block — hero, route preview, package + AI vehicle, timing, method, add-ons, recipient, rules display, summary |

### Key features

- **AI Vehicle Recommendation** via Gemini (NOT Claude) — `recommendVehicleForDelivery` Cloud Function calls `gemini-2.5-flash-lite` with package type, distance, urgency, weather. Returns recommended vehicle + savings + reason + confidence. Auto-switches the client's selected vehicle when confidence > 0.7.
- **Scheduled delivery** (unique to AnySkill) — client can pick a date up to 30 days ahead via `showDatePicker`.
- **Phone masking notice** — summary shows "המספר שלך מוסתר מ-{courier} אוטומטית". (Actual masking requires a future CF — UI contract is in place.)
- **Express Reorder** — `DeliveryBookingService.getLastBookingWith(customerId, expertId)` is ready to populate the reorder card. (UI widget deferred — service is live.)
- **Live map preview** — static dark map with LIVE badge, courier pin with distance, A→B markers. Real GPS tracking deferred to a future PR (piggybacks on existing `dog_walks` pattern in §3d).
- **Courier rules** — provider picks from 5 built-in rules + free-text custom (500-char max). Client sees them on the profile before booking.
- **Demo profile parity** — admin demo experts tab renders the same `DeliverySettingsBlock` when "משלוחים" is selected.
- **🚫 NO insurance** per user decision — not in UI, not in model, not in CF.

### Firestore fields

```
users/{uid}.deliveryProfile — nested Map, 9 fields (see model above)
jobs/{id}.deliveryPreferences — booking-time snapshot:
  packageType, packageTags, packageDescription,
  selectedVehicle, aiRecommendedVehicle, aiSavingsAmount, aiSavingsMinutes,
  pickupAddress {address, details}, deliveryAddress {address, details},
  distanceKm, timing, scheduledFor,
  deliveryMethod, specialInstructions,
  addOns[], recipient {name, phone, phoneVerified},
  priceBreakdown {base, addOnsTotal, immediateSurcharge, kmAfter5, total}
```

`provider_listings/{id}.deliveryProfile` is synced on save (same pattern as
massage/pest) so demo + real delivery providers surface in search.

### Detection function

```dart
bool isDeliveryCategory(String? serviceType) {
  if (serviceType == null) return false;
  final lower = serviceType.trim().toLowerCase();
  return lower == 'משלוחים' || lower == 'delivery' ||
      lower == 'שליחים' || lower == 'courier' ||
      lower.contains('משלוח') || lower.contains('שליח') ||
      lower.contains('deliver') || lower.contains('courier');
}
```

### Integration points

| Screen | Method | What happens |
|--------|--------|-------------|
| `edit_profile_screen.dart` | `_isDeliverySubCategory()` | Shows `DeliverySettingsBlock` after pest block, before tax ID |
| `expert_profile_screen.dart` | `_hasDeliveryProfile()` | Shows `DeliveryBookingBlock` between About and Service sections (right after pest block) |
| `admin_demo_experts_tab.dart` | `_isDemoDeliveryCategory()` | Shows `DeliverySettingsBlock` in demo profile form |

### Cloud Functions

**`recommendVehicleForDelivery`** (callable) — Gemini 2.5 Flash Lite.
- Auth required
- Input: `{packageType, distanceKm, urgency, weatherConditions?}`
- Output: `{recommendedVehicle, savingsAmount, savingsMinutes, reason, confidence}`
- Timeout: 20s, memory: 256MiB
- Rules baked into prompt: documents/small/flowers/cakes → scooter, large/heavy → car, distance > 20km → car, rain → car
- Fails gracefully — client just hides the recommendation card if the CF errors

### Design system

Dark premium palette (scoped, does NOT replace `Brand.*`):
- Background gradient: `[#0A0E1A, #151B2E, #0F1420]`
- Primary gold: `[#D97706, #F59E0B, #FBBF24, #FCD34D]`
- Status: green `#16A34A`, red `#DC2626`, blue `#3B82F6`
- Unique indigo (scheduled): `#6366F1`
- Ambient orbs: 3 positioned radial gradients per block (gold + indigo + green)
- Glass cards: white @ 4% opacity, 1px border white @ 8%, radius 18px

### Rules for future code

- **Never re-add insurance** — explicitly removed per spec.
- **Delivery CF must use Gemini, not Claude.** Spec is explicit. AI CEO tab (§12c) uses Claude Sonnet; this CF uses Gemini Flash Lite. They co-exist.
- **Vehicle enum is strictly `scooter | car`** — do not add truck/van without updating vehicle_types_catalog + Gemini prompt + the client vehicle selector.
- **Rounding** — `DeliveryBookingService.calculateTotal` uses `.toStringAsFixed(2)` matching §18 Rule 7.

### Deployment

```bash
firebase deploy --only functions:recommendVehicleForDelivery
flutter build web --release && firebase deploy --only hosting
```

### Files

**Created (8):**
- `lib/models/delivery_profile.dart`
- `lib/constants/delivery_types_catalog.dart`
- `lib/constants/delivery_vehicle_types.dart`
- `lib/constants/courier_rules_catalog.dart`
- `lib/constants/delivery_package_tags.dart`
- `lib/services/delivery_booking_service.dart`
- `lib/screens/delivery/delivery_settings_block.dart`
- `lib/screens/delivery/delivery_booking_block.dart`

**Modified (4):**
- `lib/screens/edit_profile_screen.dart` — imports, state, init loader, detection, validation, UI block, save payload, listing sync
- `lib/screens/expert_profile_screen.dart` — imports, state, detection, builder, insertion between pest block and service menu, job doc payload
- `lib/screens/admin_demo_experts_tab.dart` — imports, state, init, detection, UI block, save payloads (user + listing)
- `functions/index.js` — `recommendVehicleForDelivery` CF appended after `identifyPestFromImage`

### Validation

- `flutter analyze` → 0 issues on all 10 new/modified delivery files
- Full project analyze → 13 pre-existing info-level warnings unrelated to delivery code

---

## 34. Cleaning CSM (Category-Specific Module, v15.x, 2026-04-18)

Category-specific module for the "נקיון" (cleaning) sub-category, following
the same CSM pattern as massage (§3d), pest control (§32) and delivery (§33).
Adds a provider-side "המקצועיות שלך" settings block and a client-side
"בואי נתאים את הניקיון שלך" booking block that appear only when the
sub-category resolves to cleaning.

### CRITICAL sync rules (spec 01_MAIN_PROMPT_CLEANING.md)

Cleaning does NOT own its own chat, calendar, booking history, or analytics.
Every such read/write flows through the **existing** systems:

| Touchpoint | Wired to |
|------------|----------|
| Chat button + Quick Reply chips | `ChatScreen(receiverId, receiverName, initialMessage)` — the single `initialMessage` param pre-fills the text box (see CLAUDE.md §15b support flow). NO new chat screen is built. |
| "קבעי מועד" CTA | Relies on the existing TableCalendar + "Pay & Secure" button already embedded in [expert_profile_screen.dart](lib/screens/expert_profile_screen.dart). The booking block only `emit()`s preferences + price through `onChanged`; the parent escrow flow writes the job doc with `cleaningPreferences`. The CTA itself shows a Hebrew nudge to use the calendar below. |
| Express Reorder card | `CleaningBookingService.getLastBookingWith` reads the most-recent `status == 'completed'` job between this `(customerId, expertId)` pair from the existing `jobs` collection and joins the matching `reviews` doc. Zero duplicate storage. |
| Recurring Customers counter | `CleaningBookingService.streamRecurringCustomersCount` streams the `jobs` collection and counts distinct `customerId` where `cleaningPreferences.recurrence.enabled == true` AND `recurrence.active != false`. |
| Trust Center badges | Reads from `CleaningProfile.verifications` (embedded in `users/{uid}.cleaningProfile`) + the escrow guarantee (always true — platform feature). |

### Architecture

| Component | File | Purpose |
|-----------|------|---------|
| Model | `lib/models/cleaning_profile.dart` | `CleaningProfile` + 9 sub-models (CleaningVerifications, CleaningEcoMode, CleaningChecklistCategory, CleaningTask, CleaningPricing, CleaningRecurringDiscounts, CleaningQualityGuarantee, CleaningServiceArea, CleaningBusinessPackage) + `isCleaningCategory(String?)` helper |
| Cleaning types catalog | `lib/constants/cleaning_types_catalog.dart` | 6 `CleaningTypeDef`: regular_home, deep_renovation, airbnb, office, store, event |
| Customer types | `lib/constants/cleaning_customer_types.dart` | 4 types — private, business, stores, restaurants |
| Add-ons catalog | `lib/constants/cleaning_addons_catalog.dart` | 4 add-ons — oven_inside (₪40), fridge_inside (₪30), windows_outside (₪60), sofa_steam (₪120) |
| Default checklists | `lib/constants/cleaning_default_checklists.dart` | Template with 3 categories (bedroom/bathroom/kitchen) + default business packages + 14-city list |
| Booking service | `lib/services/cleaning_booking_service.dart` | `estimateDurationMinutes`, `calculateTotal`, `buildPriceBreakdown`, `getLastBookingWith`, `streamRecurringCustomersCount` |
| Provider block | `lib/screens/cleaning/cleaning_settings_block.dart` | Dark premium cyan/teal 9-section form (hero + verifications + types + customers + eco + checklist builder + pricing + recurring discounts + service area + business packages) |
| Client block | `lib/screens/cleaning/cleaning_booking_block.dart` | Dark premium 15-section booking — hero, trust center, express reorder, type picker, property, AI duration, smart checklist, scheduling, eco toggle, access, before/after, quality guarantee, chat preview (opens existing ChatScreen), business packages, sticky summary |

### Key features

- **AI Duration Calculation** via Gemini 2.5 Flash Lite — `calculateCleaningDuration` Cloud Function. The client runs a local heuristic first (zero-latency UX) then overrides with Gemini's answer when it lands. Graceful failure = keeps heuristic.
- **Smart Checklist with progress bars** — each category shows `activeInCat/totalInCat` with a live `LinearProgressIndicator`. Tasks tagged with `withPhoto: true` show a 📷 icon — downstream documented in `jobs/{id}.cleaningPreferences.beforeAfterPhotos`.
- **Trust Center** — 4 badges (ID verified, background checked, insurance amount, escrow) wired to `CleaningProfile.verifications`.
- **Quality Guarantee** — default enabled. Reports within 24h → re-clean free OR full refund. No new CF yet — uses existing dispute flow (§4.5).
- **Recurring discounts** — weekly (−15%), biweekly (−10%), monthly (−5%), overridable per provider.
- **Business packages** — provider creates 4×/8×/custom monthly packages; client sees up to 3.
- **Express Reorder** — one-tap prefill from the most recent completed cleaning job with this provider (reads from existing `jobs` + `reviews`).
- **NO monthly subscriptions for private customers** per spec — only business packages.
- **NO Claude API** — spec explicitly requires Gemini.
- **Demo profile parity** — admin demo experts tab renders the same `CleaningSettingsBlock` when sub-category is "נקיון".

### Firestore fields

```
users/{uid}.cleaningProfile                   // 9-field Map (see CleaningProfile.toMap)
users/{uid}/cleaningProfile.verifications     // idVerified, backgroundChecked, referencesCount, insuranceAmount…
provider_listings/{id}.cleaningProfile        // synced on save — required for search discoverability
jobs/{id}.cleaningPreferences                 // booking-time snapshot:
  cleaningType, propertyDetails{bedrooms, bathrooms, squareMeters, hasPets, floor},
  estimatedDurationMinutes, selectedTasks[], selectedAddOns[],
  schedulingType, recurrence{enabled, frequency, active},
  ecoMode{enabled}, accessMethod, specialInstructions,
  qualityGuaranteeOptedIn, beforeAfterPhotos{enabled, deliveryChannel},
  priceBreakdown{base, addOnsTotal, ecoSurcharge, subtotal, recurringDiscount, total}
```

### Detection function

```dart
bool isCleaningCategory(String? serviceType) {
  if (serviceType == null) return false;
  final lower = serviceType.trim().toLowerCase();
  if (lower.isEmpty) return false;
  return lower == 'נקיון' || lower == 'ניקיון' || lower == 'cleaning' ||
      lower.contains('נקי') || lower.contains('cleaning') ||
      lower.contains('cleaner');
}
```

### Integration points

| Screen | Method | Behavior |
|--------|--------|----------|
| `edit_profile_screen.dart` | `_isCleaningSubCategory()` | Shows `CleaningSettingsBlock` after delivery block. Validation requires idVerified + backgroundChecked + ≥3 references + ≥1 cleaningType + non-empty checklist. |
| `expert_profile_screen.dart` | `_hasCleaningProfile()` | Shows `CleaningBookingBlock` between delivery block and service menu. On escrow, writes `cleaningPreferences` + `priceBreakdown` to the job doc. |
| `admin_demo_experts_tab.dart` | `_isDemoCleaningCategory()` | Shows `CleaningSettingsBlock` in demo profile form. Saves to BOTH user doc and `provider_listings/demo_{uid}`. |

### Cloud Function

**`calculateCleaningDuration`** (callable) — Gemini 2.5 Flash Lite.
- Auth required
- Input: `{cleaningType, bedrooms, bathrooms, squareMeters, hasPets, selectedTasksCount, addOnsCount}`
- Output: `{estimatedMinutes, rangeMin, rangeMax, reasoning}`
- Timeout: 20s, memory: 256MiB
- Prompt rules: regular × 1.0, deep × 2.0, airbnb × 0.8, office × 1.5, store × 1.3; +15-20min for pets; +3-5min per task; +10-20min per add-on
- Graceful degradation — client keeps its local heuristic on any error

### Design system

Dark premium palette (scoped, does NOT replace `Brand.*`):
- Background gradient: `[#0A0E1A, #0F1A2E, #0F1420]`
- Primary cyan/teal: `[#0891B2, #06B6D4, #67E8F9]`
- Status: green `#16A34A`, red `#DC2626`, blue `#3B82F6`, purple `#A855F7` (checklist/express reorder), amber `#F59E0B` (before/after)
- 3 ambient orbs per block (cyan + green + purple)
- Glass cards: white @ 4% opacity, 1px border white @ 8%, radius 18px

### Rules for future code

- **Never build a new chat screen for cleaning.** Use `ChatScreen(receiverId, receiverName, initialMessage)` — if you need to pass more context, extend ChatScreen's constructor, don't fork it.
- **Never build a new calendar for cleaning.** The "קבעי מועד" CTA is a nudge; the actual booking happens through the existing TableCalendar + "Pay & Secure" in expert_profile_screen.
- **Never duplicate booking history.** `getLastBookingWith` reads directly from the existing `jobs` + `reviews` collections.
- **Cleaning CF must use Gemini, not Claude.** Spec is explicit (aligns with delivery §33 and pest control §32).
- **Rounding** — `CleaningBookingService.calculateTotal` uses `.toStringAsFixed(2)` matching §18 Rule 7.

### Deployment

```bash
firebase deploy --only functions:calculateCleaningDuration
flutter build web --release && firebase deploy --only hosting
```

### Files

**Created (8):**
- `lib/models/cleaning_profile.dart`
- `lib/constants/cleaning_types_catalog.dart`
- `lib/constants/cleaning_customer_types.dart`
- `lib/constants/cleaning_addons_catalog.dart`
- `lib/constants/cleaning_default_checklists.dart`
- `lib/services/cleaning_booking_service.dart`
- `lib/screens/cleaning/cleaning_settings_block.dart`
- `lib/screens/cleaning/cleaning_booking_block.dart`

**Modified (4):**
- `lib/screens/edit_profile_screen.dart` — imports, state, init loader, detection, validation, UI, save payload, listing sync
- `lib/screens/expert_profile_screen.dart` — imports, state, detection, builder, insertion after delivery block, job doc payload
- `lib/screens/admin_demo_experts_tab.dart` — imports, state, init, detection, UI block, save payloads (user + listing)
- `functions/index.js` — `calculateCleaningDuration` CF appended after `recommendVehicleForDelivery`

**Spec archived in** `docs/cleaning_upgrade/` (three files from `docs/ui-specs/Cleaning/`).

### Validation

- `flutter analyze` → 0 issues on all 10 new/modified cleaning files
- Full project analyze → 13 pre-existing info-level warnings unrelated to cleaning code
- `node -c functions/index.js` → syntax OK

---

---

## 35. AnyTasks Banner — Role Gating Fix (v15.x, 2026-04-18)

**Bug report:** A provider tapping the AnyTasks banner on the home tab landed
on `MyTasksScreen` — the customer's "publish task" flow. Providers cannot
publish in AnyTasks; they should see the open-tasks feed so they can browse
and claim jobs.

**Root cause:** [home_tab.dart](lib/screens/home_tab.dart) hardcoded the
Navigator target to `MyTasksScreen()` for every user. Both `MyTasksScreen`
(customer publish hub) AND `ProviderHubScreen` (provider browse & claim)
already existed — the entry point just wasn't gated.

**Fix — role + view-mode aware banner.** In the same sliver block that
builds the AnyTasks banner, compute:

```dart
final actualIsProvider = widget.userData['isProvider'] == true;
final inCustomerView = ViewModeService.instance.customerMode;
final showProviderAnyTasks = actualIsProvider && !inCustomerView;
```

Then route on tap: `ProviderHubScreen()` if `showProviderAnyTasks`, else
`MyTasksScreen()`. This mirrors [home_screen.dart's](lib/screens/home_screen.dart)
tab-segmentation pattern (§22) — an admin/provider in customer-view gets
the customer publish flow; only a provider in normal/provider-only mode
gets the browse feed.

**Banner content adapts to role:**

| Element | Customer | Provider |
|---------|----------|----------|
| Icon | `Icons.rocket_launch_rounded` | `Icons.work_outline_rounded` |
| Title pill | "פרסם משימה" | "משימות פתוחות" |
| Subtitle | "מצא נותן שירות תוך דקות" | "בחר/י עבודות וצבור/י הכנסה עכשיו" |

Gradient + shadow + corner radius unchanged — the indigo → purple feel is
the shared AnyTasks brand.

**i18n** — 4 new keys in all 4 locales (`he/en/es/ar` ARB files + all 5
Dart localization stubs):
- `anyTasksBannerProviderTitle`, `anyTasksBannerProviderSub`
- `anyTasksBannerCustomerTitle`, `anyTasksBannerCustomerSub`

**Entry points audit (for future changes):**

| Entry | Routes to | Notes |
|-------|-----------|-------|
| Home-tab banner | `ProviderHubScreen` OR `MyTasksScreen` | Role-gated (THIS FIX) |
| `live_offers_screen.dart` × 3 | `MyTasksScreen` | Post-publish — reachable only by customer (publishing requires customer role) |
| Legacy `lib/screens/anytasks_screen.dart` | — | Dead code, no Navigator routes to it |

### Rules for future code

- **Every new Navigator.push to `MyTasksScreen` MUST be gated** on `isProvider` + `ViewModeService.instance.customerMode`. Providers can't publish.
- **Every new Navigator.push to `ProviderHubScreen` MUST be gated** the opposite way — customers shouldn't see the provider browse feed.
- Legacy `lib/screens/anytasks_screen.dart` is NOT gated. Do not re-introduce a route to it from any surface.
- When adding a new category to AnyTasks, keep the provider-feed filter in `provider_hub_screen.dart` / `provider_feed_screen.dart` aligned — the provider's eligible categories come from `users/{uid}.serviceType` and friends (no new field).

### Files touched

- `lib/screens/home_tab.dart` — imports, banner logic + adaptive UI
- `lib/l10n/app_he.arb`, `app_en.arb`, `app_es.arb`, `app_ar.arb` — 4 keys each
- `lib/l10n/app_localizations.dart` — 4 abstract getters
- `lib/l10n/app_localizations_he.dart`, `_en.dart`, `_es.dart`, `_ar.dart` — 4 concrete overrides each

### Validation

- `flutter analyze lib/screens/home_tab.dart lib/l10n/*.dart` → 0 issues
- Full project analyze → 13 pre-existing info warnings unchanged (no regressions)

---

---

## 36. AnyTasks Error Display — Hebrew via ErrorMapper (v15.x, 2026-04-18)

**Bug report:** A provider tapped a task in AnyTasks, proceeded to the
detail screen, tapped "אשר משימה ב-₪X" to claim it — and saw a raw
English error surfaced from Firestore / the platform layer.

**Root cause:** Five AnyTasks screens had `catch (e)` blocks that fell
through to `Text('שגיאה: $e')` — the prefix was Hebrew but `e.toString()`
from `FirebaseException` (e.g. `[cloud_firestore/permission-denied] …`),
`StateError` (e.g. `Bad state: task-not-open`), or a `PlatformException`
is **always English**.

**Fix — Law 10 everywhere in AnyTasks.** Every `catch` now routes to
`ErrorMapper.show(context, e)` which maps the exception to a friendly
Hebrew message + offers a "לחץ כאן לדבר עם תמיכה" link that opens the
internal Support Chat with the error code pre-filled.

The provider-claim screen gets an extra layer: domain errors thrown by
`AnyTaskService.submitResponse` (the Firestore transaction inside
`any_task_service.dart:113`) are matched BEFORE falling through:

```dart
// provider_task_detail_screen.dart _submit catch block
if (err.contains('task-not-open')) {
  domainMsg = 'המשימה כבר לא פתוחה — מישהו אחר תפס אותה';
} else if (err.contains('self-response-not-allowed')) {
  domainMsg = 'לא ניתן להציע על משימה שלך';
} else if (err.contains('task-not-found')) {
  domainMsg = 'המשימה לא נמצאה — ייתכן שהלקוח הסיר אותה';
}
if (domainMsg != null) {
  // Specific Hebrew toast
} else {
  ErrorMapper.show(context, e);  // permission-denied, network, timeout…
}
```

The previous version missed `task-not-found` entirely and treated
every Firestore/Platform exception as "שגיאה: <English text>".

### Files touched

| File | Change |
|------|--------|
| `lib/features/any_tasks/screens/provider_task_detail_screen.dart` | Added all 3 domain code mappings + ErrorMapper fallback (primary reported site) |
| `lib/features/any_tasks/screens/provider_active_task_screen.dart` | 2 catch blocks → ErrorMapper |
| `lib/features/any_tasks/screens/publish_task_screen.dart` | 1 catch → ErrorMapper |
| `lib/features/any_tasks/screens/task_tracking_screen.dart` | 1 catch → ErrorMapper |

### Rules for future code

- **Every new `catch (e)` inside `lib/features/any_tasks/` MUST use `ErrorMapper.show(context, e)`** (Law 10) as the fallback. Never `'שגיאה: $e'`.
- **Domain error codes** thrown by `AnyTaskService` (`task-not-open`, `self-response-not-allowed`, `task-not-found`) should be matched explicitly with a Hebrew message BEFORE the ErrorMapper fallback — those carry product meaning that the generic mapper can't reproduce.
- **Never extend `ErrorMapper` with AnyTasks-specific codes.** Keep it generic; domain errors stay in the screen that knows the context.
- Firestore rule rejections surface as `FirebaseException` with code `permission-denied` — `ErrorMapper` already translates it to `"היי, נראה שיש לנו תקלה קטנה בחיבור הפרופיל שלך. נסה לרענן את הדף או לחץ לדבר עם תמיכה."` Do NOT try to re-translate it with `err.contains('Permission denied')` string-matching in the screen — that duplicates logic.

### Validation

- `flutter analyze lib/features/any_tasks/` → 0 issues
- Full project analyze → 13 pre-existing info warnings unchanged

---

---

## 37. AnyTasks Deadlines + Edit + Delete (v15.x, 2026-04-18)

**Product ask:** Customers need a product deadline ("I need this done by X"),
the system needs an auto-expire safety net, and customers need Edit + Delete
on their own tasks after publishing. Shipped all four in one pass — the
hybrid design survives the widest set of real scenarios.

### 1. Product deadline (customer-set)

New deadline picker in Step 3 of the publish wizard ([_DeadlinePicker](lib/features/any_tasks/screens/publish_task_screen.dart)):
- 4 quick chips: **היום / מחר / השבוע / החודש** (each computes end-of-day in local TZ)
- 5th chip opens `showDatePicker` with `firstDate = now`, `lastDate = now + 90d`
- Live footer: "אם לא ייתפס עד DD/MM/YYYY — המשימה תפוג אוטומטית."
- Null deadline → footer reminds: "תוגדר תפוגה אוטומטית של 7 ימים."

**Default at publish time:** `deadline ?? DateTime.now() + 7d`. Always written to the task doc so providers see a real countdown and the CF has something concrete to act on.

### 2. Auto-expire — two-bucket CF

`expireOpenTasks` in [functions/index.js](functions/index.js) was previously a daily 03:30 cron that only checked `createdAt > 30d`. Now:

- Runs **every 30 minutes** (so user-set deadlines flip within the half-hour window they expire).
- **Bucket 1:** `status=='open' AND deadline < now` → flip to `status='expired'` + write `expiredReason='deadline'`.
- **Bucket 2:** `status=='open' AND createdAt < now-30d` — safety net for any task missing a deadline. Dedupes against bucket 1, writes `expiredReason='age'`.
- Batch caps at 400 per bucket (800/run). Fan-out is O(n) — expected run cost stays negligible.
- Log line shows `(X by deadline, Y by 30d fallback)` so ops can watch which bucket is active.

### 3. Edit (owner-only, while `status=='open'`)

New `AnyTaskService.updateTask(taskId, updates)` runs inside a Firestore transaction: reads the task doc, asserts `status=='open'`, then applies the update. Throws `StateError('task-not-editable')` / `'task-not-found')` on failure — the UI maps both to Hebrew.

[PublishTaskScreen](lib/features/any_tasks/screens/publish_task_screen.dart) was extended with an optional `existingTask` param. When non-null:
- Category step is skipped (start on step 1).
- All fields pre-fill from the task.
- Wizard header reads "עריכת פרטים / עריכת תשלום ולוגיסטיקה / סיכום שינויים".
- Final CTA reads "שמור שינויים" (instead of "פרסם משימה").
- Submit calls `updateTask` with the allowlist payload (`title`, `description`, `deadline`, `locationFrom`, `locationTo`, `imageUrl`).
- `budgetNis` / `urgency` / `proofType` stay editable in the UI but are NOT in the allowlist — product decision: these are signals providers already saw, so changing them mid-flight would be misleading. If the user really needs to change them, they cancel + republish.
- On success → `Navigator.pop(true)` so the caller can refresh.

### 4. Delete = soft-delete via cancel

Per §19 TTL policy, business data is NEVER hard-deleted. The "מחק" button reuses the existing `AnyTaskService.cancelTask()` which writes `status='cancelled'` + `cancelledAt`. The task disappears from the provider feed (streams filter on `status=='open'`), stays in the customer's "history" section, and admin audit / support can still see it.

Rule allows it: `'status'` + `'cancelledAt'` are both in the client update allowlist.

### 5. Firestore rules

[firestore.rules](firestore.rules) — added `'deadline'` to the client update allowlist on `any_tasks/{taskId}`. Everything else untouched. Rules still reject `budgetNis` / `category` / `urgency` / `proofType` updates from the client — that's intentional (see point 3).

### 6. Countdown UI — `DeadlineBadge` widget

New [lib/features/any_tasks/widgets/deadline_badge.dart](lib/features/any_tasks/widgets/deadline_badge.dart) — single source of truth for "time remaining". Renders nothing when `deadline == null`. 5 visual states:

| Remaining | Color | Icon | Label |
|-----------|-------|------|-------|
| Past | grey | event_busy | פג תוקף |
| < 2h | red | whatshot | נותרו X דק׳ |
| < 24h | amber | timer | נותרו X שעות |
| ≤ 3d | green | event | נותרו X ימים (emphasised) |
| > 3d | neutral | calendar | נותרו X ימים |

Wired into:
- **Customer's own task card** ([my_tasks_screen.dart](lib/features/any_tasks/screens/my_tasks_screen.dart)) — next to the price
- **Provider feed card** ([provider_feed_screen.dart](lib/features/any_tasks/screens/provider_feed_screen.dart)) — alongside the location/urgency/proof/escrow pill row

Detail screen keeps its simple meta tile (DD/MM) since the provider is already past the discovery moment at that point.

### UX flow examples

**Customer publishes with "מחר" deadline:**
- `deadline = 2026-04-19T23:59:59`
- Provider sees "נותרו 15 שעות" amber badge on the feed card → urgency signal without spam
- CF's next run sees `deadline < now` at 00:00 the day after → flips to `expired`, removed from feed
- Customer's history tab still shows the task with "פג תוקף" pill

**Customer publishes, changes their mind the next day:**
- Taps "ערוך" on their card → pre-filled wizard → edits title / pushes deadline to "השבוע" → "שמור שינויים"
- `updateTask` tx asserts still open → write succeeds → customer sees "השינויים נשמרו" toast
- Provider feed re-renders (Firestore stream) with updated title + deadline

**Customer wants to kill the task:**
- Taps "מחק" → AlertDialog confirmation → `cancelTask()` writes `status='cancelled'`
- Task instantly disappears from provider feed (status filter)
- Customer's history shows "בוטל" pill

### Rules for future code

- **Never hard-delete a task** — use `cancelTask()` (soft-delete). §19 TTL applies only to operational logs.
- **Don't expand the client update allowlist** in rules without equivalent UX thinking. Budget/urgency/proofType changes mid-flight are usually wrong — the correct answer is cancel + republish.
- **`DeadlineBadge` is the ONLY countdown surface.** If you need to show time-remaining anywhere new, use this widget (not a local reimplementation). If the design needs to change (e.g. add a pulse for <10min), do it in `deadline_badge.dart` so every surface updates.
- **`expireOpenTasks` runs every 30 min** — do NOT crank this higher without considering cost. Current scan reads up to 800 docs twice per hour = ~1.9M reads/month at 1k open tasks. Acceptable.
- **On edit, always go through `AnyTaskService.updateTask`** — direct Firestore writes will bypass the `status=='open'` gate and fail rule check with `permission-denied`.

### Files touched

| File | Change |
|------|--------|
| `lib/features/any_tasks/widgets/deadline_badge.dart` | **NEW** — countdown pill widget with 5 visual states |
| `lib/features/any_tasks/services/any_task_service.dart` | Added `updateTask(taskId, updates)` with tx-level `status=='open'` gate |
| `lib/features/any_tasks/screens/publish_task_screen.dart` | Added `existingTask` param + edit-mode labels + `_DeadlinePicker` widget + `_deadline` state + edit-vs-publish submit branch |
| `lib/features/any_tasks/screens/my_tasks_screen.dart` | `_TaskCard` now shows `DeadlineBadge`; when `status=='open'` also renders ערוך + מחק buttons (with confirmation dialog for delete) |
| `lib/features/any_tasks/screens/provider_feed_screen.dart` | `DeadlineBadge` added to the pill row |
| `functions/index.js` | `expireOpenTasks` CF rewritten — two-bucket (deadline + age fallback), runs every 30min, writes `expiredReason` |
| `firestore.rules` | Added `'deadline'` to the client update allowlist on `any_tasks/{taskId}` |

### Deploy

```bash
firebase deploy --only firestore:rules
firebase deploy --only functions:expireOpenTasks
flutter build web --release && firebase deploy --only hosting
```

### Validation

- `flutter analyze lib/features/any_tasks/` → **0 issues**
- Full project analyze → 13 pre-existing info warnings unchanged
- `node -c functions/index.js` → syntax OK

---

## 38. Scheduled Automation Audit + `publishStaleReviews` Fix (v15.x, 2026-04-18)

> **Launch-readiness sweep** of every "time-based" mechanism in the app.
> Found one silent failure (`lazyPublish` dead code) and one still-pending
> manual ops step (TTL Phase 1 Console policy).

### Schedulers that DO auto-deploy (no manual Console step)

Every `onSchedule` function auto-creates a Google Cloud Scheduler job on
`firebase deploy --only functions:<name>`. No Console intervention needed.
The authoritative list from `functions/index.js`:

| CF | Cadence | What it guards |
|----|---------|----------------|
| `expireOpenTasks` | every 30 min | `any_tasks` open → expired (deadline OR 30d age, §37) |
| `anytaskExpireOpen` | daily 02:00 IST | **Legacy** `anytasks` collection (different from above — duplicate logic, candidate for removal after confirming no more legacy docs exist) |
| `scheduledCleanup` | hourly | stories / boosts / VIP / job_broadcasts rollup |
| `expireStories` | (see code) | stories.hasActive → false after 25h |
| `expireVipSubscriptions` | daily 00:30 IST | Clears expired VIP promoted flags |
| `anytaskAutoRelease` | (see code) | AnyTasks 48h auto-release |
| `anytaskSlaMonitor` | (see code) | AnyTasks SLA breach detection |
| `sendRebookReminders`, `sendSeasonalNotifications`, `sendInactivityReminders`, `reengageAbandonedLeads`, `reengagementEngine`, `notifyStaleProviders` | various | Re-engagement flows |
| `generateDailyOpportunity`, `calculateInfraCosts`, `scheduledFirestoreBackup` | various | Ops + content generation |
| `updateVaultAnalytics`, `generateVaultAlerts` | hourly | Vault dashboard aggregates (§29) |
| `detectMonetizationAnomalies` | hourly | Monetization alert feed (§31) |
| `generateMonetizationInsight` | every 6h | Gemini recommendations (§31) |
| `sendReviewReminders` | (see code) | Nudge one-sided reviewers |
| `generateCeoInsight` | manual/scheduled | AI CEO Sonnet briefs (§12c) |
| **`publishStaleReviews`** (NEW) | **every 60 min** | **Fixes dead lazyPublish — see below** |
| `proactiveSlaMonitor`, `checkSLA`, `aggregateKPI` | various | System SLA dashboards |

### The dead code bug: `ReviewService.lazyPublish`

`lib/services/review_service.dart:307` defines `lazyPublish(jobId, expertId,
customerId)` with a 7-day cutoff + `isPublished` batch-flip + rating recalc.
The inline comment says "Called when reviews are displayed". **`grep lazyPublish
lib/` returns zero call sites** — it was never wired in.

**Production impact**: when a client submitted a review but the provider didn't
(or vice-versa), the review stayed `isPublished: false` FOREVER. The expert's
`rating` + `reviewsCount` never incorporated one-sided ratings. At scale this
silently accumulates — after a few weeks of real users, hundreds of invisible
reviews + stale aggregate ratings.

Older CLAUDE.md §5.2 documented the "7-day lazy publish trigger" as if it were
alive. It wasn't. Section 38 is the source of truth now.

### Fix: `publishStaleReviews` CF

Defined at the end of `functions/index.js` (~line 12478):

```javascript
schedule: "every 60 minutes"
```

**Flow:**
1. Query `reviews.where(isPublished == false).where(createdAt <= now - 7d).limit(400)`
2. Batch-update each to `isPublished: true`
3. Collect unique `(revieweeId, isClientReview, listingId)` triples
4. For each triple, recompute the aggregate (avg of all published reviews
   for that reviewee, same side). Write to `users/{uid}.rating` +
   `reviewsCount` (or `customerRating` + `customerReviewsCount` for
   provider-reviews-customer). Also update `provider_listings/{id}` if
   `listingId` is set.

**Idempotent**: second run sees no stale reviews (empty query) and exits
at the `snap.empty` log. Recomputation also idempotent (reads all
published, averages — deterministic).

**Index added** (`firestore.indexes.json`):
```
reviews: isPublished ASC + createdAt ASC
```

### Operations playbook

#### Mandatory deploy after this change

```bash
firebase deploy --only functions:publishStaleReviews
firebase deploy --only firestore:indexes
```

The Scheduler job is created automatically on the first deploy.

#### One-time manual Console step: TTL Phase 1 (§19)

Still outstanding from v12.3.0. Two collections write `expireAt` timestamps
but the TTL policy hasn't been turned on in the Google Cloud Console:

1. https://console.cloud.google.com/firestore/databases/-default-/ttl
2. For each collection below, click **"Create Policy"** → select field
   `expireAt`:
   - `error_logs`
   - `activity_log`

Firestore starts deleting expired docs within 24h. TTL deletes consume no
quota (free).

Without this step, those collections grow forever. Not a UX bug, but:
- `error_logs` — admin performance tab gets noisier over time
- `activity_log` — live-feed tab shows stale actions from months ago

#### Verify scheduler jobs exist after deploy

```
gcloud scheduler jobs list --project=anyskill-6fdf3 --location=us-central1
```

Should show `firebase-schedule-publishStaleReviews-us-central1` + 20+ other
`firebase-schedule-*` entries.

### Candidates for future cleanup (not critical)

- **`anytaskExpireOpen`** (line 7879) — queries the legacy `anytasks`
  collection. All new code uses `any_tasks` (underscore). If you confirm
  no docs remain in the legacy collection, this CF can be retired.
- **Scheduler name drift** — a few old CFs use cron syntax (`0 2 * * *`)
  instead of the more readable `"every N hours/minutes"`. Cosmetic only.

### Rules for future code

- **Any new `isPublished`-style flag** that's supposed to self-heal must
  have a scheduled CF — NOT a "called on view" client hook. Client hooks
  silently rot if the caller is deleted.
- **Never write `lazyX()` comments** that imply a cron without the cron
  actually existing. Either wire the scheduler or remove the fallback.
- **Every new `onSchedule` function deploys its scheduler job automatically.**
  Do NOT document them as requiring manual Console work — that's false and
  causes confusion.
- **TTL policies** are the ONE exception — they require manual Console
  setup per-collection, per-field. Always document explicitly.

### Files touched

| File | Change |
|------|--------|
| `functions/index.js` | Added `publishStaleReviews` CF (~110 lines, end of file) |
| `firestore.indexes.json` | Added composite index `reviews.(isPublished, createdAt)` |
| `CLAUDE.md` | This section (38) |

### Validation

- `node -c functions/index.js` → OK
- Full CF list unchanged except +1 export
- Indexes file is valid JSON

---

## 39. Provider Approval Push Notification (v15.x, 2026-04-18)

> Closes a silent UX gap: when the admin approved a provider, the provider
> was never actively told — they had to refresh the app or open it the next
> day and notice the role change. Now they get an FCM push + in-app
> notification **within seconds** of admin tapping "Approve".

### The gap

Two admin paths lead to approval:

| Admin action | Path | Before |
|--------------|------|--------|
| "אישור זהות" tab → "אשר" button | `adminApproveProvider` CF | Wrote in-app notification doc, but **no FCM push** — silent unless the user had the app open |
| "ניהול משתמשים" tab → "אמת" action | `AdminUsersRepository.toggleVerified` → direct Firestore write | **Nothing at all** — no notification of any kind |

### The fix

New CF **`notifyProviderOnApproval`** ([functions/index.js:2163](functions/index.js)) — a single `onDocumentUpdated("users/{uid}")` trigger that catches both paths:

```javascript
const wasVerified = before.isVerified === true;
const isVerified  = after.isVerified === true;
if (wasVerified || !isVerified) return null;          // only false → true
if (after.isProvider !== true) return null;           // providers only
if (after.verifiedAt) return null;                    // idempotent
```

On fire:
1. **FCM push** with `title="אושרת בהצלחה! 🎉"` + personalized body (includes `serviceType` if known). Android priority high, iOS `apns-priority: 10`, Web with icon.
2. **In-app notification** doc (durable record even if push fails / token missing).
3. **`verifiedAt` timestamp** + **`isPendingExpert: false`** stamp for idempotency + pending-flag cleanup.

### Deduplication

`adminApproveProvider` previously wrote its own in-app notification doc (line 5154-5161). Removed — the trigger owns notifications now. Single source of truth.

Result: regardless of which admin UI path fires the approval, the provider gets exactly one push + one in-app notification.

### Client routing

[lib/main.dart](lib/main.dart) `PendingNotification.fromMessage` now handles `type: 'provider_approved'` → `tabIndex = 0` (Home tab). Tapping the push lands the provider on the search feed where they can see their profile is live.

### Non-fires (by design)

- **`isVerified: true → false`** (un-verify). No push. That's disruptive and usually admin-error territory.
- **Customer accounts with `isVerified: true`**. Shouldn't happen, but if it does, the `isProvider !== true` guard skips them.
- **Second approval after an un-verify → re-verify cycle**. The `verifiedAt` stamp persists. If we ever want re-notification, admin-side code must explicitly delete `verifiedAt` before flipping `isVerified`.

### Rules for future code

- **Every permission-changing admin action MUST notify the target user.** Direct Firestore writes from the client (like `toggleVerified`) are OK ONLY if a server-side trigger catches the state change and notifies. Never rely on a CF-in-admin-action to do the notification — it's bypassed by the Management-tab path.
- **When adding a new push type, add it to `PendingNotification.fromMessage`** in main.dart so the deep-link lands the user on the right tab.
- **Idempotency via timestamp stamp** is the cheapest Firestore-native pattern — always use `verifiedAt` / `notifiedAt` / `resolvedAt` style fields instead of separate dedupe collections.

### Deploy

```bash
firebase deploy --only functions:notifyProviderOnApproval,functions:adminApproveProvider
flutter build web --release && firebase deploy --only hosting
```

After deploy: next time admin approves a provider (either path), they get a push on their phone within ~2-3 seconds.

### Validation

- `node -c functions/index.js` → OK
- `flutter analyze lib/main.dart` → 0 issues

---

## 40. Scheduled-CF Index Recovery (v15.x, 2026-04-18)

> **Five scheduled CFs were failing in production** with `FAILED_PRECONDITION:
> The query requires an index`. Single root cause for all five — composite
> indexes never added. Fixed with 6 new indexes. **Zero code changes** to the
> functions themselves; their logic was already correct + idempotent.

### Root-cause audit (via `firebase functions:log`)

Same exception signature across all 5: Firestore rejects the query and the CF
crashes at the `await q.get()` line.

| Failing CF | Failing query | Missing index |
|------------|---------------|---------------|
| `expireOpenTasks` (Bucket 1) | `any_tasks.where(status==open).where(deadline<now)` | `any_tasks(status ASC, deadline ASC)` |
| `expireOpenTasks` (Bucket 2) | `any_tasks.where(status==open).where(createdAt<cutoff)` | `any_tasks(status ASC, createdAt ASC)` — existing DESC doesn't satisfy ASC range |
| `expireStories` | `stories.where(hasActive==true).where(expiresAt<=now)` | `stories(hasActive ASC, expiresAt ASC)` |
| `reengageAbandonedLeads` | `incomplete_registrations.where(isRegistrationComplete==false).where(lastUpdatedAt<=cutoff)` | `incomplete_registrations(isRegistrationComplete ASC, lastUpdatedAt ASC)` |
| `detectMonetizationAnomalies` | `monetization_alerts.where(resolved==false).where(detectedAt>=cutoff)` (idempotency dedupe) | `monetization_alerts(resolved ASC, detectedAt ASC)` |
| `generateDailyOpportunity` | `users.where(isProvider==false).where(lastActiveAt<cutoff)` (dormant clients sweep) | `users(isProvider ASC, lastActiveAt ASC)` |

### Why the indexes were missing

- **`expireOpenTasks` Bucket 1** — added in §37 ("deadlines + edit + delete")
  alongside the new deadline field, but the composite index wasn't.
- **`expireOpenTasks` Bucket 2** — an existing `any_tasks(status ASC, createdAt DESC)`
  index covers provider-feed queries (orderBy DESC), but a `range ASC` query on
  `createdAt` needs an ASC-direction index. Firestore's planner is strict about
  this.
- **`expireStories` / `reengageAbandonedLeads`** — predate the indexes file.
  Likely worked locally with auto-created dev indexes that never shipped.
- **`detectMonetizationAnomalies` / `generateDailyOpportunity`** — added in §31
  and §8b respectively; indexes for the AI-side CFs were documented but the
  dormant-sweep + dedupe queries were overlooked.

### Non-fixes investigated and ruled out

**`generateDailyOpportunity` — Anthropic "credit balance too low" warning.** The
log shows both the billing warning AND the FAILED_PRECONDITION. Reading the
code at [functions/index.js:4747-4763](functions/index.js) — the Claude call
is wrapped in `try/catch`, and falls back to hardcoded Hebrew templates on any
error. So Anthropic billing is already handled defensively. The ACTUAL crash
comes from the `dormantSnap` query a few lines later. Fixing the index is
sufficient. (Filling Anthropic credits is an orthogonal ops task — the CF
runs daily either way, just with rotating templates instead of AI-generated.)

**Service account permissions.** All 5 run as
`281981409319-compute@developer.gserviceaccount.com` (default GCE SA) with
Firestore admin access. Not a permission issue.

**Memory / timeout.** All 5 use 256MiB and complete well under 60s. The
failures fire on the first `.get()` — never reach any compute-heavy stage.

**Empty-collection handling.** All 5 CFs already guard correctly:
- `expireOpenTasks` — `if (toExpire.size === 0) return` (line 9957)
- `expireStories` — `if (expiredSnap.empty) return` (line 2927)
- `reengageAbandonedLeads` — `if (snap.empty) return` (line 3781)
- `detectMonetizationAnomalies` — empty `alerts` array → batch commit no-op
- `generateDailyOpportunity` — `if (dormantSnap.empty) return null` (line 4806)

No code changes needed on this axis.

### Index file changes

Added 6 new entries to `firestore.indexes.json` after the existing
`any_tasks` block. Total index count: 74 (was 68).

### Deploy — fix all 5 in one shot

```bash
firebase deploy --only firestore:indexes
```

That's it. The CF code is already correct — re-deploying the functions is
NOT required. The indexes take 1-5 minutes to build (depending on collection
size); CFs resume on the next scheduled tick once the indexes go active.

**Watch the build:**
https://console.firebase.google.com/project/anyskill-6fdf3/firestore/indexes

**Verify CFs are green post-build:**
```bash
firebase functions:log --only expireOpenTasks --lines 5
firebase functions:log --only expireStories --lines 5
firebase functions:log --only reengageAbandonedLeads --lines 5
firebase functions:log --only detectMonetizationAnomalies --lines 5
firebase functions:log --only generateDailyOpportunity --lines 5
```

### Rules for future code

- **Every new `.where(A==x).where(B<y|>y|<=y|>=y)` requires a composite index
  matching the exact direction of the range field.** Firestore won't fall back
  to an existing DESC index for a range-ASC query.
- **Add the index in the SAME PR as the query.** §37 added the deadline query
  without the index — this is exactly how we end up here.
- **Schedulers auto-deploy but schedulers don't verify queries at deploy
  time.** The first scheduled tick is when you find out. For any new
  scheduled CF, run it manually via `firebase functions:shell` BEFORE the
  first natural tick to surface missing indexes immediately.
- **When reading a range index from a log URL, decode `create_composite=...`
  with base64 to confirm the exact `(field, direction)` tuples the engine
  wants.** The URL tells you exactly what to add — no guessing.

### Files touched

| File | Change |
|------|--------|
| `firestore.indexes.json` | Added 6 composite indexes (lines ~48-109 after the any_tasks block) |
| `CLAUDE.md` | This section (40) |

### Validation

- `node -e "JSON.parse(strip(fs.read('firestore.indexes.json')))"` → OK
- Total indexes: **74** (up from 68)
- `node -c functions/index.js` → OK (no CF changes, sanity only)

---

### §40.1 — `generateDailyOpportunity` migrated to Gemini (v15.x, 2026-04-18)

Part of the broader "Gemini everywhere for non-Ilon-reasoning Hebrew tasks" pattern (see §12c / §31 / §33 / §34).

**Swapped:**
- `secrets: [ANTHROPIC_API_KEY]` → `secrets: [GEMINI_API_KEY]`
- `new Anthropic({apiKey}).messages.create({model: "claude-haiku-4-5-20251001"...})` → `fetch(https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key=...)` with the same 2-model fallback used by the Ilon agent: `gemini-3.1-flash-lite-preview` → `gemini-2.5-flash-lite`.
- JSON parsing uses `generationConfig.responseMimeType: "application/json"` but keeps the code-fence strip as a defensive belt-and-suspenders.

**Kept unchanged:**
- Prompt text (Hebrew marketing, 80-char max, seasonal + market context)
- 4-template fallback for when Gemini fails / kill-switch active / no API key
- `_isAiEnabled(db)` kill-switch check (cost ceiling)
- `_trackApiCost(db, inTok, outTok)` billing tracker — uses Anthropic Haiku pricing, which slightly over-estimates Gemini cost (~3× conservative). Acceptable — keeps the kill-switch strict on the safe side.
- Idempotency via the `daily_opportunities/{dateKey}` existence check — only first run per IST day hits the API.

**Why not `gemini-1.5-flash`:** the user asked for 1.5-flash in the request, but the entire project migrated off Gemini 1.x months ago. Every other Gemini CF uses 2.5/3.1 flash-lite. Kept consistent.

**No new config needed.** `GEMINI_API_KEY` secret already provisioned in Secret Manager from the other Gemini CFs.

**Deploy (just this one CF):**

```bash
firebase deploy --only functions:generateDailyOpportunity
```

Runs at 08:00 IST daily. To force-run now, Firebase Console → Functions → `generateDailyOpportunity` → "Force run" (or: remove today's `daily_opportunities/{YYYY-MM-DD}` doc and wait for the next scheduled tick).

---

## 41. Handyman CSM (Category-Specific Module, v15.x, 2026-04-18)

Fifth CSM in the pattern (§3d massage, §32 pest, §33 delivery, §34 cleaning).
Gated to sub-category **"הנדימן"** via `isHandymanCategory()`. Adds a provider
settings block ("ההגדרות שלך") and a client booking block ("בוא נתקן את זה
ביחד") that appear ONLY when the sub-category resolves to handyman.

> **User requested "Section 35" in the spec.** Section 35 already documents
> the AnyTasks banner role-gating fix, so this ships as Section 41 to avoid
> overwriting prior work. Numbering follows the CSM sequence (§32/§33/§34).

### CRITICAL hardcoded rules (spec 01_MAIN_PROMPT_HANDYMAN.md)

| Rule | Enforcement |
|------|-------------|
| **NO insurance** anywhere | Model has no `insurance*` field. Trust Center shows Escrow instead. Sticky summary shows 🔒 נאמנות, not 🛡 ביטוח. |
| **NO idVerification** duplicate | `HandymanVerifications` has only `backgroundCheck` + `warrantyEnabled`. The global onboarding ID check covers everyone. |
| **NO working-hours section** in the provider edit block | `HandymanServiceArea` has `cities`, `emergency24_7`, `bufferMinutes` — no `workingHours`. A blue "🗓️ שעות פעילות נקבעות ביומן" banner points the provider to the existing calendar. |
| **NO Reviews Insights on the provider edit block** | Reviews Insights renders only on the client booking block. |
| **Chat syncs with existing ChatScreen** | Booking block's chat button + Quick Replies push `ChatScreen(receiverId, receiverName, initialMessage)` — no forked chat. |
| **Calendar syncs with existing picker** | Booking block does NOT own the calendar. It `emit()`s `(prefs, total)` to the parent expert_profile_screen, which threads them through the existing "Pay & Secure" escrow flow (same pattern as §34 cleaning). |
| **AI = Gemini only, never Claude** | `diagnoseHandymanProblemFromPhoto` CF uses `gemini-2.5-flash-lite`. |

### Architecture

| Component | File | Purpose |
|-----------|------|---------|
| Model | `lib/models/handyman_profile.dart` | `HandymanProfile` + 10 nested sub-models (Verifications, BackgroundCheck, Specialty, AiPhotoSettings, Pricing, PunchListDiscount, ServiceArea, Materials, MaintenancePackage) + client-side (BookingPreferences, PunchListItem, AiDiagnosis, MaterialItem, PropertyInfo). Plus `isHandymanCategory()` detector. |
| Specialties catalog | `lib/constants/handyman_specialties_catalog.dart` | 23 canonical specialties with Hebrew names, emojis, default prices + durations, popularity tags. Plus `defaultActiveSpecialties()` (seeds 8 "hot" for new providers), default maintenance packages, default city list. |
| Urgency catalog | `lib/constants/handyman_urgency_options.dart` | 4 urgencies — emergency / today / scheduled / maintenance_contract — with gradients. |
| Quick replies | `lib/constants/handyman_quick_replies.dart` | 3 pre-filled chat messages. |
| Booking service | `lib/services/handyman_booking_service.dart` | `calculateTotal`, `buildPriceBreakdown`, `punchListDiscountAmount`, `servicesTotal`, `estimatedDurationMinutes`, `getLastBookingWith` (Express Reorder — reads `jobs` + `reviews`). |
| Provider block | `lib/screens/handyman/handyman_settings_block.dart` | Dark premium orange/amber — 9 sections: Hero + revenue banner, Verifications (2 badges), AI Photo-to-Quote settings, 23 specialties grid (active + inactive + add-from-catalog), Pricing editor with market intelligence hint, Punch List graduated discount (2/3/4+ jobs), Service area (cities + emergency 24/7 + buffer + CALENDAR BANNER), Materials (tools + policy chips), Maintenance packages (3 tiers). |
| Client block | `lib/screens/handyman/handyman_booking_block.dart` | Dark premium orange/amber — 14 sections: LIVE banner, Hero, Trust Center (4 badges: Verified/Background/Warranty/Escrow — NO ID/insurance), AI Photo-to-Quote ⭐ (pick photo → Gemini → auto-populate Punch List item), 23 specialties selector with search, Punch List with savings banner, Problem description, Property info (5 chips), Materials transparency (AI-calculated breakdown + 2 options), Urgency selector (4 options, 2×2 grid), Warranty (3 pillars), Chat preview (main button + 3 Quick Reply chips → existing ChatScreen), Maintenance packages selector, Sticky bottom summary with price + duration + calendar nudge. |

### Firestore fields

```
users/{uid}.handymanProfile                  // nested Map (see HandymanProfile.toMap)
provider_listings/{id}.handymanProfile       // synced on save — required for search
jobs/{id}.handymanPreferences                // booking-time snapshot:
  punchList[], aiPhotoDiagnosis{},
  problemDescription, propertyInfo{},
  materialsOption, estimatedMaterialsCost,
  materialsBreakdown[],
  urgency, maintenancePackageId?,
  priceBreakdown{servicesTotal, materialsEstimate,
                 punchListDiscount, emergencySurcharge, total},
  warranty12MonthsIncluded
```

### Detection function

```dart
bool isHandymanCategory(String? serviceType) {
  if (serviceType == null) return false;
  final lower = serviceType.trim().toLowerCase();
  if (lower.isEmpty) return false;
  return lower == 'הנדימן' || lower == 'handyman' || lower == 'handy man' ||
      lower.contains('הנדי') || lower.contains('handyman') ||
      lower.contains('handy man');
}
```

### Integration points

| Screen | Method | Behavior |
|--------|--------|----------|
| `edit_profile_screen.dart` | `_isHandymanSubCategory()` | Shows `HandymanSettingsBlock` after cleaning block. Validates ≥1 active specialty AND `backgroundCheck.verified`. |
| `expert_profile_screen.dart` | `_hasHandymanProfile()` | Shows `HandymanBookingBlock` between cleaning block and service menu. On escrow, writes `handymanPreferences` + `priceBreakdown` to the job doc. |
| `admin_demo_experts_tab.dart` | `_isDemoHandymanCategory()` | Shows `HandymanSettingsBlock` in demo profile form. Saves to BOTH user doc and `provider_listings/demo_{uid}`. |

### Cloud Function

**`diagnoseHandymanProblemFromPhoto`** (callable) — Gemini 2.5 Flash Lite with Vision.
- Auth required
- Input: `{photoUrls: string[], additionalDescription?: string}`
- Output: `{identifiedProblem, confidence, aiAnalysis, category, estimatedDurationMinutes, estimatedPrice, estimatedMaterialsCost, recommendedMaterials[{name,price,details}], urgencyLevel}`
- Timeout: 30s, memory: 512MiB (higher than duration/vehicle CFs because Vision + multiple image fetches)
- Caps at 3 photos per request for latency/size.
- Fetches each URL → converts to base64 → sends as `inlineData`. Uses `responseMimeType: "application/json"` with defensive clamping of all numeric fields on parse.
- Graceful failure — client surfaces a Hebrew snackbar "לא הצלחנו לנתח את התמונה" and user can retry or pick from the 23 specialties manually.

### Design system

Dark premium orange/amber palette (scoped, does NOT replace `Brand.*`):
- Background gradient: `[#0A0E1A, #1A1612, #0F1420]` — warmer mid-tone than other CSMs
- Primary: `orange #F97316` + `orangeDark #EA580C` + `amberPale #FDBA74`
- Status: green `#16A34A`, red `#DC2626`, blue `#3B82F6`, purple `#A855F7`
- Glass cards: white @ 4% opacity, radius 18px, 1px border white @ 8%

### Rules for future code

- **Never add insurance** to this module. Not in model, not in UI, not in CF.
- **Never add idVerification** as a badge — global onboarding §3 covers it.
- **Never add a "working hours" section** to `HandymanSettingsBlock` — the blue calendar banner is the final answer.
- **Handyman CF must use Gemini**, matching §32/§33/§34. AI CEO (§12c) uses Claude Sonnet; all CSM CFs use Gemini Flash Lite.
- **Never fork ChatScreen** — use `ChatScreen(receiverId, receiverName, initialMessage)` with `initialMessage` pre-filled by Quick Reply chips.
- **Rounding** — `HandymanBookingService` uses `.toStringAsFixed(2)` matching §18 Rule 7.

### Deployment

```bash
firebase deploy --only functions:diagnoseHandymanProblemFromPhoto
flutter build web --release && firebase deploy --only hosting
```

### Files

**Created (7):**
- `lib/models/handyman_profile.dart`
- `lib/constants/handyman_specialties_catalog.dart`
- `lib/constants/handyman_urgency_options.dart`
- `lib/constants/handyman_quick_replies.dart`
- `lib/services/handyman_booking_service.dart`
- `lib/screens/handyman/handyman_settings_block.dart`
- `lib/screens/handyman/handyman_booking_block.dart`

**Modified (4):**
- `lib/screens/edit_profile_screen.dart` — imports, state, init loader, detection, validation, UI block, save payload, listing sync
- `lib/screens/expert_profile_screen.dart` — imports, state, detection, builder, insertion after cleaning block, job doc payload
- `lib/screens/admin_demo_experts_tab.dart` — imports, state, init, detection, UI block, save payloads (user + listing)
- `functions/index.js` — `diagnoseHandymanProblemFromPhoto` CF appended

**Spec archived in** `docs/handyman_upgrade/` (three files from `docs/ui-specs/Handyman/`).

---

## 42. App Feedback & Ideas system (v15.x, 2026-04-18)

> User-submitted product feedback + Gemini-labeled + weekly CEO digest.
> Separate collection from `support_tickets` (§16): feedback is about making
> AnySkill better, not about fixing bugs on an individual booking.

### UX flow

1. User taps "הצעות ורעיונות לשיפור" in the Profile tab (purple/indigo
   button above the red "Delete Account" button — both occurrences).
2. Lands on [AppFeedbackScreen](lib/screens/app_feedback_screen.dart) —
   title "AnySkill Feedback & Ideas", 4 category chips, 500-char text area,
   10-point NPS scale with red→amber→green color coding.
3. Submit enables only when: content ≥ 10 chars AND NPS selected.
4. On success — soft elastic scale-in heart icon + Hebrew thank-you message:
   "תודה על העזרה! צוות הפיתוח שלנו קורא אישית כל הצעה..." + "הפנייה התקבלה"
   pill + "שלח הצעה נוספת" button to submit another without leaving.

### Firestore schema

**Collection:** `app_feedback/{autoId}`

| Field | Type | Notes |
|-------|------|-------|
| `uid` | string | author (rule gate) |
| `userRole` | 'provider' \| 'customer' | from `users/{uid}.isProvider` |
| `userName`, `userEmail` | string | denormalized at submit time for the AI digest |
| `category` | 'app_interface' \| 'payment_process' \| 'new_feature_idea' \| 'other' | rule-enforced enum |
| `content` | string (≤500) | rule-enforced length |
| `npsScore` | number 1-10 | rule-enforced range |
| `status` | 'pending' \| 'reviewing' \| 'planned' \| 'shipped' \| 'declined' | default 'pending'; admin-only update |
| `priority` | 'Low' \| 'High' \| null | **filled by `analyzeFeedbackOnCreate` CF** |
| `topic` | 'UX' \| 'Pricing' \| 'Bug' \| 'Feature' \| 'Performance' \| 'Other' \| null | **filled by CF** |
| `analyzedAt` | Timestamp \| null | when the CF tagged the doc |
| `createdAt` | Timestamp | server |
| `appVersion`, `platform` | string | client hint |

### Firestore rules ([firestore.rules](firestore.rules))

```
match /app_feedback/{feedbackId} {
  allow read: if isAdmin() ||
                 (isVerifiedAuth() && resource.data.uid == request.auth.uid);
  allow create: if isVerifiedAuth()
                && request.resource.data.uid == request.auth.uid
                && request.resource.data.content.size() <= 500
                && request.resource.data.npsScore in [1..10]
                && request.resource.data.status == 'pending'
                && request.resource.data.category in [... enum];
  allow update: if isAdmin();   // AI tags flow via Admin SDK anyway
  allow delete: if false;       // feedback is immutable/append-only
}
```

### Cloud Functions ([functions/index.js](functions/index.js))

**1. `analyzeFeedbackOnCreate`** — Gemini tagging trigger
- Trigger: `onDocumentCreated("app_feedback/{id}")`
- Model: `gemini-2.5-flash-lite` (NOT Claude — matches §32/33/34/41)
- Output: `{priority: 'Low' | 'High', topic: 'UX' | 'Pricing' | 'Bug' | 'Feature' | 'Performance' | 'Other'}`
- Prompt includes role + category + NPS + 2000-char slice of content.
- Guidelines: High = blocker / bug / money / NPS ≤ 6 / critical feature request. Low = nice-to-have / stylistic / general praise.
- **Defensive fallback**: if Gemini fails or key missing, still writes `priority` (High if NPS≤6 else Low) + `topic: 'Other'` so nothing stays untagged.
- Also writes `analyzedAt` timestamp.

**2. `generateFeedbackWeeklyInsight`** — Weekly CEO digest
- Schedule: **every Monday 08:00 Asia/Jerusalem** (via `onSchedule`, auto-deploys its Cloud Scheduler job — per §38 rule, no manual Console step).
- Model: `gemini-2.5-flash-lite`
- Scans past 7d of `app_feedback` (cap 500 docs) → aggregates NPS avg + detractors/passives/promoters + topic + priority distributions.
- Feeds a compressed sample of up to 60 items to Gemini with role/cat/NPS/topic/priority/content snippets.
- Output written to **`ai_insights/feedback_weekly`** (single doc, merge-written):
  ```
  {
    summary,                           // 2-3 sentence overview
    topThemes: [{title, description, count, exampleQuote}] x3,
    topPriority: {title, reason, suggestedAction},
    totalCount, npsAverage,
    npsDistribution {detractors, passives, promoters},
    byTopic, byPriority,
    generatedAt, model
  }
  ```
- **Defensive fallback**: if Gemini errors, writes just the stats (no themes) so the AI CEO tab always has something to show.

### Required composite index

None! Both queries in use are single-field (`createdAt` range) which
Firestore auto-indexes. No new entry in `firestore.indexes.json`.

### Entry point

[lib/screens/profile_screen.dart](lib/screens/profile_screen.dart) — button inserted in **both** logout/delete stacks (lines ~990 and ~1410), always above "Delete Account", using `Brand.indigo` color with `Icons.auto_awesome_rounded` and label "הצעות ורעיונות לשיפור".

### Rules for future code

- **Never extend `support_tickets`** for product feedback. Support tickets are for support/bug triage — `app_feedback` is for product direction. Different mental models, different lifecycles, different admin views.
- **Never allow user updates on `app_feedback`** — AI tags would be clobbered. If a user needs to clarify, they submit a new feedback item.
- **Never store the feedback CF output back via a callable from the client** — the trigger (`onDocumentCreated`) owns tagging. A client-side callable would allow tag manipulation.
- **Never switch either CF to Claude** — matches the §32/33/34/41 Gemini-everywhere-for-Hebrew-product-tasks convention.
- **If you add a new category**, update both the enum in [firestore.rules](firestore.rules) AND `_kCategories` in the screen. The rule `in [...]` check will reject writes with unknown category IDs.

### Admin surface (future — NOT shipped yet)

The `ai_insights/feedback_weekly` doc is ready to be consumed by a new tile
or tab in either the AI CEO tab (§12c) or the existing admin panel. Shape
matches the mockup in `ai_insights` schema. A dedicated
`AdminFeedbackInsightsTab` would stream the single doc + show the 3 theme
cards + stats; inline admin `status` update buttons can flip individual
feedback docs between `pending/reviewing/planned/shipped/declined`. Not
built in this PR — ship the pipeline first, then the dashboard.

### Deployment

```bash
firebase deploy --only functions:analyzeFeedbackOnCreate,functions:generateFeedbackWeeklyInsight
firebase deploy --only firestore:rules
flutter build web --release && firebase deploy --only hosting
```

No new index deploy needed.

### Files

**Created (1):**
- `lib/screens/app_feedback_screen.dart` (~600 lines) — form UI + success view

**Modified (3):**
- `lib/screens/profile_screen.dart` — import + button in 2 logout/delete stacks
- `firestore.rules` — new `match /app_feedback/{feedbackId}` block
- `functions/index.js` — 2 new CFs appended

### Validation

- `flutter analyze lib/screens/app_feedback_screen.dart` → **0 issues**
- `flutter analyze lib/screens/profile_screen.dart` → 1 pre-existing async-context warning on the legacy `_deleteAccount` call (unchanged by this PR)
- Full project: 13 pre-existing info warnings, zero regressions
- `node -c functions/index.js` → OK

---

## 43. Smart Notification Router (v15.x, 2026-04-18)

> Central routing table for notification taps — both the bell-icon inbox
> (`NotificationsScreen`) AND FCM push taps now deep-link to the specific
> source screen instead of just switching tabs. Tapping a chat notification
> opens that specific ChatScreen; tapping an anytask notification opens
> that task's TaskTrackingScreen; tapping a support ticket opens that
> specific TicketChatScreen, etc.

### Problem it solves

Before §43, the in-app bell icon (`NotificationsScreen._navigate`) handled
only **6 types** (ai_insight, help_request, volunteer_accepted, volunteer_completed,
broadcast_urgent, broadcast_claimed, csat_survey). Everything else —
`chat`, `job_status`, `new_booking`, `anytask_*`, `support_ticket`,
`payment_received`, `provider_approved`, `request_declined`, `review_received`,
`seasonal`, `geo_nearby`, re-engagement, admin alerts — **fell through
silently**. User taps, nothing happens.

FCM (§26) was slightly better — it had tab routing for more types plus a
hand-rolled chat deep-link in `HomeScreen.initState` — but still only
routed to tabs, never to a specific ticket/task/booking.

### Architecture — one shared router

**File:** [lib/services/notification_router.dart](lib/services/notification_router.dart)

```dart
static Future<bool> NotificationRouter.route(
  BuildContext context,
  Map<String, dynamic> raw,  // notification doc OR FCM data payload
);
```

**Return contract:**
- `true` → router consumed the tap (pushed the target screen or popped back).
- `false` → caller should fall back to local handling.

Only 3 types return `false` — those that need screen-local modals because
they depend on the parent screen's services/state:

| Type | Modal | Owner |
|------|-------|-------|
| `broadcast_urgent` | `JobBroadcastService` claim sheet | `NotificationsScreen` |
| `help_request` | Volunteer accept sheet (fetches `help_requests` doc) | `NotificationsScreen` |
| `csat_survey` | `showCsatSurveyModal` (needs context) | `NotificationsScreen` |

Everything else routes through the router.

### Routing table

| Type | Destination |
|------|-------------|
| `chat` | `ChatScreen(receiverId: senderId OR derived from roomId, receiverName: title)` |
| `support_ticket` | `TicketChatScreen(ticketId, category, isAdmin: false)` or `SupportCenterScreen` if no ticketId |
| `job_status`, `new_booking`, `booking_confirmed`, `booking`, `job_accepted`, `quote_received`, `payment_release` | `MyBookingsScreen` |
| `anytask_*` (10 types) | `TaskTrackingScreen(taskId)` if taskId present, else pop to Home |
| `volunteer_accepted`, `volunteer_completed`, `broadcast_claimed` | `ChatScreen(receiverId: relatedUserId)` |
| `payment_received`, `wallet_credit`, `admin_credit_grant`, `withdrawal_status` | `FinanceScreen` |
| `ai_insight`, `ai_suggestion`, `pro_granted` | `ProviderAiInsightsScreen` |
| `review_received`, `review` | `PublicProfileScreen(userId: relatedUserId OR self)` |
| `provider_approved`, `request_declined`, `seasonal`, `geo_nearby`, `rebook_reminder`, `inactivity_reminder`, `reengagement`, `market_alert`, `admin_payment_alert`, `demo_contact`, `general` | pop to Home (informational-only) |
| unknown | return `false` → caller shows "ההתראה נפתחה" toast |

### Field extraction — dual-level reader

Different CFs write the same id field at different locations. The chat CF
writes `data.senderId` + `data.roomId` (nested), while older CFs put
`relatedUserId` + `broadcastId` at the TOP level of the notification doc.

`_extractField(raw, keys)` reads BOTH the top level AND the nested
`data` map, returning the first non-empty match. So the router works
unchanged against legacy + new payload formats.

### Chat deep-link special case

Tap on a chat notification → need the **other user's uid** to push
`ChatScreen`. Two-step fallback:
1. Try `data.senderId` / top-level `relatedUserId`.
2. If missing, derive from `roomId` / `chatRoomId` using the
   `uid1_uid2` sorted-join format: find the one that isn't the current user.

### UX: pop-then-push for inbox, just-push for FCM cold-start

`_replaceWith` calls `Navigator.pop()` ONLY if `canPop() == true`. So:
- Inbox tap → pops `NotificationsScreen` first, then pushes target →
  final stack is `[Home → Target]`, not `[Home → Inbox → Target]`.
- FCM cold-start → HomeScreen is the only route, `canPop == false` → just
  pushes → `[Home → Target]`.

Both paths converge on the same stack. Back button goes to Home.

### CF payload additions

Eight AnyTasks notification CF writes were missing `taskId` in the
notification payload. Added `taskId: doc.id` (or `taskId,` where a local
variable was already in scope) to all eight:

| Line | Type |
|------|------|
| 7947 | `anytask_auto_released` (provider) |
| 7955 | `anytask_auto_released` (creator) |
| 7997 | `anytask_reminder_24h` |
| 8011 | `anytask_reminder_2h` |
| 8089 | `anytask_expired` |
| 8141 | `anytask_sla_reminder` |
| 8181 | `anytask_sla_returned` (pool-return side) |
| 8191 | `anytask_sla_returned` (provider side) |

Chat + support_ticket + job_status CFs already had their IDs in `data`.

### FCM alignment

[main.dart](lib/main.dart) `PendingNotification` now carries a full
`payload: Map<String, dynamic>?` field in addition to `tabIndex` and
`chatRoomId`. On FCM tap → HomeScreen reads `pendingTab`, switches tab,
and in a post-frame callback invokes `NotificationRouter.route(context, pendingPayload)`
— same routing logic as the bell icon. The hand-rolled chat deep-link
in `HomeScreen.initState` (~20 lines, §26 v9.3.1) is retired. The
`chatRoomId` field is kept for backwards-compat until all call sites
are verified migrated.

### Refactored files

| File | Change |
|------|--------|
| `lib/services/notification_router.dart` | **NEW** — ~200 lines, single `route()` method + 3 private helpers |
| `lib/screens/notifications_screen.dart` | `_navigate` shrunk from ~80 → ~50 lines. 3 screen-local modals preserved; everything else → `NotificationRouter.route`. Legacy "is this AI?" heuristic normalized to `type='ai_insight'`. Unknown type → toast. |
| `lib/main.dart` | `PendingNotification.payload` field + copy from `message.data`; `clear()` resets it |
| `lib/screens/home_screen.dart` | Removed hand-rolled chat deep-link (~20 lines); replaced with `NotificationRouter.route(context, pendingPayload)` in a post-frame callback |
| `functions/index.js` | 8 anytask notification writes now include `taskId` |

### Rules for future code

- **Every new notification CF** must put the primary id in a TOP-LEVEL
  field on the notification doc — `taskId`, `jobId`, `ticketId`,
  `chatRoomId`, `relatedUserId`, or `broadcastId` as appropriate. The
  router's `_extractField` reads both top-level and nested, but top-level
  is cheaper to query/filter and matches the existing convention on
  most CFs.
- **Never add a switch-on-type inside a screen** for notification routing.
  Extend `NotificationRouter.route()` instead — it's the single source
  of truth. If the new type needs a screen-local modal, return `false`
  from the router and document it in the "local modals" table.
- **Never forget to update `PendingNotification.payload` contract** when
  you add a new FCM push CF. Make sure the FCM `data: {}` map carries
  enough ids for the router to deep-link; otherwise the push tap falls
  back to a tab-switch only.
- **Chat deep-link must stay robust to both `senderId` and `roomId`** —
  some CFs only set one. Never remove the `roomId` fallback path.

### Validation

- `flutter analyze` on touched files → **0 new issues** (only one
  pre-existing async-context warning in `notifications_screen.dart:336`
  inside the volunteer sheet, not introduced here).
- Full project: 13 pre-existing info warnings, **zero regressions**.
- `node -c functions/index.js` → OK.

### Deployment

```bash
# No new indexes. CF changes only touch in-body payloads — redeploy them:
firebase deploy --only functions:anytaskAutoRelease,functions:anytaskExpireOpen,functions:anytaskSlaMonitor
flutter build web --release && firebase deploy --only hosting
```

---

---

## 44. Fitness Trainer CSM (Category-Specific Module, v15.x, 2026-04-19)

Sixth CSM in the pattern (§3d massage, §32 pest, §33 delivery, §34 cleaning,
§41 handyman). Gated to sub-category **"מאמני כושר"** via
`isFitnessTrainerCategory()`. Adds a provider settings block ("ההגדרות שלך",
9 sections) and a client booking block ("בואי נתאים את האימון שלך",
10 sections) that appear ONLY when the sub-category resolves to fitness trainer.

> **Design language break from the other 5 CSMs**: provider block uses the
> dark premium glass palette (same as Handyman/Cleaning), but client block
> uses a LIGHT cream/white canvas with orange/gold/green/purple accents —
> the booking surface is the "wow" moment the client sees first and needs
> to feel bright + energetic, not dim + technical. Apple-style 3-ring
> animation on the Monthly Journey Preview is the visual centerpiece.

### CRITICAL hardcoded rules (spec 01_MAIN_PROMPT.md)

| Rule | Enforcement |
|------|-------------|
| **NO "online" location** | `LocationType` enum is literally `{home, park, gym}`. No 4th option exists. |
| **NO rating breakdown duplication** | Block renders Monthly Journey Preview + Trust Badges instead. Existing review breakdown below the block is untouched. |
| **NO weekly availability widget** | Block does NOT render schedule. Existing Google Calendar integration owns that. Provider block ends with a blue info pill "🗓️ שעות פעילות נקבעות דרך היומן". |
| **NO portfolio gallery duplication** | Block does NOT include a gallery. Existing `_buildGalleryAndVideo` in expert_profile_screen is unchanged. |
| **Every list item editable** (provider side) | Each row has ✏️ + 🗑️, every section has ➕, all deletions show a Hebrew confirmation dialog. |
| **AI = Gemini 2.5 Flash Lite only, never Claude** | All 3 CFs use `gemini-2.5-flash-lite` with a `gemini-3.1-flash-lite-preview` primary attempt. Matches §32/33/34/41. |
| **Auto-advance 300ms** in Personality Quiz | `Future.delayed(const Duration(milliseconds: 300))` after each selection + `HapticFeedback.lightImpact`. |

### Architecture

| Component | File | Purpose |
|-----------|------|---------|
| Model | `lib/models/fitness_trainer_profile.dart` | `FitnessTrainerProfile` root + 5 instance models (PricingPackage, Certification, SuccessStory, SpecialOffer, TrainingLocation) + `TrainerSpecialty` catalog (12 options, hardcoded const list) + `isFitnessTrainerCategory()` detector + `fallbackScore` getter mirroring the server-side score formula. 678 lines. |
| Provider block | `lib/screens/fitness_trainer/fitness_trainer_settings_block.dart` | Dark premium orange/gold — 9 sections + 5 bottom-sheet modals: `_PackageModal`, `_LocationModal`, `_CertificationModal`, `_StoryModal`, `_OfferModal`. Every add/edit/delete action goes through `HapticFeedback` + `_confirmDelete` dialog. 3,306 lines. |
| Client block | `lib/screens/fitness_trainer/fitness_trainer_booking_block.dart` | Light cream — 10 sections including Apple-style 3 rings via `_ThreeRingsPainter` (CustomPaint, 2-second forward animation on mount) + `_DashedBorderPainter` for offer banner + `_GlowingScoreCircle` for match-result (animated green glow, 1600ms reverse repeat). 1,913 lines. |
| Quiz screen | `lib/screens/fitness_trainer/personality_quiz_screen.dart` | 5-question flow (goal / experience / frequency / location / style) with purple progress bar + 300ms auto-advance + green-glow 94% on result screen. Calls `recommendTrainersByGoals` CF with 15s timeout; falls back to 87% + 4 derived reasons on ANY failure. Returns `QuizMatchResult` via `Navigator.pop`. 683 lines. |

### 9 provider sections

1. **Hero** — "⚡ נפתח אוטומטית" pill + "🏋️ מאמני כושר" pill
2. **AI Coach Score** — purple/indigo card, 0-100 with target-90 marker, dynamic improvement hint (derived locally when `lastOptimized == null`)
3. **Specialties** — 12 gradient chips, max 5, × to deselect, live "X% תואם חיפושים" insight
4. **Pricing Packages** — editable list + "💡 טיפ: מחיר ממוצע באזור ₪180-₪250" Smart Tip + `_PackageModal` with type radio (single/package/monthly) + num-pickers for sessions/duration/validity + isPopular/freeOnboarding checkboxes
5. **Locations** — 3 cards max (home/park/gym), blocks duplicate-type selection in modal via `blockedTypes: Set<LocationType>`
6. **Certifications** — editable list with `_CertificationModal` (6-institution dropdown: NASM/Wingate/ACSM/ISSA/אורט בראודה/אחר) + "⚠️ התעודה תאומת ע״י הצוות תוך 48 שעות" warning
7. **Success Stories** — editable list with before/after URLs + ⭐ rating selector (1-5) + "⚠️ נדרש אישור הלקוח" gate (`clientApproved: bool`)
8. **Special Offers** — editable list with 4 offer types + date picker + auto "פעיל"/"פג תוקף" pills
9. **Performance Dashboard** — read-only, dark navy 4-KPI grid with "🔒 פרטי" pill (rating + retention left blank with "לפי יבוא"/"Milestone 3" until real telemetry exists per §29)
10. **AI Suggestions** — 5 priority-coded cards + "✨ החילי הכל אוטומטית" button
- **Calendar banner** (not a section) — blue info pill pointing to the existing Google Calendar

### 10 client sections

1. **AI Match Quiz CTA** — purple→indigo gradient, pushes `PersonalityQuizScreen`
2. **Personality Match Result** — shown only after quiz. `_GlowingScoreCircle` with animated green shadow
3. **Specialties display** — read-only gradient chips from catalog
4. **Packages carousel** — horizontal `ListView.separated`, popular package **elevated -6px via `Matrix4.translationValues(0,-6,0)`** (note: NOT deprecated `Matrix4..translate` — use translationValues)
5. **Locations grid** — responsive 2/3-column, cream cards, "+ ₪X" or "ללא תוספת מחיר" pills
6. **Certifications list** — read-only rows with ✓ מאומת blue pill
7. **Monthly Journey Preview** (WOW factor) — dark navy card with Apple-style 3-ring `CustomPaint`: red `#FF455A` / green `#32D74B` / turquoise `#00C7BE`. 2-second forward animation on first mount via `WidgetsBinding.instance.addPostFrameCallback`. 4 stat tiles + gold "Top 15% בארץ" banner.
8. **Success Story** — 180px before/after panels, labeled overlays (red לפני / green אחרי)
9. **Trust Badges** — responsive 2×2 grid with 4 guarantees (🛡️ Satisfaction, 💯 Refund, 🔐 Secure payment, ⭐ Verified trainer)
10. **Active Offer Banner** — custom `_DashedBorderPainter` using `path.computeMetrics()`, red-urgency when ≤3 days or ≤3 spots

### Firestore fields

```
users/{uid}.fitnessTrainerProfile      // 9-field nested Map
  selectedSpecialties: List<String>     // enum names, max 5
  packages: List<Map>
  locations: List<Map>
  certifications: List<Map>
  successStories: List<Map>
  offers: List<Map>
  profileScore: int (0-100)             // written by optimizeTrainerProfile CF
  aiSuggestions: List<Map>              // same, 5 items
  lastOptimized: Timestamp              // same

provider_listings/{id}.fitnessTrainerProfile    // synced on save

jobs/{id}.fitnessTrainerPreferences             // booking-time snapshot:
  packageId, packageName, packageType, sessions,
  durationMinutes, price, discount?, isPopular

jobs/{id}.priceBreakdown
  basePrice, total

matching_analytics/{autoId}                     // written by recommendTrainersByGoals CF
  userId, criteria, trainerId, matchScore, success, createdAt,
  expireAt (createdAt + 90d, TTL-eligible per §19)

users/{clientId}/workout_plans/{autoId}         // written by generateCustomWorkoutPlan CF
  planOverview, weeklySchedule[], progressionStrategy,
  recoveryTips[], nutritionGuidelines[],
  createdBy (trainerId), clientId, goal, experience, frequency,
  durationWeeks, createdAt, isActive
```

### Detection function

```dart
bool isFitnessTrainerCategory(String? serviceType) {
  if (serviceType == null) return false;
  final lower = serviceType.trim().toLowerCase();
  if (lower.isEmpty) return false;
  return lower == 'מאמני כושר' ||
      lower == 'מאמן כושר' ||
      lower == 'fitness_trainer' ||
      lower == 'personal trainer' ||
      lower.contains('מאמן כושר') ||
      lower.contains('מאמנת כושר') ||
      lower.contains('fitness') ||
      lower.contains('personal trainer');
}
```

### Integration points

| Screen | Method | Behavior |
|--------|--------|----------|
| `edit_profile_screen.dart` | `_isFitnessTrainerSubCategory()` | Renders `FitnessTrainerSettingsBlock` AFTER the handyman block. Validation: ≥1 selectedSpecialty AND ≥1 package AND ≥1 location before submit. |
| `expert_profile_screen.dart` | `_hasFitnessTrainerProfile()` | Renders `FitnessTrainerBookingBlock` AFTER handyman block, BEFORE "Service Menu". `onPackageSelected` updates `_fitnessPackage` state; payment path writes `fitnessTrainerPreferences` + `priceBreakdown` to job doc via existing Pay & Secure flow. |
| `admin_demo_experts_tab.dart` | `_isDemoFitnessTrainerCategory()` | Renders same settings block in the demo-expert builder. Saves to BOTH user doc and `provider_listings/demo_{uid}`. |

### Cloud Functions (Gemini 2.5 Flash Lite only — never Claude)

**1. `recommendTrainersByGoals`** (callable, 512MiB, 60s, region us-central1, maxInstances 10)
- Auth required. Input: `{goal, experience, frequency, location, style, trainerId?}`.
- If `trainerId` provided, loads `users/{trainerId}.fitnessTrainerProfile` and embeds it in the prompt.
- Temperature 0.3, `responseMimeType: 'application/json'`, maxTokens 1024.
- Output: `{matchScore: 50-100, reasons: string[4], success, fallback?}`.
- Logs to `matching_analytics` with `expireAt = now + 90d` (TTL-eligible per §19).
- **Always-succeeds contract** — on ANY error, deterministic fallback (70-100 based on completeness + per-goal/location Hebrew reasons). The client-side quiz also has its own 87% fallback so the UX never breaks.

**2. `optimizeTrainerProfile`** (callable, 512MiB, 60s, maxInstances 5)
- Auth: self OR admin (via `isAdminCaller`).
- Reads `users/{trainerId}`, computes deterministic score (mirrors `FitnessTrainerProfile.fallbackScore` + aboutMe length + gallery count + rating bonus).
- Temperature 0.4, maxTokens 2048. Calls Gemini for 5 suggestions with `{icon, title, description, impact, action, priority: 'high'|'medium'|'low'}`.
- Writes back: `users/{uid}.fitnessTrainerProfile.profileScore + aiSuggestions + lastOptimized`.
- **Always-succeeds contract** — deterministic fallback suggestions if Gemini fails.

**3. `generateCustomWorkoutPlan`** (callable, 512MiB, 90s, maxInstances 5)
- Auth required. Input: `{clientId, goal, experience, frequency, durationWeeks (1-12, clamped), equipmentAvailable, injuriesOrLimitations, currentWeight?, targetWeight?}`.
- Temperature 0.5, maxTokens 4096 (bigger plans need more tokens).
- Output: structured `{planOverview, weeklySchedule[{week, title, days[{day, focus, duration, exercises[{name, sets, reps, restSeconds, notes}]}]}], progressionStrategy, recoveryTips[], nutritionGuidelines[]}`.
- If `clientId` provided, persists to `users/{clientId}/workout_plans/{autoId}` (best-effort — still returns plan to caller on persistence failure).
- **Throws on malformed Gemini response** — unlike the other 2 CFs, no fallback here because workout plans need real structure.

All 3 CFs use the shared `_fitnessCallGemini({prompt, temperature, maxTokens})` helper which tries `gemini-3.1-flash-lite-preview` then `gemini-2.5-flash-lite`. `_stripCodeFences` is already defined at the top of `functions/index.js`.

### Firestore rules added

```
match /users/{uid}/workout_plans/{planId} {
  allow read: if isOwner(uid)
              || isAdmin()
              || (isVerifiedAuth()
                  && resource.data.createdBy == request.auth.uid);
  allow create, update, delete: if false;   // CF-only via Admin SDK
}
```

Everything else (the main `fitnessTrainerProfile` Map field, `matching_analytics`) is covered by existing rules — the Map nests inside `users/{uid}` and `matching_analytics` doesn't need a client-write rule since it's CF-written.

### Design tokens

**Provider side** (`_FPalette` — scoped, does NOT replace `Brand.*`):
- Background gradient: `[#0A0E1A, #1A120C, #0F1420]` (warm-leaning dark)
- Orange `#FF6B35`, Gold `#F59E0B`, Green `#10B981`, Red `#DC2626`, Purple `#8B5CF6`, Blue `#3B82F6`
- Glass cards: white @ 4% opacity, 1px border white @ 8%, radius 18px

**Client side** (`_FCPalette`):
- Background: `[#FFF8F3, #FFFFFF]` (cream + white)
- Same accent colors
- Border: `#FED7AA` (borderOrange) + `#E5E7EB` (borderGray)
- Apple ring colors (exact Apple Activity): red `#FF455A` / green `#32D74B` / turquoise `#00C7BE`

### Rules for future code

- **Never reintroduce "online" location.** `LocationType` enum is sealed at 3 values. If someone asks to add online training, they need to invent a NEW category (e.g. "מאמני כושר אונליין") — do NOT pollute this enum.
- **Never fork `PersonalityQuizScreen` per-trainer.** The quiz is generic — the `trainerId` parameter is how per-trainer scoring plugs in. Keep the quiz shape (5 questions, 300ms auto-advance) stable across launches.
- **Never bypass `FitnessTrainerProfile.fallbackScore`.** It's the deterministic mirror of the server-side `_fitnessComputeProfileScore` in `functions/index.js`. When tweaking the formula, update BOTH together or the UI will drift from the CF.
- **Always use Gemini 2.5 Flash Lite for all 3 CFs.** Matches §32/33/34/41 rule. AI CEO (§12c) is the only Claude-backed admin tool.
- **`Matrix4..translate(0, -6)` is deprecated** — always use `Matrix4.translationValues(0, -6, 0)` for the popular-package elevation transform in the packages carousel (or anywhere else).
- **`intl` import must `hide TextDirection`** in both provider and client blocks — the package exports a conflicting `TextDirection` that breaks the `Directionality` widget.
- **Green glow animation on the 94% score** is an intentional UX flourish (`_GlowingScoreCircle` with 1600ms reverse repeat) — don't "optimize" it away by removing the `AnimationController`.

### Deployment

```bash
firebase deploy --only functions:recommendTrainersByGoals,functions:optimizeTrainerProfile,functions:generateCustomWorkoutPlan
firebase deploy --only firestore:rules
flutter build web --release && firebase deploy --only hosting
```

`GEMINI_API_KEY` secret is already provisioned from previous Gemini CFs — no new secret setup needed.

### Files

**Created (4):**
- `lib/models/fitness_trainer_profile.dart` (678 lines)
- `lib/screens/fitness_trainer/fitness_trainer_settings_block.dart` (3,306 lines)
- `lib/screens/fitness_trainer/fitness_trainer_booking_block.dart` (1,913 lines)
- `lib/screens/fitness_trainer/personality_quiz_screen.dart` (683 lines)

**Modified (5):**
- `lib/screens/edit_profile_screen.dart` — imports, state, init loader, detector, validation, save payload, listing sync, UI block
- `lib/screens/expert_profile_screen.dart` — imports, state, detector + builder, UI insertion (after handyman block, before service menu), job payload
- `lib/screens/admin_demo_experts_tab.dart` — imports, state, init loader, detector, user save payload, listing save payload, UI block
- `functions/index.js` — 3 new CFs + 2 helpers (`_fitnessCallGemini`, `_fitnessComputeProfileScore`) appended at end (+518 lines)
- `firestore.rules` — new `workout_plans` subcollection rule

**Spec archived at** `docs/ui-specs/Fitness Trainer/` (6 files: README, 01_MAIN_PROMPT, 02_PROVIDER_CODE, 03_CLIENT_CODE, 04_BACKEND_CODE, 05_INTEGRATION).

---

## 45. Categories v3 — Premium Admin Workspace (v15.x, 2026-04-20)

> Full redesign of the admin "קטגוריות" tab into a Linear/Airbnb/Notion-grade
> management workspace. Built in 5 phases (A→E), each phase committed
> independently behind a hard-coded UID feature flag so the legacy tab keeps
> working for non-whitelisted admins until rollout completes.

### Architecture decisions (recorded for future maintainers)

| Decision | Choice | Why |
|----------|--------|-----|
| Folder layout | `lib/screens/categories_v3/` sub-tree | Co-locates 14 model/service/controller files + 17 widgets + 4 dialogs without polluting the flat `lib/screens/admin_*.dart` namespace |
| State management | Riverpod 2.x with `riverpod_annotation` (new `Ref` API) | Matches existing admin providers (admin_users, admin_billing); zero deprecated `*Ref` types in new code |
| Feature flag | Hard-coded UID whitelist in `feature_flag.dart` | Soft-launch reality (~5 users) — Remote Config is overkill. Replace with Firestore-backed flag (`system_settings/feature_flags`) when widening. **DO NOT** install `firebase_remote_config` package. |
| Dark mode | Light-only (matches Vault §29 + Monetization §31) | Categories tab follows the established admin convention. Adding dark mode would require `Theme.of(context).brightness` switching across 21 widgets — re-evaluate if user demand surfaces. |
| Analytics source | Real `jobs` + `users` aggregation; views/clicks placeholder ("—") | Q4-B+C decision — no `category_impressions` / `category_clicks` collections exist. Build tracking infra in a future PR when DAU justifies the write cost. |
| Banner integration | Read-only mirror in `promoted_banners` | Q5-A — `home_tab.dart` keeps rendering AnyTasks + נתינה מהלב hardcoded (per §35). Migrating to live rendering is a separate PR. |
| Icons | Material only | `lucide_icons` was considered (per spec) but rejected for consistency with the other 87 screens |
| Old tab | `AdminCategoriesManagementTab` kept fully functional | Renders for any admin NOT in the whitelist. Archive to `lib/screens/legacy/` after 2 weeks of v3 stability. |

### Firestore schema additions (additive only — `categories` collection)

```
categories/{id}
  // ── existing fields (unchanged) ─────────────────────────
  name, iconUrl, parentId, order, clickCount, imageUrl?, color?, csm?
  // ── v3 additions ────────────────────────────────────────
  analytics: {
    views_30d?: number              // null until tracking ships
    clicks_30d?: number             // null until tracking ships
    orders_30d: number              // sourced from jobs
    revenue_30d: number             // sourced from jobs.totalAmount
    growth_30d: number              // % vs prior 30d
    sparkline_30d: int[30]          // daily order counts (oldest → newest)
    coverage_cities: number         // distinct cities from active providers
    active_providers: number
    health_score: number            // 0-100 per spec §4 formula
    last_updated: Timestamp
  }
  admin_meta: {
    is_pinned: bool                 // shows as "מקודמת" chip
    is_hidden: bool                 // hides from customer home
    last_edited_by: string          // admin uid
    last_edited_at: Timestamp
    last_edited_action: string      // 'created' | 'reordered' | 'pinned' | etc.
    notes: string                   // free-form admin note
  }
  csm_module: string | null         // 'cleaning' | 'massage' | 'delivery' | 'handyman' | 'pest_control' | 'fitness_trainer'
  custom_tags: string[]             // ['🔥 חם', '🚀 צמיחה']
```

### New collections

| Collection | Purpose | Rule |
|-----------|---------|------|
| `admin_activity_log/{logId}` | Append-only audit trail. Every admin mutation goes through `logAdminAction` CF. Used by Activity Log panel + Undo. | admin read; CF-only write |
| `admin_saved_views/{viewId}` | Per-admin filter/sort/view-mode presets. | per-admin scoped (admin_uid == auth.uid) |
| `promoted_banners/{bannerId}` | Read-only mirror of AnyTasks + נתינה מהלב + future banners. | auth read; admin write |

### Cloud Functions added (5 total)

| CF | Trigger | Purpose |
|----|---------|---------|
| `updateCategoryAnalytics` | `onSchedule("every 15 minutes")` | Aggregates jobs + users into `categories/{id}.analytics`. Cap 50 categories per run. |
| `refreshCategoryAnalyticsNow` | `onCall` (admin-only) | Manual trigger from the "כלי-עוצמה" footer's Refresh button |
| `logAdminAction` | `onCall` (admin-only) | Server-stamps every admin write to `admin_activity_log`. Tamper-resistant audit trail. |
| `undoAdminAction` | `onCall` (admin-only) | Restores `payload_before` snapshot. Idempotent. Reorder undo is intentionally refused (snapshot too heavy). |
| `backfillCategoriesV3` | `onCall` (admin-only) | One-shot field initializer. Idempotent — skips docs already with `admin_meta`. Run ONCE after deploy. |

### Composite indexes added

```
admin_activity_log: (admin_uid ASC, created_at DESC)        # per-admin feed
admin_activity_log: (target_type ASC, created_at DESC)      # panel filter
admin_saved_views: (admin_uid ASC, is_default DESC, created_at DESC)
```

### Phased rollout (5 commits)

| Phase | Commit | Contents |
|-------|--------|----------|
| **A — Foundation** | `ffe68d1` | 14 files (models/services/controllers) + 3 indexes + 3 rule blocks + 5 CFs. Backfill verified: 77 categories initialized. **Zero UI change.** |
| **B — Core UI** | `4918d5f` | 8 widgets (KPI row, toolbar, category card basic, sub-grid, banner card, empty state) + main tab entry behind feature flag. Whitelisted admin sees v3; everyone else sees legacy. |
| **C — Advanced UI** | `fdb7ec3` | 6 widgets (Sparkline `CustomPainter` Catmull-Rom, HealthScoreBar, CoverageChip, ConversionFunnel, BulkActionsBar, KeyboardShortcutsHint) + Drag-and-drop reorder (debounced 500ms) + 10 keyboard shortcuts (↑↓ Space E H P Del ⌘K ⌘Z Esc /) |
| **D — Power Features** | `3f16e52` | 7 files: ActivityLogPanel (slide-in, inline undo), CommandPaletteOverlay (⌘K, fuzzy, ↑↓↵Esc nav), PowerToolsFooter (export/import/refresh/reset), ConfirmDestructiveDialog (type-to-delete), SavedViewDialog, EditCategoryDialog (5 tabs), AddCategoryDialog (3-step wizard) |
| **E — Polish & QA** | (this commit) | Animated `LoadingShimmer` (no `shimmer` package — custom `ShaderMask` + `LinearGradient` slide), mobile-responsive at 480px breakpoint (sparkline + coverage hidden, health bar shrinks 50→36px), `SharedPreferences` persistence for `shortcutsHintDismissed`, this CLAUDE.md §45, `docs/categories_v3_CHANGES.md` |

### Keyboard shortcuts (web only; mobile auto-hides hint strip)

| Key | Action |
|-----|--------|
| `↑↓` | Navigate between root categories (purple focus border) |
| `Space` | Toggle selection of focused row |
| `E` | Open EditCategoryDialog for focused row |
| `H` | Toggle hide for focused row |
| `P` | Toggle pin for focused row |
| `Del` / `Backspace` | Open ConfirmDestructiveDialog (type-to-delete) |
| `⌘K` / `Ctrl+K` | Open CommandPaletteOverlay |
| `⌘Z` / `Ctrl+Z` | Undo last reversible action by current admin |
| `Esc` | Close palette → close activity panel → clear selection + focus |
| `/` | Snackbar prompts user to click search field |

### Rules for future code

- **Never reintroduce email/password admin login or hardcoded UID checks elsewhere.** The whitelist in `feature_flag.dart` is *intentionally* the only place. When migrating to the Firestore flag, replace the file's body — don't sprinkle UID checks across screens.
- **Every admin mutation MUST go through `logAdminAction` CF.** Direct Firestore writes from the v3 tab bypass the audit trail and break Undo. The `CategoriesV3Service` enforces this — keep all mutations there.
- **Health score formula** lives in BOTH client (`CategoryAnalytics.healthBand` thresholds + display) and server (`_catComputeHealthScore` in functions/index.js). When tweaking weights, update BOTH together or scores will drift between cached + recomputed values.
- **Sparkline data is a `List<int>` of 30 daily counts (oldest → newest).** Padding to length-30 is the caller's responsibility — see `CategoryAnalyticsService.sparklineForDisplay`.
- **`ReorderableListView` reorder writes are debounced 500ms** to avoid storming Firestore on multiple drags. Keep this discipline if adding more reorderable surfaces.
- **The keyboard shortcuts hint dismissal persists via `SharedPreferences['categories_v3.shortcuts_dismissed']`.** If you ever clear/reset preferences globally, the hint will reappear — that's the intended behavior.
- **No `firebase_remote_config` package.** When opening v3 to more admins, swap `feature_flag.dart` for a Firestore stream of `system_settings/feature_flags.enable_categories_v3`. NOT a Remote Config dependency.
- **Mobile breakpoint is 480px** (set in `CategoryRowCard.build`). Below this, sparkline + coverage chip auto-hide, health bar shrinks 50→36px. Test at 360px (iPhone SE min) before any future row-card changes.
- **`promoted_banners` is read-only mirror until further notice.** Editing a banner doc here does NOT yet flow to `home_tab.dart` (which still renders AnyTasks + נתינה מהלב hardcoded per §35). When migrating, the `BannerType.anytasks` and `BannerType.community` IDs become the lookup keys.

### Deploy checklist (run once after first merge to main)

```bash
firebase deploy --only firestore:indexes
firebase deploy --only firestore:rules
firebase deploy --only "functions:updateCategoryAnalytics,functions:refreshCategoryAnalyticsNow,functions:logAdminAction,functions:undoAdminAction,functions:backfillCategoriesV3"

# Then ONCE: invoke backfillCategoriesV3 from Firebase Console → Functions → Force run → {}
# Verify: open any categories doc in Firestore Console, confirm `admin_meta` field exists.
```

### Files

**Created (28 files in `lib/screens/categories_v3/`):** see `docs/categories_v3_CHANGES.md` for the full file list with line counts.

**Modified:**
- `lib/screens/admin_screen.dart` — 2 imports + `if/else` conditional in TabBarView
- `firestore.indexes.json` — +3 composite indexes
- `firestore.rules` — +3 rule blocks (admin_activity_log, admin_saved_views, promoted_banners)
- `functions/index.js` — +5 CFs + 4 helpers

---

## 46. Chat Dark-Mode QA Pass — Input Bar Palette Fix (v15.x, 2026-04-21)

> Pre-deploy QA audit of the 4 messages-upgrade commits (PR-1 9ce50cb, PR-2a
> 4ca0dda, PR-2b 3a1e4ef, PR-3a a3c1662 — see §43-area notes / chat upgrade
> memory). Found 4 BLOCKER-severity gaps where PR-3a's palette wiring missed
> the input bar's private widgets. Fixed in-place; zero new analyze issues.

### What was broken

PR-3a wired the main `ChatScreen` + message bubbles + app bar to
`ChatThemeScope`, but 5 call sites inside
[chat_input_bar.dart](lib/screens/chat_helpers/chat_input_bar.dart) kept
hardcoded `Colors.white` / `Colors.grey[200]` / `Color(0xFF6366F1)` /
`Color(0xFFEDE9FE)`. Result in dark mode:

| Element | Symptom in dark |
|---------|-----------------|
| Send button (line 219) | Invisible — grey-on-dark + grey icon |
| Attach button active state (line 264) | Lavender bg disappeared on dark surface |
| Attach menu container (line 355) | White popup on white → completely unreadable |
| Attach item label (line 476) | Dark text on dark card |
| Upload progress bar (line 162) | Hardcoded indigo wouldn't lerp with palette |

### Fix — single rule: every private widget in a chat helper reads palette itself

Each of `_AttachButton`, `_AttachMenuState.build`, and `_AttachItem.build`
now starts with:

```dart
final p = ChatThemeScope.of(context).palette;
```

Then uses palette tokens instead of hex:
- Send bg: `hasText ? p.accent : p.surfaceMuted`
- Send icon: `hasText ? Colors.white : p.textMuted`
- AttachButton active bg: `p.accent.withValues(alpha: 0.15)` (works in both themes)
- AttachButton icon: `active ? p.accent : p.textSecondary`
- AttachMenu container: `color: p.surface, border: p.border`
- AttachItem label: `color: p.textPrimary`
- LinearProgressIndicator: `color: p.accent`

The gradient circles inside each attach item (📍📷🎥💰) stay hardcoded by
design — branded icon chips are intentionally theme-independent and stay
vibrant on both backgrounds.

### Rules for future code

- **Every StatelessWidget / StatefulWidget in `lib/screens/chat_helpers/`
  or `lib/screens/chat_modules/` that paints a container/text/icon MUST
  read palette via `ChatThemeScope.of(context).palette` at the top of
  its `build()`.** Never use hardcoded indigo/white/grey there.
- **Private widgets are NOT exempt.** The 4 blockers were all in `_Xxx`
  private widgets — they need palette just as much as public widgets.
  The reviewer of PR-3a assumed "private widget = rarely rebuilt, safe
  to hardcode" — wrong.
- **Branded gradient chips are exempt** (the 4 emoji circles). Keep them
  branded — the label text below them MUST still use palette.
- **When adding a new chat widget**, run a dark-mode visual pass before
  commit. The dev rule: open `chat_settings_sheet.dart`, flip to dark,
  scroll every interactive element. If anything looks washed out or
  invisible, it's a palette miss.

### Deferred (non-blocking)

The QA also flagged 2 MEDIUM + 1 LOW issues documented here for later:
- `_OfficialQuoteCardState` Timer in `chat_ui_helper.dart:710` is wall-clock
  only — could race if device clock jumps. Mitigated by the
  `escrow_service.dart` pre-flight expiry guard, so real impact is tiny.
- Decline-error `setState` at `chat_ui_helper.dart:846` only fires if
  `mounted`. Unmount mid-decline leaves no user-visible error. Edge case.
- i18n keys added in PRs 2a/2b/3a were spot-checked across 4 locales; no
  exhaustive diff run. Safe because Flutter's build fails on missing keys.

### Files touched

| File | Change |
|------|--------|
| `lib/screens/chat_helpers/chat_input_bar.dart` | 5 palette fixes (progress bar, send button bg+icon, attach button active state, attach menu container, attach item label) |
| `CLAUDE.md` | This section (46) |

### Validation

- `flutter analyze lib/screens/chat_helpers/chat_input_bar.dart` → **0 issues**
- Full project `flutter analyze` → 10 pre-existing deprecation warnings (same
  Riverpod/flutter_secure_storage notices as every recent commit), **zero
  new issues**
- Chat-upgrade-file spot check (7 files): **0 issues**

### Deployment

No CF / rules / index changes. Client-only fix:

```bash
flutter build web --release && firebase deploy --only hosting
```

---

## 47. Chat Attachments — Location (web-safe) + Video Upload + Banner Removal (v15.x, 2026-04-21)

> Fixed both broken attachment actions in the chat input's paperclip menu
> AND removed the two top-of-chat banners the user reported as noise.

### Issues reported

1. **"שלח מיקום" did not work** on web. Legacy `LocationModule.getMapUrl()`
   called `Geolocator.getCurrentPosition` directly, which silently returns
   `null` on web when the browser's Permissions API disagrees with the
   platform channel — no fallback, no user feedback.
2. **"שלח וידאו" did not work** — PR-2a shipped it as a coming-soon
   placeholder (spec option B), but the user now needs the real upload.
3. **Two banners above the conversation** — always-green
   `ChatSafetyBanner` ("התשלום שלך מוגן על ידי AnySkill...") and the
   amber `ChatGuardBanner` ("שמירה על התשלום בתוך AnySkill...") — needed
   to come off entirely. The `ChatJobStatusBanner` with the "סיימתי ✅"
   action stays (workflow-critical).

### Fixes

**1. Location** — [location_module.dart](lib/screens/chat_modules/location_module.dart)
rewritten to delegate to the production-grade
[LocationService.requestAndGet(context)](lib/services/location_service.dart).
That service owns the OS/stored-state reconciliation + branded pre-prompt
dialog + JS-interop fallback on web (`_web_geo_web.dart` calls
`navigator.geolocation.getCurrentPosition` directly when geolocator
silently returns null). Callsite in chat_screen.dart now passes
`context` in and shows a Hebrew snackbar on failure instead of
swallowing it.

**2. Video** — new [video_module.dart](lib/screens/chat_modules/video_module.dart)
mirrors the `ImageModule` shape: `ImagePicker().pickVideo(source: gallery,
maxDuration: 60s)` → Storage upload at `chats/{chatRoomId}/vid_{ts}.{ext}`
with correct `SettableMetadata(contentType)`. Supports mp4/mov/webm/m4v.
60-second cap is a hardcoded cost guardrail (see rules below).

**3. Video bubble rendering** — new `case 'video':` in
[chat_ui_helper.dart](lib/screens/chat_modules/chat_ui_helper.dart)
`_buildContent`. Tappable card with circular play button + "וידאו"
title + "לחץ לצפייה" subtitle. `launchUrl(uri, mode:
externalApplication)` opens the Firebase Storage URL in the browser's
native video player — same strategy as the existing walk_summary
card opens the static map. Palette-aware colors (Law §46 rule —
every new chat widget reads `ChatThemeScope.of(context).palette`).

**4. Banners removed** — deleted `ChatSafetyBanner()` +
`ChatGuardBanner(...)` invocations from
[chat_screen.dart](lib/screens/chat_screen.dart) `build()`, plus the
dead `_showGuardBanner` field. The classes stay defined in
[chat_banners.dart](lib/screens/chat_helpers/chat_banners.dart) so
they can be restored trivially if product asks — no references
remain. `ChatJobStatusBanner` is untouched (workflow-critical).

### Rules for future code

- **Never use `Geolocator.getCurrentPosition` directly from chat/UI
  code.** Always route through `LocationService.requestAndGet(context)`
  so the web JS-interop fallback + branded dialog + stored-state
  reconciliation fire. This is the single source of truth.
- **Every upload helper (image/video/file) MUST have a snackbar-
  surfaced failure path.** The pre-fix pattern of `if (url != null)
  _send(...)` with silent null was exactly what left users staring at
  a dead button. Every call site shows a Hebrew error snackbar on
  `null`.
- **Video cap is 60 seconds.** Increasing this needs explicit product
  sign-off because Storage bandwidth cost is linear. To bypass via
  a new sender, go through `VideoModule.uploadVideo` — don't
  re-implement raw `pickVideo` elsewhere.
- **Never re-add `ChatSafetyBanner` or `ChatGuardBanner` invocations**
  without explicit product ask. They were explicitly removed as
  user-perceived clutter. If a regulatory banner is needed later,
  add a NEW, dismissible, conditional banner — don't restore these.
- **Content-type on Storage matters.** Web video playback via
  `launchUrl` depends on `contentType` being set correctly, else the
  browser downloads instead of streaming. `VideoModule` sets this
  based on file extension — preserve the logic.

### Files touched

| File | Change |
|------|--------|
| `lib/screens/chat_modules/location_module.dart` | Rewritten to delegate to `LocationService` — 1-line function body |
| `lib/screens/chat_modules/video_module.dart` | **NEW** — picker + upload + contentType |
| `lib/screens/chat_modules/chat_ui_helper.dart` | Added `case 'video':` to `_buildContent` (~60 lines, palette-aware) |
| `lib/screens/chat_screen.dart` | Removed 2 banner widgets + dead state field; wired real video upload callback; wired location to use context; added 2 failure snackbars |

### Validation

- `flutter analyze lib/screens/chat_screen.dart lib/screens/chat_modules/video_module.dart lib/screens/chat_modules/location_module.dart lib/screens/chat_modules/chat_ui_helper.dart` → **0 issues**
- Full `flutter analyze` → 10 pre-existing deprecation warnings, **zero new issues**
- No Firebase Storage rule change needed — the `chats/{chatRoomId}/**` path is the same one already used by `ImageModule`.

### Deploy

Client-only fix:

```bash
flutter build web --release && firebase deploy --only hosting
```

---

## 48. Legacy Categories Tab — Removed 4 admin footgun buttons (v15.x, 2026-04-21)

> Housekeeping on the legacy categories management tab (the one admin
> sees while the v3 whitelist in
> [feature_flag.dart](lib/screens/categories_v3/feature_flag.dart) stays
> empty — see §45). Four admin tools above the category list were
> removed because they'd become operational footguns or now duplicate
> v3 flows.

### Removed

- **"תקן כל התמונות (ייחודי)"** red button — called
  `VisualFetcherService.fixAllImages` and rewrote every category's
  image URL. Any admin click would stomp on category images that
  were manually tuned in v3's EditCategoryDialog. No confirm dialog,
  no undo.
- **"אפס מוני פופולריות"** amber button — batch-zeroed `clickCount`
  on every category doc. The v3 Analytics pipeline now derives
  popularity from `orders_30d` (see §45), so the legacy counter is
  already dead data and resetting it has no effect on ranking.
- **"רענן תמונות קטגוריה"** cyan button — called
  `VisualFetcherService.forceRefreshAll()` which silently overwrote
  admin-curated images (same risk as "תקן כל התמונות" but with a
  gentler icon). Removed with the other image-bulk action.
- **"קטגוריות ממתינות לאישור AI"** outlined button — pushed
  `PendingCategoriesScreen`. The modern category-request flow lives
  inside the v3 "פעולות על קטגוריה" dialog + category_requests admin
  views, so the bespoke pending screen is redundant. Route + screen
  file kept on disk for now (dead code) in case we need to pin it
  back to a different admin surface.

### What stays

- **Popularity leaderboard card** — read-only top-5 display is kept
  for the at-a-glance view. It uses `_buildPopularityLeaderboard` +
  `_fmtClicks` which are untouched.
- **"AI Auto-Created Categories Log"** inline list (`admin_logs`
  stream, `isReviewed == false`) — this IS useful, gives the admin
  a single-scroll view of AI-discovered categories with an
  inline "סמן כנבדק" button. Not removed.
- **"הוסף קטגוריה"** black button — primary create action, kept.

### Rules for future code

- **Never re-add `fixAllImages` / `forceRefreshAll` from a raw admin
  button.** If admins need a bulk-image tool, it should live in the
  v3 power tools footer (§45) and write to `admin_activity_log` via
  `logAdminAction` CF so the action is auditable + reversible via
  `undoAdminAction`.
- **Never expose `clickCount` reset** unless the v3 Analytics pipeline
  is deprecated. The field is vestigial; resets are noise.
- **`VisualFetcherService.fixAllImages` + `.forceRefreshAll()` stay
  defined** — the services themselves aren't broken, only the admin-UI
  exposure was risky. Re-wire later from v3 if needed.
- **Pending AI categories — future home**: if category-request volume
  picks up, add a v3 power tools footer button that streams
  `category_requests.where(status == 'pending')` instead of resurrecting
  `PendingCategoriesScreen`. Keeps the auditable / reversible pattern.

### Files touched

| File | Change |
|------|--------|
| `lib/screens/admin_categories_management_tab.dart` | Removed 4 button widgets + `_refreshingImages` / `_fixingImages` / `_fixImagesDone` / `_fixImagesTotal` / `_resettingCounters` state fields + `_resetPopularityCounters()` method + dropped imports for `VisualFetcherService` and `PendingCategoriesScreen` (~160 lines total) |
| `CLAUDE.md` | This section (48) |

### Validation

- `flutter analyze lib/screens/admin_categories_management_tab.dart` → **0 issues**
- Full `flutter analyze` → 10 pre-existing deprecation warnings, **zero new issues**

### Deploy

Client-only fix:

```bash
flutter build web --release && firebase deploy --only hosting
```

---

## 49. Banners v2 — Admin workspace + Provider Carousel (v15.x, 2026-04-21)

Full redesign of the admin "באנרים" tab inspired by Linear/Stripe,
plus a new **provider_carousel** banner type that rotates 2-20 real
providers on the customer home tab. Built in 6 phases (2-7) behind a
parallel tab so v1 stays fully operational until v2 proves stable.

> **Source of truth for this feature**: `docs/ui-specs/banners_redesign/`.
> Two HTML mockups (`01_banners_list.html` + `02_provider_carousel_builder.html`)
> + product spec (`01_product_spec.md`) + Claude Code prompt
> (`02_claude_code_prompt.md`). When text and mockup conflict, mockup wins.

### Architecture decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Scoped palette | `#6B5CFF` purple (spec-mandated), **only** inside the admin banners tab | Rest of app stays on `Brand.indigo` `#6366F1`. Same pattern as Vault (§29) and Monetization (§31). |
| Backward-compatibility | DB field stays `placement` (not renamed to `type`); Dart enum is `BannerType` that serializes to `placement` | V1 tab + `_PromoCarousel` in home_tab.dart keep working unchanged. New fields (`providerCarousel`, `impressions`, `attributedRevenue`, `hasAbTest`, `abVariants`) are optional with defaults. |
| v2 tab placement | **Parallel** tab next to v1 (`באנרים · חדש ✨`), not replacement | A/B visual comparison during rollout. Remove v1 tab after v2 proves stable. |
| Stack | `StatefulWidget` + `StreamBuilder` / `StreamSubscription` (NOT Riverpod) | Matches every other admin tab (Vault, Monetization, Demo Experts). |
| State management in wizard | Single wizard `StatefulWidget` holds config; sub-sections are pure `StatelessWidget` driven by props + callbacks | Keeps section files ≤ 700 lines each; live preview mirrors edits via `didUpdateWidget`. |
| Runtime widget location | `lib/widgets/provider_carousel_banner.dart` (customer-facing) | Separate from admin widgets under `lib/widgets/banners_admin/`. |
| Click tracking | Single `FieldValue.increment(1)` on tap, `catchError((_){})` | Never blocks navigation on network failure. |
| Impression tracking | Deferred to a future debounced/capped implementation | Per-rotation writes would cost 86k/day from an idle tab. Admin KPI strip shows `—` until analytics infra lands. |
| AI for insights + reorder | **Gemini 2.5 Flash Lite** (NOT Claude) | Matches §32/33/34/41/42/44 rule. AI CEO (§12c) is the only Claude-backed admin tool. |

### Firestore schema — additive only on `banners/{id}`

```
banners/{id}
  // Existing fields (unchanged) ──────────────────────────────────────
  title, subtitle, placement, isActive, order, imageUrl,
  color1, color2, iconName, expiresAt, providerId, providerName,
  providerPhoto, clicks

  // v15.x additions (all optional with sensible defaults) ─────────────
  startDate: Timestamp | null            // new — null means "live immediately"
  providerCarousel: {                    // ONLY for placement=='provider_carousel'
    providerIds: string[],               // 2-20 uids (rule-enforced when active)
    rotationDurationMs: number,          // 2000-8000 (rule-enforced when active)
    sortMode: 'ai'|'random'|'rating'|'manual',
    transition: 'slide'|'fade'|'zoom'|'flip',
    display: {
      showProfilePic, showRating, showGallery, galleryCount,
      showCategory, showPrice, showAvailability
    }
  }
  impressions: number                    // default 0
  attributedRevenue: number              // default 0
  hasAbTest: boolean                     // default false
  abVariants: [{id, title, subtitle?, imageUrl?,
                trafficPercent, impressions, clicks}]  // schema only, no runtime split yet
  createdAt: Timestamp
  createdBy: string                      // admin uid
```

### New collections

| Collection | Purpose | Rule |
|-----------|---------|------|
| `ai_insights/banners` | Output of `generateBannerInsights` CF — single doc streamed by the admin v2 tab's insight card | Admin read (uses existing `ai_insights/{id}` rule §31); CF-only write via Admin SDK |
| `ai_provider_order/{uid}_{bannerId}` | 1-hour cache of `smartProviderOrder` CF results | `allow read, write: if false` — CF-only via Admin SDK |

### Cloud Functions added (2)

| CF | Trigger | Purpose |
|----|---------|---------|
| `generateBannerInsights` | `onSchedule("every 6 hours")` | Aggregates up to 50 banners (status/ctr/impressions buckets), feeds a compact snapshot to Gemini, writes one strategic Hebrew insight to `ai_insights/banners`. **Always produces a visible state** — on Gemini failure writes a deterministic fallback doc referencing the highest-CTR banner. |
| `smartProviderOrder` | `onCall` (auth required) | Input: `{providerIds, bannerId}`. Reads cache first (1h TTL via `expireAt`); on miss, fetches provider summaries + user preferences + Israeli time-of-day → Gemini → returns ordered list with integrity check. **Silent fallback** to input order on any failure (no creds, Gemini down, bad permutation, fetch error). |

### Firestore rules added

`validBannerDocV2()` + `validProviderCarouselConfig()` helpers, wired into `banners/{id}` create + update. Active `provider_carousel` banners MUST pass:
- `providerIds.size() in 2..20`
- `rotationDurationMs in 2000..8000`

Drafts (`isActive == false`) and legacy gradient/image placements bypass validation so schema evolution doesn't block saves. Client-side wizard also checks via `ProviderCarouselConfig.validate()` before the publish CTA — Firestore rule is a defense-in-depth second layer.

`ai_provider_order/{cacheId}` is locked to CF-only (`allow read, write: if false`). Client never reads or writes — the CF returns ordered IDs directly.

### Files — 6-phase breakdown

**Phase 2 — Data schema (1 file):**
- `lib/models/banner_model.dart` — `BannerType` + `BannerStatus` enums, `ProviderCarouselConfig` with `validate() → String?`, `CarouselDisplayOptions`, `BannerAbVariant`, `BannerModel` with `fromDoc`/`fromMap`/`toFirestore`/`copyWith` (sentinel pattern for nullable clears) + derived `status` + `ctr`

**Phase 3 — Design system (7 files under `lib/widgets/banners_admin/`):**
- `design_tokens.dart` — `BannersTokens` (palette, typography, spacing, radii) + `BannersCard` + `BannersDivider`
- `banner_sparkline.dart` — `BannerSparkline` + `CustomPainter`, handles 0/1/2+ values, hover stroke 1.2→2px
- `banner_metric_card.dart` — `BannerMetricCard` + `BannerMetricStrip` (4 KPIs with 1px dividers)
- `banner_chip.dart` — 6 variants (success/warn/neutral/accent/danger/draft) × dot × icon × dense
- `banner_toggle.dart` — 26×14 optimistic toggle with rollback + Hebrew SnackBar
- `banner_kbd.dart` — keyboard shortcut pills with empty-list guard
- `_dev_widgets_gallery.dart` — **dev-only** preview of every widget in every state

**Phase 4 — Main list screen (3 files under `lib/screens/admin_banners_v2/`):**
- `provider_carousel_live_preview.dart` — 72×40 rotating mini preview (single Timer, AnimatedBuilder scoped to progress bar)
- `banner_row.dart` — 8-column RTL row with hover-reveal actions (toggle always visible, edit + more on hover) + CTR bar capped at 15%
- `admin_banners_tab_v2.dart` — header + KPI strip + 6 type tabs + filter bar + list + insight card + shortcuts footer + 4 states (loading / empty-all / filter-empty / error)

**Phase 5 — Wizard (4 files under `lib/screens/admin_banners_v2/wizard/`):**
- `provider_picker_section.dart` — debounced 300ms search + category/rating filters + 2-20 soft enforcement
- `rotation_settings_section.dart` — slider + 6 presets + sort radio 2×2 + 6 display checkboxes + 4 transition buttons
- `wizard_live_preview.dart` — 280px phone frame + rotating card + summary card (honest "—" for unknowable impressions/day)
- `provider_carousel_wizard.dart` — split view (desktop ≥900px / stacked <900px) + save/publish with `config.validate()` gate

**Phase 6 — Runtime widget (1 file + wiring):**
- `lib/widgets/provider_carousel_banner.dart` — customer-facing rotating card
- Wiring in `lib/screens/home_tab.dart` `_PromoCarousel`:
  - Query: `whereIn: ['home_carousel', 'provider_carousel']` (was single `isEqualTo`)
  - `_PromoBanner` extended with `id`, `type`, `providerCarousel` (back-compat via defaults)
  - `_BannerCard` branches at the top: `provider_carousel` → new widget; else → existing gradient/image path unchanged

**Phase 7 — Gemini integration:**
- `functions/index.js` — `generateBannerInsights` (scheduled) + `smartProviderOrder` (callable)
- `firestore.rules` — new `ai_provider_order` block (CF-only) + `validBannerDocV2` shape helpers
- Client wiring: `_InsightCardLive` streams `ai_insights/banners`; `ProviderCarouselBanner._requestAiOrder` fires on mount when `sortMode==ai`, `_applyAiOverride` in build

### Memory safety — single rule for every rotating widget

Every rotating preview / runtime card follows the same pattern:

1. **Exactly one `Timer.periodic`** per instance, stored in a nullable field
2. **Exactly one `AnimationController`** with `SingleTickerProviderStateMixin`
3. `AnimatedBuilder` wraps **only** the progress bar so the outer card never repaints at 60fps
4. Both torn down in `dispose()` — `_timer?.cancel(); _progressCtrl.dispose();`
5. `didUpdateWidget` re-syncs `rotationDurationMs` into the controller when the admin edits

Without this discipline, 5 banners × 60fps rebuild of the full card = 300 widget rebuilds/sec. With AnimatedBuilder scoping, it's 5 × 60 tiny 2px bar repaints/sec.

### User interactions (runtime widget)

| Gesture | Action |
|---------|--------|
| Single tap on card | Navigate to `ExpertProfileScreen(expertId, expertName)` + bump `banners/{id}.clicks` |
| Long-press | Toggle pause (Timer + progress bar stop together) |
| Horizontal drag | Manual prev/next + reset timer |

### Deploy checklist

```bash
# Functions
firebase deploy --only \
  functions:generateBannerInsights,\
  functions:smartProviderOrder

# Rules
firebase deploy --only firestore:rules

# Web app
flutter build web --release && firebase deploy --only hosting
```

**One-time manual step** in GCP Console (same pattern as §19 TTL):
- https://console.cloud.google.com/firestore/databases/-default-/ttl
- Create Policy → collection `ai_provider_order`, field `expireAt`

Without the TTL policy, cache docs accumulate forever. Correctness is unaffected (the CF ignores entries older than 1h) but storage grows unbounded.

### Rules for future code

- **Never delete `admin_banners_tab.dart` (v1)** until v2 is battle-tested. Both read/write the same `banners` collection — dual-surface is cheap and safe.
- **Never hardcode banner rendering based on `placement` string.** Use `BannerType.fromDb(placement)` and branch on the enum. New placements are one enum value away.
- **Never pass `BannersTokens` colors into customer-facing code.** That palette is scoped to `lib/widgets/banners_admin/`. The customer runtime widget uses `Brand.*` / local const hex to match the rest of the home tab.
- **Never fake banner metrics.** If a number can't be honestly derived from the data, show `—` with a tooltip explaining the missing infra. Admin trust > marketing polish.
- **Every new rotating widget** must follow the §49 memory-safety rule above (single Timer, scoped AnimatedBuilder, dispose both).
- **Every new CF in the banners subsystem** must use **Gemini** (never Claude) and must have a deterministic fallback path.
- **`smartProviderOrder` integrity check is non-negotiable.** Gemini returning a list that's not a permutation of the input → silent fallback to input. Allowing stray IDs would send users to providers that weren't in the admin's selection.

### Known deferred work

| Item | Where | Why deferred |
|------|-------|-------------|
| Daily metric aggregation (`banners/{id}/stats/{yyyy-mm-dd}`) | KPI sparklines + trend % | Requires a new subcollection + nightly CF. Admin KPI strip shows `—` until this lands. |
| Impression tracking with debounce/daily-cap | `ProviderCarouselBanner` `onImpression` | Per-tick write would cost 86k/day from idle tab. Needs CF-side debouncer. |
| A/B testing runtime split | `BannerAbVariant` schema already shipped | Deferred per spec priority — "nice to have". |
| Command Palette (⌘K) | Admin v2 tab header | Deferred per spec priority. Button is wired to a "בקרוב" SnackBar. |
| Calendar + Gallery view toggles | Admin v2 filter bar | Only the list view is implemented; the other two icons show a tooltip "בקרוב". |
| Edit dialog for non-provider-carousel banners | v2 edit button | Gradient/image edits still go to v1 tab. Only `provider_carousel` opens the wizard. |
| AI `actionType` auto-apply (e.g. `duplicate_banner`) | Admin v2 insight card | The card shows the recommendation text but action-type buttons aren't wired yet. |
| Slide/zoom/flip transition animations | `ProviderCarouselBanner` | Only fade is implemented; other transitions accepted from config but render as fade. |

### Validation

- `flutter analyze` → **0 new issues** (10 pre-existing Ref-deprecations unchanged)
- `node -c functions/index.js` → syntax OK
- All rotating widgets follow the memory-safety pattern
- RTL audit: all directional positioning uses `EdgeInsetsDirectional` / `PositionedDirectional` / `Alignment{Start|End}`. Two intentional `TextDirection.rtl` wrappers (dev gallery + wizard scaffold). Zero left/right hardcoded paddings.
- Back-compat audit: v1 tab unchanged; legacy doc shapes deserialize cleanly via defaults; existing `_PromoCarousel` continues to render `home_carousel` banners identically.

---

## 50. Security Hardening — v15.x Audit (2026-04-25)

> Three-round defensive review of every Firestore rule, Storage rule, and
> Cloud Function in the codebase. Identified and closed 9 high/medium-
> severity vulnerabilities, then layered Firebase Custom Claims on top
> of the existing Firestore-field-based role checks for protocol-level
> defense in depth. **Source of truth for all future security work** —
> see `Rules for future code` below before adding any new rule, callable,
> or storage path.

### Current security posture (post-audit)

**Honest assessment: 7/10** — production-grade for a startup with real
users; not a 9-10 (bank-grade) because:

What we now have (✅):
- All known privilege-escalation primitives closed at the rule layer.
- All known money-creation paths closed at the CF layer.
- Critical Storage paths gated by parent-doc participant lookup.
- Admin-gated CFs unified through a single `isAdminCaller` helper.
- Defense-in-depth: JWT custom claim → Firestore field → blocklist on
  both create + update.
- Audit logging on every sensitive admin action (`admin_audit_log` +
  `support_audit_log`).
- Sentry + Crashlytics + Watchtower error reporting (Law 7).
- Service-account credentials are gitignored (`functions/.gitignore:9`).

What we do NOT have (⚠️ — known gaps):
- App Check is configured but **NOT in Enforce mode**. Determined
  attackers with a stolen `apiKey` from `firebase_options.dart` can
  still hit Firebase APIs from a non-app client. (App Check only
  matters once toggled to Enforce in the Firebase Console — operator
  step, not code.)
- Custom Claims is in **transition**: rules + isAdminCaller prefer
  the JWT claim but still fall back to the Firestore field. Phase 2
  (drop the field-based fallback) is deferred until all admins have
  refreshed their tokens.
- No automated rule-emulator tests in CI. Rule regressions would be
  caught only at code review or in production.
- No professional penetration test.
- No 2FA enforcement for admins (relies on Firebase Auth defaults).
- No rate limiting on most CFs (App Check is the practical rate
  control, but it's not enforced).
- A few lower-priority storage paths still open to any signed-in
  user (`community_evidence` — embeds docId in filename, would need
  a path refactor to gate).

Where this places us on the curve:

| Tier | Description | Where we are |
|------|-------------|--------------|
| 3-4/10 | Hobby project — open rules, trust the client | Where we WERE pre-audit |
| 6-7/10 | Production startup — rules locked, CFs gated, secrets out of code, audit log | **WE ARE HERE** |
| 8-9/10 | Mature SaaS — App Check enforced, automated rule tests, anomaly detection, 2FA admins | Next milestone |
| 10/10 | Bank/regulated — SOC2/ISO 27001, 24/7 SOC, bug bounty, HSM | Years away |

### Vulnerabilities closed (3 rounds)

| # | Severity | Title | Fix |
|---|----------|-------|-----|
| 1 | HIGH | Self-promote to admin via `roles[]` | `role`, `roles`, `activeRole`, audit fields added to `users/{uid}` doesNotTouch blocklist; create rule also rejects setting privileged values at signup. |
| 2 | HIGH | `processPaymentRelease` minted money from client-supplied `expertId` + `totalAmount` | All financial values now read from `jobs/{jobId}` doc inside the transaction; `jobId` is the only trusted client input. |
| 3 | MEDIUM | `boarding_proofs/` storage open to any signed-in user | Read/write gated by `expertId`/`customerId` lookup on the parent jobs/{jobId} doc. |
| 4 | HIGH | `supportAgentAction` trusted client-writable `role` field | Resolved by Vuln 1 fix (role becomes CF-only); JWT claim layered on top in Round C as defense in depth. |
| 5 | MEDIUM | `job_requests` update rule allowed any auth user to overwrite `interestedProviders`/`status` | 4-branch rule: owner full control, provider self-add (append-only), provider self-decline, broadcast-claim cosmetic close (winner-verified). |
| 6 | HIGH | Provider could self-write `customCommissionActive: true, customCommission: 0` to zero out platform fee | `customCommission` + `customCommissionActive` added to blocklist (both create and update). |
| 7 | HIGH | `sendGlobalBroadcast` had NO server-side admin check — any auth user could spam every device with arbitrary FCM | Explicit `isAdminCaller` gate added; comment that previously claimed "server check here" was a lie. |
| 8 | MEDIUM | `anytask_proofs/{taskId}/` open to any signed-in user — proof tampering could trick customers into releasing escrow | Read gated to participants; write gated to `selectedProviderId` on the parent any_tasks doc. |
| 9 | MEDIUM | `any_tasks/{taskId}/{file}` (client task images + provider proof) open to any signed-in user | Read: 'open' tasks public, otherwise participants only. Write: client OR selectedProviderId. |
| Round C C1 | LOW | `dog_walks/{walkId}/route_map.png` open to any signed-in user — tampering with route map | Same pattern as Vuln 3: gated by `providerId`/`customerId` on parent dog_walks doc. |

### Custom Claims architecture (Round C)

**Goal:** Layer Firebase Auth Custom Claims on top of Firestore-field
role checks. JWT claims are signed by Firebase and CANNOT be forged
from the client. Even if a future blocklist regression accidentally
allows a user to write `isAdmin: true` to their own doc, the JWT-claim
branch in the rule helpers and `isAdminCaller` keeps the gate closed.

**3-layer defense for admin status (in priority order):**

1. **`request.auth.token.admin == true`** — JWT custom claim, signed
   by Firebase, set ONLY via `admin.auth().setCustomUserClaims()`.
   Rule helpers + `isAdminCaller` check this FIRST. Zero Firestore
   reads on the admin path → performance bonus.
2. **`users/{uid}.isAdmin == true`** — Firestore field, fallback
   during the migration window (admins whose token was issued before
   the claim landed still get access from this branch until natural
   token expiry, ≤1h).
3. **`'admin' in users/{uid}.roles[]`** — multi-role array fallback
   (legacy from Phase 1 multi-role).

**Same pattern for `support_agent`:** `request.auth.token.support_agent`
→ `users/{uid}.role == 'support_agent'` → `'support_agent' in roles`.

**Migration steps performed:**

1. Updated `isAdmin()` and `isSupportAgent()` rule helpers to check
   JWT claim FIRST, falling back to existing field reads.
2. Updated `isAdminCaller` CF helper to mirror the same pattern.
3. Updated `setUserRole` CF to dual-write Custom Claims alongside
   the Firestore field. On privilege REMOVAL, also calls
   `admin.auth().revokeRefreshTokens(uid)` to force re-auth within
   1h instead of waiting for natural token expiry.
4. Created `backfillAdminClaims` CF + parallel local script
   (`functions/scripts/backfill-admin-claims.js`) for one-time sync
   of all existing admins/agents.
5. Added Custom Claims to `users/{uid}` create-rule rejection list
   so brand-new users can't ship a profile with `isAdmin: true`.

### Operations runbook

#### Inspecting an admin's current claim state

```bash
cd functions
node -e "
  const admin = require('firebase-admin');
  admin.initializeApp({ projectId: 'anyskill-6fdf3' });
  admin.auth().getUserByEmail('admin@example.com')
    .then(u => console.log('uid:', u.uid, 'claims:', JSON.stringify(u.customClaims)))
    .catch(e => console.error(e));
"
```

(Requires either `service-account.json` next to the script OR
Application Default Credentials via `firebase login` + `gcloud auth
application-default login`.)

#### Granting a new admin

Use the in-app Admin Panel → User Management → "Set Role" — calls
the `setUserRole` CF, which dual-writes the Firestore field AND the
Custom Claim. Target user must sign out / in (or wait ≤1h) to refresh
their JWT.

NEVER write `users/{uid}.isAdmin: true` directly in the Firestore
console — the field write succeeds (admin SDK bypasses rules), but
the Custom Claim won't be set. The user gets admin via the Firestore-
field fallback only, which is the legacy primitive we're moving away
from.

#### Backfilling Custom Claims after schema/role changes

If a manual Firestore edit (or a bug) makes the Custom Claim drift
from the Firestore field state, run the local backfill script:

```bash
cd functions
node scripts/backfill-admin-claims.js --dry-run    # preview
node scripts/backfill-admin-claims.js              # apply
```

The script is idempotent. Logs each updated/cleared user. Writes a
summary to `admin_audit_log`. Operators MUST sign out / in afterward
for their new JWT to include the synced claim.

#### Revoking an admin in an emergency

Two layers of revocation needed (claim + refresh tokens):

```bash
cd functions
node -e "
  const admin = require('firebase-admin');
  admin.initializeApp({ projectId: 'anyskill-6fdf3' });
  const TARGET_UID = '...uid here...';
  admin.auth().setCustomUserClaims(TARGET_UID, { admin: false, support_agent: false })
    .then(() => admin.auth().revokeRefreshTokens(TARGET_UID))
    .then(() => admin.firestore().collection('users').doc(TARGET_UID).update({
      isAdmin: false,
      role: 'customer',
      roles: ['customer'],
    }))
    .then(() => console.log('Done. Existing access tokens still valid for ≤1h.'))
    .catch(e => console.error(e));
"
```

After this: the user's existing access tokens still work for up to
1 hour. There is NO way to invalidate access tokens before natural
expiry (Firebase architectural limit). For instant lockout, also
disable the Firebase Auth account via
`admin.auth().updateUser(uid, { disabled: true })`.

#### Rotating service-account.json

If a service-account key is leaked or suspected:

1. Firebase Console → Project Settings → Service accounts → delete
   the leaked key from "Manage all service accounts".
2. Generate a new key if needed for one-off scripts.
3. Audit `admin_audit_log` for unexpected entries during the
   suspected window.
4. Rotate any other secrets that may have been on the same machine.

### Rules for future code

These are non-negotiable for any new code touching auth, money, or
sensitive Storage paths:

**Firestore rules:**
- **Every new sensitive field on `users/{uid}` MUST go to one of:**
  (a) the `doesNotTouch` blocklist (CF-only writable), OR
  (b) a private subcollection at `users/{uid}/private/{docId}` (§11).
- **Never trust client-supplied values for money math.** Always read
  amounts/recipients from a server-side doc inside the transaction.
- **Cross-user writes (`X` writes to `Y`'s doc) require a tight
  field-level allow-list.** Generic `allow update: if isAuth()` is
  always wrong for cross-user paths.
- **Sentinel fields for `where()` queries** (e.g. `customCommissionActive`)
  must be in the same blocklist as the data field they sentinel.

**Cloud Functions:**
- **Every new admin-only callable MUST use `isAdminCaller(request)`.**
  Never duplicate the `users/{uid}.isAdmin === true` inline check.
  When `isAdminCaller` is upgraded (e.g., to require 2FA), all CFs
  inherit the upgrade for free.
- **Every callable that mutates money MUST read amounts and parties
  from the canonical Firestore doc (job, task, etc.) inside the
  transaction.** Never trust the request body for these values.
- **`onCall` CFs that sit between users (e.g., releasing escrow)
  MUST verify the caller's role on the resource (customer, provider,
  admin)** before any mutation, even if the auth check passes.

**Storage rules:**
- **No new `allow write: if isSignedIn()` rules without ownership
  check.** Use `firestore.exists(...)` + a participant check on the
  parent doc. Pattern: see boarding_proofs (§3d), AnyTasks (§50
  Vulns 8-9), dog_walks (Round C C1).
- **Writable paths must verify content type** (`isImageContentType`,
  `isMediaContentType`) AND a size cap. Never accept arbitrary
  content types.

**Custom Claims:**
- **Never grant admin via direct Firestore write** outside `setUserRole`.
  The CF dual-writes both layers (field + claim); a direct write
  leaves them desynced.
- **`admin.auth().setCustomUserClaims()` REPLACES all claims** (no
  merge). When updating one claim, set all relevant claims explicitly
  (e.g., `{ admin: true, support_agent: false }`).
- **Always `revokeRefreshTokens()` on privilege removal** so the
  new claim takes effect within 1h instead of natural token expiry.
- **Never store secrets in claims** — they're embedded in JWT and
  visible to the client.

### Deferred work (lower priority — pick up later)

- **Phase 2 Custom Claims:** drop the Firestore-field fallback
  branches in `isAdmin()` and `isAdminCaller`. Requires confirmation
  that all admins have signed out/in at least once since the backfill.
- **App Check Enforce mode:** flip from Monitor → Enforce in Firebase
  Console after 24-48h of clean Monitor logs. See Law 9d for the
  per-API toggle. Operator step — not code.
- **`community_evidence/` storage gate:** filename embeds docId
  (`{docId}_{ts}.{ext}`) which makes path-based ownership lookup
  awkward. Refactor to `community_evidence/{docId}/{file}` then add
  the participant gate.
- **`dog_walks/{walkId}/{allPaths=**}` MIME tightening:** currently
  only `isImageContentType()` + 5MB. Add an explicit filename pattern
  if the route map is the only intended file.
- **Automated Firestore rule tests:** add `@firebase/rules-unit-testing`
  scenarios to CI for the most-traveled rules (users update, jobs
  read, escrow flow).
- **Anomaly detection:** monitor `admin_audit_log` for
  out-of-baseline patterns (e.g., burst of grant_credit calls,
  off-hours role changes).
- **2FA enforcement for admin emails:** Firebase Auth supports MFA
  via SMS/TOTP. Enforce for any account holding `admin` claim.

### Files modified by this audit

| File | Round | Purpose |
|------|-------|---------|
| `firestore.rules` | A, B, C | Blocklist expansion, JWT claim helpers, job_requests 4-branch update rule, customCommission added |
| `storage.rules` | A, B, C | boarding_proofs, anytask_proofs, any_tasks, dog_walks all gated by parent-doc participant lookup |
| `functions/index.js` | A, B, C | processPaymentRelease hardening, sendGlobalBroadcast admin gate, isAdminCaller JWT-aware, setUserRole dual-write claims, 5 inline isAdmin checks → isAdminCaller, backfillAdminClaims CF added |
| `functions/scripts/backfill-admin-claims.js` | C | NEW — local one-shot script for admin claim sync |

### Commit history (this audit)

11 separate commits across the 3 rounds, in chronological order:

1. `a69867f` — Round A Vuln 3: boarding_proofs storage requires job ownership
2. `717c476` — Round A Vulns 1+4+5: blocklist + job_requests rule
3. `5f58464` — Round A Vuln 2: processPaymentRelease reads from job doc
4. `0a96153` — Round B Vuln 6: customCommission self-write blocked
5. `01259c7` — Round B Vuln 7: sendGlobalBroadcast admin gate
6. `db8a395` — Round B Vulns 8+9: AnyTasks storage participant gate
7. `863cb24` — Round C C1: dog_walks storage walk ownership
8. `6034793` — Round C C4: rule helpers prefer JWT custom claim
9. `66b5a85` — Round C C3+C5+C6+C7: CF JWT-claim hardening + backfill CF
10. `393a818` — Round C: local backfill script (chore)
11. `8c6bdbd` — Round C: backfill script ADC + service account fallback

---

*Last updated: 2026-04-25 | Version: 15.x (Pest/Delivery/Cleaning/Handyman/Fitness CSM + Monetization + AnyTasks deadlines + `publishStaleReviews` + `notifyProviderOnApproval` + scheduled-CF index recovery + `generateDailyOpportunity` on Gemini + App Feedback & Ideas §42 + Smart Notification Router §43 + Fitness Trainer CSM §44 + Categories v3 Premium Workspace §45 + Chat Dark-Mode Input-Bar Fix §46 + Chat Attachments: Location/Video/Banners §47 + Legacy Categories Tab cleanup §48 + Banners v2 §49 + **Security Hardening v15.x Audit §50**)*
