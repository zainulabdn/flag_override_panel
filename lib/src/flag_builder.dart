import 'package:flutter/widgets.dart';

import 'flag.dart';
import 'flag_manager.dart';
import 'flag_scope.dart';

/// Rebuilds [builder] whenever the resolved value of [flag] changes.
///
/// ```dart
/// FlagBuilder<bool>(
///   flag: newCheckout,
///   builder: (BuildContext context, bool enabled) =>
///       enabled ? const NewCheckout() : const LegacyCheckout(),
/// )
/// ```
///
/// The manager is taken from [manager], else from the nearest [FlagScope],
/// else from [FlagManager.instance].
class FlagBuilder<T extends Object> extends StatelessWidget {
  /// Creates a widget that tracks [flag].
  const FlagBuilder({
    required this.flag,
    required this.builder,
    this.manager,
    super.key,
  });

  /// The flag to resolve.
  final Flag<T> flag;

  /// Called with the current value of [flag].
  final Widget Function(BuildContext context, T value) builder;

  /// The manager to read from. Defaults to the ambient one.
  final FlagManager? manager;

  @override
  Widget build(BuildContext context) {
    final FlagManager resolved =
        manager ?? FlagScope.maybeOf(context) ?? FlagManager.instance;
    return ListenableBuilder(
      listenable: resolved,
      builder: (BuildContext context, _) =>
          builder(context, resolved.valueOf(flag)),
    );
  }
}
