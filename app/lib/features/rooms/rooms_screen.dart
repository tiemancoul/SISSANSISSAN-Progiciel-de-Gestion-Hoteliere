import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/edit_dialog.dart';
import '../../core/supabase.dart';
import '../../core/table_data.dart';

const roomsQuery = ('rooms', 'number');
const _types = ('room_types', 'name');
const _conference = ('conference_rooms', 'name');
const _amenities = ('amenities', 'name');
const _currencies = ('currencies', 'code');

const roomStatuses = {
  'disponible': 'Disponible',
  'occupee': 'Occupée',
  'nettoyage': 'Nettoyage',
  'maintenance': 'Maintenance',
  'hors_service': 'Hors service',
};

/// Chambres, catégories, salles de conférence et équipements.
class RoomsScreen extends ConsumerWidget {
  const RoomsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).value;
    final canEdit = profile?.role?.canEditCatalog ?? false;
    final hotelId = profile?.hotelId;

    Map<String, String> options((String, String) q, String label) => {
      for (final r in ref.watch(rowsProvider(q)).value ?? const <DbRow>[])
        r['id'] as String? ?? r['code'] as String: r[label] as String,
    };

    Future<void> edit(
      (String, String) q,
      String title,
      List<Field> fields, [
      DbRow? row,
    ]) async {
      final values = await showEditDialog(
        context,
        title: title,
        fields: fields,
        initial: row ?? const {},
      );
      if (values == null || !context.mounted) return;
      final error = await saveRow(ref, q, {
        ...values,
        if (row == null) 'hotel_id': hotelId,
      }, id: row?['id']);
      if (context.mounted) showResult(context, error);
    }

    final currencies = options(_currencies, 'code');

    final roomFields = [
      const TextInput('number', 'Numéro'),
      ChoiceField('room_type_id', 'Catégorie', options(_types, 'name')),
      const TextInput('floor', 'Étage', required: false),
      const ChoiceField('status', 'Statut', roomStatuses),
      const TextInput('notes', 'Notes', required: false, lines: 3),
      const BoolField('active', 'Active'),
    ];
    final typeFields = [
      const TextInput('name', 'Nom'),
      const TextInput('description', 'Description', required: false, lines: 3),
      const NumberField('max_adults', 'Adultes max.', integer: true),
      const NumberField('max_children', 'Enfants max.', integer: true),
      const NumberField('base_rate', 'Tarif par nuit'),
      ChoiceField('currency', 'Devise', currencies),
      const BoolField('active', 'Active'),
    ];
    final conferenceFields = [
      const TextInput('name', 'Nom'),
      const NumberField('capacity', 'Capacité (personnes)', integer: true),
      const NumberField('half_day_rate', 'Tarif demi-journée'),
      const NumberField('full_day_rate', 'Tarif journée'),
      ChoiceField('currency', 'Devise', currencies),
      const TextInput('equipment', 'Équipements', required: false, lines: 2),
      const BoolField('active', 'Active'),
    ];
    const amenityFields = [TextInput('name', 'Nom')];

    final types = options(_types, 'name');

    final tabs = <(String, Widget, VoidCallback)>[
      (
        'Chambres',
        RowsView(
          query: roomsQuery,
          empty: 'Aucune chambre. Créez d\'abord une catégorie.',
          itemBuilder: (r) => ListTile(
            leading: const Icon(Icons.bed_outlined),
            title: Text('Chambre ${r['number']}'),
            subtitle: Text(
              '${types[r['room_type_id']] ?? ''} · '
              '${roomStatuses[r['status']]}'
              '${r['active'] == true ? '' : ' · inactive'}',
            ),
            onTap: canEdit
                ? () => edit(roomsQuery, 'Modifier la chambre', roomFields, r)
                : null,
          ),
        ),
        () => edit(roomsQuery, 'Nouvelle chambre', roomFields, {
          'status': 'disponible',
          'active': true,
        }),
      ),
      (
        'Catégories',
        RowsView(
          query: _types,
          itemBuilder: (r) => ListTile(
            leading: const Icon(Icons.category_outlined),
            title: Text(r['name'] as String),
            subtitle: Text(
              '${r['base_rate']} ${r['currency']} / nuit · '
              '${r['max_adults']} adulte(s), ${r['max_children']} enfant(s)',
            ),
            onTap: canEdit
                ? () => edit(_types, 'Modifier la catégorie', typeFields, r)
                : null,
          ),
        ),
        () => edit(_types, 'Nouvelle catégorie', typeFields, {
          'max_adults': 2,
          'max_children': 0,
          'active': true,
        }),
      ),
      (
        'Salles de conférence',
        RowsView(
          query: _conference,
          itemBuilder: (r) => ListTile(
            leading: const Icon(Icons.meeting_room_outlined),
            title: Text(r['name'] as String),
            subtitle: Text(
              '${r['capacity']} pers. · ${r['half_day_rate']} / '
              '${r['full_day_rate']} ${r['currency']}',
            ),
            onTap: canEdit
                ? () => edit(
                    _conference,
                    'Modifier la salle',
                    conferenceFields,
                    r,
                  )
                : null,
          ),
        ),
        () => edit(_conference, 'Nouvelle salle', conferenceFields, {
          'active': true,
        }),
      ),
      (
        'Équipements',
        RowsView(
          query: _amenities,
          itemBuilder: (r) => ListTile(
            leading: const Icon(Icons.check_circle_outline),
            title: Text(r['name'] as String),
            onTap: canEdit
                ? () => edit(
                    _amenities,
                    'Modifier l\'équipement',
                    amenityFields,
                    r,
                  )
                : null,
          ),
        ),
        () => edit(_amenities, 'Nouvel équipement', amenityFields),
      ),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Builder(
        builder: (context) => Scaffold(
          appBar: TabBar(
            isScrollable: true,
            tabs: [for (final t in tabs) Tab(text: t.$1)],
          ),
          body: TabBarView(children: [for (final t in tabs) t.$2]),
          floatingActionButton: canEdit
              ? FloatingActionButton.extended(
                  onPressed: () =>
                      tabs[DefaultTabController.of(context).index].$3(),
                  icon: const Icon(Icons.add),
                  label: const Text('Ajouter'),
                )
              : null,
        ),
      ),
    );
  }
}
