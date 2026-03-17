import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../widgets/banner_carousel.dart';
import 'withdrawal_modal.dart';
import '../l10n/app_localizations.dart';

class FinanceScreen extends StatelessWidget {
  const FinanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final String uid = FirebaseAuth.instance.currentUser?.uid ?? "";

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).financeTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

          final l10n = AppLocalizations.of(context);
          var userData = snapshot.data?.data() as Map<String, dynamic>? ?? {};
          double balance = (userData['balance'] ?? 0.0).toDouble();

          return Column(
            children: [
              const SizedBox(height: 20),
              _buildBalanceCard(context, uid, balance),
              // ── Promotional banners ── below balance card, before history ──
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: BannerCarousel(),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(15, 0, 15, 10),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(l10n.financeRecentActivity, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
              Expanded(child: _buildTransactionList(uid)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBalanceCard(BuildContext context, String uid, double balance) {
    final l10n = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 15),
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E3A5F), Color(0xFF2D6A9F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E3A5F).withValues(alpha: 0.40),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // ── Header row ──────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.shield_rounded, size: 13, color: Colors.white70),
                    const SizedBox(width: 5),
                    Text(
                      l10n.financeTrustBadge,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.75),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ]),
                ),
                const Icon(Icons.account_balance_wallet_rounded,
                    color: Colors.white38, size: 22),
              ],
            ),
            const SizedBox(height: 20),

            // ── Balance ──────────────────────────────────────────────────
            Text(
              l10n.financeAvailableBalance,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '₪${balance.toStringAsFixed(2)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 44,
                fontWeight: FontWeight.bold,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.financeMinWithdraw,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 22),

            // ── Withdraw button ──────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF1E3A5F),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.savings_rounded, size: 18),
                label: Text(
                  l10n.financeWithdrawButton,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                onPressed: () => showWithdrawalModal(context, uid, balance),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionList(String uid) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('transactions')
          .where(Filter.or(Filter('senderId', isEqualTo: uid), Filter('receiverId', isEqualTo: uid)))
          .snapshots(), 
      builder: (context, snapshot) {
        final l10n = AppLocalizations.of(context);
        if (snapshot.hasError) return Center(child: Text(l10n.financeError(snapshot.error.toString())));
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

        var docs = snapshot.data!.docs;

        if (docs.isEmpty) {
          return Center(child: Text(l10n.financeNoTransactions, style: const TextStyle(color: Colors.grey)));
        }

        // מיון ידני
        docs.sort((a, b) {
          var dateA = (a.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
          var dateB = (b.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
          if (dateA == null || dateB == null) return 0;
          return dateB.compareTo(dateA);
        });

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            var tx = docs[index].data() as Map<String, dynamic>;
            bool isSender = tx['senderId'] == uid;
            DateTime? date = (tx['timestamp'] as Timestamp?)?.toDate();

            return Card(
              elevation: 0,
              margin: const EdgeInsets.symmetric(vertical: 5),
              // כאן היה התיקון: השתמשתי ב-BorderSide במקום ב-Border.all
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15), 
                side: BorderSide(color: Colors.grey[200]!)
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: isSender ? Colors.red[50] : Colors.green[50],
                  child: Icon(isSender ? Icons.arrow_upward : Icons.arrow_downward, color: isSender ? Colors.red : Colors.green, size: 20),
                ),
                title: Text(
                  isSender ? l10n.financePaidTo(tx['receiverName'] ?? '') : l10n.financeReceivedFrom(tx['senderName'] ?? ''),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(date != null ? DateFormat('dd/MM/yyyy HH:mm').format(date) : l10n.financeProcessing),
                trailing: Text(
                  "${isSender ? '-' : '+'} ₪${tx['amount']}",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isSender ? Colors.red : Colors.green,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}