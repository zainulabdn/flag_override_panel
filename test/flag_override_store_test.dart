import 'dart:convert';

import 'package:flag_override_panel/flag_override_panel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MemoryFlagOverrideStore', () {
    test('round-trips overrides', () async {
      final MemoryFlagOverrideStore store = MemoryFlagOverrideStore();
      expect(await store.load(), isEmpty);

      await store.save(<String, Object>{'a': 1});
      expect(await store.load(), <String, Object>{'a': 1});
    });

    test('copies on save so later mutations do not leak in', () async {
      final MemoryFlagOverrideStore store = MemoryFlagOverrideStore();
      final Map<String, Object> live = <String, Object>{'a': 1};
      await store.save(live);
      live['b'] = 2;
      expect(await store.load(), <String, Object>{'a': 1});
    });
  });

  group('SharedPreferencesFlagOverrideStore', () {
    const SharedPreferencesFlagOverrideStore store =
        SharedPreferencesFlagOverrideStore();

    test('returns an empty map when nothing is stored', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      expect(await store.load(), isEmpty);
    });

    test('reads a stored payload', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.${SharedPreferencesFlagOverrideStore.defaultPreferenceKey}':
            jsonEncode(<String, Object>{'a': true, 'b': 3, 'c': 'x'}),
      });
      expect(
        await store.load(),
        <String, Object>{'a': true, 'b': 3, 'c': 'x'},
      );
    });

    test('writes and reads back through SharedPreferences', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await store.save(<String, Object>{'a': 1.5});
      expect(await store.load(), <String, Object>{'a': 1.5});
    });

    test('removes the preference when saving an empty map', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await store.save(<String, Object>{'a': 1});
      await store.save(<String, Object>{});

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(
          SharedPreferencesFlagOverrideStore.defaultPreferenceKey,
        ),
        isNull,
      );
    });

    test('discards a corrupt payload instead of throwing', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'flutter.${SharedPreferencesFlagOverrideStore.defaultPreferenceKey}':
            'not json',
      });
      expect(await store.load(), isEmpty);

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(
          SharedPreferencesFlagOverrideStore.defaultPreferenceKey,
        ),
        isNull,
        reason: 'the corrupt value should have been cleared',
      );
    });

    test('honours a custom preference key', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      const SharedPreferencesFlagOverrideStore custom =
          SharedPreferencesFlagOverrideStore(preferenceKey: 'my.flags');
      await custom.save(<String, Object>{'a': 1});

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('my.flags'), isNotNull);
      expect(
        prefs.getString(
          SharedPreferencesFlagOverrideStore.defaultPreferenceKey,
        ),
        isNull,
      );
    });
  });
}
