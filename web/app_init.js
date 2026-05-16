// ═══════════════════════════════════════════════════════════════════════════════
// AnySkill — app_init.js (NUCLEAR V5 — 2026-06-04)
//
// This file MUST load fresh on every deploy.  index.html injects it with
// a Date.now() query param, and firebase.json sets no-cache headers on it.
// ═══════════════════════════════════════════════════════════════════════════════

// ── REQUIRED APP VERSION — bump this on every deploy ────────────────────────
// 10.8.5: Soft Launch visibility sweep — every user sees every provider
//   AND every active banner. Per user request 2026-05-15:
//   (A) Removed `isVerified: false` filter from CategoryResultsScreen
//       for non-admins. All 4 filter sites updated (primary listings
//       loop, parentCategory fallback, volunteer-only path, users
//       auto-repair fallback). Now: only `isHidden: true` records
//       are filtered for non-admins. Demos (isVerified:true, isHidden:
//       false) and pending-verification real providers both visible.
//   (B) Removed `_studioScheduleAllowsNow` (hour-of-day) filter from
//       BOTH `_ProviderCarouselsRail` (VIP banner) AND `_PromoCarousel`
//       (home_carousel banner). These were silently hiding active
//       banners during off-hours / 0-7am dead zone. Admins control
//       banner visibility via `isActive` + `expiresAt` only.
// 10.8.4: Edit Profile category — restore the cascade flow.
//   רועי צברי report: the original "pick category → sub-cats appear →
//   pick sub-cat → CSM block opens" cascade was broken. My §10.8.3
//   read-only fallback was BLOCKING the dropdown entirely when
//   categories hadn't loaded yet, removing the interactive cascade.
//   Fixed:
//   (A) Removed the read-only field. The DROPDOWN is always rendered.
//   (B) While categories load (1-3s), the dropdown shows the user's
//       saved serviceType as the HINT text (no spinner) so they
//       still see what's selected. Dropdown is disabled
//       (onChanged: null) during this brief window.
//   (C) As soon as categories arrive, `_applyCategoriesSnapshot`
//       resolves `_selectedMainCatId` + `_selectedSubCatId` from the
//       saved serviceType, the dropdown becomes interactive, and
//       sub-cats + CSM block render in cascade.
//   This restores the flow רועי described as the expected behavior.
// 10.8.3 (2026-05-14): Edit Profile dropdown — eliminate spinning circle
//   רועי צברי STILL reports a stuck spinning circle on the category
//   dropdown even after the saved-value badge was added (§10.7.0). The
//   badge was correct but didn't HIDE the spinner — both rendered
//   simultaneously. Root fix this time:
//   (A) When `_mainCategories.isEmpty` AND user has a saved
//       serviceType, RENDER A READ-ONLY FIELD instead of the
//       dropdown. Shows the saved value with a check-mark icon,
//       indigo border — looks identical to a selected dropdown.
//       The empty/spinner-state dropdown is completely hidden.
//       Once categories load, the dropdown takes over.
//   (B) When NO saved value AND no categories, show a quiet
//       grey "טוען..." placeholder — NO spinning circle.
//   (C) `_buildLoadingHint` widget itself was rewritten: removed
//       the CircularProgressIndicator. It's now text-only. The
//       affordance of "loading" is the disabled dropdown
//       (onChanged: null), not a spinning icon. Applies wherever
//       _buildLoadingHint is used.
// 10.8.2 (2026-05-14): ROOT-CAUSE FIX SWEEP — stop adding bandaids,
//   eliminate the recurring "בעיית חיבור" / lost-banner / lost-history
//   complaints once and for all. רועי צברי's grief in this session.
//
//   The recurring pattern was: every time a Firestore read was slow
//   or failed, the UI showed an ALARMING red error scaffold + "בעיית
//   חיבור" text. On working internet with slow first-connect, this
//   was a false positive. Strategy now:
//
//   (A) STOP showing "בעיית חיבור" scaffolds entirely.
//     - category_results_screen.dart: empty state on fetch failure
//       is the neutral "no providers yet" copy. RefreshIndicator is
//       always available; "משוך מטה לרענון" hint added.
//     - expert_profile_screen.dart: removed the data.isEmpty retry
//       scaffold. Render with whatever fields we have (demo profiles
//       have listing fallback that fills the gaps).
//
//   (B) Background retry instead of "give up" — _loadInitial now
//     schedules a SILENT 10s-interval retry timer after both initial
//     attempts fail. Screen self-heals when connection recovers; user
//     never sees the recovery happen.
//
//   (C) History filter MORE INCLUSIVE — show jobs with empty/missing
//     status too (legacy bookings that pre-dated status tracking).
//     User report: "I did work, history shows empty". Now shows ALL
//     non-active-status jobs, including legacy ones.
//
//   (D) HomeTab uses AutomaticKeepAliveClientMixin so the VIP banner's
//     cached snapshot survives bottom-nav tab swipes (Tap Bookings →
//     tap Home: previously the VIP banner went momentarily blank).
//
//   The user's saved values (category in EditProfile, etc.) ALWAYS
//   render directly from widget.userData / cached state — never gated
//   on Firestore reads completing successfully.
// 10.8.1 (2026-05-14): Bookings History tab "stuck spinner" fix —
//   רועי צברי report: tap Bookings → History → spinning circle stuck
//   forever, never loads. Two bugs nested inside each other:
//   (A) ProviderHistoryTab fallback to `transactions` stream had NO
//       timeout — if the jobs stream timed out (6s) and the user had
//       0 history (most new providers), the SECOND stream's spinner
//       hung indefinitely.
//   (B) Same pattern in CustomerBookingsTab's `_buildTransactionFallbackHistory`
//       — nested 3-deep StreamBuilders (primary tx → no-orderBy alt tx →
//       BookingsShimmer) with no timeouts on either inner level.
//   Fixes (both files):
//     • 3s timeout per stream (was 6s for primary, none for fallbacks)
//     • Pre-warmed `_txStream` / `_txAltStream` in initState so the
//       fallback paths don't pay subscription delay when reached
//     • `_lastSnap` caches so transient re-emits don't blink list out
//     • AutomaticKeepAliveClientMixin so the tab survives tab swipes
//     • After ALL timeouts fire, render the empty state — never the
//       infinite shimmer/spinner combo that hung the screen before
// 10.8.0 (2026-05-14): Gallery → Storage + 10-image cap + save retry —
//   רועי צברי report: tried to save profile after adding gallery
//   images → got raw "FIRESTORE INTERNAL ASSERTION FAILED (ID: b815/ca9)"
//   stack trace as snackbar text. Two changes:
//   (A) Gallery images now upload to Firebase Storage at
//       `gallery/{uid}/g_{ts}.jpg` instead of base64-in-Firestore.
//       Each image up to 10 MB (Storage limit). User doc stores just
//       URLs (~120 chars each × 10 = 1.2 KB total instead of ~1 MB).
//       Eliminates the doc-size pressure that triggered the SDK race.
//   (B) Gallery cap bumped 6 → 10 images per provider (user request).
//       UI shows "X/10" counter; "+" button hides at cap; explicit
//       Hebrew snackbar if user tries to exceed.
//   (C) ProfileSaveService.save now retries up to 3× with 0/600/1500ms
//       backoff on INTERNAL_ASSERTION_FAILED (b815/ca9). The SDK
//       usually recovers on the first retry.
//   (D) Friendlier Hebrew error mapping in EditProfile save catch —
//       INTERNAL_ASSERTION_FAILED → "שגיאת תקשורת זמנית — נסה שוב";
//       document-too-large → "הנתונים גדולים מדי — הסר תמונות";
//       permission-denied → "אין הרשאה — התחבר מחדש"; etc.
// 10.7.1 (2026-05-14): Opportunities "Remove" button error fix —
//   רועי צברי report: clicking "הסר" on a stale request showed an
//   error and didn't remove the card. Root causes were multiple:
//   - If already in `declinedProviders[]`, the rule's size-must-grow-
//     by-1 check rejected the duplicate-add → permission-denied.
//   - If the doc was deleted by the customer, update threw not-found.
//   - Raw `'שגיאה: $e'` exposed Firestore error codes to the user.
//   Fix: OPTIMISTIC decline. The card hides immediately via a local
//   `_locallyHidden` set so the action FEELS instant. Server write
//   happens in background with:
//     • 8s timeout on the update
//     • not-found = success (doc gone is the same as removed)
//     • already-declined detected and treated as success
//     • permission-denied logged but not user-visible (card stayed
//       hidden via local set)
//   The user always sees "ההזמנה הוסרה" regardless of server outcome.
// 10.7.0 (2026-05-14): Edit Profile category sync fix —
//   רועי צברי report: his public profile correctly shows "גרר אופנועים"
//   but the edit-profile dropdown shows no selection AND a stuck
//   spinning circle. Root cause: when the categories collection fetch
//   fails/is slow, `_mainCategories` stays empty → dropdown's hint
//   shows _buildLoadingHint (a CircularProgressIndicator). The user
//   can't see their saved value while waiting.
//   Two fixes:
//   (A) Saved-category BADGE rendered ABOVE the dropdown when the
//       categories list hasn't loaded — shows "הקטגוריה שלך: גרר אופנועים"
//       so the user ALWAYS sees their saved value, even during slow
//       network. Resolves from `_activeListingServiceType` or
//       `widget.userData['serviceType']`, independent of any fetch.
//   (B) `_oneshotLoadCategories` now retries 3 times with 2s backoff
//       (was: single attempt with 5s timeout). Total ~22s of patient
//       retries before giving up. Stream still runs in parallel and
//       can win at any time — `_applyCategoriesSnapshot` is idempotent.
// 10.6.9 (2026-05-14): Demo profile + sub-cat banner robustness:
//   (A) "Click demo profile → אין חיבור error" — when expertId was
//       empty OR the user doc didn't exist (admin-created demo with
//       a fake uid that isn't a real Firebase Auth account),
//       CacheService.getDoc returned `{}` → my empty-data guard
//       surfaced "בעיית חיבור". Fix: the listing IS the source of
//       truth for demo profiles. Now `_loadProfileData` merges the
//       listing's name/profileImage/isVerified/isDemo/etc. into the
//       user data when the user doc is missing those fields. Demo
//       profiles render correctly even when users/{uid} doesn't exist.
//   (B) "_resolveCandidateIds hangs forever" — Firestore .get() had
//       NO timeout. Stuck WebChannel → _bannersStream stays null →
//       banner SizedBox.shrink forever. Added 4s timeout that falls
//       through to the name-only seed. Banner shows in <4s worst case.
//   (C) Pull-to-refresh in CategoryResultsScreen no longer wipes the
//       existing providers — _allExperts is replaced atomically only
//       after the new fetch succeeds. On failure, the old list stays.
// 10.6.8 (2026-05-14): Critical UX fixes after the user's frustration:
//   (A) "Pull-to-refresh wipes providers" — _loadInitial used to
//       `_allExperts.clear()` IMMEDIATELY at the start. Then the
//       spinner showed over an empty list. If the new fetch failed,
//       the user lost their data AND saw "no providers" error. Fix:
//       keep _allExperts intact during refresh — only replace
//       atomically AFTER the new fetch succeeds. Pull-to-refresh
//       failures now leave the old list visible (better than nothing).
//   (B) "Sub-cat banner hangs forever" — _resolveCandidateIds did a
//       Firestore .get() with NO timeout. On a stuck WebChannel, the
//       Future never resolved → `_bannersStream` stayed null → banner
//       returned SizedBox.shrink forever. Added 4s timeout that falls
//       through to name-only seed so the banner can still match
//       docs where `subcategoryId == name`.
//   (C) Per-query timeout dialed down: provider_listings primary 20s
//       → 12s. Combined with the 2-attempt retry, max ceiling is now
//       27s instead of 43s before showing the retry scaffold.
// 10.6.7 (2026-05-14): Fourth live user report (רועי צברי) — two CRITICAL
//   fixes for stream-recreation and aggressive-retry footguns:
//   (A) "Sub-category spinner stuck for 2 minutes" — `_loadInitial`'s
//       5-attempt retry policy (~130s total) was the previous fix gone
//       too far. Reduced to 2 attempts (20s + 3s + 20s = ~43s max).
//       The spinner also now shows "טוען נותני שירות..." caption so
//       the user knows it's working, not frozen.
//   (B) "VIP banner disappears on refresh" — both _ProviderCarouselsRail
//       and SubcategoryBannerHeader were creating their snapshot stream
//       INLINE in build(). Every parent rebuild (RefreshIndicator,
//       online toggle, search-bar focus) recreated the subscription,
//       cancelled the previous one, and showed SizedBox.shrink during
//       the brief re-resolve window. Banner appeared to "vanish".
//       Fix: cached stream in initState (StatefulWidget) + cache last
//       successful snapshot so transient re-emit windows don't blink
//       the banner out.
// 10.6.6 (2026-05-14): Third live user report (רועי צברי) — two fixes:
//   (A) "Profile card click spinner stuck" — ExpertProfileScreen's
//       _loadProfileData called CacheService.getDoc + listing .get()
//       WITHOUT TIMEOUTS. Slow WebChannel → FutureBuilder stuck on
//       CircularProgressIndicator forever, profile never opened. Added
//       12s primary + 8s fallback per §15 Law 15. On both failures,
//       returns empty map → build path now shows a "בעיית חיבור" retry
//       scaffold instead of hanging on the spinner. Also added 8s
//       timeout to the listing-merge .get().
//   (B) VIP banner still missing on גרר אופנועים sub-category — even
//       after the §10.6.4 banner indexes deploy. Root cause: the
//       `_subcatScheduleAllowsNow` filter was silently hiding banners
//       whose admin-configured scheduleHours didn't include the current
//       hour-of-day bucket (or hit the 0-7am dead zone). Removed the
//       schedule filter from the active code path. Admins control
//       visibility via isActive + expiresAt only — no surprise hiding.
// 10.6.5 (2026-05-14): Second live user report (רועי צברי) — two fixes:
//   (A) Flash Auction "stuck tow request" — the "לא מעוניין" button
//       lived INSIDE `_buildEtaInput`, so once a provider submitted
//       an offer (`myOffer != null` → `_OfferStatusBlock` rendered
//       instead), the button vanished. Provider had no way to remove
//       a stale/rejected auction from their opportunities feed.
//       Hoisted the button OUT of _buildEtaInput → renders ALWAYS
//       except when status==selected (provider won — committed to job).
//       Label adapts: "לא מעוניין" pre-submit, "הסר מהרשימה" post.
//   (B) "בעיית חיבור" false-positive on sub-categories — bumped the
//       retry policy in CategoryResultsScreen._loadInitial from 2
//       attempts to 5 with exponential backoff (0s → 2s → 4s → 8s →
//       8s). Total patient wait is now ~130s before showing the retry
//       scaffold. Spinner stays during the entire retry window — no
//       more flashing the red wifi-off scaffold during transient hiccups.
// 10.6.4 (2026-05-14): Live user report (רועי צברי) — three fixes:
//   (A) Missing Firestore composite indexes for `banners` collection
//       caused SubcategoryBannerHeader's whereIn query to silently
//       error → widget collapsed → VIP banner missing on the
//       גרר אופנועים sub-category. Added 3 composite indexes:
//       (placement+subcategoryId), (placement+order), and
//       (placement+isDefaultGlobalSubcat+isActive).
//   (B) Timeouts were too aggressive everywhere. False-positive
//       "בעיית חיבור" warnings were firing on a working internet
//       because cold-start handshakes legitimately take 3-8s. Bumped
//       all Tier-2 timeouts to 20-25s + added Tier-1.5 silent auto-
//       retries at 8-10s. CategoryResultsScreen now does ONE silent
//       retry inside _loadInitial before showing the retry scaffold.
//   (C) NotificationsScreen + HomeScreen + HomeTab: same pattern.
//       Timeouts: 8s → 25s for notifications, 5s → 25s for home user
//       stream, 6s → 20s for home categories.
// 10.6.3 (2026-05-14): Two more bell+banner fixes.
//   (A) NotificationsScreen "bell opens, stuck on spinner forever" — the
//       8s Stream.timeout() wrapper around the snapshot stream put the
//       stream in a PERMANENT error state on slow first connect, so even
//       when the connection recovered the user stayed on the wifi-off
//       error UI with no retry option. Replaced with §15 Law 15 manual
//       supervisor (1s .get() Tier-1 fallback + 8s Tier-2 timeout flag)
//       + explicit retry scaffold with "נסה שוב" button + _retry method
//       that resets flags and re-fires the .get().
//   (B) SubcategoryBannerHeader hoisted OUT of `_renderExperts` so the
//       VIP/promo banner shows even when the providers list is empty
//       or loading (was vanishing on sub-categories like גרר אופנועים
//       whenever a fetch hadn't completed yet).
// 10.6.2 (2026-05-14): CategoryResultsScreen "no providers in sub-category"
//   fix — _fetchPage's primary listings query was falling back to a
//   Source.cache read on 8s timeout. Per CLAUDE.md Law 23 web persistence
//   is OFF, so the cache fallback always returned 0 results. After the
//   §51/§52 cache-bust bumps wiped every PWA's IndexedDB, slow first
//   loads timed out and silently rendered an empty list. Fix:
//     1. Removed the broken cache fallback.
//     2. Bumped primary timeout 8s → 12s; parentCategory 6s → 10s;
//        users-collection fallback gained a 10s timeout (had none).
//     3. New `_fetchFailed` flag distinguishes TRUE empty category
//        from a network/timeout failure → empty-state widget shows a
//        red wifi-off icon + "בעיית חיבור" + "נסה שוב" CTA instead of
//        the misleading "be the first to register here" copy.
// 10.6.1 (2026-05-14): VIP banner "grey square" fix (see git history).
// 10.6.0 (2026-05-14): HomeScreen + HomeTab stream supervisors (§15 Law 15).
//   Provider login was stuck on CircularProgressIndicator forever when the
//   users/{uid}.snapshots() WebChannel zombied on iOS Safari, OR the home
//   tab rendered with categories empty because the categories snapshot
//   stream stalled and never delivered a first event. Added two-tier
//   safety nets to both:
//     1. HomeScreen — 1s tier-1 one-shot .get() fallback for user doc +
//        5s tier-2 timeout → retry scaffold.
//     2. HomeTab — 1s tier-1 .get() fallback for categories + 6s tier-2
//        timeout → empty-state w/ pull-to-refresh hint. Pull-to-refresh
//        re-fires the .get() AND re-arms the supervisor.
// 10.5.6 (2026-05-11): Category dropdowns 3-layer defense (see history).
// 10.8.6 (2026-05-15): bumped to force the cache purge for all users.
// 10.8.7 (2026-05-15): CRITICAL — the standalone-PWA purge block above
//   was incomplete (deleted caches but never unregistered the Service
//   Worker, AND pre-set the version flag so the full nuclear purge
//   skipped). Installed-PWA users (e.g. רועי) therefore stayed frozen
//   on the old build through EVERY deploy. The block is now fixed to
//   do the complete purge; this bump triggers that fixed block on
//   every device. ALWAYS bump REQUIRED_VERSION in the SAME deploy as
//   any client-code fix that users must receive.
// 10.8.8 (2026-05-15): RoleSwitcherScreen — a failed `activeRole` write
//   no longer blocks the user from entering the app (resilient _select).
var REQUIRED_VERSION = '11.9.0+15';

// ── iOS PWA STANDALONE FIX ──────────────────────────────────────────────────
// iOS PWA (Home Screen icon) aggressively caches the app shell. When opened
// in standalone mode, it often serves a frozen snapshot from weeks ago.
// This check forces a reload if the cached version doesn't match.
(function() {
  var isStandalone = window.matchMedia('(display-mode: standalone)').matches
                  || window.navigator.standalone === true;
  if (isStandalone) {
    var cachedV = '';
    try { cachedV = localStorage.getItem('anyskill_purged_v') || ''; } catch(_) {}
    if (cachedV !== REQUIRED_VERSION) {
      console.log('[PWA] Standalone stale cache (' + cachedV + ' vs ' + REQUIRED_VERSION + ') — FULL purge');
      try { localStorage.setItem('anyskill_purged_v', REQUIRED_VERSION); } catch(_) {}
      // ════════════════════════════════════════════════════════════════
      // CRITICAL FIX (2026-05-15, רועי צברי "deploys never reach me"):
      // This block USED to only delete Cache Storage + reload. That is
      // NOT enough — the old Service Worker SURVIVES and immediately
      // re-caches the old build's resources, so a standalone PWA stays
      // frozen on the old build FOREVER. Worse: this block sets
      // `anyskill_purged_v` to the new version, which makes the FULL
      // nuclear purge below (the one that DOES unregister the SW) skip.
      // Net effect: every deploy was invisible to installed-PWA users
      // (Roi), while browser-tab users (Kobi) got updates fine — because
      // for them this standalone block is skipped and the nuclear purge
      // runs in full.
      //
      // FIX: this block now does the COMPLETE purge — unregister ALL
      // service workers AND delete ALL caches — before reloading.
      // ════════════════════════════════════════════════════════════════
      var jobs = [];
      if ('serviceWorker' in navigator) {
        jobs.push(
          navigator.serviceWorker.getRegistrations().then(function(regs) {
            return Promise.all(regs.map(function(r) {
              console.log('[PWA] Unregistering SW:', r.scope);
              return r.unregister();
            }));
          })
        );
      }
      if ('caches' in self) {
        jobs.push(
          caches.keys().then(function(names) {
            return Promise.all(names.map(function(n) {
              console.log('[PWA] Deleting cache:', n);
              return caches.delete(n);
            }));
          })
        );
      }
      Promise.all(jobs)
        .then(function() {
          console.log('[PWA] Full purge done — reloading for v' + REQUIRED_VERSION);
          location.reload();
        })
        .catch(function(err) {
          console.warn('[PWA] Purge error (reloading anyway):', err);
          location.reload();
        });
      return; // stop — reload will re-run this script
    }
  }
})();

// NOTE: bfcache buster is now INLINE in index.html (not here) because
// deferred scripts don't reliably fire on bfcache pageshow restoration.

// ── NUCLEAR CACHE PURGE — version-aware ─────────────────────────────────────
// On every page load: compare REQUIRED_VERSION against localStorage.
// If mismatch: nuke ALL service workers + Cache API + force reload ONCE.
// The reload guard uses localStorage (survives tab close) not sessionStorage.
(function() {
  var PURGE_KEY = 'anyskill_purged_v';

  // Skip if we already purged for this exact version
  var purgedFor = '';
  try { purgedFor = localStorage.getItem(PURGE_KEY) || ''; } catch(_) {}

  if (purgedFor === REQUIRED_VERSION) {
    console.log('[Nuclear] Already on v' + REQUIRED_VERSION + ' — no purge needed');
    return;
  }

  console.log('[Nuclear] Version mismatch: cached=' + purgedFor + ' required=' + REQUIRED_VERSION);

  // Mark as purged BEFORE any async work — prevents re-entry on reload
  try { localStorage.setItem(PURGE_KEY, REQUIRED_VERSION); } catch(_) {}

  var tasks = [];

  // 1. Unregister ALL service workers
  if ('serviceWorker' in navigator) {
    tasks.push(
      navigator.serviceWorker.getRegistrations().then(function(regs) {
        return Promise.all(regs.map(function(r) {
          console.log('[Nuclear] Unregistering SW:', r.scope);
          return r.unregister();
        }));
      })
    );
  }

  // 2. Delete ALL Cache Storage entries
  if ('caches' in self) {
    tasks.push(
      caches.keys().then(function(names) {
        return Promise.all(names.map(function(n) {
          console.log('[Nuclear] Deleting cache:', n);
          return caches.delete(n);
        }));
      })
    );
  }

  // 3. After cleanup, reload to fetch fresh assets
  Promise.all(tasks).then(function() {
    console.log('[Nuclear] All caches purged — reloading for v' + REQUIRED_VERSION);
    location.reload();
  }).catch(function(err) {
    console.warn('[Nuclear] Purge error (reloading anyway):', err);
    location.reload();
  });
})();

// ── WATCHDOG TIMER — safety net for mobile loading hangs ────────────────────
// If the Flutter app hasn't set sessionStorage['app_ready'] within 12 seconds
// of page load, force a full reload. Increased from 7s to 12s to avoid
// premature reloads when CSP blocks or slow networks delay Flutter engine init.
//
// CRITICAL: Max 2 reload attempts per page session. After 2 failed attempts,
// the watchdog stops — preventing infinite reload loops when the underlying
// issue (CSP block, broken build) persists across reloads.
window.addEventListener('load', function() {
  // Clear the ready flag at the start of each load so we detect fresh boots
  try { sessionStorage.removeItem('app_ready'); } catch(_) {}

  // Reload attempt counter — persists across reloads within the same tab session
  var attempts = 0;
  try { attempts = parseInt(sessionStorage.getItem('watchdog_attempts') || '0', 10); } catch(_) {}

  setTimeout(function() {
    var ready = false;
    try { ready = sessionStorage.getItem('app_ready') === '1'; } catch(_) {}
    if (ready) {
      // App booted successfully — reset the attempt counter
      try { sessionStorage.removeItem('watchdog_attempts'); } catch(_) {}
      return;
    }
    if (attempts >= 2) {
      console.warn('[Watchdog] App not ready after 12s — max retries (2) reached, stopping');
      return;
    }
    console.warn('[Watchdog] App not ready after 12s — reload attempt ' + (attempts + 1) + '/2');
    try { sessionStorage.setItem('watchdog_attempts', String(attempts + 1)); } catch(_) {}
    try { localStorage.removeItem('anyskill_purged_v'); } catch(_) {}
    location.reload();
  }, 12000);
});

// ── LOAD EVENT — runs only AFTER the nuclear purge has either completed
//    or been skipped (version matches).  If the purge triggered a reload,
//    this code never executes on the first pass. ─────────────────────────────
window.addEventListener('load', function () {
  console.log('[AnySkill] App Init — v' + REQUIRED_VERSION);

  // ── Watch SW registrations for live updates (post-purge) ──────────────
  var _signalled = false;
  function watchReg(reg) {
    reg.addEventListener('updatefound', function () {
      var nw = reg.installing;
      if (!nw) return;
      nw.addEventListener('statechange', function () {
        if (nw.state === 'installed' && navigator.serviceWorker.controller && !_signalled) {
          _signalled = true;
          nw.postMessage('SKIP_WAITING');
          try { sessionStorage.setItem('sw_update_pending', '1'); } catch (_) {}
        }
      });
    });
  }

  // ── 1. Register FCM Service Worker ────────────────────────────────────
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker
      .register('/firebase-messaging-sw.js', { scope: '/' })
      .then(function (reg) {
        console.log('[SW] FCM registered');
        watchReg(reg);
      })
      .catch(function (err) {
        console.error('[SW] FCM registration failed:', err);
      });
  }

  // ── 2. Start Flutter engine ───────────────────────────────────────────
  _flutter.loader.loadEntrypoint({
    onEntrypointLoaded: function (engineInitializer) {
      engineInitializer.initializeEngine().then(function (appRunner) {
        console.log('[Flutter] Engine initialized — v' + REQUIRED_VERSION);
        appRunner.runApp();

        // Flutter SW registration removed — the FCM SW handles the / scope.
        // Having two SWs on the same scope causes registration loops on iOS PWA.
        // The Flutter engine loads assets directly (no SW caching needed since
        // persistence is OFF and firebase.json sets proper Cache-Control headers).
      });
    }
  });
});
