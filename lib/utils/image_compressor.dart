/// AnySkill — Centralized Image Compression Utility
///
/// Provides consistent compression presets across all upload paths.
/// At 3M+ users, uncompressed uploads would exhaust Storage bandwidth
/// and blow up CDN costs.
///
/// Usage:
///   final file = await ImageCompressor.pick(context, ImagePreset.profileAvatar);
///   if (file != null) uploadToStorage(file.bytes, file.name);
library;

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// Predefined compression presets for each upload context.
enum ImagePreset {
  /// Profile avatar: 300x300, 50% quality (~15-30 KB)
  profileAvatar(maxWidth: 300, maxHeight: 300, quality: 50),

  /// Gallery image: 800x800, 65% quality (~50-100 KB)
  gallery(maxWidth: 800, maxHeight: 800, quality: 65),

  /// Chat message image: 1200x1200, 70% quality (~80-150 KB)
  chatImage(maxWidth: 1200, maxHeight: 1200, quality: 70),

  /// Business document / ID scan: 1600x1600, 85% quality (~200-400 KB)
  document(maxWidth: 1600, maxHeight: 1600, quality: 85),

  /// Category / banner image: 1200x800, 75% quality (~100-200 KB)
  banner(maxWidth: 1200, maxHeight: 800, quality: 75),

  /// Admin demo expert: 600x600, 75% quality (~40-80 KB)
  demoExpert(maxWidth: 600, maxHeight: 600, quality: 75);

  const ImagePreset({
    required this.maxWidth,
    required this.maxHeight,
    required this.quality,
  });

  final double maxWidth;
  final double maxHeight;
  final int quality;
}

class CompressedImage {
  final Uint8List bytes;
  final String name;
  final String ext;

  const CompressedImage({
    required this.bytes,
    required this.name,
    required this.ext,
  });
}

class ImageCompressor {
  ImageCompressor._();

  static final _picker = ImagePicker();

  /// Picks an image from gallery with the given [preset] compression.
  /// Returns null if the user cancels.
  static Future<CompressedImage?> pick(ImagePreset preset, {
    ImageSource source = ImageSource.gallery,
  }) async {
    final file = await _picker.pickImage(
      source: source,
      maxWidth: preset.maxWidth,
      maxHeight: preset.maxHeight,
      imageQuality: preset.quality,
    );
    if (file == null) return null;

    final bytes = await file.readAsBytes();
    final ext = file.name.split('.').last;
    final name = '${DateTime.now().millisecondsSinceEpoch}.$ext';

    return CompressedImage(bytes: bytes, name: name, ext: ext);
  }

  /// Compresses existing bytes using a new ImagePicker call.
  /// For cases where bytes are already loaded but need size validation.
  static bool isOversized(Uint8List bytes, {int maxKb = 500}) {
    return bytes.lengthInBytes > maxKb * 1024;
  }
}
