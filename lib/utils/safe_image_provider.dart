import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Single source of truth for loading profile images across the app.
///
/// Handles both HTTPS URLs and base64 data URIs (`data:image/png;base64,...`).
/// Returns null if the string is empty/malformed, so callers can show a
/// placeholder (initials, icon, etc.).
///
/// Usage:
/// ```dart
/// CircleAvatar(
///   backgroundImage: safeImageProvider(data['profileImage']),
///   child: safeImageProvider(data['profileImage']) == null
///       ? Text(name[0]) : null,
/// )
/// ```
ImageProvider? safeImageProvider(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  if (raw.startsWith('http')) {
    return CachedNetworkImageProvider(raw);
  }
  // Base64 data URI: "data:image/png;base64,iVBOR..."
  try {
    final b64 = raw.contains(',') ? raw.split(',').last : raw;
    return MemoryImage(base64Decode(b64));
  } catch (_) {
    debugPrint('[SafeImage] Failed to decode base64 (${raw.length} chars)');
    return null;
  }
}

/// Builds a complete avatar widget with proper fallback.
/// Use this everywhere a profile image circle is needed.
Widget buildProfileAvatar({
  required String? imageUrl,
  required String name,
  double radius = 24,
  Color fallbackColor = const Color(0xFF6366F1),
}) {
  final provider = safeImageProvider(imageUrl);
  return CircleAvatar(
    radius: radius,
    backgroundColor: provider != null ? Colors.white : fallbackColor.withValues(alpha: 0.15),
    backgroundImage: provider,
    child: provider == null
        ? Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: TextStyle(
              color: fallbackColor,
              fontWeight: FontWeight.bold,
              fontSize: radius * 0.7,
            ),
          )
        : null,
  );
}
