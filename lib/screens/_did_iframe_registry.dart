/// Cross-platform iframe registration for the AI-teacher D-ID agent embed.
///
/// **Why this file exists** — `ai_teacher_lesson_modal.dart` originally
/// imported `dart:html` + `dart:ui_web` directly to register a custom
/// platform view. Both are web-only and made the file (and every test
/// that transitively imports `category_results_screen` →
/// `alex_profile_screen` → this modal) uncompilable on the Dart VM.
///
/// CLAUDE.md §65 fix — same conditional-import triplet pattern used for
/// the Sound Studio audio picker:
///
///   - `_did_iframe_registry.dart`        — public API (this file)
///   - `_did_iframe_registry_stub.dart`   — VM / native default
///   - `_did_iframe_registry_web.dart`    — real registerViewFactory impl
///
/// On non-web the stub is a no-op. The widget still mounts an
/// `HtmlElementView` but it just renders empty (acceptable — the modal
/// is gated on `kIsWeb` in the calling screen anyway).
library;

export '_did_iframe_registry_stub.dart'
    if (dart.library.js_interop) '_did_iframe_registry_web.dart';
