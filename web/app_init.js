// ═══════════════════════════════════════════════════════════════════════════════
// AnySkill — app_init.js (NUCLEAR V5 — 2026-06-04)
//
// This file MUST load fresh on every deploy.  index.html injects it with
// a Date.now() query param, and firebase.json sets no-cache headers on it.
// ═══════════════════════════════════════════════════════════════════════════════

// ── REQUIRED APP VERSION — bump this on every deploy ────────────────────────
var REQUIRED_VERSION = '10.5.1';

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
      console.log('[PWA] Standalone mode detected with stale cache (' + cachedV + ' vs ' + REQUIRED_VERSION + ') — forcing refresh');
      try { localStorage.setItem('anyskill_purged_v', REQUIRED_VERSION); } catch(_) {}
      // Clear all caches before reload
      if ('caches' in self) {
        caches.keys().then(function(names) {
          Promise.all(names.map(function(n) { return caches.delete(n); })).then(function() {
            location.reload();
          });
        });
      } else {
        location.reload();
      }
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
