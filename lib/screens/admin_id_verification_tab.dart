import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/hint_icon.dart';
import '../services/private_data_service.dart';

/// Self-contained ID Verification tab extracted from AdminScreen.
/// Owns its own verifying/approved UID tracking sets and all approve/reject logic.
class AdminIdVerificationTab extends StatefulWidget {
  const AdminIdVerificationTab({super.key});

  @override
  State<AdminIdVerificationTab> createState() => _AdminIdVerificationTabState();
}

class _AdminIdVerificationTabState extends State<AdminIdVerificationTab> {
  // ── ID verification -- tracks which UIDs are mid-request (prevents double-tap)
  final Set<String> _verifyingUids = {};
  // ── Locally approved UIDs -- hides the Approve button instantly after CF success
  //    without waiting for the paginated list to reload.
  final Set<String> _approvedUids = {};

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Hint icon (admin-controlled help) ───────────────────────────
          const Align(
            alignment: AlignmentDirectional.centerEnd,
            child: HintIcon(screenKey: 'identity_verification'),
          ),

          // ── Expert Applications ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: const [
                Text('🚀', style: TextStyle(fontSize: 20)),
                SizedBox(width: 8),
                Text('בקשות הצטרפות כמומחים',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          // Stream A: classic pending applications (isPendingExpert == true)
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .where('isPendingExpert', isEqualTo: true)
                .limit(50)
                .snapshots(),
            builder: (context, snapA) {
              // Stream B: providers with isApprovedProvider explicitly = false
              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .where('isProvider', isEqualTo: true)
                    .where('isApprovedProvider', isEqualTo: false)
                    .limit(50)
                    .snapshots(),
                builder: (context, snapB) {
                  // Stream C: providers whose isApprovedProvider field is ABSENT
                  return StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .where('isProvider', isEqualTo: true)
                        .limit(50)
                        .snapshots(),
                    builder: (context, snapC) {
                      if (!snapA.hasData && !snapB.hasData && !snapC.hasData) {
                        return const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      // Stream C: keep only docs where isApprovedProvider is NOT true
                      final cDocs = (snapC.data?.docs ?? []).where((d) {
                        final data = d.data() as Map<String, dynamic>;
                        return data['isApprovedProvider'] != true;
                      }).toList();

                      // Merge A + B + C, deduplicate by document ID
                      final seenIds = <String>{};
                      final docs = <DocumentSnapshot>[
                        ...?snapA.data?.docs,
                        ...?snapB.data?.docs,
                        ...cDocs,
                      ].where((d) => seenIds.add(d.id)).toList();

                      if (docs.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          child: Text('אין בקשות ממתינות',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey[500])),
                        );
                      }
                      return ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (ctx, i) =>
                            _buildExpertApplicationCard(ctx, docs[i]),
                      );
                    },
                  );
                },
              );
            },
          ),

          const Divider(height: 1, thickness: 1),
          const SizedBox(height: 8),

          // ── ID Verification ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: const [
                Text('🪪', style: TextStyle(fontSize: 20)),
                SizedBox(width: 8),
                Text('אימות זהות',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .where('idVerificationStatus', isEqualTo: 'pending')
                .limit(100)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final docs = snapshot.data!.docs;
              if (docs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  child: Text('אין ספקים הממתינים לאימות',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[500])),
                );
              }
              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (ctx, i) =>
                    _buildIdVerificationCard(ctx, docs[i]),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Expert Application Card ─────────────────────────────────────────────
  Widget _buildExpertApplicationCard(
      BuildContext context, DocumentSnapshot doc) {
    final data    = doc.data() as Map<String, dynamic>;
    final uid     = doc.id;
    final name    = data['name']  as String? ?? 'ללא שם';
    final email   = data['email'] as String? ?? '';
    final photo   = data['profileImage'] as String?;
    final appData = data['expertApplicationData'] as Map<String, dynamic>? ?? {};
    // Fall back to top-level fields for providers who bypassed the pending flow
    final category   = (appData['category']    as String? ?? data['serviceType']   as String? ?? '').trim();
    final subCat     = (appData['subCategory']  as String? ?? appData['subcategory'] as String? ?? data['subCategory'] as String? ?? '').trim();
    final aboutMe    = (appData['aboutMe']      as String? ?? appData['bio_description'] as String? ?? data['aboutMe'] as String? ?? '').trim();
    final taxId      = (appData['taxId']        as String? ?? '').trim();
    final price      = (appData['pricePerHour'] as num?    ?? data['pricePerHour']  as num?    ?? 0).toDouble();
    // v3 wizard extra fields (empty for legacy applications)
    final city             = (appData['city']                as String? ?? data['city']       as String? ?? '').trim();
    final country          = (appData['country']             as String? ?? data['country']    as String? ?? '').trim();
    final street           = (appData['street_address']      as String? ?? '').trim();
    final businessType     = (appData['business_type']       as String? ?? data['businessType'] as String? ?? '').trim();
    final businessDocUrl   = (appData['business_document_url'] as String? ?? data['businessDocUrl'] as String? ?? '').trim();
    final idDocUrl         = (appData['id_document_url']     as String? ?? '').trim();
    final bankName         = (appData['bank_name']           as String? ?? '').trim();
    final bankNumber       = (appData['bank_number']         as String? ?? '').trim();
    final branchNumber     = (appData['branch_number']       as String? ?? '').trim();
    final accountNumber    = (appData['account_number']      as String? ?? '').trim();
    final phone      = ((data['phone'] as String?) ?? (data['phoneNumber'] as String?) ?? '').trim();
    final isPending  = data['isPendingExpert'] as bool? ?? false;

    return Card(
      elevation: 2,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // ── User info row ─────────────────────────────────────────────
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.purple.shade50,
                  backgroundImage: (photo != null && photo.isNotEmpty)
                      ? NetworkImage(photo)
                      : null,
                  child: (photo == null || photo.isEmpty)
                      ? Text(
                          name.isNotEmpty ? name[0] : '?',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.purple),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(name,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      if (email.isNotEmpty)
                        Text(email,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600])),
                      if (phone.isNotEmpty)
                        GestureDetector(
                          onTap: () => launchUrl(Uri.parse('tel:$phone')),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.phone_rounded,
                                  size: 11, color: Colors.green),
                              const SizedBox(width: 3),
                              Text(phone,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.green,
                                      decoration: TextDecoration.underline,
                                      decorationColor: Colors.green)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isPending
                        ? Colors.purple.shade50
                        : Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: isPending
                            ? Colors.purple.shade200
                            : Colors.amber.shade400),
                  ),
                  child: Text(
                    isPending ? 'ממתין לאישור' : 'ספק לא מאושר',
                    style: TextStyle(
                        fontSize: 11,
                        color: isPending ? Colors.purple : Colors.amber[800],
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),

            // ── Service details ───────────────────────────────────────────
            if (category.isNotEmpty || subCat.isNotEmpty || price > 0) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                children: [
                  if (category.isNotEmpty)
                    _applicationChip(
                      subCat.isEmpty ? category : '$category › $subCat',
                      Icons.category_rounded,
                      Colors.indigo,
                    ),
                  if (price > 0)
                    _applicationChip(
                      '₪${price.toStringAsFixed(0)} / יחידה',
                      Icons.attach_money_rounded,
                      Colors.green,
                    ),
                  if (taxId.isNotEmpty)
                    _applicationChip(taxId, Icons.badge_outlined, Colors.grey),
                ],
              ),
            ],
            if (aboutMe.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Text(aboutMe,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 12.5, height: 1.5)),
              ),
            ],

            // ── v3 wizard: location + business + bank ────────────────────
            if (city.isNotEmpty || country.isNotEmpty || street.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                children: [
                  if (country.isNotEmpty)
                    _applicationChip(country, Icons.public_rounded, Colors.blueGrey),
                  if (city.isNotEmpty)
                    _applicationChip(city, Icons.location_city_rounded, Colors.teal),
                  if (street.isNotEmpty)
                    _applicationChip(street, Icons.home_outlined, Colors.brown),
                ],
              ),
            ],
            if (businessType.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                children: [
                  _applicationChip(
                      businessType, Icons.business_center_rounded, Colors.deepPurple),
                ],
              ),
            ],
            if (idDocUrl.isNotEmpty || businessDocUrl.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (idDocUrl.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () => launchUrl(Uri.parse(idDocUrl),
                          mode: LaunchMode.externalApplication),
                      icon: const Icon(Icons.badge_outlined, size: 14),
                      label: const Text('צפה בתעודת זהות',
                          style: TextStyle(fontSize: 11)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  if (idDocUrl.isNotEmpty && businessDocUrl.isNotEmpty)
                    const SizedBox(width: 6),
                  if (businessDocUrl.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () => launchUrl(Uri.parse(businessDocUrl),
                          mode: LaunchMode.externalApplication),
                      icon: const Icon(Icons.description_outlined, size: 14),
                      label: const Text('אישור עוסק',
                          style: TextStyle(fontSize: 11)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                ],
              ),
            ],
            if (bankName.isNotEmpty) ...[
              const SizedBox(height: 8),
              _BankDetailsPanel(
                bankName: bankName,
                bankNumber: bankNumber,
                branchNumber: branchNumber,
                accountNumber: accountNumber,
              ),
            ],

            const SizedBox(height: 12),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: _verifyingUids.contains(uid)
                      ? null
                      : () => _rejectExpertApplication(
                          context, uid, name),
                  icon: const Icon(Icons.close_rounded,
                      size: 16, color: Colors.red),
                  label:
                      const Text('דחה', style: TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: _verifyingUids.contains(uid)
                      ? null
                      : () => _approveExpertApplication(
                          context, uid, name, email, category),
                  icon: _verifyingUids.contains(uid)
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.verified_rounded,
                          size: 16, color: Colors.white),
                  label: const Text('אשר כספק מומחה',
                      style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── ID Verification Card ──────────────────────────────────────────────────
  Widget _buildIdVerificationCard(
      BuildContext context, DocumentSnapshot doc) {
    final data  = doc.data() as Map<String, dynamic>;
    final uid   = doc.id;
    final name  = data['name']  as String? ?? 'ללא שם';
    final email = data['email'] as String? ?? '';
    // `idVerificationUrl` stayed on the main doc (legacy field, not part of PR 1).
    final idUrl = data['idVerificationUrl'] as String?;

    return Card(
      elevation: 2,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // User info row
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: Colors.indigo.shade50,
                  child: Text(
                    name.isNotEmpty ? name[0] : '?',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(name,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      Text(email,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[600])),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: const Text('ממתין',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.amber,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),

            // ── ID + Selfie side-by-side comparison ──────────────────────
            // PR 1: URLs now live in users/{uid}/private/kyc. Legacy users
            // still have them on the main doc — PrivateDataService.getKycData
            // handles the fallback transparently.
            const SizedBox(height: 12),
            FutureBuilder<Map<String, dynamic>>(
              future: PrivateDataService.getKycData(uid),
              builder: (context, snap) {
                final kyc = snap.data ?? const {};
                final selfieUrl    = kyc['selfieVerificationUrl'] as String?;
                final idDocUrl     = kyc['idDocUrl'] as String?;
                final effectiveIdUrl = idUrl ?? idDocUrl;
                return Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Text('סלפי חי', style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w600,
                              color: Colors.grey[700])),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: selfieUrl != null
                                ? CachedNetworkImage(
                                    imageUrl: selfieUrl,
                                    height: 120, width: double.infinity,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => _verificationPlaceholder('אין סלפי'),
                                  )
                                : _verificationPlaceholder('אין סלפי'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        children: [
                          Text('תעודה מזהה', style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w600,
                              color: Colors.grey[700])),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: effectiveIdUrl != null
                                ? CachedNetworkImage(
                                    imageUrl: effectiveIdUrl,
                                    height: 120, width: double.infinity,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) => _verificationPlaceholder('אין מסמך'),
                                  )
                                : _verificationPlaceholder('אין מסמך'),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 12),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: _verifyingUids.contains(uid)
                      ? null
                      : () => _rejectVerification(
                          context, uid, name, email),
                  icon: const Icon(Icons.close_rounded,
                      size: 16, color: Colors.red),
                  label:
                      const Text('דחה', style: TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: _verifyingUids.contains(uid)
                      ? null
                      : () => _approveVerification(
                          context, uid, name, email),
                  icon: _verifyingUids.contains(uid)
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_rounded,
                          size: 16, color: Colors.white),
                  label: const Text('אמת',
                      style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Helper widgets ────────────────────────────────────────────────────────

  static Widget _verificationPlaceholder(String label) {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_not_supported_outlined,
                color: Colors.grey.shade400, size: 28),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(
                fontSize: 11, color: Colors.grey.shade500)),
          ],
        ),
      ),
    );
  }

  static Widget _applicationChip(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ── Approve / Reject actions ──────────────────────────────────────────────

  Future<void> _approveVerification(
      BuildContext context, String uid, String name, String email) async {
    if (_verifyingUids.contains(uid)) return;
    setState(() => _verifyingUids.add(uid));
    try {
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('approveUserVerification',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 30)))
          .call({'uid': uid, 'action': 'approve', 'email': email, 'name': name});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$name אומת/ה בהצלחה -- אימייל נשלח'),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('שגיאה באישור: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } finally {
      if (mounted) setState(() => _verifyingUids.remove(uid));
    }
  }

  Future<void> _rejectVerification(
      BuildContext context, String uid, String name, String email) async {
    if (_verifyingUids.contains(uid)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('אישור דחייה'),
        content: Text('לדחות את הבקשה של $name?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ביטול')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('דחה', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    setState(() => _verifyingUids.add(uid));
    try {
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('approveUserVerification',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 30)))
          .call({'uid': uid, 'action': 'reject', 'email': email, 'name': name});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$name נדחה/ה -- אימייל נשלח'),
          backgroundColor: Colors.orange.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('שגיאה בדחייה: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } finally {
      if (mounted) setState(() => _verifyingUids.remove(uid));
    }
  }

  Future<void> _approveExpertApplication(BuildContext context, String uid,
      String name, String email, String category) async {
    if (_verifyingUids.contains(uid)) return;
    setState(() => _verifyingUids.add(uid));
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'us-central1');
      await fn.httpsCallable('adminApproveProvider').call({
        'uid':      uid,
        'name':     name,
        'category': category,
      });

      // Mark as approved locally
      if (mounted) setState(() => _approvedUids.add(uid));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$name אושר/ה כספק מומחה -- התראה נשלחה'),
          backgroundColor: Colors.purple.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('שגיאה באישור: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } finally {
      if (mounted) setState(() => _verifyingUids.remove(uid));
    }
  }

  Future<void> _rejectExpertApplication(
      BuildContext context, String uid, String name) async {
    if (_verifyingUids.contains(uid)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('אישור דחייה'),
        content: Text('לדחות את הבקשה של $name?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ביטול')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('דחה', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    setState(() => _verifyingUids.add(uid));
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'isPendingExpert':    false,
        'expertApplicationData': FieldValue.delete(),
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$name -- הבקשה נדחתה'),
          backgroundColor: Colors.orange.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('שגיאה בדחייה: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } finally {
      if (mounted) setState(() => _verifyingUids.remove(uid));
    }
  }
}

// ── Collapsible bank details panel (admin-only, provider registration v3) ──
class _BankDetailsPanel extends StatefulWidget {
  final String bankName;
  final String bankNumber;
  final String branchNumber;
  final String accountNumber;
  const _BankDetailsPanel({
    required this.bankName,
    required this.bankNumber,
    required this.branchNumber,
    required this.accountNumber,
  });

  @override
  State<_BankDetailsPanel> createState() => _BankDetailsPanelState();
}

class _BankDetailsPanelState extends State<_BankDetailsPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.indigo.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_rounded,
                  size: 16, color: Colors.indigo),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _expanded
                      ? '${widget.bankName} · סניף ${widget.branchNumber} · חשבון ${widget.accountNumber}'
                      : '${widget.bankName} (${widget.bankNumber}) · לחץ להצגת פרטי חשבון',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 11.5, color: Colors.indigo),
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(_expanded ? 'הסתר' : 'הצג',
                    style: const TextStyle(fontSize: 11, color: Colors.indigo)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
