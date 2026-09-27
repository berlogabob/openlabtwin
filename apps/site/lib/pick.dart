// One way to pick from a list across the whole site, as the schedule filters always worked: what is picked shows as chips
// with ×, and a search field lists the known values (the browser's own dropdown, a <datalist>). Typing a known value picks
// it; Enter keeps typed text when free text is allowed. Not a @client component: the pages that use it are.
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

class ChipPicker extends StatelessComponent {
  const ChipPicker({
    required this.id,
    required this.caption,
    required this.options,
    required this.picked,
    required this.draft,
    required this.onDraft,
    required this.onAdd,
    required this.onRemove,
    this.chipExtra,
    this.free = true,
    this.placeholder,
    super.key,
  });

  final String id, caption, draft;
  final List<String> options, picked;
  final void Function(String) onDraft, onAdd, onRemove;
  final Component Function(String)? chipExtra; // e.g. a quantity beside the chip's text
  final bool free; // typed text that matches no option may be picked with Enter
  final String? placeholder;

  @override
  Component build(BuildContext context) {
    final known = options.toSet();
    return label(classes: 'picker', [
      .text(caption),
      span(classes: 'chips', [
        for (final v in picked)
          span(classes: 'chip', [
            .text(v),
            if (chipExtra != null) chipExtra!(v),
            button(type: ButtonType.button, attributes: {'aria-label': 'Remove $v'}, onClick: () => onRemove(v), [.text('×')]),
          ]),
        input<String>(
          type: InputType.text,
          value: draft,
          attributes: {'list': '$id-list', 'placeholder': placeholder ?? (picked.isEmpty ? 'any' : 'or…'), 'autocomplete': 'off'},
          onInput: (v) => known.contains(v) ? onAdd(v) : onDraft(v),
          onChange: (v) {
            final t = v.trim();
            if (t.isNotEmpty && (free || known.contains(t))) onAdd(t);
          },
        ),
      ]),
      datalist(id: '$id-list', [for (final v in options) if (!picked.contains(v)) option(value: v, [])]),
    ]);
  }
}
