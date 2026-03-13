import 'package:flutter/material.dart';
import '../../../services/category_service.dart';

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
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: CategoryService.stream(),
      builder: (context, snapshot) {
        final categories = snapshot.data ?? [];
        if (categories.isEmpty) return const SizedBox(height: 85);

        return Container(
          height: 85,
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
                    opacity: isSelected ? 1.0 : 0.6,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          CategoryService.getIcon(cat['iconName']),
                          color: isSelected ? Colors.black : Colors.grey[700],
                          size: 26,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          cat['name'] ?? '',
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
      },
    );
  }
}
