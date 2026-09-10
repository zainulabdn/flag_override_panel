/// The default group name used when a [Flag] does not declare one.
const String kDefaultFlagGroup = 'General';

/// Definition of a single feature flag.
///
/// A flag is a *declaration*, not a value: it carries the key used to look the
/// flag up, the value to fall back to, and enough metadata for
/// [FlagOverridePanel] to render an appropriate editor.
///
/// Use one of the concrete subtypes: [BoolFlag], [StringFlag], [IntFlag] or
/// [DoubleFlag].
sealed class Flag<T extends Object> {
  /// Creates a flag definition.
  const Flag({
    required this.key,
    required this.defaultValue,
    this.description,
    this.group = kDefaultFlagGroup,
  });

  /// Stable identifier for this flag, shared with your remote flag provider.
  final String key;

  /// Value used when there is neither a local override nor a remote value.
  final T defaultValue;

  /// Human readable explanation shown underneath the flag in the panel.
  final String? description;

  /// Section heading used to group related flags in the panel.
  final String group;

  /// Converts a raw stored or remote [value] into [T].
  ///
  /// Returns `null` when [value] cannot be represented as [T], in which case
  /// the caller falls back to the next source in the resolution chain. Raw
  /// values arrive from JSON and from third-party SDKs, so implementations
  /// accept the common loose encodings (for example `"true"` for a
  /// [BoolFlag]) rather than requiring an exact type match.
  T? parse(Object? value);

  @override
  String toString() => '$runtimeType($key)';
}

/// A boolean feature flag, rendered as a switch in the panel.
final class BoolFlag extends Flag<bool> {
  /// Creates a boolean flag identified by [key].
  const BoolFlag(
    String key, {
    super.defaultValue = false,
    super.description,
    super.group,
  }) : super(key: key);

  @override
  bool? parse(Object? value) => switch (value) {
        final bool v => v,
        'true' => true,
        'false' => false,
        1 => true,
        0 => false,
        _ => null,
      };
}

/// A string feature flag.
///
/// When [options] is non-empty the panel renders a dropdown instead of a free
/// text field, which keeps QA from typing a value the app cannot handle.
final class StringFlag extends Flag<String> {
  /// Creates a string flag identified by [key].
  const StringFlag(
    String key, {
    super.defaultValue = '',
    this.options = const <String>[],
    super.description,
    super.group,
  }) : super(key: key);

  /// Allowed values, or empty to accept any string.
  final List<String> options;

  @override
  String? parse(Object? value) {
    final String? parsed = switch (value) {
      final String v => v,
      final num v => v.toString(),
      final bool v => v.toString(),
      _ => null,
    };
    if (parsed == null) {
      return null;
    }
    if (options.isNotEmpty && !options.contains(parsed)) {
      return null;
    }
    return parsed;
  }
}

/// An integer feature flag, rendered as a numeric text field in the panel.
final class IntFlag extends Flag<int> {
  /// Creates an integer flag identified by [key].
  const IntFlag(
    String key, {
    super.defaultValue = 0,
    super.description,
    super.group,
  }) : super(key: key);

  @override
  int? parse(Object? value) => switch (value) {
        final int v => v,
        final double v => v.toInt(),
        final String v => int.tryParse(v),
        _ => null,
      };
}

/// A double feature flag, rendered as a numeric text field in the panel.
final class DoubleFlag extends Flag<double> {
  /// Creates a double flag identified by [key].
  const DoubleFlag(
    String key, {
    super.defaultValue = 0,
    super.description,
    super.group,
  }) : super(key: key);

  @override
  double? parse(Object? value) => switch (value) {
        final double v => v,
        final int v => v.toDouble(),
        final String v => double.tryParse(v),
        _ => null,
      };
}
