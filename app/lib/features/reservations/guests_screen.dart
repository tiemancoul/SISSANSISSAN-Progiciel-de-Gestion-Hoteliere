import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/edit_dialog.dart';
import '../../core/supabase.dart';
import '../../core/table_data.dart';

const guestsQuery = ('guests', 'last_name');

const guestFields = [
  TextInput('last_name', 'Nom'),
  TextInput('first_name', 'Prénom', required: false),
  TextInput('phone', 'Téléphone', required: false),
  TextInput('email', 'E-mail', required: false),
  TextInput('nationality', 'Nationalité', required: false),
  TextInput('id_document', 'Pièce d\'identité (type et n°)', required: false),
  TextInput('notes', 'Notes', required: false, lines: 3),
];

String guestName(DbRow g) =>
    [g['last_name'], g['first_name']].whereType<String>().join(' ');

/// Fiches clients, avec recherche par nom ou téléphone.
class GuestsScreen extends ConsumerStatefulWidget {
  const GuestsScreen({super.key});

  @override
  ConsumerState<GuestsScreen> createState() => _GuestsScreenState();
}

class _GuestsScreenState extends ConsumerState<GuestsScreen> {
  String _search = '';

  Future<void> _edit([DbRow? row]) async {
    final values = await showEditDialog(
      context,
      title: row == null ? 'Nouveau client' : 'Client',
      fields: guestFields,
      initial: row ?? const {},
    );
    if (values == null || !mounted) return;
    final error = await saveRow(ref, guestsQuery, {
      ...values,
      if (row == null) 'hotel_id': ref.read(profileProvider).value?.hotelId,
    }, id: row?['id']);
    if (mounted) showResult(context, error);
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.toLowerCase();
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Rechercher (nom, téléphone)',
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          Expanded(
            child: RowsView(
              query: guestsQuery,
              empty: 'Aucun client.',
              itemBuilder: (g) =>
                  !'${guestName(g)} ${g['phone'] ?? ''}'.toLowerCase().contains(
                    q,
                  )
                  ? const SizedBox.shrink()
                  : ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(guestName(g)),
                      subtitle: Text(
                        [
                          g['phone'],
                          g['email'],
                        ].whereType<String>().join(' · '),
                      ),
                      onTap: () => _edit(g),
                    ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _edit,
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Nouveau client'),
      ),
    );
  }
}
