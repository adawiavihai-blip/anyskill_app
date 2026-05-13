// Flash Auction — Step 1 of 4: "מה קרה?" (issue diagnosis).
//
// Customer picks ONE of the 6 issue buckets (engine fault / accident /
// flat tire / dead battery / wheels locked / other). The selected id is
// passed to FlashAuctionLocationScreen which carries it forward to
// auction creation.
//
// Layout matches mockup §1 (docs/ui-specs/Motorcycle/Motorcycle 2/
// customer-flow.html lines 150-180): urgency banner up top, 6-issue grid,
// safety strip near the bottom that opens FlashAuctionSafetyDialog,
// "המשך" CTA at the bottom that's only enabled once an issue is picked.
import 'package:flutter/material.dart';

import '../../constants/flash_auction_constants.dart';
import 'flash_auction_location_screen.dart';
import 'flash_auction_palette.dart';
import 'flash_auction_safety_dialog.dart';

class FlashAuctionIssueScreen extends StatefulWidget {
  const FlashAuctionIssueScreen({super.key});

  @override
  State<FlashAuctionIssueScreen> createState() =>
      _FlashAuctionIssueScreenState();
}

class _FlashAuctionIssueScreenState extends State<FlashAuctionIssueScreen> {
  String? _selectedIssueId;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: FlashPalette.bgPrimary,
        appBar: AppBar(
          backgroundColor: FlashPalette.bgPrimary,
          surfaceTintColor: FlashPalette.bgPrimary,
          elevation: 0.5,
          centerTitle: false,
          iconTheme: const IconThemeData(color: FlashPalette.textPrimary),
          title: const Text(
            'מצא גרר דחוף',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: FlashPalette.textPrimary,
            ),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _UrgencyBanner(),
                      const SizedBox(height: 18),
                      const Text(
                        'מה קרה לאופנוע?',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: FlashPalette.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'בחר את התקלה — זה יעזור לגרריסט להגיע מוכן',
                        style: TextStyle(
                          fontSize: 13,
                          color: FlashPalette.textSecondary,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _IssueGrid(
                        selectedId: _selectedIssueId,
                        onPick: (id) =>
                            setState(() => _selectedIssueId = id),
                      ),
                      const SizedBox(height: 18),
                      const _SafetyStrip(),
                    ],
                  ),
                ),
              ),
              _CtaBar(
                enabled: _selectedIssueId != null,
                onContinue: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FlashAuctionLocationScreen(
                        issueType: _selectedIssueId!,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SUB-WIDGETS
// ═══════════════════════════════════════════════════════════════════════

class _UrgencyBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: FlashPalette.red50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: FlashPalette.red500.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: FlashPalette.red500,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'מצב חירום פעיל',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: FlashPalette.red700,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'המערכת תשלח התראה לכל הגרריסטים ברדיוס',
                  style: TextStyle(
                    fontSize: 12,
                    color: FlashPalette.red700,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IssueGrid extends StatelessWidget {
  final String? selectedId;
  final ValueChanged<String> onPick;

  const _IssueGrid({required this.selectedId, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: FlashAuctionIssueType.all.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.95,
      ),
      itemBuilder: (_, i) {
        final id = FlashAuctionIssueType.all[i];
        final selected = selectedId == id;
        return _IssueTile(
          id: id,
          selected: selected,
          onTap: () => onPick(id),
        );
      },
    );
  }
}

class _IssueTile extends StatelessWidget {
  final String id;
  final bool selected;
  final VoidCallback onTap;
  const _IssueTile({
    required this.id,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label = FlashAuctionIssueType.labelOf(id);
    final icon = FlashAuctionIssueType.iconOf(id);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? FlashPalette.purple50 : FlashPalette.bgPrimary,
          border: Border.all(
            color: selected
                ? FlashPalette.purple500
                : FlashPalette.borderTertiary,
            width: selected ? 1.5 : 0.5,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color:
                        FlashPalette.purple500.withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 28,
              color:
                  selected ? FlashPalette.purple700 : FlashPalette.purple500,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected
                    ? FlashPalette.purple700
                    : FlashPalette.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SafetyStrip extends StatelessWidget {
  const _SafetyStrip();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: FlashPalette.amber50,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => showFlashAuctionSafetyDialog(context),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const Icon(
                Icons.health_and_safety_rounded,
                size: 20,
                color: FlashPalette.amber600,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'אתה במקום בטוח?',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: FlashPalette.amber800,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'אם לא — לחץ לקבלת הנחיות בטיחות',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: FlashPalette.amber800,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_back_ios_rounded,
                size: 13,
                color: FlashPalette.amber600,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CtaBar extends StatelessWidget {
  final bool enabled;
  final VoidCallback onContinue;

  const _CtaBar({required this.enabled, required this.onContinue});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: FlashPalette.bgPrimary,
        border: Border(
          top: BorderSide(color: FlashPalette.borderTertiary, width: 0.5),
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton(
          onPressed: enabled ? onContinue : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: FlashPalette.purple500,
            disabledBackgroundColor:
                FlashPalette.borderSecondary.withValues(alpha: 0.55),
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Text(
                'המשך',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(width: 6),
              Icon(Icons.arrow_back_rounded, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
