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
| Hosting | Firebase Hosting (SPA) |

**Version:** 8.9.4 &bull; **Firebase Project:** anyskill-6fdf3

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

## 10. Firestore Collections Reference

| Collection | Key Fields | Purpose |
|-----------|-----------|---------|
| `users/{uid}` | isProvider, isVolunteer, isVerified, isDemo, isElderlyOrNeedy, isAnySkillPro, proManualOverride, serviceType, xp, balance, pendingBalance, rating, reviewsCount, customerRating, isOnline, lastVolunteerTaskAt, volunteerTaskCount, hasActiveVolunteerBadge, stripeAccountId, cancellationPolicy, streak, lastStreakDate, streakBestEver, lastDailyDropDate, profileBoostUntil | User profiles |
| `jobs/{jobId}` | customerId, expertId, totalAmount, netAmountForExpert, commission, status, quoteId, chatRoomId, clientReviewDone, providerReviewDone, cancellationDeadline, stripePaymentIntentId, stripeTransferId | Bookings |
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
| `stories/{uid}` | mediaUrl, timestamp, viewCount, likeCount | Skills Stories |
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

## 15b. Code Health Snapshot (2026-04-03)

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

### Database Indexing (30 composite indexes)
8 new indexes added for new collections (2026-03-30):
- `volunteer_tasks`: 4 indexes (anti-fraud cooldown, reciprocal, daily cap, client stream)
- `job_broadcasts`: 1 index (status + category + createdAt)
- `support_tickets`: 2 indexes (admin inbox, user tickets)
- `user_rewards`: 1 index (active rewards by user)

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

*Last updated: 2026-04-03 | Version: 8.9.4*
