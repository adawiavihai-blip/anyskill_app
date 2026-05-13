import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:url_launcher/url_launcher.dart';

const _kPurple     = Color(0xFF6366F1);
const _kPurpleSoft = Color(0xFFF0F0FF);
const _kSuccess    = Color(0xFF10B981);
const _kError      = Color(0xFFEF4444);

/// Data Export — Right of Access ("זכות עיון") under Israeli Privacy Law.
///
/// Calls the `exportUserData` Cloud Function which bundles the caller's
/// personal data (profile, jobs, transactions, reviews, notifications,
/// chat list metadata) into a JSON payload.
///
/// The user can:
///   1. View it on screen
///   2. Copy to clipboard
///   3. Download as JSON file (web only)
class DataExportScreen extends StatefulWidget {
  const DataExportScreen({super.key});

  @override
  State<DataExportScreen> createState() => _DataExportScreenState();
}

class _DataExportScreenState extends State<DataExportScreen> {
  bool _loading = false;
  Map<String, dynamic>? _data;
  String? _error;
  DateTime? _generatedAt;

  Future<void> _runExport() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _error = 'יש להתחבר כדי לייצא נתונים.');
      return;
    }
    setState(() {
      _loading = true;
      _error   = null;
      _data    = null;
    });
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'exportUserData',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
      );
      final result = await callable.call(<String, dynamic>{});
      final data = (result.data as Map?)?.cast<String, dynamic>();
      if (data == null) {
        throw StateError('Empty response from server');
      }
      setState(() {
        _data = data;
        _generatedAt = DateTime.now();
      });
    } on FirebaseFunctionsException catch (e) {
      setState(() => _error = 'שגיאה: ${e.message ?? e.code}');
    } catch (e) {
      setState(() => _error = 'שגיאה לא צפויה. נסה/י שוב או פנה/י ל-privacy@anyskill.app.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _copyToClipboard() async {
    if (_data == null) return;
    final json = const JsonEncoder.withIndent('  ').convert(_data);
    await Clipboard.setData(ClipboardData(text: json));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('הועתק ללוח')),
    );
  }

  Future<void> _downloadFile() async {
    if (_data == null) return;
    final json = const JsonEncoder.withIndent('  ').convert(_data);
    final base64 = base64Encode(utf8.encode(json));
    final uri = Uri.parse('data:application/json;base64,$base64');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FF),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.black87),
            onPressed: () => Navigator.pop(context),
          ),
          centerTitle: true,
          title: const Text(
            'ייצוא הנתונים שלי',
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildIntroCard(),
              const SizedBox(height: 20),
              _buildContentSection(),
              const SizedBox(height: 20),
              _buildActionButton(),
              if (_data != null) ...[
                const SizedBox(height: 16),
                _buildResultCard(),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                _buildErrorCard(),
              ],
              const SizedBox(height: 24),
              _buildFooterNote(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIntroCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.download_rounded, color: Colors.white, size: 24),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'זכות עיון לפי חוק הגנת הפרטיות',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'בלחיצה אחת תוכל/י לקבל עותק מלא של כל הנתונים האישיים '
            'שאנו שומרים עליך. הקובץ יוחזר בפורמט JSON שניתן לקריאה '
            'אנושית או ייבוא לכל פלטפורמה אחרת.',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.94),
                fontSize: 13.5,
                height: 1.55),
          ),
        ],
      ),
    );
  }

  Widget _buildContentSection() {
    final items = [
      ('פרופיל אישי', Icons.person_outline_rounded),
      ('היסטוריית הזמנות', Icons.receipt_long_rounded),
      ('עסקאות פיננסיות', Icons.account_balance_wallet_outlined),
      ('דירוגים שכתבת וקיבלת', Icons.star_outline_rounded),
      ('התראות', Icons.notifications_none_rounded),
      ('רשימת שיחות (מטא-דאטה בלבד)', Icons.chat_bubble_outline_rounded),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'מה ייכלל בייצוא?',
            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ...items.map((it) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: _kPurpleSoft,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(it.$2, size: 16, color: _kPurple),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(it.$1,
                          style: const TextStyle(
                              fontSize: 13.5, color: Colors.black87)),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Icon(Icons.info_outline_rounded,
                    size: 14, color: Color(0xFFB45309)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'תוכן הודעות הצ\'אט אינו נכלל בייצוא הסטנדרטי כדי '
                    'להגן על פרטיות הצד השני בשיחה. ניתן לבקש בנפרד '
                    'ב-privacy@anyskill.app.',
                    style: TextStyle(
                        fontSize: 11.5, color: Color(0xFF92400E), height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _loading ? null : _runExport,
        icon: _loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Colors.white))
            : const Icon(Icons.cloud_download_rounded, size: 20),
        label: Text(_loading ? 'מכין את הקובץ...' : 'הפק ייצוא עכשיו'),
        style: ElevatedButton.styleFrom(
          backgroundColor: _kPurple,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _buildResultCard() {
    final data = _data!;
    final size = const JsonEncoder.withIndent('  ').convert(data).length;
    final sizeKb = (size / 1024).toStringAsFixed(1);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF6EE7B7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                    color: _kSuccess, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('הייצוא מוכן',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold)),
                    Text('גודל: $sizeKb KB',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[700])),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _copyToClipboard,
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('העתק'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kPurple,
                    side: const BorderSide(color: _kPurple),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _downloadFile,
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: const Text('הורד JSON'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kSuccess,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5F5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: _kError, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(_error!,
                style: const TextStyle(
                    fontSize: 13, color: Color(0xFF991B1B), height: 1.5)),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterNote() {
    final stamp = _generatedAt;
    final stampText = stamp == null
        ? null
        : 'הופק: ${stamp.day}/${stamp.month}/${stamp.year} ${stamp.hour.toString().padLeft(2, '0')}:${stamp.minute.toString().padLeft(2, '0')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'הייצוא מתבצע באופן מאובטח דרך Cloud Function. '
          'הקובץ נוצר באמצעות Admin SDK וכפוף לאותם כללי הצפנה כמו '
          'יתר הנתונים שלך. אין שמירה של הקובץ בצד שרת.',
          style: TextStyle(
              fontSize: 11.5, color: Colors.grey[600], height: 1.55),
        ),
        if (stampText != null) ...[
          const SizedBox(height: 8),
          Text(stampText,
              style: TextStyle(
                  fontSize: 11, color: Colors.grey[500])),
        ],
      ],
    );
  }
}
