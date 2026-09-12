import 'dart:convert';

import 'package:flag_override_panel/flag_override_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
const StringFlag apiHost = StringFlag('api_host', defaultValue: 'prod');

const List<Flag<Object>> allFlags = <Flag<Object>>[
  newCheckout,
  pageSize,
  theme,
  apiHost,
];

FlagManager buildManager({bool enabled = true, FlagSource? source}) =>
    FlagManager(flags: allFlags, enabled: enabled, source: source);

Widget wrap(FlagManager manager, {Widget? child}) => MaterialApp(
      home: FlagScope(
        manager: manager,
        child: Scaffold(body: child ?? const FlagOverridePanel()),
      ),
    );

void main() {
  tearDown(FlagManager.resetInstance);

  group('FlagOverridePanel', () {
    testWidgets('lists every flag under its group',
        (WidgetTester tester) async {
      await tester.pumpWidget(wrap(buildManager()));

      expect(find.text('CHECKOUT'), findsOneWidget);
      expect(find.text(kDefaultFlagGroup.toUpperCase()), findsOneWidget);
      for (final Flag<Object> flag in allFlags) {
        expect(find.byKey(Key('flag_override_panel.tile.${flag.key}')),
            findsOneWidget);
      }
      expect(find.text('Use the rebuilt checkout flow'), findsOneWidget);
    });

    testWidgets('toggling a switch overrides the flag',
        (WidgetTester tester) async {
      final FlagManager manager = buildManager();
      await tester.pumpWidget(wrap(manager));

      await tester.tap(
          find.byKey(const Key('flag_override_panel.switch.new_checkout')));
      await tester.pumpAndSettle();

      expect(manager.valueOf(newCheckout), isTrue);
      expect(manager.isOverridden(newCheckout), isTrue);
      expect(find.byKey(const Key('flag_override_panel.reset.new_checkout')),
          findsOneWidget);
    });

    testWidgets('the per-flag reset button clears the override',
        (WidgetTester tester) async {
      final FlagManager manager = buildManager();
      await manager.setOverride(newCheckout, true);
      await tester.pumpWidget(wrap(manager));

      await tester
          .tap(find.byKey(const Key('flag_override_panel.reset.new_checkout')));
      await tester.pumpAndSettle();

      expect(manager.isOverridden(newCheckout), isFalse);
      expect(manager.valueOf(newCheckout), isFalse);
      expect(find.byKey(const Key('flag_override_panel.reset.new_checkout')),
          findsNothing);
    });

    testWidgets('reset all appears only with overrides and clears them',
        (WidgetTester tester) async {
      final FlagManager manager = buildManager();
      await tester.pumpWidget(wrap(manager));
      expect(
          find.byKey(const Key('flag_override_panel.reset_all')), findsNothing);

      await manager.setOverride(pageSize, 5);
      await manager.setOverride(newCheckout, true);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('flag_override_panel.reset_all')));
      await tester.pumpAndSettle();

      expect(manager.hasOverrides, isFalse);
      expect(
          find.byKey(const Key('flag_override_panel.reset_all')), findsNothing);
    });

    testWidgets('shows the resolved value each control starts from',
        (WidgetTester tester) async {
      final FlagManager manager =
          buildManager(source: (String key) => key == 'page_size' ? 50 : null);
      await tester.pumpWidget(wrap(manager));

      final TextField field = tester.widget<TextField>(
        find.byKey(const Key('flag_override_panel.field.page_size')),
      );
      expect(field.controller?.text, '50');
    });

    testWidgets('editing a numeric field stores a parsed override',
        (WidgetTester tester) async {
      final FlagManager manager = buildManager();
      await tester.pumpWidget(wrap(manager));

      await tester.enterText(
        find.byKey(const Key('flag_override_panel.field.page_size')),
        '75',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(manager.valueOf(pageSize), 75);
    });

    testWidgets('unparseable input snaps back to the value in effect',
        (WidgetTester tester) async {
      final FlagManager manager = buildManager();
      await tester.pumpWidget(wrap(manager));

      final Finder field =
          find.byKey(const Key('flag_override_panel.field.page_size'));
      await tester.enterText(field, '-');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(manager.isOverridden(pageSize), isFalse);
      expect(tester.widget<TextField>(field).controller?.text, '20');
    });

    testWidgets('tapping through a field without editing overrides nothing',
        (WidgetTester tester) async {
      final FlagManager manager = buildManager();
      await tester.pumpWidget(wrap(manager));

      await tester
          .tap(find.byKey(const Key('flag_override_panel.field.page_size')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const Key('flag_override_panel.field.api_host')));
      await tester.pumpAndSettle();

      expect(manager.hasOverrides, isFalse);
    });

    testWidgets('a string flag with options renders a dropdown',
        (WidgetTester tester) async {
      final FlagManager manager = buildManager();
      await tester.pumpWidget(wrap(manager));

      expect(find.byKey(const Key('flag_override_panel.dropdown.theme')),
          findsOneWidget);
      expect(find.byKey(const Key('flag_override_panel.field.api_host')),
          findsOneWidget);

      await tester
          .tap(find.byKey(const Key('flag_override_panel.dropdown.theme')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('dark').last);
      await tester.pumpAndSettle();

      expect(manager.valueOf(theme), 'dark');
    });

    testWidgets('a value outside the declared options stays selectable',
        (WidgetTester tester) async {
      final FlagManager manager =
          buildManager(source: (String key) => key == 'theme' ? 'sepia' : null);
      // 'sepia' is not in options, so the flag resolves to its default and the
      // dropdown must not assert.
      await tester.pumpWidget(wrap(manager));
      expect(tester.takeException(), isNull);
      expect(manager.valueOf(theme), 'system');
    });

    testWidgets('the filter narrows the list', (WidgetTester tester) async {
      await tester.pumpWidget(wrap(buildManager()));

      await tester.enterText(
        find.byKey(const Key('flag_override_panel.search')),
        'checkout',
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('flag_override_panel.tile.new_checkout')),
          findsOneWidget);
      expect(find.byKey(const Key('flag_override_panel.tile.page_size')),
          findsNothing);

      await tester.enterText(
        find.byKey(const Key('flag_override_panel.search')),
        'zzz',
      );
      await tester.pumpAndSettle();
      expect(find.text('No flags match this filter.'), findsOneWidget);
    });

    testWidgets('warns when overrides are disabled in this build',
        (WidgetTester tester) async {
      await tester.pumpWidget(wrap(buildManager(enabled: false)));
      expect(find.textContaining('Overrides are disabled'), findsOneWidget);

      await tester.pumpWidget(wrap(buildManager()));
      expect(find.textContaining('Overrides are disabled'), findsNothing);
    });

    testWidgets('falls back to FlagManager.instance without a scope',
        (WidgetTester tester) async {
      FlagManager.instance = buildManager();
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: FlagOverridePanel())),
      );
      expect(find.byKey(const Key('flag_override_panel.tile.page_size')),
          findsOneWidget);
    });
  });

  group('copy and paste overrides', () {
    setUp(() {
      // Intercept the platform clipboard so the test owns both ends.
      final Map<String, Object?> clipboard = <String, Object?>{};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform,
              (MethodCall call) async {
        switch (call.method) {
          case 'Clipboard.setData':
            clipboard['text'] = (call.arguments as Map<Object?, Object?>)['text'];
            return null;
          case 'Clipboard.getData':
            return clipboard.isEmpty ? null : <String, Object?>{...clipboard};
          default:
            return null;
        }
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });
    });

    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('flag_override_panel.menu')));
      await tester.pumpAndSettle();
    }

    testWidgets('copy puts the overrides on the clipboard',
        (WidgetTester tester) async {
      final FlagManager manager = buildManager();
      await manager.setOverride(newCheckout, true);
      await manager.setOverride(pageSize, 5);
      await tester.pumpWidget(wrap(manager));

      await openMenu(tester);
      await tester.tap(find.byKey(const Key('flag_override_panel.menu.copy')));
      await tester.pumpAndSettle();

      final ClipboardData? clip = await Clipboard.getData(Clipboard.kTextPlain);
      expect(jsonDecode(clip!.text!),
          <String, Object>{'new_checkout': true, 'page_size': 5});
      expect(find.text('Copied 2 overrides'), findsOneWidget);
    });

    testWidgets('copy is disabled when nothing is overridden',
        (WidgetTester tester) async {
      await tester.pumpWidget(wrap(buildManager()));
      await openMenu(tester);

      final PopupMenuItem<Object?> item = tester.widget<PopupMenuItem<Object?>>(
        find.byKey(const Key('flag_override_panel.menu.copy')),
      );
      expect(item.enabled, isFalse);
    });

    testWidgets('paste opens prefilled from the clipboard and applies it',
        (WidgetTester tester) async {
      await Clipboard.setData(
          const ClipboardData(text: '{"page_size": 42, "theme": "dark"}'));
      final FlagManager manager = buildManager();
      await tester.pumpWidget(wrap(manager));

      await openMenu(tester);
      await tester.tap(find.byKey(const Key('flag_override_panel.menu.paste')));
      await tester.pumpAndSettle();

      final TextField field = tester.widget<TextField>(
        find.byKey(const Key('flag_override_panel.import_field')),
      );
      expect(field.controller?.text, '{"page_size": 42, "theme": "dark"}');

      await tester
          .tap(find.byKey(const Key('flag_override_panel.import_confirm')));
      await tester.pumpAndSettle();

      expect(manager.valueOf(pageSize), 42);
      expect(manager.valueOf(theme), 'dark');
      expect(find.text('Imported 2 overrides'), findsOneWidget);
    });

    testWidgets('cancelling the paste dialog changes nothing',
        (WidgetTester tester) async {
      await Clipboard.setData(const ClipboardData(text: '{"page_size": 42}'));
      final FlagManager manager = buildManager();
      await tester.pumpWidget(wrap(manager));

      await openMenu(tester);
      await tester.tap(find.byKey(const Key('flag_override_panel.menu.paste')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(manager.hasOverrides, isFalse);
    });

    testWidgets('a bad payload reports instead of throwing',
        (WidgetTester tester) async {
      await Clipboard.setData(const ClipboardData(text: 'nonsense'));
      final FlagManager manager = buildManager();
      await tester.pumpWidget(wrap(manager));

      await openMenu(tester);
      await tester.tap(find.byKey(const Key('flag_override_panel.menu.paste')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const Key('flag_override_panel.import_confirm')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(manager.hasOverrides, isFalse);
      expect(find.textContaining('not a JSON object'), findsOneWidget);
    });

    testWidgets('the panel redraws to match an imported set',
        (WidgetTester tester) async {
      await Clipboard.setData(const ClipboardData(text: '{"new_checkout": true}'));
      final FlagManager manager = buildManager();
      await tester.pumpWidget(wrap(manager));
      expect(find.byKey(const Key('flag_override_panel.reset.new_checkout')),
          findsNothing);

      await openMenu(tester);
      await tester.tap(find.byKey(const Key('flag_override_panel.menu.paste')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const Key('flag_override_panel.import_confirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('flag_override_panel.reset.new_checkout')),
          findsOneWidget);
      expect(find.byKey(const Key('flag_override_panel.reset_all')),
          findsOneWidget);
    });
  });

  group('showFlagOverridePanel', () {
    testWidgets('opens the panel in a modal sheet',
        (WidgetTester tester) async {
      final FlagManager manager = buildManager();
      await tester.pumpWidget(
        wrap(
          manager,
          child: Builder(
            builder: (BuildContext context) => ElevatedButton(
              onPressed: () => showFlagOverridePanel(context),
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Feature flags'), findsOneWidget);
      await tester.tap(
          find.byKey(const Key('flag_override_panel.switch.new_checkout')));
      await tester.pumpAndSettle();
      expect(manager.valueOf(newCheckout), isTrue);
    });
  });

  group('FlagScope and FlagBuilder', () {
    testWidgets('FlagBuilder rebuilds when an override changes',
        (WidgetTester tester) async {
      final FlagManager manager = buildManager();
      await tester.pumpWidget(
        wrap(
          manager,
          child: FlagBuilder<bool>(
            flag: newCheckout,
            builder: (BuildContext context, bool value) =>
                Text(value ? 'new' : 'legacy'),
          ),
        ),
      );
      expect(find.text('legacy'), findsOneWidget);

      await manager.setOverride(newCheckout, true);
      await tester.pumpAndSettle();
      expect(find.text('new'), findsOneWidget);
    });

    testWidgets('context.flagValue rebuilds its widget',
        (WidgetTester tester) async {
      final FlagManager manager = buildManager();
      await tester.pumpWidget(
        wrap(
          manager,
          child: Builder(
            builder: (BuildContext context) =>
                Text('size ${context.flagValue(pageSize)}'),
          ),
        ),
      );
      expect(find.text('size 20'), findsOneWidget);

      await manager.setOverride(pageSize, 3);
      await tester.pumpAndSettle();
      expect(find.text('size 3'), findsOneWidget);
    });

    testWidgets('FlagScope.of throws a helpful error without a scope',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) {
              expect(() => FlagScope.of(context), throwsFlutterError);
              expect(FlagScope.maybeOf(context), isNull);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });
  });
}
