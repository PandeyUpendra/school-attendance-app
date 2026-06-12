import 'dart:async';
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

    // Premium easeOutQuart curve (fast start, gradual settle)
    const curve = Cubic(0.16, 1, 0.3, 1);
    
    final curvedAnim = CurvedAnimation(
      parent: animation,
      curve: curve,
      reverseCurve: curve,
    );

    final secondaryCurvedAnim = CurvedAnimation(
      parent: secondaryAnimation,
      curve: curve,
      reverseCurve: curve,
    );

    if (isFullscreen) {
      // Modal transition: gentle scale from 95% to 100% + fade
      final scaleAnim = Tween<double>(begin: 0.95, end: 1.0).animate(curvedAnim);
      final fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(curvedAnim);
      return FadeTransition(
        opacity: fadeAnim,
        child: ScaleTransition(
          scale: scaleAnim,
          child: child,
        ),
      );
    }

    // Default screen transition: subtle slide (8% horizontal slide) + fade
    final slideAnim = Tween<Offset>(
      begin: const Offset(0.08, 0.0),
      end: Offset.zero,
    ).animate(curvedAnim);
    final fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(curvedAnim);

    // Secondary transition: underlying screen slides slightly left (3%) when pushed on top
    final secondarySlideAnim = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-0.03, 0.0),
    ).animate(secondaryCurvedAnim);

    return SlideTransition(
      position: secondarySlideAnim,
      child: FadeTransition(
        opacity: fadeAnim,
        child: SlideTransition(
          position: slideAnim,
          child: child,
        ),
      ),
    );
  }
}

/// CustomPageRoute with explicit transitions, custom durations (350ms/250ms)
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
              : const Duration(milliseconds: 350),
          reverseTransitionDuration: transition == AppRouteTransition.none
              ? Duration.zero
              : const Duration(milliseconds: 250),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            if (transition == AppRouteTransition.none) {
              return child;
            }

            const curve = Cubic(0.16, 1, 0.3, 1);
            
            final curvedAnim = CurvedAnimation(
              parent: animation,
              curve: curve,
              reverseCurve: curve,
            );

            final secondaryCurvedAnim = CurvedAnimation(
              parent: secondaryAnimation,
              curve: curve,
              reverseCurve: curve,
            );

            if (isFullscreenDialog || transition == AppRouteTransition.modal) {
              final scaleAnim = Tween<double>(begin: 0.95, end: 1.0).animate(curvedAnim);
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
              begin: const Offset(0.08, 0.0),
              end: Offset.zero,
            ).animate(curvedAnim);
            final fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(curvedAnim);

            final secondarySlideAnim = Tween<Offset>(
              begin: Offset.zero,
              end: const Offset(-0.03, 0.0),
            ).animate(secondaryCurvedAnim);

            return SlideTransition(
              position: secondarySlideAnim,
              child: FadeTransition(
                opacity: fadeAnim,
                child: SlideTransition(
                  position: slideAnim,
                  child: child,
                ),
              ),
            );
          },
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

/// A custom, high-performance entrance animation widget that fades in
/// and slides up its child with a custom delay and offset.
class FadeInUp extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Duration delay;
  final double yOffset;

  const FadeInUp({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 350),
    this.delay = Duration.zero,
    this.yOffset = 16.0,
  });

  @override
  State<FadeInUp> createState() => _FadeInUpState();
}

class _FadeInUpState extends State<FadeInUp> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _slideAnimation;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Cubic(0.16, 1, 0.3, 1),
      ),
    );
    _slideAnimation = Tween<double>(begin: widget.yOffset, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Cubic(0.16, 1, 0.3, 1),
      ),
    );

    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _fadeAnimation.value,
          child: Transform.translate(
            offset: Offset(0.0, _slideAnimation.value),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// A custom, high-performance fade-in transition widget.
class FadeIn extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Duration delay;

  const FadeIn({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 350),
    this.delay = Duration.zero,
  });

  @override
  State<FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<FadeIn> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Cubic(0.16, 1, 0.3, 1),
      ),
    );

    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _fadeAnimation.value,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
