/// Non-web stub for [downloadCsv] — no-op. The calling widget gates the
/// export button on `kIsWeb`, so this code path is unreachable from real
/// users; the stub exists purely so the test VM and mobile native builds
/// can compile the file (CLAUDE.md §65).
library;

void downloadCsv({required String filename, required String content}) {
  // Intentionally empty — non-web platforms cannot trigger a browser download.
}
