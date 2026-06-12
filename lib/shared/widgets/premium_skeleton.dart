import 'package:flutter/material.dart';

/// A custom, high-performance shimmer skeleton widget
/// that runs at a solid 60fps using core Flutter transformations.
class PremiumSkeleton extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius borderRadius;

  const PremiumSkeleton({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
  });

  /// Factory for a single text line skeleton
  static Widget textLine({double width = double.infinity, double height = 14}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: PremiumSkeleton(width: width, height: height),
      );

  /// Factory for a generic list item skeleton (avatar + two-line text)
  static Widget listItem({double height = 72}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
        ),
        child: Row(
          children: [
            PremiumSkeleton(width: 48, height: 48, borderRadius: BorderRadius.circular(24)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const PremiumSkeleton(width: 140, height: 16),
                  const SizedBox(height: 8),
                  const PremiumSkeleton(width: 200, height: 12),
                ],
              ),
            ),
          ],
        ),
      );

  /// Factory for a card/tile skeleton
  static Widget card({double height = 150}) => Container(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: SizedBox(
          height: height - 32, // adjust for padding
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PremiumSkeleton(width: 120, height: 18),
              const SizedBox(height: 12),
              const PremiumSkeleton(width: double.infinity, height: 14),
              const SizedBox(height: 8),
              const PremiumSkeleton(width: 200, height: 14),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  PremiumSkeleton(width: 80, height: 28, borderRadius: BorderRadius.all(Radius.circular(6))),
                  PremiumSkeleton(width: 60, height: 20),
                ],
              ),
            ],
          ),
        ),
      );

  @override
  State<PremiumSkeleton> createState() => _PremiumSkeletonState();
}

class _PremiumSkeletonState extends State<PremiumSkeleton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: const [
                Color(0xFFE5E7EB),
                Color(0xFFF3F4F6),
                Color(0xFFE5E7EB),
              ],
              stops: const [0.0, 0.5, 1.0],
              transform: _SlidingGradientTransform(slidePercent: _controller.value),
            ),
          ),
        );
      },
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  final double slidePercent;
  const _SlidingGradientTransform({required this.slidePercent});

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    final double translation = bounds.width * (slidePercent - 0.5) * 2;
    return Matrix4.translationValues(translation, 0.0, 0.0);
  }
}
