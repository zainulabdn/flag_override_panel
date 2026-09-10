import 'package:flag_override_panel/flag_override_panel.dart';
import 'package:flutter/material.dart';

import 'flags.dart';

/// Stands in for Firebase Remote Config, LaunchDarkly, or your own backend.
///
/// In a real app this closure reads whatever your provider already gives you.
Object? remoteConfig(String key) => switch (key) {
      'page_size' => 25,
      'api_host' => 'https://api.staging.example.com',
      _ => null,
    };

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final FlagManager manager = await FlagManager.init(
    flags: appFlags,
    store: const SharedPreferencesFlagOverrideStore(),
    source: remoteConfig,
    // `enabled` defaults to kDebugMode, so overrides are inert in a release
    // build. Pass `enabled: true` if you also ship a QA/internal flavour.
  );
  runApp(FlagScope(manager: manager, child: const ExampleApp()));
}

/// Root widget of the example.
class ExampleApp extends StatelessWidget {
  /// Creates the example app.
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Reading a flag through the scope rebuilds this widget when it is
    // overridden from the panel, so the theme changes as you toggle it.
    final ThemeMode mode = switch (context.flagValue(themeMode)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    return MaterialApp(
      title: 'flag_override_panel example',
      themeMode: mode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
      ),
      home: const CatalogueScreen(),
    );
  }
}

/// A screen whose contents are driven entirely by feature flags.
class CatalogueScreen extends StatelessWidget {
  /// Creates the catalogue screen.
  const CatalogueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Catalogue'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.flag_outlined),
            tooltip: 'Feature flags',
            onPressed: () => showFlagOverridePanel(context),
          ),
        ],
      ),
      body: ListView(
        children: <Widget>[
          const _HostBanner(),
          FlagBuilder<bool>(
            flag: newProductList,
            builder: (BuildContext context, bool isNew) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                isNew ? 'New product list' : 'Legacy product list',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const _ProductCards(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showFlagOverridePanel(context),
        icon: const Icon(Icons.tune),
        label: const Text('Flags'),
      ),
    );
  }
}

class _HostBanner extends StatelessWidget {
  const _HostBanner();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: ListTile(
          leading: const Icon(Icons.cloud_outlined),
          title: const Text('API host'),
          // `api_host` has no override at startup, so this shows the value
          // `remoteConfig` returns until you change it in the panel.
          subtitle: Text(context.flagValue(apiHost)),
        ),
      ),
    );
  }
}

class _ProductCards extends StatelessWidget {
  const _ProductCards();

  @override
  Widget build(BuildContext context) {
    final int count = context.flagValue(pageSize).clamp(0, 50);
    final double radius = context.flagValue(cardRadius);
    final bool isNew = context.flagValue(newProductList);
    return Column(
      children: <Widget>[
        for (int i = 0; i < count; i++)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Container(
              height: isNew ? 88 : 56,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(radius),
              ),
              child: Text('Product ${i + 1}'),
            ),
          ),
      ],
    );
  }
}
