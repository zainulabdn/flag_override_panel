# flag_override_panel example

A small catalogue screen whose theme, list length, card radius and API host all come from feature
flags. `remoteConfig` in `lib/main.dart` stands in for Firebase Remote Config or LaunchDarkly, so
you can watch a local override take precedence over a "remote" value.

```sh
flutter run
```

Tap **Flags** (or the flag icon in the app bar) to open the panel, then toggle
`new_product_list`, change `theme_mode`, or set `page_size` to something small. The screen updates
as you edit, and the overrides survive a restart.

Flags are declared in `lib/flags.dart`.
