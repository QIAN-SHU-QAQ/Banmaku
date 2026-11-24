import 'package:flutter/material.dart';

class CategoryTabs extends StatelessWidget {
  final List<String> categories;
  final String selectedCategory;
  final ValueChanged<String> onCategorySelected;

  const CategoryTabs({
    super.key,
    required this.categories,
    required this.selectedCategory,
    required this.onCategorySelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final height = (MediaQuery.textScalerOf(context).scale(14) + 24).clamp(
      44.0,
      double.infinity,
    );
    final radius = BorderRadius.circular(18);
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final category = categories[index];
          final selected = category == selectedCategory;
          return Semantics(
            selected: selected,
            button: true,
            child: Material(
              color: selected ? colors.primaryContainer : Colors.transparent,
              borderRadius: radius,
              child: InkWell(
                onTap: () => onCategorySelected(category),
                borderRadius: radius,
                focusColor: colors.primary.withValues(alpha: 0.16),
                hoverColor: colors.primary.withValues(alpha: 0.08),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Center(
                    child: Text(
                      category,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color:
                            selected
                                ? colors.onPrimaryContainer
                                : colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
