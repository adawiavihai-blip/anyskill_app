import 'package:flutter/material.dart' show Color;

/// Shared data models for StripeService.
/// Imported by both stripe_service_web.dart and stripe_service_native.dart.
/// No platform-specific code here.

// ─────────────────────────────────────────────────────────────────────────────
// SavedCard
// ─────────────────────────────────────────────────────────────────────────────

class SavedCard {
  final String id;
  final String brand;
  final String last4;
  final int    expMonth;
  final int    expYear;

  const SavedCard({
    required this.id,
    required this.brand,
    required this.last4,
    required this.expMonth,
    required this.expYear,
  });

  factory SavedCard.fromMap(Map<String, dynamic> m) => SavedCard(
    id:       m['id']                    as String? ?? '',
    brand:    m['brand']                 as String? ?? '',
    last4:    m['last4']                 as String? ?? '',
    expMonth: (m['expMonth'] as num?)?.toInt() ?? 0,
    expYear:  (m['expYear']  as num?)?.toInt() ?? 0,
  );

  String get brandDisplayName {
    switch (brand.toLowerCase()) {
      case 'visa':       return 'Visa';
      case 'mastercard': return 'Mastercard';
      case 'amex':       return 'American Express';
      case 'discover':   return 'Discover';
      case 'unionpay':   return 'UnionPay';
      default:
        return brand.isEmpty
            ? 'Card'
            : '${brand[0].toUpperCase()}${brand.substring(1)}';
    }
  }

  Color get brandColor {
    switch (brand.toLowerCase()) {
      case 'visa':       return const Color(0xFF1A1F71);
      case 'mastercard': return const Color(0xFFEB001B);
      case 'amex':       return const Color(0xFF2E77BC);
      case 'discover':   return const Color(0xFFFF6600);
      default:           return const Color(0xFF374151);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PayQuoteResult
// ─────────────────────────────────────────────────────────────────────────────

class PayQuoteResult {
  final bool    ok;
  final String  jobId;
  final String? error;
  /// True on web: user was redirected to Stripe Checkout.
  /// The payment is in progress; jobId arrives via webhook.
  final bool    isWebRedirect;

  const PayQuoteResult._({
    required this.ok,
    required this.jobId,
    this.error,
    this.isWebRedirect = false,
  });

  factory PayQuoteResult.success(String jobId) =>
      PayQuoteResult._(ok: true, jobId: jobId);

  factory PayQuoteResult.failure(String message) =>
      PayQuoteResult._(ok: false, jobId: '', error: message);

  factory PayQuoteResult.webRedirect() =>
      PayQuoteResult._(ok: true, jobId: '', isWebRedirect: true);
}
