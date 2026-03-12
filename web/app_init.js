window.addEventListener('load', function(ev) {
  console.log("QA: App Init Start");

  // 1. רישום ה-Service Worker של פיירבייס (ההתראות)
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register('/firebase-messaging-sw.js', { scope: '/' })
      .then(function(reg) {
        console.log('QA: Service Worker Registered for Push');
      }).catch(function(err) {
        console.error('QA: SW Registration Error:', err);
      });
  }

  // 2. הפעלת מנוע פלאטר בצורה בטוחה
  _flutter.loader.loadEntrypoint({
    onEntrypointLoaded: function(engineInitializer) {
      engineInitializer.initializeEngine().then(function(appRunner) {
        console.log("QA: Engine Initialized");
        appRunner.runApp();
      });
    }
  });
});