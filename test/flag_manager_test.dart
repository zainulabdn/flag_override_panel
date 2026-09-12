import 'dart:convert';

import 'package:flag_override_panel/flag_override_panel.dart';
import 'package:flutter_test/flutter_test.dart';

const BoolFlag newCheckout = BoolFlag(
  'new_checkout',
  description: 'Use the rebuilt checkout flow',
  group: 'Checkout',
);
const IntFlag pageSize = IntFlag('page_size', defaultValue: 20);
const StringFlag theme = StringFlag(
  'theme',
  defaultValue: 'system',
  options: <String>['system', 'light', 'dark'],
);

const List<Flag<Object>> allFlags = <Flag<Object>>[
  newCheckout,
  pageSize,
  theme,
];

void main() {
  tearDown(FlagManager.resetInstance);

  group('resolution order', () {
    test('falls back to the default value', () {
      final FlagManager manager = FlagManager(flags: allFlags, enabled: true);
      expect(manager.valueOf(newCheckout), isFalse);
      expect(manager.valueOf(pageSize), 20);
      expect(manager.valueOf(theme), 'system');
    });

    test('prefers the source over the default', () {
      final FlagManager manager = FlagManager(
        flags: allFlags,
        enabled: true,
        source: (String key) => switch (key) {
          'new_checkout' => true,
          'page_size' => 50,
          _ => null,
        },
      );
      expect(manager.valueOf(newCheckout), isTrue);
      expect(manager.valueOf(pageSize), 50);
      expect(manager.valueOf(theme), 'system');
    });

    test('prefers an override over the source', () async {
      final FlagManager manager = FlagManager(
        flags: allFlags,
        enabled: true,
        source: (String key) => key == 'new_checkout' ? true : null,
      );
      await manager.setOverride(newCheckout, false);
      expect(manager.valueOf(newCheckout), isFalse);
      expect(manager.isOverridden(newCheckout), isTrue);
    });

    test('ignores a source value the flag cannot parse', () {
      final FlagManager manager = FlagManager(
        flags: allFlags,
        enabled: true,
        source: (String key) => 'not a bool',
      );
      expect(manager.valueOf(newCheckout), isFalse);
      // 'not a bool' is outside the declared options, so theme falls back too.
      expect(manager.valueOf(theme), 'system');
    });

    test('baseValueOf reports the value behind an override', () async {
      final FlagManager manager = FlagManager(
        flags: allFlags,
        enabled: true,
        source: (String key) => key == 'page_size' ? 50 : null,
      );
      await manager.setOverride(pageSize, 5);
      expect(manager.valueOf(pageSize), 5);
      expect(manager.baseValueOf(pageSize), 50);
      expect(manager.baseValueOf(newCheckout), isFalse);
    });
  });

  group('enabled', () {
    test('stores overrides but does not apply them when disabled', () async {
      final FlagManager manager = FlagManager(
        flags: allFlags,
        enabled: false,
        source: (String key) => key == 'new_checkout' ? true : null,
      );
      await manager.setOverride(newCheckout, false);
      expect(manager.valueOf(newCheckout), isTrue, reason: 'source wins');
      expect(manager.isOverridden(newCheckout), isTrue);
      expect(manager.rawOverrideOf(newCheckout), isFalse);
    });

    test('defaults to kDebugMode', () {
      // The test runner is a debug build, so overrides are live by default.
      expect(FlagManager(flags: allFlags).enabled, isTrue);
    });
  });

  group('clearing', () {
    test('clearOverride restores the underlying value', () async {
      final FlagManager manager = FlagManager(flags: allFlags, enabled: true);
      await manager.setOverride(pageSize, 99);
      expect(manager.valueOf(pageSize), 99);

      await manager.clearOverride(pageSize);
      expect(manager.isOverridden(pageSize), isFalse);
      expect(manager.valueOf(pageSize), 20);
    });

    test('clearAllOverrides empties every override', () async {
      final FlagManager manager = FlagManager(flags: allFlags, enabled: true);
      await manager.setOverride(pageSize, 99);
      await manager.setOverride(newCheckout, true);
      expect(manager.hasOverrides, isTrue);

      await manager.clearAllOverrides();
      expect(manager.hasOverrides, isFalse);
      expect(manager.valueOf(pageSize), 20);
      expect(manager.valueOf(newCheckout), isFalse);
    });

    test('clearing an unset flag does not notify', () async {
      final FlagManager manager = FlagManager(flags: allFlags, enabled: true);
      int notifications = 0;
      manager.addListener(() => notifications++);

      await manager.clearOverride(pageSize);
      await manager.clearAllOverrides();
      expect(notifications, 0);
    });
  });

  group('persistence', () {
    test('overrides survive a new manager on the same store', () async {
      final MemoryFlagOverrideStore store = MemoryFlagOverrideStore();
      final FlagManager first =
          FlagManager(flags: allFlags, store: store, enabled: true);
      await first.setOverride(theme, 'dark');
      await first.setOverride(pageSize, 5);

      final FlagManager second =
          FlagManager(flags: allFlags, store: store, enabled: true);
      await second.load();
      expect(second.valueOf(theme), 'dark');
      expect(second.valueOf(pageSize), 5);
    });

    test('clearing is persisted too', () async {
      final MemoryFlagOverrideStore store =
          MemoryFlagOverrideStore(<String, Object>{'page_size': 7});
      final FlagManager manager =
          FlagManager(flags: allFlags, store: store, enabled: true);
      await manager.load();
      expect(manager.valueOf(pageSize), 7);

      await manager.clearAllOverrides();
      expect(await store.load(), isEmpty);
    });

    test('init loads overrides and assigns the singleton', () async {
      final FlagManager manager = await FlagManager.init(
        flags: allFlags,
        store: MemoryFlagOverrideStore(<String, Object>{'theme': 'light'}),
        enabled: true,
      );
      expect(manager.valueOf(theme), 'light');
      expect(FlagManager.instance, same(manager));
    });
  });

  group('registry', () {
    test('groups flags in declaration order', () {
      final FlagManager manager = FlagManager(flags: allFlags);
      expect(
        manager.groupedFlags.keys.toList(),
        <String>['Checkout', kDefaultFlagGroup],
      );
      expect(manager.groupedFlags['Checkout'], <Flag<Object>>[newCheckout]);
      expect(
        manager.groupedFlags[kDefaultFlagGroup],
        <Flag<Object>>[pageSize, theme],
      );
    });

    test('snapshot reports every resolved value', () async {
      final FlagManager manager = FlagManager(flags: allFlags, enabled: true);
      await manager.setOverride(newCheckout, true);
      expect(manager.snapshot(), <String, Object>{
        'new_checkout': true,
        'page_size': 20,
        'theme': 'system',
      });
    });

    test('rejects duplicate keys', () {
      expect(
        () => FlagManager(
          flags: const <Flag<Object>>[BoolFlag('dupe'), BoolFlag('dupe')],
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('notifies listeners when an override changes', () async {
      final FlagManager manager = FlagManager(flags: allFlags, enabled: true);
      int notifications = 0;
      manager.addListener(() => notifications++);

      await manager.setOverride(newCheckout, true);
      await manager.clearOverride(newCheckout);
      expect(notifications, 2);
    });
  });

  group('export and import', () {
    test('exports only the flags that were overridden', () async {
      final FlagManager manager = FlagManager(
        flags: allFlags,
        enabled: true,
        source: (String key) => key == 'page_size' ? 50 : null,
      );
      expect(jsonDecode(manager.exportOverrides()), isEmpty);

      await manager.setOverride(newCheckout, true);
      expect(
        jsonDecode(manager.exportOverrides()),
        <String, Object>{'new_checkout': true},
        reason: 'page_size resolves from the source, it was not overridden',
      );
    });

    test('round-trips through a second manager', () async {
      final FlagManager first = FlagManager(flags: allFlags, enabled: true);
      await first.setOverride(newCheckout, true);
      await first.setOverride(pageSize, 7);
      await first.setOverride(theme, 'dark');

      final FlagManager second = FlagManager(flags: allFlags, enabled: true);
      final FlagImportResult result =
          await second.importOverrides(first.exportOverrides());

      expect(result.applied, 3);
      expect(result.hasProblems, isFalse);
      expect(second.snapshot(), first.snapshot());
    });

    test('replaces rather than merges', () async {
      final FlagManager manager = FlagManager(flags: allFlags, enabled: true);
      await manager.setOverride(newCheckout, true);

      await manager.importOverrides('{"page_size": 3}');
      expect(manager.isOverridden(newCheckout), isFalse);
      expect(manager.valueOf(pageSize), 3);
    });

    test('an empty object clears every override', () async {
      final FlagManager manager = FlagManager(flags: allFlags, enabled: true);
      await manager.setOverride(newCheckout, true);

      final FlagImportResult result = await manager.importOverrides('{}');
      expect(result.applied, 0);
      expect(manager.hasOverrides, isFalse);
    });

    test('normalises loose encodings on the way in', () async {
      final FlagManager manager = FlagManager(flags: allFlags, enabled: true);
      await manager.importOverrides('{"new_checkout": "true", "page_size": 9}');

      expect(manager.valueOf(newCheckout), isTrue);
      expect(manager.rawOverrideOf(newCheckout), isTrue,
          reason: 'the string should have been parsed before storing');
      expect(jsonDecode(manager.exportOverrides()),
          <String, Object>{'new_checkout': true, 'page_size': 9});
    });

    test('skips unknown keys and unparseable values, applying the rest',
        () async {
      final FlagManager manager = FlagManager(flags: allFlags, enabled: true);
      final FlagImportResult result = await manager.importOverrides('''
        {
          "new_checkout": true,
          "retired_flag": 1,
          "page_size": "lots",
          "theme": "sepia"
        }
      ''');

      expect(result.applied, 1);
      expect(result.unknownKeys, <String>['retired_flag']);
      expect(result.rejectedKeys, <String>['page_size', 'theme'],
          reason: '"sepia" is outside the declared options');
      expect(result.hasProblems, isTrue);
      expect(manager.valueOf(newCheckout), isTrue);
      expect(manager.valueOf(pageSize), 20);
    });

    test('persists the imported set', () async {
      final MemoryFlagOverrideStore store = MemoryFlagOverrideStore();
      final FlagManager manager =
          FlagManager(flags: allFlags, store: store, enabled: true);
      await manager.importOverrides('{"page_size": 4}');

      expect(await store.load(), <String, Object>{'page_size': 4});
    });

    test('notifies listeners once', () async {
      final FlagManager manager = FlagManager(flags: allFlags, enabled: true);
      int notifications = 0;
      manager.addListener(() => notifications++);

      await manager.importOverrides('{"page_size": 4}');
      expect(notifications, 1);
    });

    test('rejects payloads that are not a JSON object', () async {
      final FlagManager manager = FlagManager(flags: allFlags, enabled: true);
      expect(() => manager.importOverrides('not json'),
          throwsA(isA<FormatException>()));
      expect(() => manager.importOverrides('[1, 2]'),
          throwsA(isA<FormatException>()));
    });

    test('describe summarises what happened', () {
      const FlagImportResult clean = FlagImportResult(
        applied: 1,
        unknownKeys: <String>[],
        rejectedKeys: <String>[],
      );
      expect(clean.describe(), 'Imported 1 override');
      expect(
        const FlagImportResult(
          applied: 2,
          unknownKeys: <String>['a'],
          rejectedKeys: <String>['b'],
        ).describe(),
        'Imported 2 overrides, 1 unknown, 1 rejected',
      );
    });
  });

  test('instance throws a helpful error before init', () {
    expect(() => FlagManager.instance, throwsStateError);
  });
}
