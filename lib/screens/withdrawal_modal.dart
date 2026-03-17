// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../l10n/app_localizations.dart';

// ─── Israeli banks list ───────────────────────────────────────────────────────
const _kBanks = [
  'בנק הפועלים (12)',
  'בנק לאומי (10)',
  'בנק דיסקונט (11)',
  'בנק מזרחי-טפחות (20)',
  'בנק אוצר החייל (14)',
  'הבנק הבינלאומי (31)',
  'בנק הדואר (09)',
  'בנק ירושלים (54)',
  'אחר',
];

const double _kMinWithdraw = 50.0;

// ─── Entry point ──────────────────────────────────────────────────────────────

void showWithdrawalModal(
    BuildContext context, String uid, double balance) {
  if (balance < _kMinWithdraw) {
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(l10n.withdrawMinBalance(_kMinWithdraw.toInt())),
      backgroundColor: Colors.orange[800],
    ));
    return;
  }
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => WithdrawalModal(uid: uid, balance: balance),
  );
}

// ─── Modal widget ─────────────────────────────────────────────────────────────

class WithdrawalModal extends StatefulWidget {
  final String uid;
  final double balance;

  const WithdrawalModal({
    super.key,
    required this.uid,
    required this.balance,
  });

  @override
  State<WithdrawalModal> createState() => _WithdrawalModalState();
}

class _WithdrawalModalState extends State<WithdrawalModal> {
  // ── Step: 0 = tax choice, 1 = form, 2 = success ──────────────────────────
  int     _step      = 0;
  String? _taxStatus; // 'business' | 'individual'

  // ── Form ─────────────────────────────────────────────────────────────────
  final _formKey     = GlobalKey<FormState>();
  String? _bankName;
  final _branchCtrl  = TextEditingController();
  final _accountCtrl = TextEditingController();

  // ── Tax certificate ───────────────────────────────────────────────────────
  String? _certUrl;
  String? _certName;
  bool    _uploadingCert = false;

  // ── Tax declaration consent ───────────────────────────────────────────────
  bool    _taxDeclarationOk = false;

  // ── Misc ──────────────────────────────────────────────────────────────────
  bool    _submitting = false;
  String? _errorText;
  String  _userName  = '';

  @override
  void initState() {
    super.initState();
    _prefillExisting();
  }

  @override
  void dispose() {
    _branchCtrl.dispose();
    _accountCtrl.dispose();
    super.dispose();
  }

  Future<void> _prefillExisting() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .get();
      final d = doc.data() ?? {};
      if (!mounted) return;
      setState(() {
        _userName   = d['name'] as String? ?? '';
        _taxStatus  = d['taxStatus'] as String?;
        _certUrl    = d['taxCertificateUrl'] as String?;
        if (_certUrl != null) _certName = AppLocalizations.of(context).withdrawExistingCert;
        final bank  = d['bankDetails'] as Map<String, dynamic>?;
        if (bank != null) {
          _bankName             = bank['bankName'] as String?;
          _branchCtrl.text      = bank['branch']        as String? ?? '';
          _accountCtrl.text     = bank['accountNumber'] as String? ?? '';
        }
        // If we already have a taxStatus, pre-select it
        if (_taxStatus != null) _step = 1;
      });
    } catch (_) {}
  }

  // ── Tax certificate upload ────────────────────────────────────────────────

  Future<void> _pickAndUploadCert() async {
    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(
      source:     ImageSource.gallery,
      imageQuality: 85,
    );
    if (file == null || !mounted) return;

    setState(() {
      _uploadingCert = true;
      _errorText     = null;
    });
    try {
      final bytes = await file.readAsBytes();
      final ext   = file.name.contains('.')
          ? file.name.split('.').last.toLowerCase()
          : 'jpg';
      final ref = FirebaseStorage.instance
          .ref()
          .child('tax_certificates/${widget.uid}/cert.$ext');
      final task = await ref.putData(
        bytes,
        SettableMetadata(contentType: 'image/$ext'),
      );
      final url = await task.ref.getDownloadURL();
      if (mounted) {
        setState(() {
          _certUrl  = url;
          _certName = file.name;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _errorText = AppLocalizations.of(context).withdrawUploadError);
    } finally {
      if (mounted) setState(() => _uploadingCert = false);
    }
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_bankName == null) {
      setState(() => _errorText = l10n.withdrawSelectBankError);
      return;
    }
    if (_taxStatus == 'business' && _certUrl == null) {
      setState(() => _errorText = l10n.withdrawNoCertError);
      return;
    }
    if (!_taxDeclarationOk) {
      setState(() => _errorText = l10n.withdrawNoDeclarationError);
      return;
    }

    setState(() {
      _submitting = true;
      _errorText  = null;
    });

    try {
      final db  = FirebaseFirestore.instance;
      final amtStr = widget.balance % 1 == 0
          ? '₪${widget.balance.toInt()}'
          : '₪${widget.balance.toStringAsFixed(2)}';

      final bankDetails = {
        'bankName':      _bankName,
        'branch':        _branchCtrl.text.trim(),
        'accountNumber': _accountCtrl.text.trim(),
      };

      // Write in a single batch
      final batch = db.batch();

      // 1. Save bank details + tax status to user profile
      final userRef = db.collection('users').doc(widget.uid);
      final userUpdate = <String, dynamic>{
        'bankDetails': bankDetails,
        'taxStatus':   _taxStatus,
      };
      if (_certUrl != null) userUpdate['taxCertificateUrl'] = _certUrl;
      batch.update(userRef, userUpdate);

      // 2. Create withdrawal request record
      final reqRef = db.collection('withdrawalRequests').doc();
      batch.set(reqRef, {
        'uid':        widget.uid,
        'userName':   _userName,
        'amount':     widget.balance,
        'taxStatus':  _taxStatus,
        'bankDetails': bankDetails,
        if (_certUrl != null) 'taxCertificateUrl': _certUrl,
        'status':     'pending',
        // ── Legal paper-trail ────────────────────────────────────────────────
        'tax_declaration_confirmed': true,
        'tos_version':               '2.0',
        'declared_at':               FieldValue.serverTimestamp(),
        'createdAt':  FieldValue.serverTimestamp(),
      });

      // 3. Append to transaction history
      final txRef = db.collection('transactions').doc();
      batch.set(txRef, {
        'userId':      widget.uid,      // required by wallet history stream query
        'senderId':    widget.uid,
        'senderName':  _userName,
        'receiverId':  'bank',
        'receiverName': l10n.withdrawBankTransferPending,
        'amount':      widget.balance,
        'amountStr':   amtStr,
        'type':        'withdrawal_pending',
        // ── Legal paper-trail ────────────────────────────────────────────────
        'tax_declaration_confirmed': true,
        'tos_version':               '2.0',
        'declared_at':               FieldValue.serverTimestamp(),
        'timestamp':   FieldValue.serverTimestamp(),
      });

      await batch.commit();

      if (mounted) setState(() => _step = 2);
    } catch (e) {
      if (mounted) {
        setState(() => _errorText = l10n.withdrawSubmitError);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: mq.size.height * 0.90,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Handle ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 2),
              child: Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),

            // ── Content ─────────────────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(
                              begin: const Offset(0.05, 0),
                              end: Offset.zero)
                          .animate(anim),
                      child: child,
                    ),
                  ),
                  child: _buildStep(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _buildTaxChoice();
      case 1:
        return _buildDetailsForm();
      default:
        return _buildSuccess();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Step 0 — Tax status choice
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildTaxChoice() {
    final l10n = AppLocalizations.of(context);
    final amtStr = widget.balance % 1 == 0
        ? '₪${widget.balance.toInt()}'
        : '₪${widget.balance.toStringAsFixed(2)}';

    return Column(
      key: const ValueKey(0),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Security header ────────────────────────────────────────────────
        _SecurityHeader(amount: amtStr, label: l10n.withdrawAvailableBalance),
        const SizedBox(height: 24),

        Text(
          l10n.withdrawTaxStatusTitle,
          textAlign: TextAlign.right,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.withdrawTaxStatusSubtitle,
          textAlign: TextAlign.right,
          style: TextStyle(fontSize: 13, color: Colors.grey[500]),
        ),
        const SizedBox(height: 20),

        // ── Option A — Business ────────────────────────────────────────────
        _TaxOptionCard(
          icon:       Icons.store_rounded,
          iconBg:     const Color(0xFFF0F0FF),
          iconColor:  const Color(0xFF6366F1),
          title:      l10n.withdrawTaxBusiness,
          subtitle:   l10n.withdrawTaxBusinessSub,
          badge:      null,
          onTap: () => setState(() {
            _taxStatus = 'business';
            _step      = 1;
          }),
        ),
        const SizedBox(height: 12),

        // ── Option B — Individual ──────────────────────────────────────────
        _TaxOptionCard(
          icon:       Icons.person_rounded,
          iconBg:     const Color(0xFFF0FFF4),
          iconColor:  const Color(0xFF16A34A),
          title:      l10n.withdrawTaxIndividual,
          subtitle:   l10n.withdrawTaxIndividualSub,
          badge:      l10n.withdrawTaxIndividualBadge,
          onTap: () => setState(() {
            _taxStatus = 'individual';
            _step      = 1;
          }),
        ),
        const SizedBox(height: 16),

        // Encryption notice
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.lock_rounded, size: 12, color: Colors.grey[400]),
          const SizedBox(width: 5),
          Text(l10n.withdrawEncryptedNotice,
              style: TextStyle(fontSize: 11, color: Colors.grey[400])),
        ]),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Step 1 — Bank details form
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildDetailsForm() {
    final l10n = AppLocalizations.of(context);
    final isBusiness = _taxStatus == 'business';

    return Form(
      key: _formKey,
      child: Column(
        key: const ValueKey(1),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Back + title ───────────────────────────────────────────────
          Row(children: [
            GestureDetector(
              onTap: () => setState(() => _step = 0),
              child: const Icon(Icons.arrow_forward_ios_rounded,
                  size: 18, color: Color(0xFF6366F1)),
            ),
            const Spacer(),
            Text(
              isBusiness ? l10n.withdrawBusinessFormTitle : l10n.withdrawIndividualFormTitle,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(width: 4),
            Icon(
              isBusiness
                  ? Icons.store_rounded
                  : Icons.person_rounded,
              size: 18,
              color: isBusiness
                  ? const Color(0xFF6366F1)
                  : const Color(0xFF16A34A),
            ),
          ]),
          const SizedBox(height: 20),

          // ── Individual explanation card ────────────────────────────────
          if (!isBusiness) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FFF4),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: const Color(0xFF22C55E).withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(l10n.withdrawIndividualTitle,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Color(0xFF16A34A))),
                      const SizedBox(width: 6),
                      const Icon(Icons.handshake_rounded,
                          color: Color(0xFF16A34A), size: 16),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.withdrawIndividualDesc,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.green[700],
                        height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],

          // ── Business: certificate upload ───────────────────────────────
          if (isBusiness) ...[
            _SectionLabel(label: l10n.withdrawCertSection),
            const SizedBox(height: 8),
            _CertUploadTile(
              certName:    _certName,
              uploading:   _uploadingCert,
              onTap:       _pickAndUploadCert,
              uploadLabel: l10n.withdrawCertUploadBtn,
              replaceLabel: l10n.withdrawCertReplace,
              hintLabel:   l10n.withdrawCertHint,
            ),
            const SizedBox(height: 18),
          ],

          // ── Bank details ───────────────────────────────────────────────
          _SectionLabel(label: l10n.withdrawBankSection),
          const SizedBox(height: 10),

          // Bank name dropdown
          DropdownButtonFormField<String>(
            value: _kBanks.contains(_bankName) ? _bankName : null,
            isExpanded: true,
            decoration: _inputDeco(label: l10n.withdrawBankName, icon: Icons.account_balance_rounded),
            items: _kBanks
                .map((b) => DropdownMenuItem(value: b, child: Text(b, textAlign: TextAlign.right)))
                .toList(),
            onChanged: (v) => setState(() => _bankName = v),
            validator: (v) => v == null ? l10n.withdrawBankRequired : null,
          ),
          const SizedBox(height: 10),

          // Branch + Account row
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _branchCtrl,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.right,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: _inputDeco(label: l10n.withdrawBankBranch, icon: Icons.pin_rounded),
                validator: (v) =>
                    (v == null || v.isEmpty) ? l10n.withdrawBranchRequired : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: _accountCtrl,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.right,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: _inputDeco(label: l10n.withdrawBankAccount, icon: Icons.numbers_rounded),
                validator: (v) =>
                    (v == null || v.length < 4) ? l10n.withdrawAccountMinDigits : null,
              ),
            ),
          ]),
          const SizedBox(height: 20),

          // ── Error message ──────────────────────────────────────────────
          if (_errorText != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(children: [
                const Icon(Icons.error_outline_rounded,
                    color: Colors.red, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_errorText!,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          color: Colors.red, fontSize: 12)),
                ),
              ]),
            ),
            const SizedBox(height: 14),
          ],

          // ── Tax declaration checkbox ───────────────────────────────────
          GestureDetector(
            onTap: () => setState(() {
              _taxDeclarationOk = !_taxDeclarationOk;
              _errorText = null;
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: _taxDeclarationOk
                    ? const Color(0xFFF0FFF4)
                    : const Color(0xFFFAFAFA),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _taxDeclarationOk
                      ? const Color(0xFF22C55E)
                      : Colors.grey.shade200,
                  width: 1.2,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: RichText(
                      textAlign: TextAlign.right,
                      text: TextSpan(
                        style: TextStyle(
                            fontSize: 12,
                            height: 1.55,
                            color: Colors.grey[700]),
                        children: [
                          TextSpan(
                            text: l10n.withdrawDeclarationText,
                          ),
                          TextSpan(
                            text: l10n.withdrawDeclarationSection,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0EA5E9),
                            ),
                          ),
                          TextSpan(
                            text: l10n.withdrawDeclarationSuffix,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: _taxDeclarationOk
                          ? const Color(0xFF22C55E)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _taxDeclarationOk
                            ? const Color(0xFF22C55E)
                            : Colors.grey.shade400,
                        width: 1.5,
                      ),
                    ),
                    child: _taxDeclarationOk
                        ? const Icon(Icons.check_rounded,
                            color: Colors.white, size: 14)
                        : null,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // ── Submit button ──────────────────────────────────────────────
          AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: _taxDeclarationOk ? 1.0 : 0.45,
            child: SizedBox(
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: (_submitting || !_taxDeclarationOk) ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.send_rounded,
                          color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        l10n.withdrawSubmitButton(widget.balance % 1 == 0 ? '₪${widget.balance.toInt()}' : '₪${widget.balance.toStringAsFixed(2)}'),
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14),
                      ),
                    ]),
            ),
          ),   // SizedBox
          ), // AnimatedOpacity
          const SizedBox(height: 12),

          // Encryption notice
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.lock_rounded, size: 12, color: Colors.grey[400]),
            const SizedBox(width: 5),
            Text(l10n.withdrawBankEncryptedNotice,
                style: TextStyle(fontSize: 11, color: Colors.grey[400])),
          ]),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Step 2 — Success
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildSuccess() {
    final l10n = AppLocalizations.of(context);
    final amtStr = widget.balance % 1 == 0
        ? '₪${widget.balance.toInt()}'
        : '₪${widget.balance.toStringAsFixed(2)}';

    return Column(
      key: const ValueKey(2),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),

        // ── Success icon ────────────────────────────────────────────────
        Center(
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFF22C55E).withValues(alpha: 0.35),
                    blurRadius: 20,
                    offset: const Offset(0, 8)),
              ],
            ),
            child: const Icon(Icons.check_rounded,
                color: Colors.white, size: 40),
          ),
        ),
        const SizedBox(height: 18),

        Text(l10n.withdrawSuccessTitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(
          l10n.withdrawSuccessSubtitle(amtStr),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
        ),
        const SizedBox(height: 28),

        // ── Timeline ────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFF),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade100),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _TimelineRow(
                icon:   Icons.mark_email_read_rounded,
                color:  const Color(0xFF6366F1),
                title:  l10n.withdrawTimeline1Title,
                sub:    l10n.withdrawTimeline1Sub,
                done:   true,
                isLast: false,
              ),
              _TimelineRow(
                icon:   Icons.manage_search_rounded,
                color:  const Color(0xFFF59E0B),
                title:  l10n.withdrawTimeline2Title,
                sub:    l10n.withdrawTimeline2Sub,
                done:   false,
                isLast: false,
              ),
              _TimelineRow(
                icon:   Icons.account_balance_rounded,
                color:  const Color(0xFF22C55E),
                title:  l10n.withdrawTimeline3Title,
                sub:    l10n.withdrawTimeline3Sub,
                done:   false,
                isLast: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ── Notice ──────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.amber[50],
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: Colors.amber.withValues(alpha: 0.40)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded,
                  color: Colors.amber[800], size: 15),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.withdrawSuccessNotice,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.amber[900],
                      height: 1.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // ── Close button ────────────────────────────────────────────────
        SizedBox(
          height: 52,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context).close,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15)),
          ),
        ),
      ],
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  InputDecoration _inputDeco(
      {required String label, required IconData icon}) {
    return InputDecoration(
      labelText: label,
      alignLabelWithHint: true,
      suffixIcon: Icon(icon, size: 18, color: Colors.grey[400]),
      filled: true,
      fillColor: const Color(0xFFF5F6FA),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade200)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF6366F1))),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.red)),
      focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.red)),
    );
  }
}

// ─── Security header ──────────────────────────────────────────────────────────

class _SecurityHeader extends StatelessWidget {
  final String amount;
  final String label;
  const _SecurityHeader({required this.amount, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E1B4B), Color(0xFF312E81)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                amount,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5),
              ),
              Text(
                label,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12),
              ),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.shield_rounded,
                color: Colors.white, size: 28),
          ),
        ],
      ),
    );
  }
}

// ─── Tax option card ──────────────────────────────────────────────────────────

class _TaxOptionCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String? badge;
  final VoidCallback onTap;

  const _TaxOptionCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.grey.shade100),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.arrow_back_ios_rounded,
                size: 14, color: Colors.grey),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (badge != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green[50],
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: Colors.green.withValues(alpha: 0.4)),
                        ),
                        child: Text(badge!,
                            style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFF16A34A),
                                fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(subtitle,
                    style: TextStyle(
                        color: Colors.grey[500], fontSize: 12)),
              ],
            ),
            const SizedBox(width: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: iconBg, shape: BoxShape.circle),
              child: Icon(icon, color: iconColor, size: 22),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Section label ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Color(0xFF1A1A2E))),
        const SizedBox(width: 6),
        Container(
          width: 4,
          height: 4,
          decoration: const BoxDecoration(
            color: Color(0xFF6366F1),
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }
}

// ─── Certificate upload tile ──────────────────────────────────────────────────

class _CertUploadTile extends StatelessWidget {
  final String? certName;
  final bool uploading;
  final VoidCallback onTap;
  final String uploadLabel;
  final String replaceLabel;
  final String hintLabel;

  const _CertUploadTile({
    required this.certName,
    required this.uploading,
    required this.onTap,
    required this.uploadLabel,
    required this.replaceLabel,
    required this.hintLabel,
  });

  @override
  Widget build(BuildContext context) {
    final uploaded = certName != null;

    return GestureDetector(
      onTap: uploading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: uploaded
              ? const Color(0xFFF0FFF4)
              : const Color(0xFFF5F6FA),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: uploaded
                ? const Color(0xFF22C55E).withValues(alpha: 0.5)
                : Colors.grey.shade200,
          ),
        ),
        child: Row(
          children: [
            if (uploading)
              const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
            else
              Icon(
                uploaded
                    ? Icons.check_circle_rounded
                    : Icons.upload_file_rounded,
                color: uploaded
                    ? const Color(0xFF16A34A)
                    : const Color(0xFF6366F1),
                size: 22,
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    uploaded ? certName! : uploadLabel,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: uploaded
                          ? const Color(0xFF16A34A)
                          : const Color(0xFF1A1A2E),
                    ),
                  ),
                  Text(
                    uploaded ? replaceLabel : hintLabel,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Timeline row ─────────────────────────────────────────────────────────────

class _TimelineRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String sub;
  final bool done;
  final bool isLast;

  const _TimelineRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.sub,
    required this.done,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Spacer on left (RTL: right-side content)
        const Spacer(),

        // Text block
        Flexible(
          flex: 5,
          child: Padding(
            padding: const EdgeInsets.only(right: 12, bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: done
                            ? const Color(0xFF1A1A2E)
                            : Colors.grey[500])),
                const SizedBox(height: 2),
                Text(sub,
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey[400])),
              ],
            ),
          ),
        ),

        // Icon + line
        Column(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: done
                    ? color.withValues(alpha: 0.12)
                    : Colors.grey[100],
                shape: BoxShape.circle,
                border: Border.all(
                  color: done ? color : Colors.grey.shade300,
                  width: done ? 2 : 1,
                ),
              ),
              child: Icon(icon,
                  size: 16,
                  color: done ? color : Colors.grey[400]),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 20,
                color: Colors.grey[200],
              ),
          ],
        ),
      ],
    );
  }
}
