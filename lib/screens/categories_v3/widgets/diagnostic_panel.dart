// ignore_for_file: avoid_print
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/categories_v3_controller.dart';

/// Live diagnostic strip that renders AT THE TOP of the v3 tab so we can
/// see the actual runtime state without opening DevTools. Shows:
///   • auth uid
///   • stream state (loading / data N / error)
///   • filtered count
///   • root count
///   • raw Firestore count (one-shot probe — bypasses all the Riverpod
///     layers so we can confirm docs actually exist in Firestore)
///
/// When any row shows red/amber we know which layer is breaking. The panel
/// is dismissable so it doesn't permanently clutter the tab.
class DiagnosticPanel extends ConsumerStatefulWidget {
  const DiagnosticPanel({super.key});

  @override
  ConsumerState<DiagnosticPanel> createState() => _DiagnosticPanelState();
}

class _DiagnosticPanelState extends ConsumerState<DiagnosticPanel> {
  bool _dismissed = false;
  int? _rawCount;
  String? _rawError;
  bool _rawLoading = true;

  @override
  void initState() {
    super.initState();
    _probeFirestore();
  }

  Future<void> _probeFirestore() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('categories')
          .limit(200)
          .get();
      if (!mounted) return;
      setState(() {
        _rawCount = snap.docs.length;
        _rawLoading = false;
      });
      print('[V3-DIAG] raw Firestore categories read: ${snap.docs.length} docs');
      if (snap.docs.isNotEmpty) {
        print('[V3-DIAG] first doc id=${snap.docs.first.id} keys=${snap.docs.first.data().keys.toList()}');
      }
    } catch (e, st) {
      if (!mounted) return;
      setState(() {
        _rawError = e.toString();
        _rawLoading = false;
      });
      print('[V3-DIAG] raw Firestore read FAILED: $e\n$st');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '(none)';
    final asyncCategories = ref.watch(categoriesV3StreamProvider);
    final filtered = ref.watch(filteredCategoriesV3Provider);
    final root = filtered.where((c) => c.isRoot).toList();

    final streamLabel = asyncCategories.when(
      data: (list) => '✅ data · ${list.length} docs',
      loading: () => '⏳ loading…',
      error: (e, _) => '❌ ${e.runtimeType}: $e',
    );

    final rawLabel = _rawLoading
        ? '⏳ probing…'
        : _rawError != null
            ? '❌ $_rawError'
            : '✅ $_rawCount docs';

    return Container(
      margin: const EdgeInsetsDirectional.only(bottom: 12),
      padding: const EdgeInsetsDirectional.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF0EA5E9), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.bug_report_rounded,
                  size: 16, color: Color(0xFF0369A1)),
              const SizedBox(width: 6),
              const Text('V3 DIAG · live state',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: Color(0xFF0369A1),
                  )),
              const Spacer(),
              InkWell(
                onTap: () => setState(() => _dismissed = true),
                child: const Icon(Icons.close_rounded,
                    size: 16, color: Color(0xFF0369A1)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _row('auth uid', uid.length > 10 ? '${uid.substring(0, 10)}…' : uid),
          _row('stream',   streamLabel),
          _row('filtered', '${filtered.length} docs'),
          _row('root',     '${root.length} docs'),
          _row('raw probe',rawLabel),
          _row('build mode', kDebugMode ? 'debug' : 'release'),
          if (asyncCategories.hasError) ...[
            const SizedBox(height: 6),
            const Text('STREAM ERROR STACK:',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 10.5)),
            SelectableText(
              asyncCategories.stackTrace?.toString() ?? '(no stack)',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: Color(0xFF991B1B),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 2),
      child: Row(
        children: [
          SizedBox(
            width: 78,
            child: Text('$label:',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF0369A1),
                  fontWeight: FontWeight.w600,
                )),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF1E293B),
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
