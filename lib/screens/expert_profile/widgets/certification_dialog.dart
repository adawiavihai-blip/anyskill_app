import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

/// Provider certification image viewer.
///
/// Renders a dialog with the certification image (HTTPS URL or base64 data
/// URI) and a "load failed" fallback. Extracted from
/// `expert_profile_screen.dart` in §80 (file-splitting refactor).
///
/// Both methods are static because they hold no state — the only inputs
/// are `context` and the raw image string. Public so the parent screen
/// (and any future callers) can invoke them directly.
class CertificationDialog {
  CertificationDialog._();

  /// Opens the certification image as a centered dialog. Tap-to-close + an
  /// explicit X button. Image is rendered via [buildCertImage] which falls
  /// back gracefully on malformed input.
  static void show(BuildContext context, String imageData) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.workspace_premium_rounded,
                      color: Colors.amber[700]),
                  const SizedBox(width: 8),
                  Text(AppLocalizations.of(context).expCertificateTitle,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
              child: buildCertImage(context, imageData),
            ),
          ],
        ),
      ),
    );
  }

  /// Renders the certification image. Supports:
  ///   • HTTPS URLs    → `Image.network`
  ///   • Base64 raw    → `Image.memory(base64Decode(raw))`
  ///   • Data URI      → strips the `data:image/...;base64,` prefix first
  ///   • Anything else → graceful error placeholder
  ///
  /// Note: NOT private because the parent screen invokes it directly when
  /// rendering inline certification thumbnails (not just inside the dialog).
  static Widget buildCertImage(BuildContext context, String raw) {
    if (raw.startsWith('http')) {
      return Image.network(raw, fit: BoxFit.contain);
    }
    try {
      final b64 = raw.contains(',') ? raw.split(',').last : raw;
      return Image.memory(base64Decode(b64), fit: BoxFit.contain);
    } catch (_) {
      return SizedBox(
        height: 200,
        child: Center(
          child: Text(AppLocalizations.of(context).expImageLoadError),
        ),
      );
    }
  }
}
