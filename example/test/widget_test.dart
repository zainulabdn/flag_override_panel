import 'package:flag_override_panel/flag_override_panel.dart';
import 'package:flag_override_panel_example/flags.dart';
import 'package:flag_override_panel_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<FlagManager> pumpExample(WidgetTester tester) async {
  final FlagManager manager = FlagManager(
    flags: appFlags,
    source: remoteConfig,
    enabled: true,
  );
  await tester.pumpWidget(
    FlagScope(manager: manager, child: const ExampleApp()),
  );
  return manager;
}

void main() {
  tearDown(FlagManager.resetInstance);

  testWidgets('starts from the values the remote source reports',
      (WidgetTester tester) async {
    await pumpExample(tester);

    expect(find.text('https://api.staging.example.com'), findsOneWidget);
    expect(find.text('Legacy product list'), findsOneWidget);
    // page_size is 25 from remoteConfig, not the flag's default of 10.
    expect(find.text('Product 25'), findsOneWidget);
  });

  testWidgets('overriding a flag in the panel updates the screen',
      (WidgetTester tester) async {
    final FlagManager manager = await pumpExample(tester);

    await tester.tap(find.byTooltip('Feature flags'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('flag_override_panel.switch.new_product_list')),
    );
    await tester.pumpAndSettle();

    expect(manager.valueOf(newProductList), isTrue);

    await tester.tapAt(const Offset(20, 20)); // dismiss the sheet
    await tester.pumpAndSettle();

    expect(find.text('New product list'), findsOneWidget);
  });

  testWidgets('resetting an override restores the remote value',
      (WidgetTester tester) async {
    final FlagManager manager = await pumpExample(tester);
    await manager.setOverride(pageSize, 2);
    await tester.pumpAndSettle();

    expect(find.text('Product 2'), findsOneWidget);
    expect(find.text('Product 3'), findsNothing);

    await manager.clearAllOverrides();
    await tester.pumpAndSettle();

    expect(find.text('Product 25'), findsOneWidget);
  });
}
