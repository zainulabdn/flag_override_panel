import 'dart:convert';

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

/// What [FlagManager.importOverrides] made of a payload.
///
/// An import never fails part-way: keys it cannot use are reported here and
/// skipped, so a payload written against an older build of the app still
/// applies everything it legitimately can.
final class FlagImportResult {
  /// Creates a result describing an import.
  const FlagImportResult({
    required this.applied,
    required this.unknownKeys,
    required this.rejectedKeys,
  });

  /// How many overrides were applied.
  final int applied;

  /// Keys in the payload that no registered flag declares.
  ///
  /// Usually a flag that has since been removed, or a typo.
  final List<String> unknownKeys;

  /// Keys of registered flags whose value did not parse to the flag's type.
  ///
  /// For example `"page_size": "lots"`, or a string outside a
  /// [StringFlag.options] list.
  final List<String> rejectedKeys;

  /// Whether anything in the payload had to be skipped.
  bool get hasProblems => unknownKeys.isNotEmpty || rejectedKeys.isNotEmpty;

  /// A one-line summary suitable for a snack bar.
  String describe() {
    final StringBuffer buffer = StringBuffer()
      ..write('Imported $applied override${applied == 1 ? '' : 's'}');
    if (unknownKeys.isNotEmpty) {
      buffer.write(', ${unknownKeys.length} unknown');
    }
    if (rejectedKeys.isNotEmpty) {
      buffer.write(', ${rejectedKeys.length} rejected');
    }
    return buffer.toString();
  }

  @override
  String toString() => 'FlagImportResult(${describe()})';
}

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

  /// How many overrides are currently set, regardless of [enabled].
  int get overrideCount => _overrides.length;

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
  /// Handy for attaching flag state to a bug report or a log line. This is
  /// every flag and the value actually in effect; [exportOverrides] is only
  /// the flags someone deliberately changed.
  Map<String, Object> snapshot() => <String, Object>{
        for (final Flag<Object> flag in _flags) flag.key: valueOf(flag),
      };

  /// Every override currently set, as indented JSON.
  ///
  /// The payload is a flat object of flag key to value — the same shape the
  /// store persists — so it is readable enough to paste into a bug report and
  /// round-trips through [importOverrides]:
  ///
  /// ```json
  /// {
  ///   "new_checkout": true,
  ///   "page_size": 5
  /// }
  /// ```
  ///
  /// Flags left alone are absent rather than written out at their current
  /// value, so importing this reproduces the overrides without pinning
  /// everything else to whatever the exporting device happened to resolve.
  String exportOverrides() =>
      const JsonEncoder.withIndent('  ').convert(_overrides);

  /// Replaces every override with the ones encoded in [json].
  ///
  /// This *replaces* rather than merges: after a successful import the only
  /// overrides set are the ones in the payload, which is what reproducing
  /// someone else's flag state means. An empty object therefore clears them.
  ///
  /// Entries are stored parsed, so loose encodings are normalised on the way
  /// in — `"true"` for a [BoolFlag] lands as `true`. Keys that no flag
  /// declares, and values that do not parse to their flag's type, are skipped
  /// and reported in the [FlagImportResult] instead of failing the import.
  ///
  /// Throws a [FormatException] when [json] is not a JSON object.
  Future<FlagImportResult> importOverrides(String json) async {
    final Object? decoded = jsonDecode(json);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'Expected a JSON object mapping flag keys to values.',
      );
    }

    final Map<String, Flag<Object>> byKey = <String, Flag<Object>>{
      for (final Flag<Object> flag in _flags) flag.key: flag,
    };
    final Map<String, Object> accepted = <String, Object>{};
    final List<String> unknown = <String>[];
    final List<String> rejected = <String>[];

    for (final MapEntry<String, dynamic> entry in decoded.entries) {
      final Flag<Object>? flag = byKey[entry.key];
      if (flag == null) {
        unknown.add(entry.key);
        continue;
      }
      final Object? parsed = flag.parse(entry.value);
      if (parsed == null) {
        rejected.add(entry.key);
        continue;
      }
      accepted[entry.key] = parsed;
    }

    _overrides
      ..clear()
      ..addAll(accepted);
    notifyListeners();
    await _store.save(_overrides);

    return FlagImportResult(
      applied: accepted.length,
      unknownKeys: unknown,
      rejectedKeys: rejected,
    );
  }
}
