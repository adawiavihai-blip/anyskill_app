import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/admin_users_provider.dart';
import '../utils/web_utils.dart';

// ── Filter enum ──────────────────────────────────────────────────────────────

enum AdminUserFilter { all, customers, providers, banned }

// ─────────────────────────────────────────────────────────────────────────────
/// Extracted Users Tab — replaces the inline `_buildList()` inside
/// `AdminScreen`.
///
/// Architecture:
///   AdminUsersRepository  (Firestore)
///       ↓
///   AdminUsersNotifier    (Riverpod autoDispose provider)
///       ↓
///   AdminUsersTab         (ConsumerStatefulWidget — this file)
///
/// Memory: autoDispose means when the admin closes this tab, all Firestore
/// streams and cached user data are garbage-collected automatically.
// ─────────────────────────────────────────────────────────────────────────────

class AdminUsersTab extends ConsumerStatefulWidget {
  const AdminUsersTab({super.key, this.filter = AdminUserFilter.all});

  final AdminUserFilter filter;

  @override
  ConsumerState<AdminUsersTab> createState() => _AdminUsersTabState();
}

class _AdminUsersTabState extends ConsumerState<AdminUsersTab> {
  // Local UI state for action dialogs (not worth putting in provider)
  final Set<String> _verifyingUids = {};
  final Set<String> _approvedUids = {};

  // ── Filtered list selector (only rebuilds when filtered list changes) ──

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _selectFiltered(
      AdminUsersState s) {
    switch (widget.filter) {
      case AdminUserFilter.all:
        return s.filtered;
      case AdminUserFilter.customers:
        return s.customers;
      case AdminUserFilter.providers:
        return s.providers;
      case AdminUserFilter.banned:
        return s.banned;
    }
  }

  @override
  Widget build(BuildContext context) {
    // select() — only rebuilds this widget when the specific filtered list
    // changes, NOT on every state mutation (e.g., search query update in
    // another tab won't rebuild this one).
    final users = ref.watch(
      adminUsersNotifierProvider.select(_selectFiltered),
    );
    final isLoading = ref.watch(
      adminUsersNotifierProvider.select((s) => s.isLoading),
    );
    final hasMore = ref.watch(
      adminUsersNotifierProvider.select((s) => s.hasMore),
    );
    final notifier = ref.read(adminUsersNotifierProvider.notifier);

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 100, top: 10),
      itemCount: users.length + (hasMore || isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        // ── "Load More" footer ───────────────────────────────────────
        if (index == users.length) {
          return Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : OutlinedButton.icon(
                    onPressed: notifier.loadNextPage,
                    icon: const Icon(Icons.expand_more_rounded),
                    label: const Text('טען 50 משתמשים נוספים'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
          );
        }

        return _UserCard(
          doc: users[index],
          verifyingUids: _verifyingUids,
          approvedUids: _approvedUids,
          onLongPress: () => _showUserActions(
            users[index].id,
            users[index].data(),
          ),
          onApprove: (uid, name, email, cat) =>
              _approveExpertApplication(context, uid, name, email, cat),
          onVerifyToggle: (uid, current) => notifier.toggleVerified(uid, current),
          onPromoteToggle: (uid, current) => notifier.togglePromoted(uid, current),
          onTopUp: (uid, name) => _showAddBalanceDialog(uid, name),
        );
      },
    );
  }

  // ── Dialogs & actions (need BuildContext, stay in widget) ───────────────

  void _showUserActions(String uid, Map<String, dynamic> data) {
    final notifier = ref.read(adminUsersNotifierProvider.notifier);
    bool isBanned = data['isBanned'] ?? false;
    bool isVerified = data['isVerified'] ?? false;
    bool isPromoted = data['isPromoted'] ?? false;
    bool isVerifiedProvider = data['isVerifiedProvider'] ?? true;
    final compliance = data['compliance'] as Map<String, dynamic>?;
    final docUrl = compliance?['docUrl'] as String?;
    final taxStatus = compliance?['taxStatus'] as String?;
    final bool isProvider = data['isProvider'] == true;
    String name = data['name'] ?? 'משתמש';
    String currentNote = data['adminNote'] ?? '';

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => SafeArea(
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(10))),
              const SizedBox(height: 20),
              Text(name,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold)),
              const Divider(),
              ListTile(
                leading: Icon(
                    isVerified ? Icons.verified_user : Icons.verified,
                    color: Colors.blue),
                title: Text(isVerified
                    ? 'בטל אימות (הסר וי כחול)'
                    : 'אמת מומחה (הענק וי כחול)'),
                onTap: () {
                  notifier.toggleVerified(uid, isVerified);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: Icon(
                    isPromoted
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: isPromoted ? Colors.amber : Colors.grey),
                title: Text(isPromoted
                    ? 'בטל קידום (הסר זוהר זהוב)'
                    : 'קדם ספק (הוסף זוהר זהוב + עדיפות)'),
                subtitle: const Text('ספקים מקודמים מופיעים ראשונים בחיפוש',
                    style: TextStyle(fontSize: 11)),
                onTap: () {
                  notifier.togglePromoted(uid, isPromoted);
                  Navigator.pop(context);
                },
              ),
              if (isProvider && compliance != null) ...[
                const Divider(),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.shield_rounded,
                          color: isVerifiedProvider
                              ? Colors.green
                              : Colors.orange,
                          size: 18),
                      const SizedBox(width: 6),
                      Text(
                        isVerifiedProvider ? 'ספק מאושר' : 'ממתין לאישור ציות',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isVerifiedProvider
                              ? Colors.green
                              : Colors.orange,
                          fontSize: 13,
                        ),
                      ),
                      if (taxStatus != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            taxStatus == 'business'
                                ? 'עוסק פטור/מורשה'
                                : 'חשבונית לשכיר',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (docUrl != null)
                  ListTile(
                    leading: const Icon(Icons.folder_open_rounded,
                        color: Colors.blue),
                    title: const Text('צפה במסמך שהועלה'),
                    subtitle: const Text('פתח קישור לקובץ',
                        style: TextStyle(fontSize: 11)),
                    onTap: () {
                      Navigator.pop(context);
                      openUrl(docUrl);
                    },
                  ),
                ListTile(
                  leading: Icon(
                    isVerifiedProvider
                        ? Icons.shield_outlined
                        : Icons.verified_user_rounded,
                    color: isVerifiedProvider ? Colors.red : Colors.green,
                  ),
                  title: Text(
                    isVerifiedProvider
                        ? 'בטל אישור ספק (נעל חשבון)'
                        : 'אשר ספק (פתח גישה)',
                    style: TextStyle(
                      color: isVerifiedProvider ? Colors.red : Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onTap: () {
                    if (isVerifiedProvider) {
                      ref
                          .read(adminUsersRepositoryProvider)
                          .revokeProvider(uid);
                    } else {
                      notifier.approveProvider(uid);
                    }
                    Navigator.pop(context);
                  },
                ),
                const Divider(),
              ],
              if (isProvider)
                ListTile(
                  leading:
                      const Icon(Icons.percent_rounded, color: Colors.purple),
                  title: const Text('עמלת עסקה מותאמת אישית'),
                  subtitle: Text(
                    data['customCommission'] != null
                        ? '${((data['customCommission'] as num) * 100).toStringAsFixed(0)}% (מותאם)'
                        : 'לא הוגדרה — ברירת מחדל גלובלית',
                    style: const TextStyle(fontSize: 11),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showCustomCommissionDialog(
                      uid,
                      name,
                      (data['customCommission'] as num?)?.toDouble(),
                    );
                  },
                ),
              ListTile(
                leading: const Icon(Icons.edit_note, color: Colors.amber),
                title: const Text('עדכן הערת מנהל פנימית'),
                subtitle:
                    Text(currentNote.isNotEmpty ? currentNote : 'אין הערות'),
                onTap: () {
                  Navigator.pop(context);
                  _showAddNoteDialog(uid, currentNote);
                },
              ),
              ListTile(
                leading: Icon(
                    isBanned ? Icons.lock_open : Icons.block,
                    color: Colors.orange),
                title: Text(isBanned
                    ? 'שחרר חסימת חשבון'
                    : 'חסום משתמש מהמערכת'),
                onTap: () {
                  notifier.toggleBanned(uid, isBanned);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.delete_forever, color: Colors.red),
                title: const Text('מחק חשבון לצמיתות',
                    style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDelete(uid, name);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddNoteDialog(String uid, String currentNote) {
    final ctrl = TextEditingController(text: currentNote);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('הערת מנהל'),
        content: TextField(
            controller: ctrl,
            maxLines: 3,
            decoration: const InputDecoration(
                hintText: 'כתוב הערה...', border: OutlineInputBorder())),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ביטול')),
          ElevatedButton(
            onPressed: () {
              ref
                  .read(adminUsersNotifierProvider.notifier)
                  .setAdminNote(uid, ctrl.text);
              Navigator.pop(ctx);
            },
            child: const Text('שמור'),
          ),
        ],
      ),
    );
  }

  void _showCustomCommissionDialog(
      String uid, String name, double? current) {
    final ctrl = TextEditingController(
        text: current != null ? (current * 100).toStringAsFixed(0) : '');
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('עמלה מותאמת — $name'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: 'לדוגמה: 8',
                suffixText: '%',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'השאר ריק כדי לחזור לברירת מחדל גלובלית',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ביטול')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              final text = ctrl.text.trim();
              double? rate;
              if (text.isNotEmpty) {
                final pct = double.tryParse(text);
                if (pct == null || pct < 0 || pct > 100) {
                  messenger.showSnackBar(const SnackBar(
                      content: Text('אחוז לא תקין')));
                  return;
                }
                rate = pct / 100;
              }
              ref
                  .read(adminUsersNotifierProvider.notifier)
                  .setCustomCommission(uid, rate);
              messenger.showSnackBar(SnackBar(
                content: Text(rate != null
                    ? 'עמלה מותאמת עודכנה ל-${(rate * 100).toStringAsFixed(0)}%'
                    : 'עמלה מותאמת הוסרה — חזרה לברירת מחדל'),
              ));
            },
            child: const Text('שמור'),
          ),
        ],
      ),
    );
  }

  void _showAddBalanceDialog(String uid, String name) {
    final messenger = ScaffoldMessenger.of(context);
    final amountCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('הטענת ארנק ל-$name'),
        content: TextField(
            controller: amountCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                hintText: 'סכום להוספה',
                suffixText: '₪',
                border: OutlineInputBorder())),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ביטול')),
          ElevatedButton(
            onPressed: () async {
              final val = double.tryParse(amountCtrl.text.trim());
              if (val == null || val <= 0) return;
              Navigator.pop(ctx);
              await FirebaseFirestore.instance.runTransaction((tx) async {
                final userRef =
                    FirebaseFirestore.instance.collection('users').doc(uid);
                tx.update(userRef, {'balance': FieldValue.increment(val)});
                tx.set(
                    FirebaseFirestore.instance.collection('transactions').doc(),
                    {
                      'userId': uid,
                      'amount': val,
                      'title': 'טעינת ארנק ע״י מנהל',
                      'timestamp': FieldValue.serverTimestamp(),
                      'type': 'admin_topup',
                    });
              });
              messenger.showSnackBar(
                  SnackBar(content: Text('נטענו ₪$val לארנק של $name')));
            },
            child: const Text('אשר והטען'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(String uid, String name) {
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('מחיקה סופית'),
        content: Text(
            'האם למחוק את $name לצמיתות?\nהחשבון יימחק גם מ-Auth וגם מהמסד. לא ניתן לשחזר.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ביטול')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await FirebaseFunctions.instance
                    .httpsCallable('deleteUser')
                    .call({'uid': uid});
                messenger.showSnackBar(SnackBar(
                    backgroundColor: Colors.green,
                    content: Text('$name נמחק בהצלחה')));
              } catch (e) {
                messenger.showSnackBar(SnackBar(
                    backgroundColor: Colors.red,
                    content: Text('שגיאה במחיקה: $e')));
              }
            },
            child:
                const Text('מחק', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _approveExpertApplication(BuildContext context, String uid,
      String name, String email, String category) async {
    if (_verifyingUids.contains(uid)) return;
    setState(() => _verifyingUids.add(uid));
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'us-central1');
      await fn.httpsCallable('adminApproveProvider').call({
        'uid': uid,
        'name': name,
        'category': category,
      });
      if (mounted) setState(() => _approvedUids.add(uid));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$name אושר/ה כספק מומחה — התראה נשלחה'),
          backgroundColor: Colors.purple.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('שגיאה באישור: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ));
      }
    } finally {
      if (mounted) setState(() => _verifyingUids.remove(uid));
    }
  }
}

// ── Individual user card widget ──────────────────────────────────────────────

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.doc,
    required this.verifyingUids,
    required this.approvedUids,
    required this.onLongPress,
    required this.onApprove,
    required this.onVerifyToggle,
    required this.onPromoteToggle,
    required this.onTopUp,
  });

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final Set<String> verifyingUids;
  final Set<String> approvedUids;
  final VoidCallback onLongPress;
  final void Function(String uid, String name, String email, String cat)
      onApprove;
  final void Function(String uid, bool current) onVerifyToggle;
  final void Function(String uid, bool current) onPromoteToggle;
  final void Function(String uid, String name) onTopUp;

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final uid = doc.id;
    final isVerified = data['isVerified'] ?? false;
    final isPromoted = data['isPromoted'] ?? false;
    final isOnline = data['isOnline'] ?? false;
    final isProvider = data['isProvider'] ?? false;
    final isVerifiedProvider = data['isVerifiedProvider'] ?? true;
    final compliance = data['compliance'] as Map<String, dynamic>?;
    final docUrl = compliance?['docUrl'] as String?;
    final hasPendingCompliance =
        isProvider && !isVerifiedProvider && docUrl != null;

    final joinDate =
        (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(
          color: hasPendingCompliance
              ? Colors.orange.shade300
              : Colors.grey.shade100,
          width: hasPendingCompliance ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Compliance banner ─────────────────────────────────────
          if (hasPendingCompliance)
            _ComplianceBanner(
              taxStatus: compliance?['taxStatus'] as String?,
              docUrl: docUrl,
              onApprove: () {
                FirebaseFirestore.instance
                    .collection('users')
                    .doc(uid)
                    .update({'isVerifiedProvider': true});
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content:
                      Text('${data['name'] ?? ''} אומת — גישה לעבודות אופשרה'),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 3),
                ));
              },
            ),

          ListTile(
            onLongPress: onLongPress,
            leading: Stack(
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundImage:
                      (data['profileImage'] != null &&
                              data['profileImage'] != '')
                          ? NetworkImage(data['profileImage'])
                          : null,
                  child: data['profileImage'] == null
                      ? const Icon(Icons.person)
                      : null,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: isOnline ? Colors.green : Colors.grey,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            title: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              children: [
                Text(data['name'] ?? 'משתמש',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                if (isVerified)
                  const Icon(Icons.verified, color: Colors.blue, size: 16),
                if (isProvider && isVerifiedProvider)
                  const Tooltip(
                    message: 'מס אומת',
                    child: Icon(Icons.shield_rounded,
                        color: Colors.green, size: 14),
                  ),
                if (isProvider && !isVerifiedProvider && docUrl == null)
                  const Tooltip(
                    message: 'מסמך מס חסר',
                    child: Icon(Icons.shield_outlined,
                        color: Colors.red, size: 14),
                  ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data['email'] ?? '',
                    style: const TextStyle(fontSize: 12)),
                // Phone
                Builder(builder: (_) {
                  final phone = ((data['phone'] as String?) ??
                          (data['phoneNumber'] as String?) ??
                          '')
                      .trim();
                  if (phone.isEmpty) return const SizedBox.shrink();
                  return GestureDetector(
                    onTap: () => launchUrl(Uri.parse('tel:$phone')),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.phone_rounded,
                            size: 12, color: Colors.green),
                        const SizedBox(width: 3),
                        Text(phone,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.green,
                              decoration: TextDecoration.underline,
                              decorationColor: Colors.green,
                            )),
                      ],
                    ),
                  );
                }),
                Text(
                  'יתרה: ₪${(data['balance'] ?? 0.0).toStringAsFixed(2)} | וותק: ${_calculateSeniority(joinDate)}',
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600),
                ),
                // Provider category + approve button
                if (isProvider) ...[
                  const SizedBox(height: 4),
                  _CategoryLabel(data: data),
                  const SizedBox(height: 4),
                  _ProviderActions(
                    uid: uid,
                    data: data,
                    isProvider: isProvider,
                    verifyingUids: verifyingUids,
                    approvedUids: approvedUids,
                    onApprove: onApprove,
                  ),
                ],
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Verify toggle
                _QuickToggle(
                  active: isVerified,
                  activeIcon: Icons.verified,
                  inactiveIcon: Icons.verified_outlined,
                  activeColor: Colors.blue,
                  tooltip: isVerified ? 'בטל אימות' : 'אמת מומחה',
                  onTap: () => onVerifyToggle(uid, isVerified),
                ),
                // Promote toggle
                _QuickToggle(
                  active: isPromoted,
                  activeIcon: Icons.star_rounded,
                  inactiveIcon: Icons.star_outline_rounded,
                  activeColor: Colors.amber.shade700,
                  tooltip: isPromoted ? 'בטל קידום' : 'קדם ספק',
                  onTap: () => onPromoteToggle(uid, isPromoted),
                ),
                // Top-up
                IconButton(
                  icon: const Icon(Icons.add_card, color: Colors.green),
                  onPressed: () =>
                      onTopUp(uid, data['name'] ?? 'משתמש'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _calculateSeniority(DateTime createdAt) {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inDays >= 365) {
      return '${(diff.inDays / 365).toStringAsFixed(1)} שנים';
    } else if (diff.inDays >= 30) {
      return '${(diff.inDays / 30).floor()} חודשים';
    } else {
      return '${diff.inDays} ימים';
    }
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _ComplianceBanner extends StatelessWidget {
  const _ComplianceBanner({
    required this.taxStatus,
    required this.docUrl,
    required this.onApprove,
  });

  final String? taxStatus;
  final String docUrl;
  final VoidCallback onApprove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(15)),
      ),
      child: Row(
        children: [
          const Icon(Icons.shield_outlined,
              color: Colors.orange, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'ממתין לאימות מסמך מס — ${taxStatus == 'business' ? 'עוסק רשום' : 'חשבונית לשכיר'}',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.orange),
            ),
          ),
          GestureDetector(
            onTap: () => openUrl(docUrl),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.folder_open_rounded,
                      size: 13, color: Colors.orange),
                  SizedBox(width: 4),
                  Text('צפה במסמך',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onApprove,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified_user_rounded,
                      size: 13, color: Colors.green),
                  SizedBox(width: 4),
                  Text('אשר',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.green)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryLabel extends StatelessWidget {
  const _CategoryLabel({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final cat = (data['serviceType'] as String? ?? '').trim();
    final sub = (data['subCategory'] as String? ?? '').trim();
    final reviewed = data['categoryReviewedByAdmin'] as bool? ?? false;

    return Wrap(
      spacing: 4,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Icon(Icons.category_rounded,
            size: 11, color: reviewed ? Colors.indigo : Colors.orange),
        Text(
          cat.isEmpty
              ? 'ללא קטגוריה'
              : sub.isEmpty
                  ? cat
                  : '$cat › $sub',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: reviewed ? Colors.indigo : Colors.orange,
          ),
        ),
        if (!reviewed)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(6),
              border:
                  Border.all(color: Colors.orange.shade300, width: 0.8),
            ),
            child: const Text('AI Suggested',
                style: TextStyle(
                    fontSize: 9,
                    color: Colors.orange,
                    fontWeight: FontWeight.bold)),
          ),
      ],
    );
  }
}

class _ProviderActions extends StatelessWidget {
  const _ProviderActions({
    required this.uid,
    required this.data,
    required this.isProvider,
    required this.verifyingUids,
    required this.approvedUids,
    required this.onApprove,
  });

  final String uid;
  final Map<String, dynamic> data;
  final bool isProvider;
  final Set<String> verifyingUids;
  final Set<String> approvedUids;
  final void Function(String uid, String name, String email, String cat)
      onApprove;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        if (!approvedUids.contains(uid) &&
            ((data['isPendingExpert'] == true) ||
                (isProvider && data['isApprovedProvider'] != true)))
          GestureDetector(
            onTap: verifyingUids.contains(uid)
                ? null
                : () => onApprove(
                      uid,
                      data['name'] as String? ?? 'ספק',
                      data['email'] as String? ?? '',
                      data['serviceType'] as String? ?? '',
                    ),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.purple.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: Colors.purple.shade300, width: 0.8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  verifyingUids.contains(uid)
                      ? const SizedBox(
                          width: 11,
                          height: 11,
                          child: CircularProgressIndicator(
                              strokeWidth: 1.5, color: Colors.purple),
                        )
                      : const Icon(Icons.verified_rounded,
                          size: 11, color: Colors.purple),
                  const SizedBox(width: 3),
                  Text('אשר',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.purple.shade700,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _QuickToggle extends StatelessWidget {
  const _QuickToggle({
    required this.active,
    required this.activeIcon,
    required this.inactiveIcon,
    required this.activeColor,
    required this.tooltip,
    required this.onTap,
  });

  final bool active;
  final IconData activeIcon;
  final IconData inactiveIcon;
  final Color activeColor;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: tooltip,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding:
              const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          decoration: BoxDecoration(
            color: active
                ? activeColor.withValues(alpha: 0.1)
                : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: active
                    ? activeColor.withValues(alpha: 0.6)
                    : Colors.grey.shade300),
          ),
          child: Icon(
            active ? activeIcon : inactiveIcon,
            color: active ? activeColor : Colors.grey,
            size: 20,
          ),
        ),
      ),
    );
  }
}
