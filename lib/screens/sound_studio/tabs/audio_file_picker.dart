/// Cross-platform audio file picker for the Sound Studio Library tab (§54).
///
/// **Why this file exists** — `library_tab.dart` originally inlined a
/// `package:web` + `dart:js_interop` upload picker. That made the file
/// uncompilable on the Dart VM (test VM + native targets) because
/// `dart:js_interop` is web-only. The downstream effect was that any
/// widget test importing `library_tab.dart` (directly or transitively
/// through any admin-screen test) crashed at compile time.
///
/// CLAUDE.md §65 fix: extract the picker into a conditional-import
/// triplet:
///
///   - `audio_file_picker.dart`        — public API (this file)
///   - `_audio_file_picker_stub.dart`  — VM / native default
///   - `_audio_file_picker_web.dart`   — real `<input type=file>` impl
///
/// At compile time, Dart picks the stub by default; on platforms
/// where `dart.library.js_interop` is available (= web), it picks
/// the web file instead. The consumer just calls `pickAudioFile()`.
///
/// **For test authors**: the stub returns `null` synchronously, so
/// any widget test that hits this code path gets a deterministic
/// "no file picked" outcome without the test VM ever loading
/// `dart:js_interop`.
library;

import 'package:flutter/foundation.dart' show Uint8List;

// Conditional impl pick.
export '_audio_file_picker_stub.dart'
    if (dart.library.js_interop) '_audio_file_picker_web.dart';

/// A file the user picked via the audio upload sheet.
///
/// Defined here (not in the impls) so callers and both impls share a
/// single canonical type — no duplicate class definitions, no
/// circular-export weirdness.
class PickedAudioFile {
  final String name;
  final Uint8List bytes;
  const PickedAudioFile({required this.name, required this.bytes});
}
