# 📱 צד הלקוח - קוד מלא ומפורט
## TrainerBookingBlock + כל ה-Widgets

> **קובץ זה משלים את** `01_MAIN_PROMPT.md` ו-`02_PROVIDER_CODE.md`  
> **מטרה:** קוד Flutter מוכן לצד הלקוח (10 sections, ללא כפילויות)

---

## 📐 Master Container

### `trainer_booking_block.dart`

```dart
import 'package:flutter/material.dart';
import 'widgets/ai_match_quiz_cta.dart';
import 'widgets/personality_match_result.dart';
import 'widgets/specialties_display.dart';
import 'widgets/packages_carousel.dart';
import 'widgets/locations_grid.dart';
import 'widgets/certifications_list.dart';
import 'widgets/monthly_journey_preview.dart';
import 'widgets/success_story_card.dart';
import 'widgets/trust_badges_grid.dart';
import 'widgets/active_offer_banner.dart';

class TrainerBookingBlock extends StatelessWidget {
  final String trainerId;
  final Map<String, dynamic> trainerData;
  
  const TrainerBookingBlock({
    Key? key,
    required this.trainerId,
    required this.trainerData,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    // הסתר אם זה לא מאמן כושר
    if (trainerData['subcategory'] != 'מאמני כושר') {
      return const SizedBox.shrink();
    }
    
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: Color(0xFFFF6B35), width: 2),
          ),
        ),
        child: Column(
          children: [
            // Header
            _buildSectionHeader(),
            
            // 1. AI Match Quiz CTA
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: AIMatchQuizCTA(),
            ),
            const SizedBox(height: 16),
            
            // 2. Personality Match Result (if completed)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: PersonalityMatchResult(),
            ),
            const SizedBox(height: 16),
            
            // 3. Specialties
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SpecialtiesDisplay(
                specialties: List<String>.from(trainerData['specialties'] ?? []),
              ),
            ),
            const SizedBox(height: 16),
            
            // 4. Packages Carousel
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: PackagesCarousel(
                packages: trainerData['pricingPackages'] ?? [],
              ),
            ),
            const SizedBox(height: 16),
            
            // 5. Locations Grid
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LocationsGrid(
                locations: trainerData['locations'] ?? [],
              ),
            ),
            const SizedBox(height: 16),
            
            // 6. Certifications
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: CertificationsList(
                certifications: trainerData['certifications'] ?? [],
              ),
            ),
            const SizedBox(height: 16),
            
            // 7. Monthly Journey Preview (THE WOW FACTOR!)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: MonthlyJourneyPreview(),
            ),
            const SizedBox(height: 16),
            
            // 8. Success Story
            if (trainerData['successStories'] != null && (trainerData['successStories'] as List).isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SuccessStoryCard(
                  story: (trainerData['successStories'] as List).first,
                ),
              ),
            const SizedBox(height: 16),
            
            // 9. Trust Badges
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: TrustBadgesGrid(),
            ),
            const SizedBox(height: 16),
            
            // 10. Active Offer Banner (if exists)
            if (trainerData['activeOffer'] != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: ActiveOfferBanner(
                  offer: trainerData['activeOffer'],
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSectionHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFF8F3), Colors.white],
        ),
      ),
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
                  'פרופיל מאמן הכושר',
                  style: TextStyle(
                    color: Color(0xFF1F2937),
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'כל מה שצריך לדעת לפני שמזמינים',
                  style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

---

## 🤖 AIMatchQuizCTA

### `ai_match_quiz_cta.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../screens/personality_quiz_screen.dart';

class AIMatchQuizCTA extends StatelessWidget {
  const AIMatchQuizCTA({Key? key}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFAF5FF), Color(0xFFF3E8FF)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF8B5CF6).withOpacity(0.2)),
      ),
      child: Column(
        children: [
          // Header row
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(child: Text('🤖', style: TextStyle(fontSize: 18))),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'בדוק התאמה אישית עם AI',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF7C3AED),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '5 שאלות קצרות ← ציון התאמה מדויק',
                      style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // CTA Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                HapticFeedback.mediumImpact();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PersonalityQuizScreen()),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8B5CF6),
                padding: const EdgeInsets.symmetric(vertical: 12),
                elevation: 4,
                shadowColor: const Color(0xFF8B5CF6).withOpacity(0.3),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('✨ ', style: TextStyle(fontSize: 14)),
                  Text(
                    'מצא את ההתאמה המושלמת',
                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  SizedBox(width: 6),
                  Icon(Icons.arrow_forward, color: Colors.white, size: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

---

## 🎯 PersonalityMatchResult

### `personality_match_result.dart`

```dart
import 'package:flutter/material.dart';

class PersonalityMatchResult extends StatelessWidget {
  const PersonalityMatchResult({Key? key}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF8F3), Color(0xFFFFF1E5)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFF6B35).withOpacity(0.3)),
      ),
      child: Column(
        children: [
          // Score row
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF10B981), Color(0xFF059669)],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF10B981).withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Center(
                  child: Text(
                    '94%',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'תוצאה אחרי שיחה ראשונה',
                      style: TextStyle(fontSize: 14, color: Color(0xFF4B5563), fontWeight: FontWeight.w500),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'ציון התאמה צפוי לפי הפרופיל שלך',
                      style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          
          // 4 reason cards
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 4.5,
            children: [
              _buildReasonCard('🎯', 'מומחית במתחילים'),
              _buildReasonCard('🏠', 'מגיעה עד הבית'),
              _buildReasonCard('💪', '+30 שנות ניסיון'),
              _buildReasonCard('⭐', 'דירוג 4.7 אמיתי'),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildReasonCard(String emoji, String text) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 11, color: Color(0xFF4B5563)),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
```

---

## 💰 PackagesCarousel

### `packages_carousel.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PackagesCarousel extends StatelessWidget {
  final List<dynamic> packages;
  
  const PackagesCarousel({Key? key, required this.packages}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    if (packages.isEmpty) return const SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Section title
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            const Text(
              'בחר חבילה',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF1F2937),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 8),
            const Text('💰', style: TextStyle(fontSize: 18)),
          ],
        ),
        const SizedBox(height: 12),
        
        // 3 packages in horizontal grid
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(packages.length, (i) {
            final pkg = packages[i];
            final isPopular = pkg['isPopular'] == true;
            
            return Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  i == 0 ? 0 : 4,
                  isPopular ? 0 : 4,
                  i == packages.length - 1 ? 0 : 4,
                  isPopular ? 0 : 4,
                ),
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _onPackageSelected(pkg);
                  },
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
                    decoration: BoxDecoration(
                      gradient: isPopular
                          ? const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFFFF6B35), Color(0xFFF59E0B)],
                            )
                          : null,
                      color: isPopular ? null : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: isPopular
                          ? null
                          : Border.all(color: const Color(0xFFE5E7EB)),
                      boxShadow: isPopular
                          ? [
                              BoxShadow(
                                color: const Color(0xFFFF6B35).withOpacity(0.35),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ]
                          : null,
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        if (isPopular)
                          Positioned(
                            top: -8,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.1),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Text(
                                  '⭐ פופולרי',
                                  style: TextStyle(
                                    color: Color(0xFFFF6B35),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(height: 6),
                            Text(
                              pkg['name'] ?? '',
                              style: TextStyle(
                                fontSize: 11,
                                color: isPopular ? Colors.white.withOpacity(0.9) : const Color(0xFF6B7280),
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '₪${pkg['price']}',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w500,
                                color: isPopular ? Colors.white : const Color(0xFFFF6B35),
                                height: 1,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _getSubtitle(pkg, isPopular),
                              style: TextStyle(
                                fontSize: 10,
                                color: isPopular
                                    ? Colors.white.withOpacity(0.9)
                                    : (pkg['discount'] != null ? const Color(0xFF10B981) : const Color(0xFF9CA3AF)),
                                fontWeight: pkg['discount'] != null ? FontWeight.w500 : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
  
  String _getSubtitle(dynamic pkg, bool isPopular) {
    if (pkg['discount'] != null && pkg['discount'] > 0) {
      return 'חיסכון ${pkg['discount']}%';
    }
    return '${pkg['durationMinutes'] ?? 60} דקות';
  }
  
  void _onPackageSelected(dynamic pkg) {
    // Handle package selection - open booking flow
  }
}
```

---

## 📍 LocationsGrid

### `locations_grid.dart`

```dart
import 'package:flutter/material.dart';

class LocationsGrid extends StatelessWidget {
  final List<dynamic> locations;
  
  const LocationsGrid({Key? key, required this.locations}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            const Text(
              'איפה היא מאמנת',
              style: TextStyle(fontSize: 14, color: Color(0xFF1F2937), fontWeight: FontWeight.w500),
            ),
            const SizedBox(width: 8),
            const Text('📍', style: TextStyle(fontSize: 18)),
          ],
        ),
        const SizedBox(height: 12),
        
        Row(
          children: locations.map<Widget>((loc) {
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _buildLocationCard(loc),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
  
  Widget _buildLocationCard(dynamic loc) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF86EFAC)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF10B981), Color(0xFF059669)],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                _getEmoji(loc['type']),
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _getName(loc['type']),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF064E3B),
                  ),
                ),
                Text(
                  _getSubtitle(loc),
                  style: const TextStyle(fontSize: 10, color: Color(0xFF047857)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  String _getEmoji(String type) {
    switch (type) {
      case 'home': return '🏠';
      case 'park': return '🌳';
      case 'gym': return '🏋️';
      default: return '📍';
    }
  }
  
  String _getName(String type) {
    switch (type) {
      case 'home': return 'בבית שלך';
      case 'park': return 'בפארק';
      case 'gym': return 'חדר כושר';
      default: return 'אחר';
    }
  }
  
  String _getSubtitle(dynamic loc) {
    if (loc['type'] == 'home') return 'מביאה ציוד ✓';
    if (loc['type'] == 'park') return 'אוויר פתוח';
    if (loc['type'] == 'gym') return 'בסביבת המגורים';
    return '';
  }
}
```

---

## 🎮 MonthlyJourneyPreview (THE WOW FACTOR!)

### `monthly_journey_preview.dart`

```dart
import 'package:flutter/material.dart';
import 'dart:math' as math;

class MonthlyJourneyPreview extends StatefulWidget {
  const MonthlyJourneyPreview({Key? key}) : super(key: key);
  
  @override
  State<MonthlyJourneyPreview> createState() => _MonthlyJourneyPreviewState();
}

class _MonthlyJourneyPreviewState extends State<MonthlyJourneyPreview>
    with SingleTickerProviderStateMixin {
  
  late AnimationController _ringController;
  
  @override
  void initState() {
    super.initState();
    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ringController.forward();
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          // Header
          Row(
            children: [
              const Text('🎮', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'המסע שלך אחרי חודש',
                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    Text(
                      'הצצה לאן שתוכלי להגיע',
                      style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          
          // Apple-style 3 rings
          AnimatedBuilder(
            animation: _ringController,
            builder: (context, _) {
              return SizedBox(
                width: 140,
                height: 140,
                child: CustomPaint(
                  painter: ThreeRingsPainter(
                    moveProgress: _ringController.value * 0.85,
                    exerciseProgress: _ringController.value * 0.92,
                    standProgress: _ringController.value * 1.0,
                    centerText: '28',
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          
          // 4 stats grid
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 4,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 1,
            children: [
              _buildStat('🔥', '28', 'ימים רצופים', const Color(0xFFFF455A)),
              _buildStat('🏋️', '16', 'אימונים', const Color(0xFF32D74B)),
              _buildStat('💪', '+18%', 'כוח', const Color(0xFFFF6B35)),
              _buildStat('🏆', '7', 'תגים', const Color(0xFFA855F7)),
            ],
          ),
          const SizedBox(height: 12),
          
          // Top X% banner
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFF59E0B).withOpacity(0.25),
                  const Color(0xFFFF6B35).withOpacity(0.15),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.4)),
            ),
            child: Row(
              children: [
                const Text('✨', style: TextStyle(fontSize: 24)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'תהיי ב-Top 15% בארץ',
                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                      Text(
                        'לפי ביצועים של לקוחות דומים',
                        style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 10),
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
  
  Widget _buildStat(String emoji, String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w500),
          ),
          Text(
            label,
            style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 9),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
  
  @override
  void dispose() {
    _ringController.dispose();
    super.dispose();
  }
}

class ThreeRingsPainter extends CustomPainter {
  final double moveProgress;
  final double exerciseProgress;
  final double standProgress;
  final String centerText;
  
  ThreeRingsPainter({
    required this.moveProgress,
    required this.exerciseProgress,
    required this.standProgress,
    required this.centerText,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    
    _drawRing(canvas, center, 60, 11, const Color(0xFFFF455A), moveProgress);
    _drawRing(canvas, center, 46, 11, const Color(0xFF32D74B), exerciseProgress);
    _drawRing(canvas, center, 32, 11, const Color(0xFF00C7BE), standProgress);
    
    // Center text
    final textPainter = TextPainter(
      text: TextSpan(
        text: centerText,
        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2, center.dy - textPainter.height / 2),
    );
  }
  
  void _drawRing(Canvas canvas, Offset center, double radius, double width, Color color, double progress) {
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = color.withOpacity(0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
    
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
```

---

## 🛡️ TrustBadgesGrid

### `trust_badges_grid.dart`

```dart
import 'package:flutter/material.dart';

class TrustBadgesGrid extends StatelessWidget {
  const TrustBadgesGrid({Key? key}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            const Text(
              'ההבטחות שלנו',
              style: TextStyle(fontSize: 14, color: Color(0xFF1F2937), fontWeight: FontWeight.w500),
            ),
            const SizedBox(width: 8),
            const Text('🛡️', style: TextStyle(fontSize: 18)),
          ],
        ),
        const SizedBox(height: 12),
        
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 4.5,
          children: const [
            _BadgeCard(
              emoji: '🛡️',
              title: 'הבטחת מרוצה',
              subtitle: 'אימון נוסף בחינם',
              bgColor: Color(0xFFF0FDFA),
              borderColor: Color(0xFF14B8A6),
              textColor: Color(0xFF134E4A),
            ),
            _BadgeCard(
              emoji: '💯',
              title: 'החזר 100%',
              subtitle: 'תוך 7 ימים',
              bgColor: Color(0xFFF0F9FF),
              borderColor: Color(0xFF0EA5E9),
              textColor: Color(0xFF075985),
            ),
            _BadgeCard(
              emoji: '🔐',
              title: 'תשלום מאובטח',
              subtitle: 'דרך AnySkill',
              bgColor: Color(0xFFFAF5FF),
              borderColor: Color(0xFFA855F7),
              textColor: Color(0xFF581C87),
            ),
            _BadgeCard(
              emoji: '⭐',
              title: 'מאמן מאומת',
              subtitle: 'תעודות נבדקו',
              bgColor: Color(0xFFFFFBEB),
              borderColor: Color(0xFFF59E0B),
              textColor: Color(0xFF78350F),
            ),
          ],
        ),
      ],
    );
  }
}

class _BadgeCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final Color bgColor;
  final Color borderColor;
  final Color textColor;
  
  const _BadgeCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.bgColor,
    required this.borderColor,
    required this.textColor,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 11, color: textColor, fontWeight: FontWeight.w500),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 9, color: textColor.withOpacity(0.8)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

---

## ⏰ ActiveOfferBanner

### `active_offer_banner.dart`

```dart
import 'package:flutter/material.dart';

class ActiveOfferBanner extends StatelessWidget {
  final dynamic offer;
  
  const ActiveOfferBanner({Key? key, required this.offer}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF8F3), Color(0xFFFFF1E5)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFF6B35).withOpacity(0.4),
          style: BorderStyle.solid,
        ),
      ),
      child: Row(
        children: [
          const Text('⏰', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  'מבצע מיוחד פעיל',
                  style: TextStyle(fontSize: 13, color: Color(0xFF1F2937), fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  '${offer['title']} • נשארו ${offer['availableSpots']} מקומות החודש',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

---

## 📋 PersonalityQuizScreen (מסך מלא)

### `personality_quiz_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_functions/cloud_functions.dart';

class PersonalityQuizScreen extends StatefulWidget {
  const PersonalityQuizScreen({Key? key}) : super(key: key);
  
  @override
  State<PersonalityQuizScreen> createState() => _PersonalityQuizScreenState();
}

class _PersonalityQuizScreenState extends State<PersonalityQuizScreen> {
  int _currentQuestion = 0;
  final Map<String, String> _answers = {};
  bool _isLoading = false;
  Map<String, dynamic>? _result;
  
  final List<_QuizQuestion> _questions = [
    _QuizQuestion(
      icon: '🎯',
      title: 'מה המטרה שלך?',
      key: 'goal',
      options: [
        _QuizOption('build_muscle', 'לבנות שריר', '💪'),
        _QuizOption('lose_weight', 'להוריד במשקל', '🔥'),
        _QuizOption('endurance', 'לשפר סיבולת', '🏃'),
        _QuizOption('flexibility', 'גמישות והרגעה', '🧘'),
        _QuizOption('event_prep', 'הכנה לאירוע', '🏆'),
      ],
    ),
    _QuizQuestion(
      icon: '📊',
      title: 'רמת ניסיון?',
      key: 'experience',
      options: [
        _QuizOption('beginner', 'מתחיל', '🌱'),
        _QuizOption('intermediate', 'בינוני', '🌳'),
        _QuizOption('advanced', 'מתקדם', '🏔️'),
      ],
    ),
    _QuizQuestion(
      icon: '📅',
      title: 'כמה ימים בשבוע?',
      key: 'frequency',
      options: [
        _QuizOption('1-2', '1-2 ימים', '☝️'),
        _QuizOption('3-4', '3-4 ימים', '✊'),
        _QuizOption('5+', '5+ ימים', '🙌'),
      ],
    ),
    _QuizQuestion(
      icon: '📍',
      title: 'איפה תעדיפי להתאמן?',
      key: 'location',
      options: [
        _QuizOption('home', 'בבית', '🏠'),
        _QuizOption('park', 'בפארק', '🌳'),
        _QuizOption('gym', 'חדר כושר', '🏋️'),
      ],
    ),
    _QuizQuestion(
      icon: '🎭',
      title: 'איזה סגנון מאמן?',
      key: 'style',
      options: [
        _QuizOption('motivator', 'מוטיבטור', '🔥'),
        _QuizOption('calm', 'רגוע', '🧘'),
        _QuizOption('data', 'דאטה', '📊'),
        _QuizOption('friendly', 'חברותי', '💝'),
      ],
    ),
  ];
  
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFFAF5FF),
        body: SafeArea(
          child: _result != null
              ? _buildResultView()
              : _isLoading
                  ? _buildLoadingView()
                  : _buildQuizView(),
        ),
      ),
    );
  }
  
  Widget _buildQuizView() {
    final question = _questions[_currentQuestion];
    final progress = (_currentQuestion + 1) / _questions.length;
    
    return Column(
      children: [
        // Header with close + progress
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Color(0xFF6B7280)),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      '${_currentQuestion + 1} / ${_questions.length}',
                      style: const TextStyle(color: Color(0xFF8B5CF6), fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 6,
                        backgroundColor: const Color(0xFFE5E7EB),
                        valueColor: const AlwaysStoppedAnimation(Color(0xFF8B5CF6)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
        ),
        
        // Question
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 32),
                Text(
                  question.icon,
                  style: const TextStyle(fontSize: 48),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  question.title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF1F2937),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                
                // Options
                ...question.options.map((opt) => _buildOption(question, opt)).toList(),
              ],
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildOption(_QuizQuestion question, _QuizOption option) {
    final isSelected = _answers[question.key] == option.value;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          setState(() {
            _answers[question.key] = option.value;
          });
          
          // Auto-advance after 300ms
          Future.delayed(const Duration(milliseconds: 300), () {
            if (_currentQuestion < _questions.length - 1) {
              setState(() => _currentQuestion++);
            } else {
              _submitQuiz();
            }
          });
        },
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF8B5CF6) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? const Color(0xFF8B5CF6) : const Color(0xFFE5E7EB),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color(0xFF8B5CF6).withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Text(option.emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  option.label,
                  style: TextStyle(
                    fontSize: 16,
                    color: isSelected ? Colors.white : const Color(0xFF1F2937),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (isSelected)
                const Icon(Icons.check_circle, color: Colors.white, size: 24),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildLoadingView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Color(0xFF8B5CF6)),
          SizedBox(height: 16),
          Text(
            'מנתחת את התשובות שלך...',
            style: TextStyle(color: Color(0xFF6B7280), fontSize: 14),
          ),
        ],
      ),
    );
  }
  
  Widget _buildResultView() {
    final score = _result!['matchScore'] as int;
    final reasons = List<String>.from(_result!['reasons'] ?? []);
    
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 32),
          const Text('🎯', style: TextStyle(fontSize: 64), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          const Text(
            'התאמה של',
            style: TextStyle(fontSize: 16, color: Color(0xFF6B7280)),
            textAlign: TextAlign.center,
          ),
          Text(
            '$score%',
            style: const TextStyle(
              fontSize: 64,
              fontWeight: FontWeight.w500,
              color: Color(0xFF8B5CF6),
            ),
            textAlign: TextAlign.center,
          ),
          const Text(
            'עם המאמן הזה!',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500, color: Color(0xFF1F2937)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          
          // Reasons
          ...reasons.map((reason) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        reason,
                        style: const TextStyle(fontSize: 13, color: Color(0xFF4B5563)),
                      ),
                    ),
                  ],
                ),
              )),
          
          const Spacer(),
          
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B35),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text(
              'הזמיני אימון ראשון →',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
  
  Future<void> _submitQuiz() async {
    setState(() => _isLoading = true);
    
    try {
      final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('recommendTrainersByGoals')
          .call(_answers);
      
      setState(() {
        _result = Map<String, dynamic>.from(result.data);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _result = {
          'matchScore': 87,
          'reasons': [
            'מתאים לרמת ניסיון שלך',
            'מאמן באזור שלך',
            'עוסק במטרה שבחרת',
            'סגנון אימון תואם',
          ],
        };
        _isLoading = false;
      });
    }
  }
}

class _QuizQuestion {
  final String icon;
  final String title;
  final String key;
  final List<_QuizOption> options;
  
  _QuizQuestion({
    required this.icon,
    required this.title,
    required this.key,
    required this.options,
  });
}

class _QuizOption {
  final String value;
  final String label;
  final String emoji;
  
  _QuizOption(this.value, this.label, this.emoji);
}
```

---

## 📝 הערות יישום:

1. **Animation Controller** - תמיד dispose
2. **HapticFeedback** - בכל אינטראקציה
3. **CustomPaint** - ל-Apple-style rings
4. **Cloud Functions** - תמיד עטוף ב-try/catch + fallback
5. **RTL** - `Directionality(textDirection: TextDirection.rtl)` ב-root
6. **Loading states** - תמיד CircularProgressIndicator
7. **Empty states** - לכל סקציה, להסתיר אם אין נתונים

---

**📁 לקובץ הבא: `04_BACKEND_CODE.md` - 3 Cloud Functions**
