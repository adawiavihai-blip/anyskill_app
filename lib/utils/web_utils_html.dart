// Web implementations using dart:html (stable, no dart:js_interop required).
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:convert';

String? sessionGet(String key) =>
    html.window.sessionStorage[key];

void sessionSet(String key, String value) =>
    html.window.sessionStorage[key] = value;

void pageReload() => html.window.location.reload();

void triggerCsvDownload(String content, String filename) {
  final encoded = base64Encode(utf8.encode(content));
  (html.AnchorElement(href: 'data:text/csv;charset=utf-8;base64,$encoded')
    ..setAttribute('download', filename))
    .click();
}

/// Opens [url] in a new browser tab.
void openUrl(String url) {
  html.window.open(url, '_blank');
}

/// Disables the browser's back-forward cache (bfcache) for this page.
/// Called once at app startup. When the user navigates away and presses Back,
/// the browser will do a fresh load instead of restoring a frozen snapshot.
void disableBfcache() {
  // The `unload` listener prevents the browser from storing the page in bfcache.
  // This is intentional — Flutter SPA state cannot survive bfcache restoration.
  html.window.addEventListener('unload', (event) {
    // Intentionally empty — the mere presence of this listener
    // tells the browser NOT to put the page in bfcache.
  });
}

/// Clears browser caches (IndexedDB + Cache API) to force fresh Firestore
/// and service-worker data after a version upgrade.
/// Returns a Future that completes when cleanup is done (best-effort).
Future<void> clearWebCaches() async {
  try {
    // 1. Delete all IndexedDB databases (Firestore persistence, etc.)
    //    The window.indexedDB.databases() API is not available in dart:html,
    //    so we delete the known Firestore DB by name.
    html.window.indexedDB!.deleteDatabase('firebaseLocalStorageDb');
    html.window.indexedDB!.deleteDatabase('firestore/[DEFAULT]/anyskill-6fdf3/main');
  } catch (_) {}
  try {
    // 2. Clear the Cache API (service-worker cached assets)
    //    caches.keys() → delete each cache store.
    final cacheKeys = await html.window.caches!.keys();
    for (final key in cacheKeys) {
      await html.window.caches!.delete(key);
    }
  } catch (_) {}
}
