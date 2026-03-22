import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shimmer/shimmer.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/category_service.dart';
import '../services/settings_service.dart';
import '../widgets/category_edit_sheet.dart';
import 'category_results_screen.dart';
import '../l10n/app_localizations.dart'; // ignore: unused_import — partial i18n pass

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
    final isAdmin =
        FirebaseAuth.instance.currentUser?.email == 'adawiavihai@gmail.com';

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
            return _SubCategoryShimmerGrid();
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

          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: SettingsService.stream,
            builder: (context, settingsSnap) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          const cols       = 4;
                          const spacing    = 6.0;
                          // Fixed ratio — uniform across all items.
                          const childRatio = 0.75;

                          return GridView.builder(
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount:   cols,
                              crossAxisSpacing: spacing,
                              mainAxisSpacing:  spacing,
                              childAspectRatio: childRatio,
                            ),
                            itemCount: subs.length,
                            itemBuilder: (context, index) {
                              final sub          = subs[index];
                              final name         = sub['name']      as String? ?? '';
                              final imageUrl     = sub['img']       as String? ?? '';
                              final iconName     = sub['iconName']  as String? ?? '';
                              final icon         = CategoryService.getIcon(iconName);
                              final perCardScale =
                                  (sub['cardScale'] as num? ?? 1.0).toDouble();

                              return _SubCategoryCard(
                                docId:        sub['id'] as String? ?? '',
                                name:         name,
                                iconName:     iconName,
                                imageUrl:     imageUrl,
                                icon:         icon,
                                isAdmin:      isAdmin,
                                perCardScale: perCardScale,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        CategoryResultsScreen(categoryName: name),
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
          );
        },
      ),
    );
  }
}

class _SubCategoryCard extends StatefulWidget {
  final String      docId;
  final String      name;
  final String      iconName;
  final String      imageUrl;
  final IconData    icon;
  final bool        isAdmin;
  final double      perCardScale; // visual zoom within fixed grid cell
  final VoidCallback onTap;

  const _SubCategoryCard({
    required this.docId,
    required this.name,
    required this.iconName,
    required this.imageUrl,
    required this.icon,
    required this.onTap,
    this.isAdmin      = false,
    this.perCardScale = 1.0,
  });

  @override
  State<_SubCategoryCard> createState() => _SubCategoryCardState();
}

class _SubCategoryCardState extends State<_SubCategoryCard> {
  bool _hovered = false;
  bool _pressed = false;

  void _openEditSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => CategoryEditSheet(
        docId:            widget.docId,
        initialName:      widget.name,
        initialIconName:  widget.iconName,
        initialImageUrl:  widget.imageUrl,
        initialCardScale: widget.perCardScale,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Card-level press-down scale.
    final double cardScale  = _pressed ? 0.97 : 1.0;
    // Image zoom on hover / press.
    final double imageScale = _hovered ? 1.06 : (_pressed ? 1.02 : 1.0);

    // perCardScale is intentionally NOT applied — all cells must be identical.
    return MouseRegion(
      cursor:  SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      child: GestureDetector(
      onTap: () {
        CategoryService.incrementClickCount(widget.docId);
        widget.onTap();
      },
      onTapDown:   (_) => setState(() => _pressed = true),
      onTapUp:     (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve:    Curves.easeOut,
        transform: Matrix4.identity()
          ..scaleByDouble(cardScale, cardScale, 1.0, 1.0),
        transformAlignment: Alignment.center,
        // ── White-square card layout: image on top, label below ──────
        child: Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            // ── Fixed-ratio square image — uniform across all items ───
            AspectRatio(
              aspectRatio: 1.0,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // White container with soft shadow
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                              alpha: _hovered ? 0.14 : 0.07),
                          blurRadius:   _hovered ? 18 : 8,
                          spreadRadius: 0,
                          offset: Offset(0, _hovered ? 6 : 3),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: widget.imageUrl.isNotEmpty
                          ? AnimatedScale(
                              scale:    imageScale,
                              duration: const Duration(milliseconds: 320),
                              curve:    Curves.easeOutCubic,
                              child: CachedNetworkImage(
                                imageUrl:       widget.imageUrl,
                                fit:            BoxFit.cover,
                                memCacheWidth:  300,
                                memCacheHeight: 300,
                                fadeInDuration: const Duration(
                                    milliseconds: 260),
                                placeholder: (_, __) => Container(
                                  color: const Color(0xFFF5F5F5),
                                ),
                                errorWidget: (_, __, ___) => Container(
                                  color: const Color(0xFFF0F0FF),
                                  child: Center(
                                    child: Icon(widget.icon,
                                        size: 32,
                                        color: const Color(0xFF6366F1)),
                                  ),
                                ),
                              ),
                            )
                          : Container(
                              color: const Color(0xFFF0F0FF),
                              child: Center(
                                child: Icon(widget.icon,
                                    size: 32,
                                    color: const Color(0xFF6366F1)),
                              ),
                            ),
                    ),
                  ),

                  // ── ✏️ Admin edit button — top-right ─────────────────
                  if (widget.isAdmin)
                    Positioned(
                      top:   8,
                      right: 8,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _openEditSheet,
                        child: Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color:  Colors.black.withValues(alpha: 0.55),
                            shape:  BoxShape.circle,
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.30)),
                          ),
                          child: const Icon(Icons.edit_rounded,
                              size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // ── Sub-category name below the square ────────────────────
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                widget.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color:      Colors.black,
                  fontSize:   13,
                  fontWeight: FontWeight.w600,
                  height:     1.2,
                ),
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),         // closes AnimatedContainer
      ),         // closes GestureDetector
    );           // closes MouseRegion
  }
}

// ── Shimmer skeleton grid shown while sub-categories are loading ──────────────
class _SubCategoryShimmerGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w    = constraints.maxWidth;
          final cols = w >= 900 ? 4 : w >= 600 ? 3 : 2;
          return GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount:   cols,
              crossAxisSpacing: 14,
              mainAxisSpacing:  14,
              childAspectRatio: w >= 900 ? 1.0 : w >= 600 ? 0.90 : 0.85,
            ),
            itemCount: cols * 2, // fill two rows
            itemBuilder: (_, __) => Shimmer.fromColors(
              baseColor:      const Color(0xFFE2E8F0),
              highlightColor: const Color(0xFFF8FAFC),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(22),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
