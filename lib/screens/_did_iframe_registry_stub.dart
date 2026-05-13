/// Non-web stub — `registerDIDAgentIframe` is a no-op on the Dart VM
/// and on mobile native builds. The calling widget should already gate
/// the entire modal on `kIsWeb` (see `ai_teacher_lesson_modal.dart`),
/// so this stub will only be invoked from a code path that is itself
/// hidden from the user.
library;

void registerDIDAgentIframe({
  required String viewType,
  required String url,
}) {
  // Intentionally empty — non-web platforms cannot host an iframe view
  // factory. See `_did_iframe_registry_web.dart` for the real impl.
}
