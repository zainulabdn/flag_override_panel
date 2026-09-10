import 'package:flag_override_panel/flag_override_panel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BoolFlag.parse', () {
    const BoolFlag flag = BoolFlag('b');

    test('accepts booleans and their common encodings', () {
      expect(flag.parse(true), isTrue);
      expect(flag.parse(false), isFalse);
      expect(flag.parse('true'), isTrue);
      expect(flag.parse('false'), isFalse);
      expect(flag.parse(1), isTrue);
      expect(flag.parse(0), isFalse);
    });

    test('rejects anything else', () {
      expect(flag.parse(null), isNull);
      expect(flag.parse('yes'), isNull);
      expect(flag.parse(2), isNull);
    });
  });

  group('StringFlag.parse', () {
    test('stringifies primitives', () {
      const StringFlag flag = StringFlag('s');
      expect(flag.parse('a'), 'a');
      expect(flag.parse(7), '7');
      expect(flag.parse(true), 'true');
      expect(flag.parse(null), isNull);
    });

    test('rejects values outside options', () {
      const StringFlag flag = StringFlag('s', options: <String>['red', 'blue']);
      expect(flag.parse('red'), 'red');
      expect(flag.parse('green'), isNull);
    });
  });

  group('IntFlag.parse', () {
    const IntFlag flag = IntFlag('i');

    test('accepts ints, truncates doubles, parses strings', () {
      expect(flag.parse(3), 3);
      expect(flag.parse(3.7), 3);
      expect(flag.parse('42'), 42);
      expect(flag.parse('-5'), -5);
    });

    test('rejects non-numeric strings', () {
      expect(flag.parse('abc'), isNull);
      expect(flag.parse(null), isNull);
    });
  });

  group('DoubleFlag.parse', () {
    const DoubleFlag flag = DoubleFlag('d');

    test('accepts doubles, widens ints, parses strings', () {
      expect(flag.parse(1.5), 1.5);
      expect(flag.parse(2), 2.0);
      expect(flag.parse('0.25'), 0.25);
    });

    test('rejects non-numeric strings', () {
      expect(flag.parse('abc'), isNull);
    });
  });

  test('flags default to the shared group', () {
    expect(const BoolFlag('b').group, kDefaultFlagGroup);
    expect(const BoolFlag('b', group: 'Checkout').group, 'Checkout');
  });
}
