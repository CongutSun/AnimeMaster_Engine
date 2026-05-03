import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class SkeletonBlock extends StatelessWidget {
  final double? width;
  final double height;
  final BorderRadiusGeometry borderRadius;

  const SkeletonBlock({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: colors.surfaceContainerHighest.withValues(
        alpha: isDark ? 0.34 : 0.72,
      ),
      highlightColor: colors.surface.withValues(alpha: isDark ? 0.46 : 0.92),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: borderRadius,
        ),
      ),
    );
  }
}

class AnimeGridSkeleton extends StatelessWidget {
  final int itemCount;

  const AnimeGridSkeleton({super.key, this.itemCount = 6});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        final int crossAxisCount = switch (width) {
          < 420 => 3,
          < 720 => 4,
          < 980 => 5,
          _ => 6,
        };
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: itemCount,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 14,
            mainAxisSpacing: 18,
            childAspectRatio: 0.58,
          ),
          itemBuilder: (BuildContext context, int index) {
            return const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: SkeletonBlock(
                    height: double.infinity,
                    borderRadius: BorderRadius.all(Radius.circular(14)),
                  ),
                ),
                SizedBox(height: 10),
                SkeletonBlock(width: double.infinity, height: 12),
                SizedBox(height: 6),
                SkeletonBlock(width: 80, height: 10),
              ],
            );
          },
        );
      },
    );
  }
}
