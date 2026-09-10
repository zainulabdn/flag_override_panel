import 'package:flutter/foundation.dart';

import 'flag.dart';
import 'flag_override_store.dart';

/// Reads the value your real flag provider reports for [key].
///
/// Return `null` when the provider does not know [key], or when its value
/// cannot be used; the flag's `defaultValue` is used instead. Wire this to
/// Firebase Remote Config, LaunchDarkly, your own backend, or anything else:
///
/// ```dart
/// source: (String key) => FirebaseRemoteConfig.instance.getValue(key).asString(),
/// ```
typedef FlagSource = Object? Function(String key);

/// Resolves feature flag values and owns the local overrides shown by
/// [FlagOverridePanel].
///
/// Values resolve in a fixed order:
///
/// 1. a local override, if one is set **and** [enabled] is true;
/// 2. the value reported by [source], if any;
/// 3. the flag's `defaultValue`.
///
/// [enabled] defaults to [kDebugMode], so a forgotten override cannot change
/// behaviour in a release build. Overrides are still stored and listed in that
/// case, they simply do not win over [source].
///
/// A [FlagManager] is a [ChangeNotifier] and notifies whenever an override
/// changes, so widgets built with [FlagBuilder] or [FlagScope] rebuild as soon
/// as a flag is toggled in the panel.
class FlagManager extends ChangeNotifier {
  /// Creates a manager for [flags].
  ///
  /// Overrides are not read from [store] until [load] completes; prefer
  /// [FlagManager.init], which does that for you.
  FlagManager({
    required List<Flag<Object>> flags,
    FlagOverrideStore? store,
    this.source,
    bool? enabled,
  })  : _flags = List<Flag<Object>>.unmodifiable(flags),
        _store = store ?? MemoryFlagOverrideStore(),
        enabled = enabled ?? kDebugMode {
    final Set<String> seen = <String>{};
    for (final Flag<Object> flag in _flags) {
      assert(
        seen.add(flag.key),
        'Duplicate flag key "${flag.key}". Flag keys must be unique.',
      );
    }
  }

  /// Creates a manager and loads any persisted overrides before returning.
  ///
  /// Also assigns [instance]. Call this once during startup:
  ///
  /// ```dart
  /// Future<void> main() async {
  ///   WidgetsFlutterBinding.ensureInitialized();
  ///   await FlagManager.init(
  ///     flags: appFlags,
  ///     store: const SharedPreferencesFlagOverrideStore(),
  ///   );
  ///   runApp(const MyApp());
  /// }
  /// ```
  static Future<FlagManager> init({
    required List<Flag<Object>> flags,
    FlagOverrideStore? store,
    FlagSource? source,
    bool? enabled,
  }) async {
    final FlagManager manager = FlagManager(
      flags: flags,
      store: store,
      source: source,
      enabled: enabled,
    );
    await manager.load();
    return instance = manager;
  }

  static FlagManager? _instance;

  /// The manager assigned by [init], or set directly.
  ///
  /// Throws a [StateError] when no manager has been created yet. Prefer
  /// [FlagScope.of] inside widgets; this exists for code with no
  /// [BuildContext].
  static FlagManager get instance {
    final FlagManager? manager = _instance;
    if (manager == null) {
      throw StateError(
        'FlagManager.instance was read before a manager was created. '
        'Call FlagManager.init() during startup, or assign '
        'FlagManager.instance yourself.',
      );
    }
    return manager;
  }

  static set instance(FlagManager manager) => _instance = manager;

  /// Clears [instance]. Intended for `tearDown` in tests.
  @visibleForTesting
  static void resetInstance() => _instance = null;

  final List<Flag<Object>> _flags;
  final FlagOverrideStore _store;
  final Map<String, Object> _overrides = <String, Object>{};

  /// The provider consulted when a flag has no local override.
  final FlagSource? source;

  /// Whether local overrides take effect.
  ///
  /// Defaults to [kDebugMode].
  final bool enabled;

  /// Every registered flag, in declaration order.
  List<Flag<Object>> get flags => _flags;

  /// Whether any override is currently set, regardless of [enabled].
  bool get hasOverrides => _overrides.isNotEmpty;

  /// The registered flags bucketed by [Flag.group], preserving the order in
  /// which groups and flags were declared.
  Map<String, List<Flag<Object>>> get groupedFlags {
    final Map<String, List<Flag<Object>>> grouped =
        <String, List<Flag<Object>>>{};
    for (final Flag<Object> flag in _flags) {
      grouped.putIfAbsent(flag.group, () => <Flag<Object>>[]).add(flag);
    }
    return grouped;
  }

  /// Reads persisted overrides from the store, replacing any held in memory.
  Future<void> load() async {
    final Map<String, Object> stored = await _store.load();
    _overrides
      ..clear()
      ..addAll(stored);
    notifyListeners();
  }

  /// Resolves the current value of [flag].
  T valueOf<T extends Object>(Flag<T> flag) {
    if (enabled) {
      final T? overridden = flag.parse(_overrides[flag.key]);
      if (overridden != null) {
        return overridden;
      }
    }
    final T? remote = flag.parse(source?.call(flag.key));
    if (remote != null) {
      return remote;
    }
    return flag.defaultValue;
  }

  /// Whether [flag] currently has a local override stored.
  bool isOverridden(Flag<Object> flag) => _overrides.containsKey(flag.key);

  /// The raw stored override for [flag], or `null` when there is none.
  Object? rawOverrideOf(Flag<Object> flag) => _overrides[flag.key];

  /// The value [flag] would resolve to with overrides ignored.
  ///
  /// This is what the panel shows as the underlying value a flag will fall
  /// back to once its override is cleared.
  T baseValueOf<T extends Object>(Flag<T> flag) =>
      flag.parse(source?.call(flag.key)) ?? flag.defaultValue;

  /// Overrides [flag] with [value] and persists it.
  Future<void> setOverride<T extends Object>(Flag<T> flag, T value) async {
    _overrides[flag.key] = value;
    notifyListeners();
    await _store.save(_overrides);
  }

  /// Removes the override for [flag], falling back to [source] or the default.
  Future<void> clearOverride(Flag<Object> flag) async {
    if (_overrides.remove(flag.key) == null) {
      return;
    }
    notifyListeners();
    await _store.save(_overrides);
  }

  /// Removes every override.
  Future<void> clearAllOverrides() async {
    if (_overrides.isEmpty) {
      return;
    }
    _overrides.clear();
    notifyListeners();
    await _store.save(_overrides);
  }

  /// A snapshot of every flag's resolved value, keyed by [Flag.key].
  ///
  /// Handy for attaching flag state to a bug report or a log line.
  Map<String, Object> snapshot() => <String, Object>{
        for (final Flag<Object> flag in _flags) flag.key: valueOf(flag),
      };
}
