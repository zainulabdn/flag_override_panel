import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'flag.dart';
import 'flag_manager.dart';
import 'flag_scope.dart';

/// A scrollable list of every registered flag, with an editor for each.
///
/// The panel expects a bounded height: put it in a [Scaffold] body, a sized
/// box, or use [showFlagOverridePanel] to present it as a modal sheet.
///
/// The manager is taken from [manager], else from the nearest [FlagScope],
/// else from [FlagManager.instance].
class FlagOverridePanel extends StatefulWidget {
  /// Creates a panel for the ambient or supplied [manager].
  const FlagOverridePanel({
    this.manager,
    this.title = 'Feature flags',
    this.showSearchField = true,
    super.key,
  });

  /// The manager to read and write. Defaults to the ambient one.
  final FlagManager? manager;

  /// Heading shown at the top of the panel.
  final String title;

  /// Whether to show the filter field above the list.
  final bool showSearchField;

  @override
  State<FlagOverridePanel> createState() => _FlagOverridePanelState();
}

class _FlagOverridePanelState extends State<FlagOverridePanel> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matches(Flag<Object> flag) {
    if (_query.isEmpty) {
      return true;
    }
    final String query = _query.toLowerCase();
    return flag.key.toLowerCase().contains(query) ||
        (flag.description?.toLowerCase().contains(query) ?? false) ||
        flag.group.toLowerCase().contains(query);
  }

  @override
  Widget build(BuildContext context) {
    final FlagManager manager =
        widget.manager ?? FlagScope.maybeOf(context) ?? FlagManager.instance;
    return ListenableBuilder(
      listenable: manager,
      builder: (BuildContext context, _) {
        final Map<String, List<Flag<Object>>> groups =
            <String, List<Flag<Object>>>{
          for (final MapEntry<String, List<Flag<Object>>> entry
              in manager.groupedFlags.entries)
            if (entry.value.where(_matches).isNotEmpty)
              entry.key: entry.value.where(_matches).toList(),
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _PanelHeader(title: widget.title, manager: manager),
            if (!manager.enabled) const _DisabledBanner(),
            if (widget.showSearchField)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  key: const Key('flag_override_panel.search'),
                  controller: _searchController,
                  onChanged: (String value) => setState(() => _query = value),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Filter flags',
                    border: const OutlineInputBorder(),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            tooltip: 'Clear filter',
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                          ),
                  ),
                ),
              ),
            Expanded(
              child: groups.isEmpty
                  ? const _EmptyState()
                  : ListView(
                      key: const Key('flag_override_panel.list'),
                      padding: const EdgeInsets.only(bottom: 24),
                      children: <Widget>[
                        for (final MapEntry<String, List<Flag<Object>>> entry
                            in groups.entries) ...<Widget>[
                          _GroupHeader(label: entry.key),
                          for (final Flag<Object> flag in entry.value)
                            _FlagTile(flag: flag, manager: manager),
                        ],
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.title, required this.manager});

  final String title;
  final FlagManager manager;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleLarge,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (manager.hasOverrides)
            TextButton.icon(
              key: const Key('flag_override_panel.reset_all'),
              icon: const Icon(Icons.restart_alt),
              label: const Text('Reset all'),
              onPressed: () => manager.clearAllOverrides(),
            ),
          _ShareMenu(manager: manager),
        ],
      ),
    );
  }
}

enum _ShareAction { copy, paste }

/// Moves the override set between devices.
///
/// The point is the round trip: a tester copies their overrides into a bug
/// report, and whoever picks it up pastes them back to land on the same state.
class _ShareMenu extends StatelessWidget {
  const _ShareMenu({required this.manager});

  final FlagManager manager;

  Future<void> _copy(BuildContext context) async {
    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
    final int count = manager.overrideCount;
    await Clipboard.setData(ClipboardData(text: manager.exportOverrides()));
    messenger?.showSnackBar(
      SnackBar(
        content: Text('Copied $count override${count == 1 ? '' : 's'}'),
      ),
    );
  }

  Future<void> _paste(BuildContext context) async {
    // Captured before the first await: the menu item this ran from is gone by
    // the time the dialog closes, so its context can no longer be looked up.
    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
    final ClipboardData? clip = await Clipboard.getData(Clipboard.kTextPlain);
    if (!context.mounted) {
      return;
    }
    final String? payload = await showDialog<String>(
      context: context,
      builder: (BuildContext context) =>
          _ImportDialog(initialText: clip?.text ?? ''),
    );
    if (payload == null) {
      return;
    }
    void report(String message) => messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
    try {
      final FlagImportResult result = await manager.importOverrides(payload);
      report(result.describe());
    } on FormatException {
      report('That is not a JSON object of flag keys.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_ShareAction>(
      key: const Key('flag_override_panel.menu'),
      tooltip: 'Share overrides',
      onSelected: (_ShareAction action) async {
        switch (action) {
          case _ShareAction.copy:
            await _copy(context);
          case _ShareAction.paste:
            await _paste(context);
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<_ShareAction>>[
        PopupMenuItem<_ShareAction>(
          key: const Key('flag_override_panel.menu.copy'),
          value: _ShareAction.copy,
          enabled: manager.hasOverrides,
          child: const ListTile(
            leading: Icon(Icons.copy_all),
            title: Text('Copy overrides'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem<_ShareAction>(
          key: Key('flag_override_panel.menu.paste'),
          value: _ShareAction.paste,
          child: ListTile(
            leading: Icon(Icons.content_paste_go),
            title: Text('Paste overrides'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}

/// Collects a pasted payload for [FlagManager.importOverrides].
///
/// Opens prefilled from the clipboard, so the common path — copy on one
/// device, paste on another — is two taps.
class _ImportDialog extends StatefulWidget {
  const _ImportDialog({required this.initialText});

  final String initialText;

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Paste overrides'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'A JSON object of flag key to value. This replaces every '
              'override currently set.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('flag_override_panel.import_field'),
              controller: _controller,
              minLines: 4,
              maxLines: 8,
              autofocus: true,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('flag_override_panel.import_confirm'),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Import'),
        ),
      ],
    );
  }
}

class _DisabledBanner extends StatelessWidget {
  const _DisabledBanner();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.warning_amber, color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Overrides are disabled in this build. Values below come from '
              'your flag provider and any override you set will be stored '
              'but ignored.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('No flags match this filter.'),
        ),
      );
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _FlagTile extends StatelessWidget {
  const _FlagTile({required this.flag, required this.manager});

  final Flag<Object> flag;
  final FlagManager manager;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool overridden = manager.isOverridden(flag);
    return ListTile(
      key: Key('flag_override_panel.tile.${flag.key}'),
      title: Text(flag.key),
      isThreeLine: flag.description != null && overridden,
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (flag.description != null) Text(flag.description!),
          if (overridden)
            Text(
              'Overridden · reverts to ${manager.baseValueOf(flag)}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _FlagControl(flag: flag, manager: manager),
          SizedBox(
            width: 48,
            child: overridden
                ? IconButton(
                    key: Key('flag_override_panel.reset.${flag.key}'),
                    icon: const Icon(Icons.undo),
                    tooltip: 'Reset ${flag.key}',
                    onPressed: () => manager.clearOverride(flag),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

class _FlagControl extends StatelessWidget {
  const _FlagControl({required this.flag, required this.manager});

  final Flag<Object> flag;
  final FlagManager manager;

  @override
  Widget build(BuildContext context) {
    switch (flag) {
      case final BoolFlag boolFlag:
        return Switch(
          key: Key('flag_override_panel.switch.${flag.key}'),
          value: manager.valueOf(boolFlag),
          onChanged: (bool value) => manager.setOverride(boolFlag, value),
        );
      case final StringFlag stringFlag when stringFlag.options.isNotEmpty:
        return _OptionsControl(flag: stringFlag, manager: manager);
      case StringFlag():
        return _TextControl(
          flag: flag,
          manager: manager,
          keyboardType: TextInputType.text,
        );
      case IntFlag():
        return _TextControl(
          flag: flag,
          manager: manager,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(RegExp(r'^-?\d*')),
          ],
        );
      case DoubleFlag():
        return _TextControl(
          flag: flag,
          manager: manager,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*')),
          ],
        );
    }
  }
}

class _OptionsControl extends StatelessWidget {
  const _OptionsControl({required this.flag, required this.manager});

  final StringFlag flag;
  final FlagManager manager;

  @override
  Widget build(BuildContext context) {
    final String current = manager.valueOf(flag);
    // A remote or default value outside `options` must still be selectable,
    // otherwise DropdownButton asserts on a value with no matching item.
    final List<String> items = <String>[
      ...flag.options,
      if (!flag.options.contains(current)) current,
    ];
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 160),
      child: DropdownButton<String>(
        key: Key('flag_override_panel.dropdown.${flag.key}'),
        value: current,
        isDense: true,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        items: <DropdownMenuItem<String>>[
          for (final String option in items)
            DropdownMenuItem<String>(
              value: option,
              child: Text(option, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (String? value) {
          if (value != null) {
            manager.setOverride(flag, value);
          }
        },
      ),
    );
  }
}

class _TextControl extends StatefulWidget {
  const _TextControl({
    required this.flag,
    required this.manager,
    required this.keyboardType,
    this.inputFormatters,
  });

  final Flag<Object> flag;
  final FlagManager manager;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  @override
  State<_TextControl> createState() => _TextControlState();
}

class _TextControlState extends State<_TextControl> {
  late final TextEditingController _controller =
      TextEditingController(text: _currentText);
  late final FocusNode _focusNode = FocusNode()..addListener(_onFocusChange);

  String get _currentText => widget.manager.valueOf(widget.flag).toString();

  @override
  void didUpdateWidget(_TextControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep in step with resets and external changes, but never fight the user
    // while they are typing.
    if (!_focusNode.hasFocus && _controller.text != _currentText) {
      _controller.text = _currentText;
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_onFocusChange)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      _commit(_controller.text);
    }
  }

  void _commit(String text) {
    if (text == _currentText) {
      // Nothing was edited. Committing here anyway would pin an override
      // identical to the value already in effect, every time the field is
      // merely tapped through.
      return;
    }
    final Object? parsed = widget.flag.parse(text);
    if (parsed == null) {
      // Unparseable input: snap back to the value actually in effect.
      _controller.text = _currentText;
      return;
    }
    widget.manager.setOverride(widget.flag, parsed);
    // `parsed` may normalise the text ("2" for a double flag becomes "2.0").
    _controller.text = parsed.toString();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 110,
      child: TextField(
        key: Key('flag_override_panel.field.${widget.flag.key}'),
        controller: _controller,
        focusNode: _focusNode,
        keyboardType: widget.keyboardType,
        inputFormatters: widget.inputFormatters,
        textAlign: TextAlign.end,
        textInputAction: TextInputAction.done,
        onSubmitted: _commit,
        decoration: const InputDecoration(isDense: true),
      ),
    );
  }
}

/// Presents a [FlagOverridePanel] as a modal bottom sheet.
///
/// ```dart
/// IconButton(
///   icon: const Icon(Icons.flag),
///   onPressed: () => showFlagOverridePanel(context),
/// )
/// ```
Future<void> showFlagOverridePanel(
  BuildContext context, {
  FlagManager? manager,
  String title = 'Feature flags',
  double heightFactor = 0.85,
}) {
  final FlagManager resolved =
      manager ?? FlagScope.maybeOf(context) ?? FlagManager.instance;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (BuildContext sheetContext) => FractionallySizedBox(
      heightFactor: heightFactor,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: FlagOverridePanel(manager: resolved, title: title),
      ),
    ),
  );
}
