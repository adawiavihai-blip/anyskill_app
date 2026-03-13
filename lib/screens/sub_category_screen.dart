import 'package:flutter/material.dart';
import '../services/category_service.dart';
import 'category_results_screen.dart';

class SubCategoryScreen extends StatelessWidget {
  final String parentId;
  final String parentName;

  const SubCategoryScreen({
    super.key,
    required this.parentId,
    required this.parentName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          "בחר תחום — $parentName",
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: CategoryService.streamSubCategories(parentId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final subs = snapshot.data ?? [];

          if (subs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.category_outlined, size: 56, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  const Text(
                    "אין תת-קטגוריות עדיין",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "מציג את כל המומחים ב$parentName",
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CategoryResultsScreen(categoryName: parentName),
                      ),
                    ),
                    child: Text(
                      "הצג מומחי $parentName",
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  "בחר התמחות ספציפית",
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final w = constraints.maxWidth;
                      final cols = w >= 900 ? 4 : w >= 600 ? 3 : 2;
                      final ratio = w >= 900 ? 1.0 : w >= 600 ? 0.90 : 0.85;
                      return GridView.builder(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                          childAspectRatio: ratio,
                        ),
                        itemCount: subs.length,
                        itemBuilder: (context, index) {
                          final sub = subs[index];
                          final name     = sub['name']     as String? ?? '';
                          final imageUrl = sub['img']      as String? ?? '';
                          final iconName = sub['iconName'] as String? ?? '';
                          final icon     = CategoryService.getIcon(iconName);

                          return _SubCategoryCard(
                            name: name,
                            imageUrl: imageUrl,
                            icon: icon,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CategoryResultsScreen(categoryName: name),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SubCategoryCard extends StatelessWidget {
  final String name;
  final String imageUrl;
  final IconData icon;
  final VoidCallback onTap;

  const _SubCategoryCard({
    required this.name,
    required this.imageUrl,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background image
            imageUrl.isNotEmpty
                ? Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(color: Colors.grey[200]),
                    loadingBuilder: (_, child, progress) =>
                        progress == null ? child : Container(color: Colors.grey[100]),
                  )
                : Container(color: Colors.grey[200]),

            // Dark gradient overlay
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.68),
                  ],
                  stops: const [0.4, 1.0],
                ),
              ),
            ),

            // Name + icon at bottom
            Positioned(
              bottom: 16,
              left: 14,
              right: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Icon(icon, color: Colors.white, size: 22),
                  const SizedBox(height: 6),
                  Text(
                    name,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
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
