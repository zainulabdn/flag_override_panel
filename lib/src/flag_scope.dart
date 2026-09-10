import 'package:flutter/widgets.dart';

import 'flag.dart';
import 'flag_manager.dart';

/// Provides a [FlagManager] to the widgets below it and rebuilds them when an
/// override changes.
///
/// ```dart
/// runApp(
///   FlagScope(
///     manager: manager,
///     child: const MyApp(),
///   ),
/// );
/// ```
class FlagScope extends InheritedNotifier<FlagManager> {
  /// Provides [manager] to [child] and its descendants.
  const FlagScope({
    required FlagManager manager,
    required super.child,
    super.key,
  }) : super(notifier: manager);

  /// The nearest enclosing manager, or `null` when there is no [FlagScope]
  /// above [context].
  ///
  /// Registers [context] as a dependency, so its widget rebuilds when an
  /// override changes.
  static FlagManager? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FlagScope>()?.notifier;

  /// The nearest enclosing manager.
  ///
  /// Throws a [FlutterError] when there is no [FlagScope] above [context]; use
  /// [maybeOf] if its absence is expected.
  static FlagManager of(BuildContext context) {
    final FlagManager? manager = maybeOf(context);
    if (manager == null) {
      throw FlutterError.fromParts(<DiagnosticsNode>[
        ErrorSummary('FlagScope.of() called with a context that has no '
            'FlagScope above it.'),
        ErrorHint('Wrap your app in a FlagScope, or read '
            'FlagManager.instance directly if you are not in a widget.'),
        context.describeElement('The context used was'),
      ]);
    }
    return manager;
  }
}

/// Convenience access to feature flags from a [BuildContext].
extension FlagScopeContext on BuildContext {
  /// Resolves [flag] using the nearest [FlagScope], rebuilding this widget
  /// when the flag's override changes.
  T flagValue<T extends Object>(Flag<T> flag) =>
      FlagScope.of(this).valueOf(flag);
}
