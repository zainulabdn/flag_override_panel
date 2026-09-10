# flag_override_panel

A debug-only panel for viewing and overriding feature flags on-device, independent of whatever
serves your flags in production.

Every team that ships feature flags eventually hand-rolls the same debug drawer: a list of flags,
a switch next to each one, and a reset button. This is that drawer, as a package. It does not
replace Firebase Remote Config, LaunchDarkly or your own backend — it sits in front of them so QA
can force a flag on without waiting for a config to propagate.

## Why

- **Force any flag from inside the app.** No backend change, no new build, no propagation delay.
- **See every flag in one place**, with the value actually in effect and where it came from.
- **Overrides persist** across restarts, and clear in one tap.
- **Safe by default.** Overrides only apply when `FlagManager.enabled` is true, which defaults to
  `kDebugMode`. A forgotten override cannot change behaviour in a release build.
- **Provider agnostic.** One closure connects it to whatever you already use.

## Install

```yaml
dependencies:
  flag_override_panel: ^0.1.0
```

## Usage

### 1. Declare your flags

```dart
import 'package:flag_override_panel/flag_override_panel.dart';

const BoolFlag newCheckout = BoolFlag(
  'new_checkout',
  description: 'Use the rebuilt checkout flow',
  group: 'Checkout',
);
const IntFlag pageSize = IntFlag('page_size', defaultValue: 20);
const StringFlag themeMode = StringFlag(
  'theme_mode',
  defaultValue: 'system',
  options: <String>['system', 'light', 'dark'],
);

const List<Flag<Object>> appFlags = <Flag<Object>>[
  newCheckout,
  pageSize,
  themeMode,
];
```

`group` becomes a section heading in the panel. A `StringFlag` with `options` renders as a
dropdown instead of a text field, so QA cannot type a value your app does not handle.

### 2. Create the manager at startup

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final FlagManager manager = await FlagManager.init(
    flags: appFlags,
    store: const SharedPreferencesFlagOverrideStore(),
    source: (String key) => FirebaseRemoteConfig.instance.getValue(key).asString(),
  );
  runApp(FlagScope(manager: manager, child: const MyApp()));
}
```

`source` is optional. Without it, flags resolve to their declared defaults until overridden.

### 3. Read flags

```dart
// Rebuilds when the flag is overridden.
final bool enabled = context.flagValue(newCheckout);

// Or, scoped to a subtree:
FlagBuilder<bool>(
  flag: newCheckout,
  builder: (BuildContext context, bool enabled) =>
      enabled ? const NewCheckout() : const LegacyCheckout(),
)

// Outside the widget tree:
final int size = FlagManager.instance.valueOf(pageSize);
```

### 4. Open the panel

```dart
IconButton(
  icon: const Icon(Icons.flag_outlined),
  onPressed: () => showFlagOverridePanel(context),
)
```

Wire it to a debug menu, a shake gesture, or an internal-only build. `FlagOverridePanel` is a
plain widget, so you can also drop it into a `Scaffold` body as a full screen.

## How a value is resolved

For each flag, in order:

1. the local override, if one is set **and** `FlagManager.enabled` is true;
2. the value returned by `source`, if it parses to the flag's type;
3. the flag's `defaultValue`.

A value that does not parse is skipped rather than thrown — a remote returning `"maybe"` for a
`BoolFlag` falls through to the default instead of crashing. `bool` flags accept `true`/`false`,
`"true"`/`"false"` and `1`/`0`, since providers disagree about encoding.

`baseValueOf` tells you what a flag reverts to, which the panel shows next to every override.

## Release builds

`enabled` defaults to `kDebugMode`. In a release build overrides are still stored and listed, but
`source` wins, and the panel shows a banner saying so. If you ship an internal or QA flavour where
overrides *should* apply, pass it explicitly:

```dart
FlagManager.init(flags: appFlags, enabled: isInternalBuild);
```

## Persistence

`SharedPreferencesFlagOverrideStore` keeps every override in a single JSON preference, so clearing
them touches exactly one key. A corrupt payload is discarded rather than thrown.

Implement `FlagOverrideStore` to store them elsewhere:

```dart
abstract interface class FlagOverrideStore {
  Future<Map<String, Object>> load();
  Future<void> save(Map<String, Object> overrides);
}
```

`MemoryFlagOverrideStore` is the default and is what you want in tests.

## Testing with flags

```dart
testWidgets('shows the new checkout when the flag is on', (WidgetTester tester) async {
  final FlagManager manager = FlagManager(flags: appFlags, enabled: true);
  await manager.setOverride(newCheckout, true);

  await tester.pumpWidget(FlagScope(manager: manager, child: const MyApp()));
  expect(find.byType(NewCheckout), findsOneWidget);
});
```

`FlagManager.snapshot()` returns every resolved value, which is worth attaching to bug reports so
you know which flags were on when something broke.

## Example

A runnable app is in [`example/`](example), where the flags drive the theme, the list length and
the card styling so you can watch the UI change as you toggle them.

## License

MIT
