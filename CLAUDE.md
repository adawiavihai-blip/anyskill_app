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

*Last updated: 2026-04-14 | Version: 13.0.0 (STABLE — Pet Stay Tracker + QA'd)*
