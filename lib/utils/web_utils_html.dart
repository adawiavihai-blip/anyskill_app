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
