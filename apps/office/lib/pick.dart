// Searchable picker used for office lists that are too long for a plain dropdown.
import 'package:flutter/material.dart';

class Pick<T> extends StatefulWidget {
  const Pick({super.key, required this.label, required this.value, required this.options, required this.onChanged, this.nullText});

  final String label;
  final T? value;
  final List<(T, String)> options;
  final void Function(T?) onChanged;
  final String? nullText;

  @override
  State<Pick<T>> createState() => _PickState<T>();
}

class _PickState<T> extends State<Pick<T>> {
  late final controller = TextEditingController(text: _text(widget.value));

  String _text(T? value) => value == null ? '' : widget.options.firstWhere((o) => o.$1 == value, orElse: () => (value, '')).$2;

  @override
  void didUpdateWidget(covariant Pick<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) controller.text = _text(widget.value);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  // the outlined label floats above the border: the top gap keeps it off the field above
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: _menu(),
      );

  Widget _menu() => DropdownMenu<T?>(
        controller: controller,
        label: Text(widget.label),
        enableFilter: true,
        enableSearch: true,
        requestFocusOnTap: true,
        expandedInsets: EdgeInsets.zero,
        menuHeight: 320,
        trailingIcon: widget.value == null
            ? null
            : IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.close),
                onPressed: () {
                  controller.clear();
                  widget.onChanged(null);
                },
              ),
        dropdownMenuEntries: [
          if (widget.nullText != null) DropdownMenuEntry<T?>(value: null, label: widget.nullText!),
          for (final (value, text) in widget.options) DropdownMenuEntry<T?>(value: value, label: text),
        ],
        onSelected: widget.onChanged,
      );
}
