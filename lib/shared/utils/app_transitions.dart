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
    return child;
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
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          transitionsBuilder: (context, animation, secondaryAnimation, child) => child,
        );

  @override
  bool get fullscreenDialog => isFullscreenDialog;
}

/// A premium, high-performance TabBarView replacement.
/// Supports swiping right and left to navigate between tabs using the native TabBarView.
class PremiumTabBarView extends StatelessWidget {
  final List<Widget> children;
  final TabController? controller;

  const PremiumTabBarView({
    super.key,
    required this.children,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return TabBarView(
      controller: controller,
      children: children,
    );
  }
}
