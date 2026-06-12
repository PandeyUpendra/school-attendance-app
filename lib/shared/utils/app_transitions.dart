import 'package:flutter/material.dart';

enum AppRouteTransition {
  slideAndFade,
  modal,
  fade,
  none,
}

/// Global PageTransitionsBuilder that enforces premium transition style across the entire app
/// for any native page routes (e.g. MaterialPageRoute).
class PremiumPageTransitionsBuilder extends PageTransitionsBuilder {
  const PremiumPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final isFullscreen = route.fullscreenDialog;

    final isReversing = animation.status == AnimationStatus.reverse;
    final curve = isReversing
        ? Curves.easeInCubic
        : const Cubic(0.16, 1, 0.3, 1); // Premium easeOutQuart curve

    final curvedAnim = CurvedAnimation(
      parent: animation,
      curve: curve,
      reverseCurve: curve,
    );

    if (isFullscreen) {
      // Modal transition: gentle scale from 98% to 100% + fade
      final scaleAnim = Tween<double>(begin: 0.98, end: 1.0).animate(curvedAnim);
      final fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(curvedAnim);
      return FadeTransition(
        opacity: fadeAnim,
        child: ScaleTransition(
          scale: scaleAnim,
          child: child,
        ),
      );
    }

    // Default screen transition: subtle slide (16px equivalent fraction) + fade
    final slideAnim = Tween<Offset>(
      begin: const Offset(0.04, 0.0), // ~16px subtle horizontal slide
      end: Offset.zero,
    ).animate(curvedAnim);
    final fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(curvedAnim);

    return FadeTransition(
      opacity: fadeAnim,
      child: SlideTransition(
        position: slideAnim,
        child: child,
      ),
    );
  }
}

/// CustomPageRoute with explicit transitions, custom durations (250ms/200ms)
/// and configurable styles.
class AppPageRoute<T> extends PageRouteBuilder<T> {
  final Widget child;
  final AppRouteTransition transition;
  final bool isFullscreenDialog;

  AppPageRoute({
    required this.child,
    this.transition = AppRouteTransition.slideAndFade,
    this.isFullscreenDialog = false,
    super.settings,
    super.maintainState = true,
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) => child,
          transitionDuration: transition == AppRouteTransition.none
              ? Duration.zero
              : const Duration(milliseconds: 250),
          reverseTransitionDuration: transition == AppRouteTransition.none
              ? Duration.zero
              : const Duration(milliseconds: 200),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            if (transition == AppRouteTransition.none) {
              return child;
            }

            final isReversing = animation.status == AnimationStatus.reverse;
            final curve = isReversing
                ? Curves.easeInCubic
                : const Cubic(0.16, 1, 0.3, 1); // Premium easeOutQuart curve

            final curvedAnim = CurvedAnimation(
              parent: animation,
              curve: curve,
              reverseCurve: curve,
            );

            if (isFullscreenDialog || transition == AppRouteTransition.modal) {
              final scaleAnim = Tween<double>(begin: 0.98, end: 1.0).animate(curvedAnim);
              final fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(curvedAnim);
              return FadeTransition(
                opacity: fadeAnim,
                child: ScaleTransition(
                  scale: scaleAnim,
                  child: child,
                ),
              );
            }

            if (transition == AppRouteTransition.fade) {
              final fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(curvedAnim);
              return FadeTransition(
                opacity: fadeAnim,
                child: child,
              );
            }

            // Slide + Fade (Forward/Back navigation)
            final slideAnim = Tween<Offset>(
              begin: const Offset(0.04, 0.0), // ~16px subtle horizontal slide
              end: Offset.zero,
            ).animate(curvedAnim);
            final fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(curvedAnim);

            return FadeTransition(
              opacity: fadeAnim,
              child: SlideTransition(
                position: slideAnim,
                child: child,
              ),
            );
          },
        );

  @override
  bool get fullscreenDialog => isFullscreenDialog;
}

/// A premium, high-performance TabBarView replacement.
/// Instantly swaps tabs with a micro-fade (150ms) to avoid layout lag and sliding frame drops.
class PremiumTabBarView extends StatefulWidget {
  final List<Widget> children;
  final TabController? controller;

  const PremiumTabBarView({
    super.key,
    required this.children,
    this.controller,
  });

  @override
  State<PremiumTabBarView> createState() => _PremiumTabBarViewState();
}

class _PremiumTabBarViewState extends State<PremiumTabBarView> {
  TabController? _controller;
  int _currentIndex = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateController();
  }

  @override
  void didUpdateWidget(PremiumTabBarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _updateController();
    }
  }

  void _updateController() {
    final TabController? newController = widget.controller ?? DefaultTabController.maybeOf(context);
    if (_controller != newController) {
      if (_controller != null) {
        _controller!.removeListener(_handleTabChange);
      }
      _controller = newController;
      if (_controller != null) {
        _controller!.addListener(_handleTabChange);
        _currentIndex = _controller!.index;
      }
    }
  }

  void _handleTabChange() {
    if (_controller != null && _controller!.index != _currentIndex) {
      setState(() {
        _currentIndex = _controller!.index;
      });
    }
  }

  @override
  void dispose() {
    if (_controller != null) {
      _controller!.removeListener(_handleTabChange);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.children.isEmpty) return const SizedBox.shrink();
    final index = _currentIndex.clamp(0, widget.children.length - 1);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      switchInCurve: Curves.easeIn,
      switchOutCurve: Curves.easeOut,
      child: KeyedSubtree(
        key: ValueKey<int>(index),
        child: widget.children[index],
      ),
    );
  }
}
