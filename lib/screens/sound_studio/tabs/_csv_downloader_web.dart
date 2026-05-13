/// Web-only impl of [downloadCsv] — spawns an `<a download>` element and
/// triggers a click so the browser saves the file. Selected via the
/// conditional import in `_csv_downloader.dart` (CLAUDE.md §65).
library;

import 'package:web/web.dart' as web;

void downloadCsv({required String filename, required String content}) {
  final dataUrl = 'data:text/csv;charset=utf-8,${Uri.encodeComponent(content)}';
  final anchor = web.HTMLAnchorElement()
    ..href = dataUrl
    ..download = filename
    ..style.display = 'none';
  web.document.body?.appendChild(anchor);
  anchor.click();
  web.document.body?.removeChild(anchor);
}
