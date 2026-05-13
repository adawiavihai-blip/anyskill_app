/// Web-only audio file picker. Uses package:web to spawn a transient
/// `<input type=file>` element + a FileReader for the bytes.
///
/// Selected via conditional import from [audio_file_picker.dart] when
/// `dart.library.js_interop` is available. On non-web platforms,
/// the stub at `_audio_file_picker_stub.dart` is used instead — that
/// keeps the test VM and mobile native builds compilable (CLAUDE.md §65).
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'audio_file_picker.dart';

Future<PickedAudioFile?> pickAudioFile() async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = 'audio/*';
  final completer = Completer<PickedAudioFile?>();
  input.onChange.listen((_) {
    final files = input.files;
    if (files == null || files.length == 0) {
      completer.complete(null);
      return;
    }
    final file = files.item(0);
    if (file == null) {
      completer.complete(null);
      return;
    }
    final reader = web.FileReader();
    // package:web exposes events via assignable handler properties
    // (`onload` / `onerror` are JSFunction-typed, not Dart streams).
    reader.onload = ((web.Event _) {
      try {
        final result = reader.result;
        if (result == null) {
          completer.complete(null);
          return;
        }
        // readAsArrayBuffer guarantees JSArrayBuffer in `result`.
        final buffer = result as JSArrayBuffer;
        final bytes = buffer.toDart.asUint8List();
        completer.complete(PickedAudioFile(name: file.name, bytes: bytes));
      } catch (e) {
        completer.completeError(e);
      }
    }).toJS;
    reader.onerror = ((web.Event _) {
      completer.completeError(
        reader.error?.message ?? 'FileReader error',
      );
    }).toJS;
    reader.readAsArrayBuffer(file);
  });
  input.click();
  return completer.future;
}
