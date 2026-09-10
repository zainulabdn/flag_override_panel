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

  test('instance throws a helpful error before init', () {
    expect(() => FlagManager.instance, throwsStateError);
  });
}
