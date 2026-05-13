# 🛠️ צד הספק - קוד מלא ומפורט
## TrainerSettingsBlock + כל ה-Widgets

> **קובץ זה משלים את** `01_MAIN_PROMPT.md`  
> **מטרה:** קוד Flutter מוכן לשימוש לכל widget בצד הספק

---

## 📐 Master Container

### `trainer_settings_block.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'widgets/ai_coach_score_card.dart';
import 'widgets/specialties_section.dart';
import 'widgets/pricing_packages_section.dart';
import 'widgets/training_locations_section.dart';
import 'widgets/certifications_section.dart';
import 'widgets/success_stories_section.dart';
import 'widgets/special_offers_section.dart';
import 'widgets/performance_dashboard.dart';
import 'widgets/ai_suggestions_card.dart';

class TrainerSettingsBlock extends StatefulWidget {
  final String providerId;
  final String subcategory;
  final VoidCallback? onSaved;
  
  const TrainerSettingsBlock({
    Key? key,
    required this.providerId,
    required this.subcategory,
    this.onSaved,
  }) : super(key: key);
  
  @override
  State<TrainerSettingsBlock> createState() => _TrainerSettingsBlockState();
}

class _TrainerSettingsBlockState extends State<TrainerSettingsBlock>
    with SingleTickerProviderStateMixin {
  
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  
  bool _isLoading = false;
  bool _hasUnsavedChanges = false;
  
  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(_fadeAnimation);
    
    _animationController.forward();
  }
  
  @override
  Widget build(BuildContext context) {
    // הסתר אם זה לא תת-קטגוריה של מאמני כושר
    if (widget.subcategory != 'מאמני כושר' && 
        widget.subcategory != 'fitness_trainer') {
      return const SizedBox.shrink();
    }
    
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.black.withOpacity(0.06),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Column(
                children: [
                  _buildHeader(),
                  const SizedBox(height: 16),
                  
                  // 1. AI Coach Score
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: AICoachScoreCard(
                      providerId: widget.providerId,
                      onActionTap: _scrollToSuggestions,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // 2. Specialties
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SpecialtiesSection(
                      providerId: widget.providerId,
                      onChanged: _markUnsavedChanges,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // 3. Pricing Packages
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: PricingPackagesSection(
                      providerId: widget.providerId,
                      onChanged: _markUnsavedChanges,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // 4. Training Locations
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TrainingLocationsSection(
                      providerId: widget.providerId,
                      onChanged: _markUnsavedChanges,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // 5. Certifications
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: CertificationsSection(
                      providerId: widget.providerId,
                      onChanged: _markUnsavedChanges,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // 6. Success Stories
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SuccessStoriesSection(
                      providerId: widget.providerId,
                      onChanged: _markUnsavedChanges,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // 7. Special Offers
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SpecialOffersSection(
                      providerId: widget.providerId,
                      onChanged: _markUnsavedChanges,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // 8. Performance Dashboard
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: PerformanceDashboard(
                      providerId: widget.providerId,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // 9. AI Suggestions
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: AISuggestionsCard(
                      providerId: widget.providerId,
                      onApplyAll: _applyAllSuggestions,
                    ),
                  ),
                  
                  // Footer
                  _buildFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFFF8F3),
            Color(0xFFFFFFFF),
          ],
        ),
        border: Border(
          top: BorderSide(
            color: const Color(0xFFFF6B35),
            width: 2,
          ),
        ),
      ),
      child: Stack(
        children: [
          // "Auto-opened" badge
          Positioned(
            top: -16,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: const BoxDecoration(
                color: Color(0xFFFF6B35),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
              ),
              child: const Text(
                '⚡ נפתח אוטומטית',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 24,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF6B35), Color(0xFFF59E0B)],
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'הגדרות מאמן כושר',
                        style: TextStyle(
                          color: Color(0xFF1F2937),
                          fontSize: 17,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        '9 קלפיות לבניית פרופיל מנצח',
                        style: TextStyle(
                          color: Color(0xFF9CA3AF),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildFooter() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFFFFFF),
            Color(0xFFFAFBFC),
          ],
        ),
        border: Border(
          top: BorderSide(
            color: Colors.black.withOpacity(0.05),
          ),
        ),
      ),
      child: Row(
        children: [
          // Preview button
          Expanded(
            flex: 1,
            child: OutlinedButton(
              onPressed: _onPreviewTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF6B7280),
                padding: const EdgeInsets.symmetric(vertical: 12),
                side: const BorderSide(color: Color(0xFFE5E7EB)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'תצוגה מקדימה',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
          ),
          const SizedBox(width: 8),
          
          // Save button
          Expanded(
            flex: 2,
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF6B35), Color(0xFFF59E0B)],
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF6B35).withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _isLoading ? null : _onSaveTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('💾 ', style: TextStyle(fontSize: 16)),
                          Text(
                            'שמרי שינויים',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  void _markUnsavedChanges() {
    if (!_hasUnsavedChanges) {
      setState(() => _hasUnsavedChanges = true);
    }
  }
  
  void _scrollToSuggestions() {
    // Scroll to AI Suggestions section
  }
  
  void _applyAllSuggestions() {
    // Apply all AI suggestions automatically
  }
  
  void _onPreviewTap() {
    // Open preview screen
  }
  
  Future<void> _onSaveTap() async {
    setState(() => _isLoading = true);
    HapticFeedback.mediumImpact();
    
    try {
      // Save to Firestore
      // ... save logic
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('הפרופיל נשמר בהצלחה!'),
              ],
            ),
            backgroundColor: Color(0xFF10B981),
          ),
        );
        
        widget.onSaved?.call();
        setState(() {
          _hasUnsavedChanges = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('שגיאה בשמירה: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
}
```

---

## 🎯 EditableItemCard - Generic Component

### `editable_item_card.dart`

**זה הbuilding block לכל פריט עריך בכל סקציה!**

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class EditableItemCard extends StatelessWidget {
  final Widget child;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool isHighlighted;
  final String? badge;
  final Color? badgeColor;
  
  const EditableItemCard({
    Key? key,
    required this.child,
    required this.onEdit,
    required this.onDelete,
    this.isHighlighted = false,
    this.badge,
    this.badgeColor,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isHighlighted
                ? const Color(0xFFFFF8F3)
                : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isHighlighted
                  ? const Color(0xFFFF6B35)
                  : const Color(0xFFE5E7EB),
              width: isHighlighted ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(child: child),
              const SizedBox(width: 8),
              _buildEditButton(),
              const SizedBox(width: 4),
              _buildDeleteButton(context),
            ],
          ),
        ),
        
        if (badge != null)
          Positioned(
            top: -8,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    badgeColor ?? const Color(0xFFFF6B35),
                    (badgeColor ?? const Color(0xFFF59E0B)),
                  ],
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                badge!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
      ],
    );
  }
  
  Widget _buildEditButton() {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onEdit();
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.edit_outlined,
          color: Color(0xFF6B7280),
          size: 14,
        ),
      ),
    );
  }
  
  Widget _buildDeleteButton(BuildContext context) {
    return InkWell(
      onTap: () => _confirmDelete(context),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.delete_outline,
          color: Color(0xFF991B1B),
          size: 14,
        ),
      ),
    );
  }
  
  Future<void> _confirmDelete(BuildContext context) async {
    HapticFeedback.mediumImpact();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('האם למחוק?'),
        content: const Text('פעולה זו אינה ניתנת לביטול'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFEF4444)),
            child: const Text('מחק'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      onDelete();
    }
  }
}
```

---

## 💰 PricingPackagesSection (קוד מלא)

### `pricing_packages_section.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/pricing_package.dart';
import '../modals/add_edit_package_modal.dart';
import 'editable_item_card.dart';

class PricingPackagesSection extends StatefulWidget {
  final String providerId;
  final VoidCallback onChanged;
  
  const PricingPackagesSection({
    Key? key,
    required this.providerId,
    required this.onChanged,
  }) : super(key: key);
  
  @override
  State<PricingPackagesSection> createState() => _PricingPackagesSectionState();
}

class _PricingPackagesSectionState extends State<PricingPackagesSection> {
  List<PricingPackage> _packages = [
    PricingPackage(
      id: '1',
      name: 'אימון יחיד',
      type: PackageType.single,
      sessions: 1,
      durationMinutes: 60,
      price: 200,
      isPopular: false,
    ),
    PricingPackage(
      id: '2',
      name: 'חבילת 5 אימונים',
      type: PackageType.package,
      sessions: 5,
      durationMinutes: 60,
      price: 900,
      discount: 10,
      isPopular: true,
      validityMonths: 3,
    ),
    PricingPackage(
      id: '3',
      name: '10 אימונים',
      type: PackageType.package,
      sessions: 10,
      durationMinutes: 60,
      price: 1700,
      discount: 15,
      isPopular: false,
      validityMonths: 6,
    ),
  ];
  
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header
          _buildHeader(),
          
          // Smart Tip
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: _buildSmartTip(),
          ),
          
          // Packages list
          ...List.generate(_packages.length, (i) {
            return Padding(
              padding: EdgeInsets.fromLTRB(14, i == 0 ? 0 : 8, 14, i == _packages.length - 1 ? 14 : 0),
              child: _buildPackageCard(_packages[i]),
            );
          }),
        ],
      ),
    );
  }
  
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFFF7ED), Colors.white],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF6B35), Color(0xFFF59E0B)],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(
              child: Text('💰', style: TextStyle(fontSize: 18)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'חבילות ומחירים',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF1F2937),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '${_packages.length} חבילות פעילות',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
              ],
            ),
          ),
          
          // Add button
          ElevatedButton.icon(
            onPressed: _addPackage,
            icon: const Icon(Icons.add, size: 14, color: Colors.white),
            label: const Text(
              'חבילה חדשה',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B35),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              elevation: 2,
              shadowColor: const Color(0xFFFF6B35).withOpacity(0.3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              minimumSize: const Size(0, 28),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSmartTip() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFECFDF5), Color(0xFFD1FAE5)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(
              child: Text('📊', style: TextStyle(fontSize: 18)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text.rich(
                  TextSpan(
                    style: TextStyle(fontSize: 11, color: Color(0xFF047857)),
                    children: [
                      TextSpan(text: 'מחיר ממוצע באזור: '),
                      TextSpan(
                        text: '₪180-220',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF065F46),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  '📈 מאמני 4.5★+ גובים +25%',
                  style: TextStyle(fontSize: 10, color: Color(0xFF047857)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildPackageCard(PricingPackage pkg) {
    return EditableItemCard(
      isHighlighted: pkg.isPopular,
      badge: pkg.isPopular ? '⭐ הפופולרי' : null,
      onEdit: () => _editPackage(pkg),
      onDelete: () => _deletePackage(pkg),
      child: Row(
        children: [
          // Price column
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${pkg.price}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      color: pkg.isPopular ? const Color(0xFFFF6B35) : const Color(0xFF1F2937),
                    ),
                  ),
                  Text(
                    '₪',
                    style: TextStyle(
                      fontSize: 11,
                      color: pkg.isPopular ? const Color(0xFFFF6B35) : const Color(0xFF9CA3AF),
                    ),
                  ),
                ],
              ),
              if (pkg.discount != null && pkg.discount! > 0) ...[
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'חיסכון ${pkg.discount}%',
                    style: const TextStyle(
                      color: Color(0xFF047857),
                      fontSize: 9,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${pkg.durationMinutes} דק',
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 9,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(width: 10),
          
          // Name + description
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  pkg.name,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF1F2937),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _getPackageDescription(pkg),
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  String _getPackageDescription(PricingPackage pkg) {
    if (pkg.type == PackageType.single) {
      return 'למתעניינים, תשלום פר-אימון';
    }
    final pricePerSession = (pkg.price / pkg.sessions).round();
    final validity = pkg.validityMonths != null ? ' • תוקף ${pkg.validityMonths} חודשים' : '';
    return '₪$pricePerSession לאימון$validity';
  }
  
  void _addPackage() async {
    HapticFeedback.lightImpact();
    final newPackage = await showModalBottomSheet<PricingPackage>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AddEditPackageModal(
        onSave: (pkg) => Navigator.pop(ctx, pkg),
      ),
    );
    
    if (newPackage != null) {
      setState(() {
        _packages.add(newPackage);
      });
      widget.onChanged();
    }
  }
  
  void _editPackage(PricingPackage pkg) async {
    final updated = await showModalBottomSheet<PricingPackage>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AddEditPackageModal(
        existing: pkg,
        onSave: (updated) => Navigator.pop(ctx, updated),
      ),
    );
    
    if (updated != null) {
      setState(() {
        final index = _packages.indexWhere((p) => p.id == updated.id);
        if (index != -1) _packages[index] = updated;
      });
      widget.onChanged();
    }
  }
  
  void _deletePackage(PricingPackage pkg) {
    setState(() {
      _packages.removeWhere((p) => p.id == pkg.id);
    });
    widget.onChanged();
  }
}
```

---

## 🎓 CertificationsSection (דוגמה לסקציה עם editable items)

### `certifications_section.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/certification.dart';
import '../modals/add_edit_certification_modal.dart';

class CertificationsSection extends StatefulWidget {
  final String providerId;
  final VoidCallback onChanged;
  
  const CertificationsSection({
    Key? key,
    required this.providerId,
    required this.onChanged,
  }) : super(key: key);
  
  @override
  State<CertificationsSection> createState() => _CertificationsSectionState();
}

class _CertificationsSectionState extends State<CertificationsSection> {
  List<Certification> _certifications = [
    Certification(
      id: '1',
      name: 'מאמן/ת כושר מוסמך/ת',
      institution: 'מכון וינגייט',
      year: 2008,
      isVerified: true,
    ),
    Certification(
      id: '2',
      name: 'Certified Personal Trainer',
      institution: 'NASM',
      year: 2015,
      isVerified: true,
    ),
    Certification(
      id: '3',
      name: 'תזונה ספורטיבית',
      institution: 'אורט בראודה',
      year: 2019,
      isVerified: true,
    ),
  ];
  
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _buildHeader(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: _certifications.map(_buildCertItem).toList(),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFFFFF7ED), Colors.white]),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF6B35), Color(0xFFF59E0B)],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(child: Text('🎓', style: TextStyle(fontSize: 18))),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'תעודות והסמכות',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF1F2937),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '${_certifications.where((c) => c.isVerified).length} מאומתות',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                ),
              ],
            ),
          ),
          
          // Light add button
          OutlinedButton.icon(
            onPressed: _addCertification,
            icon: const Icon(Icons.add, size: 14, color: Color(0xFFC2410C)),
            label: const Text(
              'תעודה',
              style: TextStyle(
                color: Color(0xFFC2410C),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
            style: OutlinedButton.styleFrom(
              backgroundColor: const Color(0xFFFFF7ED),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              side: const BorderSide(color: Color(0xFFFED7AA)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              minimumSize: const Size(0, 28),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildCertItem(Certification cert) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBFC),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          // Verified badge
          if (cert.isVerified)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFDBEAFE),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                '✓ מאומת',
                style: TextStyle(
                  color: Color(0xFF1E40AF),
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          const SizedBox(width: 10),
          
          // Title + year
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${cert.institution} - ${cert.name}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF1F2937),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '${cert.year}',
                  style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF)),
                ),
              ],
            ),
          ),
          
          // Edit + Delete buttons
          const SizedBox(width: 8),
          _buildSmallButton(
            icon: Icons.edit_outlined,
            onTap: () => _editCertification(cert),
          ),
          const SizedBox(width: 4),
          _buildSmallButton(
            icon: Icons.delete_outline,
            color: const Color(0xFF991B1B),
            bgColor: const Color(0xFFFEE2E2),
            onTap: () => _deleteCertification(cert),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSmallButton({
    required IconData icon,
    required VoidCallback onTap,
    Color? color,
    Color? bgColor,
  }) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: bgColor ?? Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: bgColor == null
              ? Border.all(color: const Color(0xFFE5E7EB))
              : null,
        ),
        child: Icon(icon, size: 13, color: color ?? const Color(0xFF6B7280)),
      ),
    );
  }
  
  void _addCertification() async {
    final newCert = await showModalBottomSheet<Certification>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AddEditCertificationModal(
        onSave: (cert) => Navigator.pop(ctx, cert),
      ),
    );
    
    if (newCert != null) {
      setState(() => _certifications.add(newCert));
      widget.onChanged();
    }
  }
  
  void _editCertification(Certification cert) async {
    final updated = await showModalBottomSheet<Certification>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AddEditCertificationModal(
        existing: cert,
        onSave: (cert) => Navigator.pop(ctx, cert),
      ),
    );
    
    if (updated != null) {
      setState(() {
        final i = _certifications.indexWhere((c) => c.id == updated.id);
        if (i != -1) _certifications[i] = updated;
      });
      widget.onChanged();
    }
  }
  
  void _deleteCertification(Certification cert) async {
    final confirmed = await _showDeleteConfirm();
    if (confirmed) {
      setState(() => _certifications.removeWhere((c) => c.id == cert.id));
      widget.onChanged();
    }
  }
  
  Future<bool> _showDeleteConfirm() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('מחיקת תעודה'),
        content: const Text('האם את בטוחה שברצונך למחוק את התעודה?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ביטול'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFEF4444)),
            child: const Text('מחק'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
```

---

## 🤖 AICoachScoreCard (קוד מלא)

### `ai_coach_score_card.dart`

```dart
import 'package:flutter/material.dart';

class AICoachScoreCard extends StatelessWidget {
  final String providerId;
  final VoidCallback onActionTap;
  
  const AICoachScoreCard({
    Key? key,
    required this.providerId,
    required this.onActionTap,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    const score = 78;
    const target = 90;
    const pointsToTarget = target - score;
    
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E1B4B), Color(0xFF312E81)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: [
          // AI Coach badge
          Positioned(
            top: 0,
            left: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFF59E0B), Color(0xFFFB923C)],
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'AI Coach',
                style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w500),
              ),
            ),
          ),
          
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const SizedBox(height: 8),
              
              // Title row
              Row(
                children: [
                  const Text('🎯', style: TextStyle(fontSize: 24)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          'איך הפרופיל שלך מסתכם?',
                          style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                        Text(
                          'עודכן לפני 5 דקות',
                          style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              
              // Score + progress
              Row(
                children: [
                  Column(
                    children: [
                      const Text(
                        '$score',
                        style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w500, height: 1),
                      ),
                      Text(
                        '/ 100',
                        style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 10),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('100', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11)),
                            const Spacer(),
                            const Text(
                              'היעד: 90',
                              style: TextStyle(color: Color(0xFFF59E0B), fontSize: 11, fontWeight: FontWeight.w500),
                            ),
                            const Spacer(),
                            Text('0', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Stack(
                          children: [
                            Container(
                              height: 8,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            FractionallySizedBox(
                              widthFactor: score / 100,
                              child: Container(
                                height: 8,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFFF59E0B), Color(0xFFFB923C)],
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                            // Target marker
                            Positioned(
                              top: -2,
                              left: '${(target / 100 * 100)}%' as dynamic,
                              child: Container(
                                width: 2,
                                height: 12,
                                color: const Color(0xFFF59E0B),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              
              // Action tip
              GestureDetector(
                onTap: onActionTap,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Text('💡', style: TextStyle(fontSize: 16)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: RichText(
                          textAlign: TextAlign.right,
                          text: TextSpan(
                            style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 12),
                            children: const [
                              TextSpan(
                                text: '$pointsToTarget נקודות מהיעד. ',
                                style: TextStyle(fontWeight: FontWeight.w500),
                              ),
                              TextSpan(text: 'הוסיפי תמונות לפני/אחרי → '),
                              TextSpan(
                                text: '+15 נק׳',
                                style: TextStyle(color: Color(0xFFFBBF24), fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

---

## 📦 Models

### `pricing_package.dart`

```dart
enum PackageType { single, package, monthly }

class PricingPackage {
  final String id;
  final String name;
  final PackageType type;
  final int sessions;
  final int durationMinutes;
  final int price;
  final int? discount;
  final int? validityMonths;
  final bool isPopular;
  
  PricingPackage({
    required this.id,
    required this.name,
    required this.type,
    required this.sessions,
    required this.durationMinutes,
    required this.price,
    this.discount,
    this.validityMonths,
    this.isPopular = false,
  });
  
  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'type': type.name,
    'sessions': sessions,
    'durationMinutes': durationMinutes,
    'price': price,
    'discount': discount,
    'validityMonths': validityMonths,
    'isPopular': isPopular,
  };
  
  factory PricingPackage.fromMap(Map<String, dynamic> map) => PricingPackage(
    id: map['id'],
    name: map['name'],
    type: PackageType.values.firstWhere((e) => e.name == map['type']),
    sessions: map['sessions'],
    durationMinutes: map['durationMinutes'],
    price: map['price'],
    discount: map['discount'],
    validityMonths: map['validityMonths'],
    isPopular: map['isPopular'] ?? false,
  );
}
```

### `certification.dart`

```dart
class Certification {
  final String id;
  final String name;
  final String institution;
  final int year;
  final String? imageUrl;
  final bool isVerified;
  
  Certification({
    required this.id,
    required this.name,
    required this.institution,
    required this.year,
    this.imageUrl,
    this.isVerified = false,
  });
}
```

### `success_story.dart`

```dart
class SuccessStory {
  final String id;
  final String clientName;
  final String result;
  final String? testimonial;
  final String? beforeImageUrl;
  final String? afterImageUrl;
  final int rating;
  final DateTime createdAt;
  final bool clientApproved;
  
  SuccessStory({
    required this.id,
    required this.clientName,
    required this.result,
    this.testimonial,
    this.beforeImageUrl,
    this.afterImageUrl,
    this.rating = 5,
    required this.createdAt,
    this.clientApproved = false,
  });
}
```

### `special_offer.dart`

```dart
enum OfferType { discount, firstFree, buyXgetY, custom }

class SpecialOffer {
  final String id;
  final OfferType type;
  final String title;
  final String description;
  final int? discountPercent;
  final int? availableSpots;
  final DateTime expiresAt;
  final bool isActive;
  
  SpecialOffer({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    this.discountPercent,
    this.availableSpots,
    required this.expiresAt,
    this.isActive = true,
  });
  
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
```

### `training_location.dart`

```dart
enum LocationType { home, park, gym }

class TrainingLocation {
  final String id;
  final LocationType type;
  final int radiusKm;
  final int? extraCost;
  final String? notes;
  
  TrainingLocation({
    required this.id,
    required this.type,
    this.radiusKm = 15,
    this.extraCost,
    this.notes,
  });
  
  String get displayName {
    switch (type) {
      case LocationType.home: return 'בבית הלקוח';
      case LocationType.park: return 'בפארק';
      case LocationType.gym: return 'חדר כושר';
    }
  }
  
  String get emoji {
    switch (type) {
      case LocationType.home: return '🏠';
      case LocationType.park: return '🌳';
      case LocationType.gym: return '🏋️';
    }
  }
}
```

### `trainer_specialty.dart`

```dart
enum SpecialtyType {
  strength, fatLoss, pregnancy, seniors, rehab,
  flexibility, endurance, martialArts, calisthenics,
  functional, competitionPrep, bulking,
}

class TrainerSpecialty {
  final SpecialtyType type;
  final String label;
  final String emoji;
  final List<int> colors; // [primary, secondary]
  
  const TrainerSpecialty({
    required this.type,
    required this.label,
    required this.emoji,
    required this.colors,
  });
  
  static const List<TrainerSpecialty> all = [
    TrainerSpecialty(type: SpecialtyType.strength, label: 'כוח ומסה', emoji: '💪', colors: [0xFFEF4444, 0xFFDC2626]),
    TrainerSpecialty(type: SpecialtyType.fatLoss, label: 'הרזיה', emoji: '🔥', colors: [0xFFF59E0B, 0xFFD97706]),
    TrainerSpecialty(type: SpecialtyType.pregnancy, label: 'הריון ולאחר לידה', emoji: '🤰', colors: [0xFF3B82F6, 0xFF2563EB]),
    TrainerSpecialty(type: SpecialtyType.seniors, label: 'מבוגרים 50+', emoji: '👴', colors: [0xFF6366F1, 0xFF4F46E5]),
    TrainerSpecialty(type: SpecialtyType.rehab, label: 'שיקום', emoji: '🏥', colors: [0xFF10B981, 0xFF059669]),
    TrainerSpecialty(type: SpecialtyType.flexibility, label: 'גמישות', emoji: '🧘', colors: [0xFFEC4899, 0xFFDB2777]),
    TrainerSpecialty(type: SpecialtyType.endurance, label: 'סיבולת', emoji: '🏃', colors: [0xFFFBBF24, 0xFFF59E0B]),
    TrainerSpecialty(type: SpecialtyType.martialArts, label: 'לחימה', emoji: '🥊', colors: [0xFF991B1B, 0xFF7F1D1D]),
    TrainerSpecialty(type: SpecialtyType.calisthenics, label: 'קליסטניקס', emoji: '🤸', colors: [0xFF8B5CF6, 0xFF7C3AED]),
    TrainerSpecialty(type: SpecialtyType.functional, label: 'פונקציונלי', emoji: '🏊', colors: [0xFF06B6D4, 0xFF0891B2]),
    TrainerSpecialty(type: SpecialtyType.competitionPrep, label: 'הכנה לתחרויות', emoji: '🏆', colors: [0xFFA855F7, 0xFF9333EA]),
    TrainerSpecialty(type: SpecialtyType.bulking, label: 'הקצנת מסה', emoji: '🎯', colors: [0xFF14B8A6, 0xFF0D9488]),
  ];
}
```

---

## 📝 הערות יישום חשובות:

1. **HapticFeedback** - להוסיף בכל אינטראקציה (lightImpact למחיקה/בחירה, mediumImpact לשמירה)
2. **AnimatedSwitcher** - להוסיף ב-listings כשמוסיפים/מוחקים פריטים
3. **Modals** - תמיד `showModalBottomSheet` עם `isScrollControlled: true`
4. **Loading states** - `Skeleton loaders` לכל סקציה
5. **Empty states** - לכל סקציה הצעה חכמה אם ריקה
6. **Confirmation dialogs** - תמיד לפני מחיקה

---

**📁 לקובץ הבא: `03_CLIENT_CODE.md` - הצד של הלקוח**
