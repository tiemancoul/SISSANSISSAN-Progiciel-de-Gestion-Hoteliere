import 'package:flutter/material.dart';

/// Champ d'un formulaire de [showEditDialog].
sealed class Field {
  const Field(this.key, this.label, {this.required = true});
  final String key;
  final String label;
  final bool required;
}

class TextInput extends Field {
  const TextInput(super.key, super.label, {super.required, this.lines = 1});
  final int lines;
}

/// Nombre décimal positif ; renvoyé en chaîne pour éviter les flottants
/// (la base stocke en NUMERIC).
class NumberField extends Field {
  const NumberField(
    super.key,
    super.label, {
    super.required,
    this.integer = false,
  });
  final bool integer;
}

class ChoiceField extends Field {
  const ChoiceField(super.key, super.label, this.options, {super.required});

  /// valeur stockée -> libellé affiché
  final Map<String, String> options;
}

class BoolField extends Field {
  const BoolField(super.key, super.label) : super(required: false);
}

final _decimal = RegExp(r'^\d+([.,]\d+)?$');

/// Valide une saisie selon le champ ; renvoie un message d'erreur ou null.
String? validateField(Field f, String? raw) {
  final v = raw?.trim() ?? '';
  if (v.isEmpty) return f.required ? 'Champ requis' : null;
  if (f is NumberField) {
    if (f.integer ? int.tryParse(v) == null : !_decimal.hasMatch(v)) {
      return 'Nombre invalide';
    }
  }
  return null;
}

/// Ouvre un formulaire modal pré-rempli avec [initial] ; renvoie les valeurs
/// saisies (null si annulé). Les champs vides non requis valent null.
Future<Map<String, Object?>?> showEditDialog(
  BuildContext context, {
  required String title,
  required List<Field> fields,
  Map<String, Object?> initial = const {},
}) {
  return showDialog<Map<String, Object?>>(
    context: context,
    builder: (_) => _EditDialog(title: title, fields: fields, initial: initial),
  );
}

class _EditDialog extends StatefulWidget {
  const _EditDialog({
    required this.title,
    required this.fields,
    required this.initial,
  });
  final String title;
  final List<Field> fields;
  final Map<String, Object?> initial;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  final _form = GlobalKey<FormState>();
  late final Map<String, Object?> _values = {
    for (final f in widget.fields)
      f.key: switch (f) {
        BoolField() => widget.initial[f.key] ?? false,
        _ => widget.initial[f.key]?.toString(),
      },
  };

  void _save() {
    if (!_form.currentState!.validate()) return;
    _form.currentState!.save();
    Navigator.pop(context, {
      for (final f in widget.fields)
        f.key: switch (f) {
          NumberField() =>
            (_values[f.key] as String?)
                ?.trim()
                .replaceAll(',', '.')
                .nullIfEmpty,
          TextInput() => (_values[f.key] as String?)?.trim().nullIfEmpty,
          _ => _values[f.key],
        },
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [for (final f in widget.fields) _field(f)],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(onPressed: _save, child: const Text('Enregistrer')),
      ],
    );
  }

  Widget _field(Field f) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: switch (f) {
      BoolField() => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(f.label),
        value: _values[f.key]! as bool,
        onChanged: (v) => setState(() => _values[f.key] = v),
      ),
      ChoiceField(:final options) => DropdownButtonFormField<String>(
        initialValue: options.containsKey(_values[f.key])
            ? _values[f.key] as String?
            : null,
        decoration: InputDecoration(labelText: f.label),
        items: [
          for (final e in options.entries)
            DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
        validator: (v) => validateField(f, v),
        onChanged: (v) => _values[f.key] = v,
      ),
      NumberField() || TextInput() => TextFormField(
        initialValue: _values[f.key] as String?,
        decoration: InputDecoration(labelText: f.label),
        maxLines: f is TextInput ? f.lines : 1,
        keyboardType: f is NumberField
            ? const TextInputType.numberWithOptions(decimal: true)
            : null,
        validator: (v) => validateField(f, v),
        onSaved: (v) => _values[f.key] = v,
      ),
    },
  );
}

extension on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}
