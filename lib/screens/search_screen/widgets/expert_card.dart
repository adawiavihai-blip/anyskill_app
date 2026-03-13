import 'package:flutter/material.dart';
import '../../../utils/price_formatter.dart';
import '../../expert_profile_screen.dart';

class ExpertCard extends StatelessWidget {
  final String  expertId;
  final String  name;
  final String  bio;
  final double  rating;
  final dynamic price;   // int | double | String | null
  final String  imageUrl;

  const ExpertCard({
    super.key,
    required this.expertId,
    required this.name,
    required this.bio,
    required this.rating,
    required this.price,
    required this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ExpertProfileScreen(expertId: expertId, expertName: name),
        ),
      ),
      child: Padding(
      padding: const EdgeInsets.only(bottom: 28), // רווח מעט גדול יותר לנשימה
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. תמונה עם הגנות ועיצוב Airbnb
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  imageUrl,
                  height: 240, // הגדלתי מעט את הגובה למראה מרשים יותר
                  width: double.infinity,
                  fit: BoxFit.cover,
                  // QA: טיפול במקרה שהתמונה שבורה או לא קיימת
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 240,
                    width: double.infinity,
                    color: Colors.grey[100],
                    child: Icon(Icons.person, size: 50, color: Colors.grey[400]),
                  ),
                  // QA: מחוון טעינה בזמן שהתמונה יורדת מהרשת
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      height: 240,
                      width: double.infinity,
                      color: Colors.grey[50],
                      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    );
                  },
                ),
              ),
              // כפתור לב (Wishlist) - סימן ההיכר של Airbnb
              const Positioned(
                top: 12,
                right: 12,
                child: Icon(Icons.favorite_border, color: Colors.white, size: 24),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 2. שורת כותרת ודירוג
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.black,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Row(
                children: [
                  const Icon(Icons.star, size: 16, color: Colors.black),
                  const SizedBox(width: 4),
                  Text(
                    rating.toStringAsFixed(1), // QA: מוודא ספרה אחת אחרי הנקודה
                    style: const TextStyle(fontWeight: FontWeight.w400, fontSize: 14),
                  ),
                ],
              ),
            ],
          ),

          // 3. תיאור (Bio)
          Text(
            bio,
            style: TextStyle(color: Colors.grey[600], fontSize: 14, height: 1.4),
            maxLines: 1,
            overflow: TextOverflow.ellipsis, // QA: מונע מהטקסט לגלוש ולשבור את העיצוב
          ),

          const SizedBox(height: 6),

          // 4. מחיר מודגש — מעוצב על-ידי formatPriceDisplay
          Text(
            formatPriceDisplay(price),
            style: const TextStyle(
              color: Colors.black,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    ),
    );
  }
}