## 0.2.0

- Overrides can be moved between devices. `FlagManager.exportOverrides()`
  returns them as JSON and `importOverrides()` applies a payload back, so a
  tester can paste their flag state into a bug report and whoever picks it up
  can reproduce it exactly.
- The panel gained a ⋮ menu wiring both to the clipboard. Paste opens
  prefilled from the clipboard, so the round trip is two taps.
- `importOverrides` replaces rather than merges, normalises loose encodings on
  the way in, and skips keys it cannot use — reporting them in
  `FlagImportResult` instead of failing the whole payload.
- Added `FlagManager.overrideCount`.

No breaking changes.

## 0.1.1

- Add screenshots and an animated demo to the README and to pub.dev. They are
  rendered from the example app by `example/tool/capture_test.dart`, so they
  stay in step with what the package actually draws.

No API changes.

## 0.1.0

Initial release.

- `Flag` definitions for `bool`, `String` (free text or a fixed option list),
  `int` and `double`.
- `FlagManager` resolves each flag from a local override, then your own flag
  provider, then the declared default. Overrides only apply when `enabled` is
  true, which defaults to `kDebugMode`.
- `FlagOverridePanel` and `showFlagOverridePanel` list every registered flag,
  grouped and filterable, with a per-flag editor, a per-flag reset and a reset
  all action.
- `FlagScope`, `context.flagValue` and `FlagBuilder` rebuild your UI as soon as
  a flag is overridden.
- Overrides persist through `SharedPreferencesFlagOverrideStore`, or any
  `FlagOverrideStore` you implement. `MemoryFlagOverrideStore` is provided for
  tests.
