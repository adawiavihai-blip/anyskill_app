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
| Database | Cloud Firestore (42+ collections) |
| Storage | Firebase Storage |
| Functions | Cloud Functions for Firebase (Node.js 24) |
| Payments | Stripe Connect (flutter_stripe) + Firestore credits (legacy) |
| AI | Anthropic Claude API, Vertex AI, Google Generative AI |
| Maps | flutter_map + Geolocator |
| i18n | 4 locales: Hebrew (he), English (en), Spanish (es), Arabic (ar) -- 942 keys each |
| Monitoring | Sentry (sentry_flutter ^8.0.0), Firebase Crashlytics, Watchtower |
| Hosting | Firebase Hosting (SPA) |

**Version:** 9.1.2 &bull; **Firebase Project:** anyskill-6fdf3

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
  services/                  # 40 services (volunteer, escrow, gamification, ranking, location, AI, stripe, etc.)
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

## 4. Escrow & Payment Lifecycle

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

**Stripe path** (`payments.js: releaseEscrow`):
1. Verify PaymentIntent status == `succeeded`
2. Verify provider has `stripeAccountId` + `stripePayoutsEnabled: true`
3. `stripe.transfers.create()` -- amount in agorot (shekel * 100), currency `ils`
4. Generate Morning (Green Invoice) tax documents (non-blocking)
5. Batch: job -> `completed`, platform_earnings -> `settled`, transactions -> `completed`

**Legacy/Credits path** (`index.js: processPaymentRelease`):
1. Read admin fee inside transaction (support per-expert `customCommission` override)
2. `expert.balance += netToExpert`, `expert.orderCount += 1`
3. `admin.totalPlatformBalance += feeAmount`
4. Write `platform_earnings` + `transactions` records

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

- **Font:** Google Fonts Heebo (dynamic), NotoSansHebrew (fallback, bundled)
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

## 10. Firestore Collections Reference

| Collection | Key Fields | Purpose |
|-----------|-----------|---------|
| `users/{uid}` | isProvider, isVolunteer, isVerified, isDemo, isElderlyOrNeedy, isAnySkillPro, proManualOverride, serviceType, xp, balance, pendingBalance, rating, reviewsCount, customerRating, isOnline, lastVolunteerTaskAt, volunteerTaskCount, hasActiveVolunteerBadge, stripeAccountId, cancellationPolicy, streak, lastStreakDate, streakBestEver, lastDailyDropDate, profileBoostUntil, workingHours, selfieVerificationUrl | User profiles |
| `jobs/{jobId}` | customerId, expertId, totalAmount, netAmountForExpert, commission, status, quoteId, chatRoomId, clientReviewDone, providerReviewDone, providerReviewShown, completedAt, cancellationDeadline, stripePaymentIntentId, stripeTransferId | Bookings |
| `quotes/{id}` | providerId, clientId, amount, status, jobId | Price quotes |
| `reviews/{id}` | jobId, reviewerId, revieweeId, isClientReview, ratingParams, overallRating, publicComment, privateAdminComment, isPublished, createdAt | Double-blind reviews |
| `volunteer_tasks/{id}` | clientId, providerId, category, description, status, clientConfirmed, gpsValidated, providerLat/Lng, clientLat/Lng, gpsDistanceMeters, xpAwarded, xpAmount, clientReview, completedAt | Volunteer lifecycle |
| `help_requests/{id}` | userId, category, description, status | Community help requests |
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
| `updateUserXP` | callable | Award/deduct XP by event ID |
| `processPaymentRelease` | callable | Release escrow (Firestore credits path) |
| `releaseEscrow` | callable | Release escrow (Stripe transfer path) |
| `processCancellation` | callable | Cancel with policy enforcement |
| `processRefund` | callable | Stripe refund for disputes |
| `resolveDisputeAdmin` | callable | Admin dispute resolution (refund/release/split) |
| `activateVipSubscription` | callable | Deduct 99 NIS, set isPromoted for 30d |
| `expireVipSubscriptions` | cron 00:30 IST | Clear expired VIP flags |
| `sendReceiptEmail` | Firestore trigger | Email receipt on completion |
| `createStripePaymentSession` | callable | Stripe checkout URL |
| `generateServiceSchema` | callable (admin) | AI generates category-specific schema fields |
| `generateCeoInsight` | callable (admin) | AI CEO strategic analysis from platform metrics |

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

*Last updated: 2026-04-04 | Version: 9.1.2 (STABLE)*
