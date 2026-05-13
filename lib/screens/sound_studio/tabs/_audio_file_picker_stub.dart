/// Non-web (mobile native + Dart VM) stub for the audio file picker.
///
/// On these platforms there's no `<input type=file>` to spawn — admins are
/// expected to upload sounds from the web admin surface. The stub returns
/// `null` so the caller can show a "available on web" toast.
///
/// This file is selected via the conditional import in
/// [audio_file_picker.dart] when `dart.library.js_interop` is NOT available
/// (i.e. in the test VM and on native targets).
library;

import 'audio_file_picker.dart';

Future<PickedAudioFile?> pickAudioFile() async => null;
