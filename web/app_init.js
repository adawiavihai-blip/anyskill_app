// ── FORCE CACHE BUST — V4 2026-05-31 ────────────────────────────────────────
// On first load after deploy: unregister ALL old service workers + clear
// caches, then reload so the browser fetches fresh main.dart.js.
// The flag 'v5_purged' in sessionStorage prevents an infinite reload loop.
(function() {
  if ('serviceWorker' in navigator && !sessionStorage.getItem('v5_purged')) {
    sessionStorage.setItem('v5_purged', '1');
    navigator.serviceWorker.getRegistrations().then(function(regs) {
      var hadWorkers = regs.length > 0;
      var promises = regs.map(function(r) {
        console.log('[V4] Unregistering SW:', r.scope);
        return r.unregister();
      });
      // Also nuke all Cache Storage entries (service worker asset cache)
      if ('caches' in self) {
        caches.keys().then(function(names) {
          names.forEach(function(n) {
            console.log('[V4] Deleting cache:', n);
            caches.delete(n);
          });
        });
      }
      if (hadWorkers) {
        Promise.all(promises).then(function() {
          console.log('[V4] All SWs unregistered — reloading for fresh assets');
          location.reload();
        });
        return; // stop — the reload will re-run this file with v5_purged set
      }
    });
  }
})();

window.addEventListener('load', function () {
  console.log("QA: App Init Start — V4 build 300526");

  // ── Watch a SW registration for updates ───────────────────────────────────
  function watchRegistration(reg) {
    reg.update().catch(function (err) {
      console.warn('QA: SW update check failed:', err);
    });

    reg.addEventListener('updatefound', function () {
      var newWorker = reg.installing;
      if (!newWorker) return;
      console.log('QA: New SW version found — watching installation');

      newWorker.addEventListener('statechange', function () {
        if (newWorker.state === 'installed' && navigator.serviceWorker.controller) {
          console.log('QA: New SW ready — sending SKIP_WAITING');
          newWorker.postMessage('SKIP_WAITING');
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
        console.log('QA: FCM Service Worker registered');
        watchRegistration(reg);
      })
      .catch(function (err) {
        console.error('QA: FCM SW Registration Error:', err);
      });
  }

  // ── 2. Start Flutter engine ────────────────────────────────────────────────
  _flutter.loader.loadEntrypoint({
    onEntrypointLoaded: function (engineInitializer) {
      engineInitializer.initializeEngine().then(function (appRunner) {
        console.log("QA: Engine Initialized — V4");
        appRunner.runApp();

        if ('serviceWorker' in navigator) {
          navigator.serviceWorker
            .register('/flutter_service_worker.js', { scope: '/' })
            .then(function (reg) {
              console.log('QA: Flutter SW registration obtained — watching for updates');
              watchRegistration(reg);
            })
            .catch(function (err) {
              console.warn('QA: Could not watch Flutter SW:', err);
            });
        }
      });
    }
  });
});
