import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../l10n/app_strings.dart';

/// A standardized loading indicator with an accompanying message.
///
/// Used as the "until the data gets loaded" state across every Firestore-backed
/// screen so the loading experience is consistent app-wide.
import 'premium_skeleton.dart';

/// A standardized loading indicator with a premium shimmer skeleton loader.
///
/// Used as the "until the data gets loaded" state across every Firestore-backed
/// screen so the loading experience is consistent app-wide.
class LoadingState extends StatelessWidget {
  /// Message shown beneath the spinner while data is loading.
  final String message;

  const LoadingState({super.key, this.message = 'Loading…'});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        children: List.generate(6, (index) => PremiumSkeleton.listItem()),
      ),
    );
  }
}

/// A standardized empty-state placeholder shown when a load completes but
/// returns no data. Kept scrollable-friendly so it still works inside a
/// [RefreshIndicator] (user can pull to retry even when empty).
class EmptyState extends StatelessWidget {
  final String message;
  final IconData icon;

  const EmptyState({
    super.key,
    this.message = 'Nothing here yet',
    this.icon = Icons.inbox_outlined,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }
}

/// A standardized error-state placeholder shown when a load fails.
class ErrorState extends StatelessWidget {
  final String message;

  const ErrorState({super.key, this.message = 'Could not load data'});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 6),
          Text(
            'Pull down to retry',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }
}

/// Wraps screen content in a [RefreshIndicator] and renders the correct
/// loading / empty / error / loaded state from a single set of flags.
///
/// Designed for screens that hold their data in local state (the common
/// pattern in this app: `_loading` bool + a list/model + an async `_load()`).
///
/// Usage:
/// ```dart
/// RefreshableData(
///   loading: _loading,
///   isEmpty: _items.isEmpty,
///   onRefresh: _load,
///   loadingMessage: 'Loading students…',
///   emptyMessage: 'No students yet',
///   builder: (context) => ListView(children: [...]),
/// )
/// ```
///
/// The loading, empty, and error states are always wrapped in a scrollable so
/// the pull-to-refresh gesture works in every state — the user can pull to
/// retry even while the message is showing.
class RefreshableData extends StatelessWidget {
  /// True while the initial (or a manual) load is in flight AND no data is
  /// available yet to display.
  final bool loading;

  /// True when the load has completed but produced no items.
  final bool isEmpty;

  /// True when the last load failed.
  final bool hasError;

  /// Called when the user pulls to refresh. Must return a Future that
  /// completes when the refresh is done (so the spinner dismisses correctly).
  final Future<void> Function() onRefresh;

  /// Builds the loaded content (typically a scrollable list/column).
  final WidgetBuilder builder;

  final String loadingMessage;
  final String emptyMessage;
  final IconData emptyIcon;
  final String errorMessage;

  /// Accent colour for the refresh spinner.
  final Color color;

  const RefreshableData({
    super.key,
    required this.loading,
    required this.onRefresh,
    required this.builder,
    this.isEmpty = false,
    this.hasError = false,
    this.loadingMessage = 'Loading…',
    this.emptyMessage = 'Nothing here yet',
    this.emptyIcon = Icons.inbox_outlined,
    this.errorMessage = 'Could not load data',
    this.color = AppTheme.primary,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedLoadingMessage = loadingMessage == 'Loading…' ? context.tr('loadingEllipsis') : loadingMessage;
    final resolvedEmptyMessage = emptyMessage == 'Nothing here yet' ? context.tr('nothingHereYet') : emptyMessage;
    final resolvedErrorMessage = errorMessage == 'Could not load data' ? context.tr('couldNotLoadData') : errorMessage;

    Widget child;
    if (loading) {
      child = _scrollable(LoadingState(message: resolvedLoadingMessage));
    } else if (hasError) {
      child = _scrollable(ErrorState(message: resolvedErrorMessage));
    } else if (isEmpty) {
      child = _scrollable(EmptyState(message: resolvedEmptyMessage, icon: emptyIcon));
    } else {
      child = builder(context);
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: color,
      child: child,
    );
  }

  /// Wraps a placeholder in a full-height scrollable so the
  /// [RefreshIndicator] gesture is available even when there is no list.
  Widget _scrollable(Widget placeholder) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(child: placeholder),
        ),
      ),
    );
  }
}
