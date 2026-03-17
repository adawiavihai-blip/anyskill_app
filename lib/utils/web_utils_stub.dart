// No-op stubs for Android / iOS / desktop.
// These are called from platform-agnostic code but do nothing on native.

String? sessionGet(String key) => null;
void sessionSet(String key, String value) {}
void pageReload() {}
void triggerCsvDownload(String content, String filename) {}
void openUrl(String url) {}
