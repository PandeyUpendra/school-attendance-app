import 'package:flutter/material.dart';

import '../theme.dart';

/// Returns true when [error] is a Firestore "composite index still building"
/// failure (`failed-precondition` / `requires an index`).
///
/// A freshly deployed composite index takes a few minutes to build; queries
/// that depend on it fail with one of these messages until it is ready.
bool isIndexBuildingError(Object? error) {
  if (error == null) return false;
  final msg = error.toString();
  return msg.contains('failed-precondition') ||
      msg.contains('requires an index');
}

/// Friendly placeholder shown while a Firestore composite index is still
/// building, instead of a raw red error.
///
/// Pair it with [isIndexBuildingError] at the top of a `StreamBuilder` builder:
///
/// ```dart
/// if (snapshot.hasError && isIndexBuildingError(snapshot.error)) {
///   return IndexBuildingNotice(onRetry: () => setState(() {}));
/// }
/// ```
///
/// [onRetry] should rebuild the host so the query re-subscribes; pass null
/// (e.g. from a StatelessWidget) to hide the retry button.
class IndexBuildingNotice extends StatelessWidget {
  /// Rebuilds the host to re-run the query. Null hides the retry button.
  final VoidCallback? onRetry;

  const IndexBuildingNotice({super.key, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.build_circle, color: AppTheme.warning, size: 40),
          const SizedBox(height: 8),
          const Text(
            'Setting up... Please wait',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Refresh in 2-3 minutes',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
              ),
              child: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }
}
