import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/app_localizations.dart';
import 'certification_dialog.dart';
import 'tokens.dart';

/// Row of two large action squares — "Video Intro" + "Work Gallery" —
/// plus an optional certification badge below.
///
/// Extracted from `expert_profile_screen.dart` in §80. The widget is
/// stateless: all state (gallery list, video URLs, cert image) flows
/// from the [data] Map. The single side effect is [onPortfolioTap]
/// which opens the gallery viewer in the parent screen.
///
/// Video priority order (matches the original logic):
///   1. admin-verified video (`verificationVideoUrl` + `videoVerifiedByAdmin`)
///   2. provider's self-uploaded intro video (`introVideoUrl`)
///   3. legacy YouTube link (`videoUrl`)
class ActionSquares extends StatelessWidget {
  const ActionSquares({
    super.key,
    required this.data,
    required this.onPortfolioTap,
  });

  final Map<String, dynamic> data;
  final void Function(int initialIndex) onPortfolioTap;

  /// Extracts a YouTube video ID from a URL. Public so future callers
  /// (e.g. the specialist card hero video) can reuse the same logic.
  static String? extractYouTubeId(String url) {
    if (url.isEmpty) return null;
    // youtu.be/<id>
    final short = RegExp(r'youtu\.be/([^?&\s]+)').firstMatch(url);
    if (short != null) return short.group(1);
    // ?v=<id>
    final long = RegExp(r'[?&]v=([^&\s]+)').firstMatch(url);
    if (long != null) return long.group(1);
    // bare 11-char ID
    if (url.length == 11 && !url.contains('/')) return url;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final gallery = (data['gallery'] as List? ?? []).cast<String>();
    final certImage = data['certificationImage'] as String?;
    final hasCert = certImage != null && certImage.isNotEmpty;

    final verifiedVideoUrl = data['verificationVideoUrl'] as String? ?? '';
    final videoVerifiedByAdmin = data['videoVerifiedByAdmin'] as bool? ?? false;
    final hasVerifiedVideo =
        videoVerifiedByAdmin && verifiedVideoUrl.isNotEmpty;
    final introVideoUrl = data['introVideoUrl'] as String? ?? '';
    final hasIntroVideo = introVideoUrl.isNotEmpty;
    final youtubeUrl = data['videoUrl'] as String? ?? '';
    final videoId = extractYouTubeId(youtubeUrl);
    final hasAnyVideo = hasVerifiedVideo || hasIntroVideo || videoId != null;

    return Column(
      children: [
        Row(
          children: [
            // ── Video Introduction square ──────────────────────────────────
            Expanded(
              child: InkWell(
                onTap: hasAnyVideo
                    ? () async {
                        final String url;
                        if (hasVerifiedVideo) {
                          url = verifiedVideoUrl;
                        } else if (hasIntroVideo) {
                          url = introVideoUrl;
                        } else {
                          url = youtubeUrl.startsWith('http')
                              ? youtubeUrl
                              : 'https://www.youtube.com/watch?v=$videoId';
                        }
                        final uri = Uri.parse(url);
                        if (await canLaunchUrl(uri)) launchUrl(uri);
                      }
                    : null,
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.07),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(
                      vertical: 28, horizontal: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.play_circle_outline_rounded,
                          size: 32,
                          color: hasAnyVideo
                              ? ExpertProfileTokens.purple
                              : Colors.grey[300]),
                      const SizedBox(height: 10),
                      Text(
                        AppLocalizations.of(context).expVideoIntro,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: hasAnyVideo
                              ? Colors.black
                              : Colors.grey[300]!,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            // ── Work Gallery square ────────────────────────────────────────
            Expanded(
              child: InkWell(
                onTap: gallery.isEmpty ? null : () => onPortfolioTap(0),
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.07),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(
                      vertical: 28, horizontal: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.photo_library_outlined,
                          size: 32,
                          color: gallery.isEmpty
                              ? Colors.grey[300]
                              : Colors.black),
                      const SizedBox(height: 10),
                      Text(
                        AppLocalizations.of(context).expGallery,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: gallery.isEmpty
                              ? Colors.grey[300]
                              : Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        // ── Certification badge ─────────────────────────────────────────
        if (hasCert) ...[
          const SizedBox(height: 14),
          InkWell(
            onTap: () => CertificationDialog.show(context, certImage),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.amber.shade50, Colors.amber.shade100],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Row(
                children: [
                  Icon(Icons.workspace_premium_rounded,
                      color: Colors.amber[700], size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      AppLocalizations.of(context).expVerifiedCertificate,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ),
                  Text(AppLocalizations.of(context).expView,
                      style:
                          TextStyle(fontSize: 12, color: Colors.amber[800])),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_back_ios_rounded,
                      size: 12, color: Colors.amber[800]),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
