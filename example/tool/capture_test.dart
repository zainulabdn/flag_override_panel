// Capture harness for the images used in the README and in `screenshots:`.
//
// This is not a test of anything — it drives the example app and the panel
// through a scripted sequence and writes the rendered frames to `doc/`. It
// lives under `tool/` so `flutter test` does not pick it up by accident.
//
//     cd example && flutter test tool/capture_test.dart
//
// Then stitch the animation frames into a GIF with `tool/make_gif.sh`.
@TestOn('mac-os')
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flag_override_panel/flag_override_panel.dart';
import 'package:flag_override_panel_example/flags.dart';
import 'package:flag_override_panel_example/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Logical size of the rendered canvas.
const Size kCanvas = Size(1180, 860);

/// Multiplier applied when rasterising a still, so the PNGs stay crisp on a
/// HiDPI display and when pub.dev downscales them into a thumbnail.
const double kStillScale = 2;

/// Animation frames are rasterised at 1x — they get scaled down into the GIF
/// anyway, and there are ~120 of them.
const double kFrameScale = 1;

const Size kPhone = Size(372, 748);
const double kPanelWidth = 560;

final GlobalKey _captureKey = GlobalKey();

Directory get _repoRoot {
  Directory dir = Directory.current;
  if (dir.path.endsWith('example')) {
    dir = dir.parent;
  }
  return dir;
}

Directory get _docDir =>
    Directory('${_repoRoot.path}/doc')..createSync(recursive: true);

Directory get _frameDir =>
    Directory('${_repoRoot.path}/doc/.frames')..createSync(recursive: true);

/// Registers the real Roboto and MaterialIcons faces.
///
/// Without this every glyph rasterises as a filled box, because the test
/// environment ships no fonts of its own.
Future<void> _loadFonts() async {
  final String flutterRoot = Platform.environment['FLUTTER_ROOT'] ??
      (throw StateError(
          'FLUTTER_ROOT is unset; run this through `flutter test`.'));
  final String fonts = '$flutterRoot/bin/cache/artifacts/material_fonts';

  Future<void> load(String family, List<String> files) async {
    final FontLoader loader = FontLoader(family);
    for (final String file in files) {
      final Uint8List bytes = File('$fonts/$file').readAsBytesSync();
      loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  await load('Roboto', <String>[
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]);
  await load('MaterialIcons', <String>['MaterialIcons-Regular.otf']);
}

/// The gradient backdrop both stills and frames are composed on.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Color(0xFF1B1A3A),
              Color(0xFF3B2E63),
              Color(0xFF1F3A63)
            ],
          ),
        ),
        child: Padding(padding: const EdgeInsets.all(40), child: child),
      );
}

/// A rounded, shadowed card — the phone body and the panel sheet share it.
class _Card extends StatelessWidget {
  const _Card(
      {required this.child, required this.radius, this.width, this.height});

  final Widget child;
  final double radius;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 42,
              spreadRadius: -6,
              offset: const Offset(0, 22),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: child,
        ),
      );
}

/// A caption strip, so a still frame explains itself without the README.
class _Caption extends StatelessWidget {
  const _Caption(this.text, {this.icon = Icons.bolt});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, color: Colors.white.withValues(alpha: 0.85), size: 20),
            const SizedBox(width: 10),
            Text(
              text,
              // `flutter test` runs with `--use-test-fonts`, so a style that
              // does not name a family renders every glyph as a filled box.
              style: const TextStyle(
                fontFamily: 'Roboto',
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      );
}

/// The app and the panel side by side, both driven by [manager] so a change
/// made on the right is visible on the left in the same frame.
Widget _showcase(FlagManager manager, {String? caption}) {
  return RepaintBoundary(
    key: _captureKey,
    child: MediaQuery(
      data: const MediaQueryData(size: kCanvas),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: FlagScope(
          manager: manager,
          child: _Backdrop(
            child: Column(
              children: <Widget>[
                if (caption != null) _Caption(caption),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      _Card(
                        radius: 34,
                        width: kPhone.width,
                        height: kPhone.height,
                        child: const ExampleApp(),
                      ),
                      const SizedBox(width: 40),
                      _Card(
                        radius: 22,
                        width: kPanelWidth,
                        height: kPhone.height,
                        child: MaterialApp(
                          debugShowCheckedModeBanner: false,
                          theme: ThemeData(
                            colorScheme:
                                ColorScheme.fromSeed(seedColor: Colors.indigo),
                          ),
                          home: const Scaffold(body: FlagOverridePanel()),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// The panel on its own.
///
/// [height] is sized to the content rather than the canvas, so the card hugs
/// the last flag instead of trailing a band of empty sheet.
Widget _panelOnly(
  FlagManager manager, {
  required String caption,
  IconData icon = Icons.bolt,
  double height = 640,
}) {
  return RepaintBoundary(
    key: _captureKey,
    child: MediaQuery(
      data: const MediaQueryData(size: kCanvas),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: FlagScope(
          manager: manager,
          child: _Backdrop(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _Caption(caption, icon: icon),
                _Card(
                  radius: 24,
                  width: 620,
                  height: height,
                  child: MaterialApp(
                    debugShowCheckedModeBanner: false,
                    theme: ThemeData(
                      colorScheme:
                          ColorScheme.fromSeed(seedColor: Colors.indigo),
                    ),
                    home: const Scaffold(body: FlagOverridePanel()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _write(WidgetTester tester, File target,
    {double scale = kStillScale}) async {
  final RenderRepaintBoundary boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_captureKey));
  // Rasterising is real async work on the engine, which the fake-async zone a
  // widget test runs in will never pump. Without runAsync this simply hangs.
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: scale);
    final ByteData? png =
        await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    target.writeAsBytesSync(png!.buffer.asUint8List());
  });
}

FlagManager _manager({bool enabled = true}) => FlagManager(
      flags: appFlags,
      enabled: enabled,
      source: remoteConfig,
    );

/// Runs [body] with shadows painting and the DEBUG ribbon suppressed.
///
/// Both are global debug flags that the framework asserts are back to their
/// defaults by the time the test body returns, and `addTearDown` callbacks run
/// too late to satisfy that — hence the explicit `finally`.
Future<void> _capturing(
    WidgetTester tester, Future<void> Function() body) async {
  debugDisableShadows = false;
  WidgetsApp.debugAllowBannerOverride = false;
  tester.view
    ..physicalSize = kCanvas
    ..devicePixelRatio = 1.0;
  try {
    await body();
  } finally {
    debugDisableShadows = true;
    WidgetsApp.debugAllowBannerOverride = true;
    tester.view.reset();
  }
}

void main() {
  setUpAll(_loadFonts);

  testWidgets('stills', (WidgetTester tester) async {
    await _capturing(tester, () async {
      // 1. The hero: an override on the right, its effect on the left.
      final FlagManager hero = _manager();
      await hero.setOverride(newProductList, true);
      await hero.setOverride(cardRadius, 26);
      await tester.pumpWidget(_showcase(
        hero,
        caption: 'Flip a flag in the panel, watch the app change',
      ));
      await tester.pumpAndSettle();
      await _write(tester, File('${_docDir.path}/showcase.png'));

      // 2. The panel alone, which becomes the pub.dev thumbnail.
      final FlagManager solo = _manager();
      await solo.setOverride(newProductList, true);
      await solo.setOverride(pageSize, 4);
      await tester.pumpWidget(_panelOnly(
        solo,
        caption: 'Every flag, its value in effect, and what it reverts to',
        icon: Icons.flag_outlined,
      ));
      await tester.pumpAndSettle();
      await _write(tester, File('${_docDir.path}/panel.png'));

      // 3. The release-build safety banner.
      final FlagManager disabled = _manager(enabled: false);
      await disabled.setOverride(newProductList, true);
      await tester.pumpWidget(_panelOnly(
        disabled,
        caption:
            'In a release build, overrides are inert and the panel says so',
        icon: Icons.shield_outlined,
        height: 700,
      ));
      await tester.pumpAndSettle();
      await _write(tester, File('${_docDir.path}/release_build.png'));
    });
  });

  testWidgets('animation frames', (WidgetTester tester) async {
    await _capturing(tester, () async {
      for (final FileSystemEntity entity in _frameDir.listSync()) {
        entity.deleteSync();
      }

      final FlagManager manager = _manager();
      await tester.pumpWidget(_showcase(manager));
      await tester.pumpAndSettle();

      int frame = 0;
      Future<void> shoot(
          {int times = 1,
          Duration step = const Duration(milliseconds: 60)}) async {
        for (int i = 0; i < times; i++) {
          await tester.pump(step);
          await _write(
            tester,
            File('${_frameDir.path}/f${frame.toString().padLeft(4, '0')}.png'),
            scale: kFrameScale,
          );
          frame++;
        }
      }

      Future<void> hold() => shoot(times: 12);
      Future<void> settleShooting() => shoot(times: 8);

      await hold();

      // Toggle the product list on: cards grow.
      await tester.tap(
          find.byKey(const Key('flag_override_panel.switch.new_product_list')));
      await settleShooting();
      await hold();

      // Switch the theme: the whole app on the left flips to dark.
      await tester.tap(
          find.byKey(const Key('flag_override_panel.dropdown.theme_mode')));
      await settleShooting();
      await tester.tap(find.text('dark').last);
      await settleShooting();
      await hold();

      // Round the cards off.
      await tester.enterText(
        find.byKey(const Key('flag_override_panel.field.card_radius')),
        '28',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settleShooting();
      await hold();

      // Show the clipboard round trip exists. Opening the menu is enough —
      // actually copying raises a snack bar whose 4s timeout outlives the
      // rest of the sequence and would sit over the finale.
      await tester.tap(find.byKey(const Key('flag_override_panel.menu')));
      await settleShooting();
      await hold();
      await hold();
      // The menu's dismiss barrier belongs to the panel card's own Navigator,
      // so it is clipped to the card — tapping the backdrop outside it does
      // nothing. Tap empty space inside the card, below the menu.
      await tester.tapAt(const Offset(600, 730));
      await settleShooting();

      // One tap puts everything back.
      await tester.tap(find.byKey(const Key('flag_override_panel.reset_all')));
      await settleShooting();
      await hold();
      await hold();

      stdout.writeln('captured $frame frames in ${_frameDir.path}');
    });
  });
}
