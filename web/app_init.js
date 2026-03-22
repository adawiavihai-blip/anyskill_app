window.addEventListener('load', function () {
  console.log("QA: App Init Start");

  // ── Watch a SW registration for updates ───────────────────────────────────
  // Calls reg.update() so the browser checks for a new SW on every page load
  // (instead of waiting for the default 24-hour check interval).
  // When a new SW finishes installing, posts 'SKIP_WAITING' so it becomes the
  // active controller immediately — ready to serve assets the moment the user
  // taps the update banner and the page reloads.
  //
  // ⚠️  Auto-reload on controllerchange was intentionally REMOVED.
  // Reason: on iOS Safari the SW state machine fires controllerchange at
  // unexpected times (including on first load), which caused an infinite reload
  // loop. The Flutter update banner now owns the reload decision — it fires
  // only on explicit user action, which iOS always respects.
  function watchRegistration(reg) {
    reg.update().catch(function (err) {
      console.warn('QA: SW update check failed:', err);
    });

    reg.addEventListener('updatefound', function () {
      var newWorker = reg.installing;
      if (!newWorker) return;
      console.log('QA: New SW version found — watching installation');

      newWorker.addEventListener('statechange', function () {
        // Only send SKIP_WAITING in the update scenario (existing controller
        // present). On first install the browser activates automatically.
        if (newWorker.state === 'installed' && navigator.serviceWorker.controller) {
          console.log('QA: New SW ready — sending SKIP_WAITING (banner will prompt user)');
          newWorker.postMessage('SKIP_WAITING');
          // Signal Flutter that a SW update is waiting.
          // _handleWebUpdates() in main.dart reads this flag on next startup
          // and shows the update banner without requiring an admin login.
          try { sessionStorage.setItem('sw_update_pending', '1'); } catch (_) {}
        }
      });
    });
  }

  // ── 1. Register FCM Service Worker ────────────────────────────────────────
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
        console.log("QA: Engine Initialized");
        appRunner.runApp();

        // After Flutter's engine runs, it registers flutter_service_worker.js.
        // Re-register here (browser deduplicates by URL) so we get the
        // registration object and can watch it for updates.
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
