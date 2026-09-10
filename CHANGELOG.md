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
