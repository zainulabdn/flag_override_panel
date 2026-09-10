import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistence backend for local flag overrides.
///
/// Overrides are a small map of flag key to primitive value (`bool`, `int`,
/// `double` or `String`). Implement this to store them somewhere other than
/// [SharedPreferences] — for example Hive, or an in-memory map in tests.
abstract interface class FlagOverrideStore {
  /// Reads every persisted override.
  ///
  /// Must return an empty map rather than throwing when nothing has been
  /// written yet or the stored payload is unreadable.
  Future<Map<String, Object>> load();

  /// Replaces the persisted overrides with [overrides].
  Future<void> save(Map<String, Object> overrides);
}

/// A [FlagOverrideStore] that keeps overrides in memory only.
///
/// Overrides are lost when the app restarts. This is the default when
/// [FlagManager] is constructed without a store, and is the store to use in
/// tests.
class MemoryFlagOverrideStore implements FlagOverrideStore {
  /// Creates an in-memory store, optionally seeded with [initialOverrides].
  MemoryFlagOverrideStore([Map<String, Object>? initialOverrides])
      : _overrides = <String, Object>{...?initialOverrides};

  Map<String, Object> _overrides;

  @override
  Future<Map<String, Object>> load() async => <String, Object>{..._overrides};

  @override
  Future<void> save(Map<String, Object> overrides) async {
    _overrides = <String, Object>{...overrides};
  }
}

/// A [FlagOverrideStore] backed by [SharedPreferences].
///
/// All overrides are stored as a single JSON object under [preferenceKey], so
/// clearing them touches exactly one preference and cannot leave stragglers
/// behind.
class SharedPreferencesFlagOverrideStore implements FlagOverrideStore {
  /// Creates a store that reads and writes [preferenceKey].
  const SharedPreferencesFlagOverrideStore({
    this.preferenceKey = defaultPreferenceKey,
  });

  /// The [SharedPreferences] key used when none is supplied.
  static const String defaultPreferenceKey = 'flag_override_panel.overrides';

  /// The [SharedPreferences] key holding the encoded override map.
  final String preferenceKey;

  @override
  Future<Map<String, Object>> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(preferenceKey);
    if (raw == null || raw.isEmpty) {
      return <String, Object>{};
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return <String, Object>{};
      }
      return <String, Object>{
        for (final MapEntry<String, dynamic> entry in decoded.entries)
          if (entry.value != null) entry.key: entry.value as Object,
      };
    } on FormatException catch (error) {
      // A corrupt payload must never take the app down: drop it and start
      // from a clean slate.
      debugPrint('flag_override_panel: discarding corrupt overrides ($error)');
      await prefs.remove(preferenceKey);
      return <String, Object>{};
    }
  }

  @override
  Future<void> save(Map<String, Object> overrides) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (overrides.isEmpty) {
      await prefs.remove(preferenceKey);
      return;
    }
    await prefs.setString(preferenceKey, jsonEncode(overrides));
  }
}
