import 'package:flutter/material.dart';
import '../../../constants.dart';

class CategoryPills extends StatelessWidget {
  final String selectedCategory;
  final Function(String) onCategorySelected;

  const CategoryPills({
    super.key,
    required this.selectedCategory,
    required this.onCategorySelected,
  });

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> categories = APP_CATEGORIES;

    return Container(
      height: 85, // QA: הקטנו מעט את הגובה למראה נקי יותר
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        // QA: reverse: true מאפשר תמיכה טבעית בעברית (מימין לשמאל)
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: 15),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final cat = categories[index];
          bool isSelected = selectedCategory == cat['name'];
          
          return GestureDetector(
            onTap: () => onCategorySelected(cat['name']),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 100,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isSelected ? Colors.black : Colors.transparent,
                    width: 2.0,
                  ),
                ),
              ),
              child: Opacity(
                // QA: מי שאינו נבחר מקבל שקיפות נמוכה יותר כדי להבליט את הנבחר
                opacity: isSelected ? 1.0 : 0.6,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      cat['icon'],
                      color: isSelected ? Colors.black : Colors.grey[700],
                      size: 26,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      cat['name'],
                      style: TextStyle(
                        fontSize: 12,
                        color: isSelected ? Colors.black : Colors.grey[700],
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}