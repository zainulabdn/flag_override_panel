/// A debug-only panel for viewing and overriding feature flags on-device.
///
/// Declare your flags once, point [FlagManager.source] at whatever provider
/// already serves them, and QA can force any flag on or off from inside the
/// app without waiting for a remote config to propagate.
///
/// ```dart
/// const BoolFlag newCheckout = BoolFlag('new_checkout');
///
/// Future<void> main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   final FlagManager manager = await FlagManager.init(
///     flags: const <Flag<Object>>[newCheckout],
///     store: const SharedPreferencesFlagOverrideStore(),
///   );
///   runApp(FlagScope(manager: manager, child: const MyApp()));
/// }
/// ```
///
/// Overrides only take effect when [FlagManager.enabled] is true, which
/// defaults to `kDebugMode`.
library;

export 'src/flag.dart';
export 'src/flag_builder.dart';
export 'src/flag_manager.dart';
export 'src/flag_override_panel.dart';
export 'src/flag_override_store.dart';
export 'src/flag_scope.dart';
