/// Cross-platform CSV file download trigger for the Sound Studio Logs tab
/// (CLAUDE.md §65 conditional-import pattern).
///
/// On web → spawns an `<a download>` element + click. On non-web → no-op
/// (the calling tab gates the export button behind `kIsWeb`, so this stub
/// is unreachable from real code paths but keeps the test VM compilable).
library;

export '_csv_downloader_stub.dart'
    if (dart.library.js_interop) '_csv_downloader_web.dart';
