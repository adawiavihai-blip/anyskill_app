import 'package:flutter/material.dart';

import '../../../constants/quick_tags.dart';
import '../../../l10n/app_localizations.dart';
import 'tokens.dart';

/// Provider quick-tag chips ("recommended", "fast response", etc.).
///
/// Extracted from `expert_profile_screen.dart` in §81 (C.3). Pure render —
/// reads from `data['quickTags']` and looks up each key via
/// `quickTagByKey()` from the shared constants file.
class QuickTagsSection extends StatelessWidget {
  const QuickTagsSection({super.key, required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final tagKeys = ((data['quickTags'] as List?) ?? []).cast<String>();
    final resolved = tagKeys
        .map(quickTagByKey)
        .whereType<Map<String, String>>()
        .toList();
    if (resolved.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: resolved
          .map((t) => Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: ExpertProfileTokens.purpleSoft,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: ExpertProfileTokens.purple
                          .withValues(alpha: 0.2)),
                ),
                child: Text(
                  '${t['emoji']} ${t['label']}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: ExpertProfileTokens.purple),
                ),
              ))
          .toList(),
    );
  }
}

/// Provider bio/about section with "read more" / "show less" toggle.
///
/// Extracted from `expert_profile_screen.dart` in §81 (C.3). The expanded
/// state is purely UI-local, so this is a `StatefulWidget` that owns it —
/// the parent no longer needs `_bioExpanded` on its State class.
class BioSection extends StatefulWidget {
  const BioSection({super.key, required this.data});

  final Map<String, dynamic> data;

  @override
  State<BioSection> createState() => _BioSectionState();
}

class _BioSectionState extends State<BioSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bio = widget.data['aboutMe'] as String? ?? l10n.expertBioPlaceholder;
    const maxLines = 3;
    final isLong = bio.split('\n').length > maxLines || bio.length > 160;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          bio,
          textAlign: TextAlign.right,
          maxLines: _expanded ? null : maxLines,
          overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 15, height: 1.6, color: Colors.grey[800]),
        ),
        if (isLong)
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _expanded ? l10n.expertBioShowLess : l10n.expertBioReadMore,
                style: const TextStyle(
                    color: ExpertProfileTokens.purple,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
      ],
    );
  }
}
