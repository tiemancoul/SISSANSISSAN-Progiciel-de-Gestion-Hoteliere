import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/edit_dialog.dart';
import '../../core/supabase.dart';
import '../../core/table_data.dart';

const _hotel = ('hotels', 'name');
const _settings = ('hotel_settings', 'hotel_id');
const _currencies = ('currencies', 'code');
const _rates = ('exchange_rates', 'valid_from');
const _taxes = ('taxes', 'name');

const _identityFields = [
  TextInput('name', 'Nom commercial'),
  TextInput('legal_name', 'Raison sociale', required: false),
  TextInput('address', 'Adresse', required: false, lines: 2),
  TextInput('phone', 'Téléphone', required: false),
  TextInput('email', 'E-mail', required: false),
  TextInput('tax_id', 'N° fiscal (NIF / RCCM)', required: false),
  TextInput('timezone', 'Fuseau horaire (ex. Africa/Bamako)'),
];

const _rulesFields = [
  TextInput('check_in_time', 'Heure d\'arrivée (HH:MM)'),
  TextInput('check_out_time', 'Heure de départ (HH:MM)'),
  NumberField(
    'free_cancellation_hours',
    'Annulation gratuite jusqu\'à (heures avant)',
    integer: true,
  ),
  NumberField('deposit_percent', 'Acompte (%)'),
  NumberField(
    'no_show_nights_charged',
    'Nuits facturées en cas de no-show',
    integer: true,
  ),
  BoolField('walk_in_allowed', 'Clients sans réservation acceptés'),
  TextInput(
    'invoice_mentions',
    'Mentions obligatoires sur facture',
    required: false,
    lines: 4,
  ),
];

const _currencyFields = [
  TextInput('code', 'Code ISO (ex. XOF, EUR)'),
  TextInput('name', 'Nom'),
  NumberField('decimals', 'Décimales', integer: true),
  BoolField('is_base', 'Devise principale'),
  BoolField('active', 'Active'),
];

const _taxKinds = {
  'pourcentage': 'Pourcentage',
  'montant_par_nuit': 'Montant fixe par nuit',
};
const _taxScopes = {
  'hebergement': 'Hébergement',
  'restauration': 'Restaurant / bar',
  'prestations': 'Prestations',
  'tout': 'Tout',
};

/// Identité de l'hôtel et règles configurables par le super administrateur.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).value;
    final role = profile?.role;
    final hotelId = profile?.hotelId;
    if (role == null || hotelId == null) return const SizedBox.shrink();
    final rules = role.canEditRules;

    Future<void> edit(
      (String, String) q,
      String title,
      List<Field> fields,
      DbRow? row, {
      String idColumn = 'id',
      DbRow extra = const {},
    }) async {
      final values = await showEditDialog(
        context,
        title: title,
        fields: fields,
        initial: row ?? const {},
      );
      if (values == null || !context.mounted) return;
      final error = await saveRow(
        ref,
        q,
        {...values, ...extra},
        id: row?[idColumn],
        idColumn: idColumn,
      );
      if (context.mounted) showResult(context, error);
    }

    final currencies = {
      for (final c
          in ref.watch(rowsProvider(_currencies)).value ?? const <DbRow>[])
        c['code'] as String: c['code'] as String,
    };
    final base = (ref.watch(rowsProvider(_currencies)).value ?? const <DbRow>[])
        .where((c) => c['is_base'] == true)
        .map((c) => c['code'])
        .firstOrNull;

    Widget section(String title, Widget body, {VoidCallback? onAdd}) => Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (onAdd != null)
                  IconButton(
                    tooltip: 'Ajouter',
                    onPressed: onAdd,
                    icon: const Icon(Icons.add),
                  ),
              ],
            ),
            SizedBox(height: 220, child: body),
          ],
        ),
      ),
    );

    return ListView(
      children: [
        section(
          'Établissement',
          RowsView(
            query: _hotel,
            itemBuilder: (h) => ListTile(
              title: Text(h['name'] as String),
              subtitle: Text(
                [
                  h['legal_name'],
                  h['address'],
                  h['phone'],
                  h['email'],
                  h['tax_id'],
                ].whereType<String>().join('\n'),
              ),
              trailing: role.canEditIdentity
                  ? const Icon(Icons.edit_outlined)
                  : null,
              onTap: role.canEditIdentity
                  ? () => edit(_hotel, 'Établissement', _identityFields, h)
                  : null,
            ),
          ),
        ),
        section(
          'Règles de séjour',
          RowsView(
            query: _settings,
            empty: rules
                ? 'Touchez + pour définir les règles.'
                : 'Règles non définies.',
            itemBuilder: (s) => ListTile(
              title: Text(
                'Arrivée ${s['check_in_time']} · départ ${s['check_out_time']}',
              ),
              subtitle: Text(
                'Annulation gratuite ${s['free_cancellation_hours']} h avant · '
                'acompte ${s['deposit_percent']} % · no-show '
                '${s['no_show_nights_charged']} nuit(s) · walk-in '
                '${s['walk_in_allowed'] == true ? 'oui' : 'non'}',
              ),
              onTap: rules
                  ? () => edit(
                      _settings,
                      'Règles de séjour',
                      _rulesFields,
                      s,
                      idColumn: 'hotel_id',
                    )
                  : null,
            ),
          ),
          onAdd:
              rules &&
                  (ref.watch(rowsProvider(_settings)).value?.isEmpty ?? false)
              ? () => edit(
                  _settings,
                  'Règles de séjour',
                  _rulesFields,
                  null,
                  extra: {'hotel_id': hotelId},
                )
              : null,
        ),
        section(
          'Devises${base == null ? '' : ' (principale : $base)'}',
          RowsView(
            query: _currencies,
            itemBuilder: (c) => ListTile(
              title: Text('${c['code']} · ${c['name']}'),
              subtitle: Text(
                '${c['is_base'] == true ? 'Principale · ' : ''}'
                '${c['active'] == true ? 'Active' : 'Inactive'}',
              ),
              onTap: rules
                  ? () => edit(
                      _currencies,
                      'Devise',
                      _currencyFields.sublist(1),
                      c,
                      idColumn: 'code',
                    )
                  : null,
            ),
          ),
          onAdd: rules
              ? () => edit(
                  _currencies,
                  'Nouvelle devise',
                  _currencyFields,
                  {'decimals': 2, 'active': true},
                  extra: {'hotel_id': hotelId},
                ).ignore()
              : null,
        ),
        section(
          'Taux de change (1 unité = x ${base ?? 'devise principale'})',
          RowsView(
            query: _rates,
            empty: 'Aucun taux saisi.',
            itemBuilder: (r) => ListTile(
              title: Text('1 ${r['code']} = ${r['rate']} ${base ?? ''}'),
              subtitle: Text('Depuis le ${r['valid_from']}'),
            ),
          ),
          onAdd: rules
              ? () => edit(
                  _rates,
                  'Nouveau taux',
                  [
                    ChoiceField('code', 'Devise', currencies),
                    const NumberField('rate', 'Valeur en devise principale'),
                  ],
                  null,
                  extra: {'hotel_id': hotelId},
                )
              : null,
        ),
        section(
          'Taxes',
          RowsView(
            query: _taxes,
            empty: 'Aucune taxe configurée.',
            itemBuilder: (t) => ListTile(
              title: Text(t['name'] as String),
              subtitle: Text(
                '${t['rate']}${t['kind'] == 'pourcentage' ? ' %' : ' ${t['currency']} / nuit'}'
                ' · ${_taxScopes[t['applies_to']]}'
                '${t['active'] == true ? '' : ' · inactive'}',
              ),
              onTap: rules
                  ? () => edit(_taxes, 'Taxe', _taxFields(currencies), t)
                  : null,
            ),
          ),
          onAdd: rules
              ? () => edit(
                  _taxes,
                  'Nouvelle taxe',
                  _taxFields(currencies),
                  {'active': true, 'applies_to': 'hebergement'},
                  extra: {'hotel_id': hotelId},
                )
              : null,
        ),
      ],
    );
  }
}

List<Field> _taxFields(Map<String, String> currencies) => [
  const TextInput('name', 'Nom (ex. TVA, taxe de séjour)'),
  const ChoiceField('kind', 'Type', _taxKinds),
  const NumberField('rate', 'Taux ou montant'),
  ChoiceField(
    'currency',
    'Devise (montant fixe uniquement)',
    currencies,
    required: false,
  ),
  const ChoiceField('applies_to', 'S\'applique à', _taxScopes),
  const BoolField('active', 'Active'),
];
