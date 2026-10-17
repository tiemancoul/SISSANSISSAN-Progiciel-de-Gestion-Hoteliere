import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/edit_dialog.dart';
import '../../core/supabase.dart';
import '../../core/table_data.dart';
import '../rooms/rooms_screen.dart' show roomsQuery;
import 'guests_screen.dart';

const reservationsQuery = ('reservations', 'check_in');

const reservationStatuses = {
  'en_attente': 'En attente',
  'confirmee': 'Confirmée',
  'arrivee': 'Arrivée (en séjour)',
  'partie': 'Partie',
  'annulee': 'Annulée',
  'no_show': 'No-show',
};

/// Nuits entre deux dates AAAA-MM-JJ, départ exclu.
int nights(String checkIn, String checkOut) =>
    DateTime.parse(checkOut).difference(DateTime.parse(checkIn)).inDays;

/// Actions proposées selon le statut : (libellé, nouveau statut ou RPC).
List<(String, String)> actionsFor(String status) => switch (status) {
  'en_attente' => [('Confirmer', 'confirmee'), ('Annuler', 'annulee')],
  'confirmee' => [
    ('Enregistrer l\'arrivée', 'rpc:check_in'),
    ('Annuler', 'annulee'),
    ('Marquer no-show', 'no_show'),
  ],
  'arrivee' => [('Enregistrer le départ', 'rpc:check_out')],
  _ => const [],
};

class ReservationsScreen extends ConsumerWidget {
  const ReservationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guests = {
      for (final g
          in ref.watch(rowsProvider(guestsQuery)).value ?? const <DbRow>[])
        g['id'] as String: guestName(g),
    };
    final rooms = {
      for (final r
          in ref.watch(rowsProvider(roomsQuery)).value ?? const <DbRow>[])
        if (r['active'] == true) r['id'] as String: 'Chambre ${r['number']}',
    };

    Future<void> act(DbRow r, String action) async {
      final db = ref.read(supabaseProvider);
      String? error;
      try {
        if (action.startsWith('rpc:')) {
          await db.rpc(action.substring(4), params: {'reservation': r['id']});
        } else {
          await db
              .from('reservations')
              .update({'status': action})
              .eq('id', r['id']);
        }
        ref
          ..invalidate(rowsProvider(reservationsQuery))
          ..invalidate(rowsProvider(roomsQuery));
      } on Object catch (e) {
        error = errorText(e);
      }
      if (context.mounted) {
        showResult(context, error, ok: 'Réservation mise à jour.');
      }
    }

    Future<void> create() async {
      final values = await showEditDialog(
        context,
        title: 'Nouvelle réservation',
        initial: const {'adults': 1, 'children': 0, 'status': 'confirmee'},
        fields: [
          ChoiceField('guest_id', 'Client', guests),
          ChoiceField('room_id', 'Chambre', rooms),
          const DateField('check_in', 'Arrivée'),
          const DateField('check_out', 'Départ'),
          const NumberField('adults', 'Adultes', integer: true),
          const NumberField('children', 'Enfants', integer: true),
          const ChoiceField('status', 'Statut', {
            'confirmee': 'Confirmée',
            'en_attente': 'En attente',
          }),
          const TextInput('notes', 'Notes', required: false, lines: 2),
        ],
      );
      if (values == null || !context.mounted) return;
      final error = await saveRow(ref, reservationsQuery, {
        ...values,
        'hotel_id': ref.read(profileProvider).value?.hotelId,
      });
      if (context.mounted) showResult(context, error);
    }

    return Scaffold(
      body: RowsView(
        query: reservationsQuery,
        empty: guests.isEmpty
            ? 'Aucune réservation. Créez d\'abord un client.'
            : 'Aucune réservation.',
        itemBuilder: (r) {
          final n = nights(r['check_in'] as String, r['check_out'] as String);
          final actions = actionsFor(r['status'] as String);
          return ListTile(
            leading: const Icon(Icons.event_outlined),
            title: Text('${r['reference']} · ${guests[r['guest_id']] ?? ''}'),
            subtitle: Text(
              '${rooms[r['room_id']] ?? ''} · du ${r['check_in']} au ${r['check_out']} '
              '($n nuit${n > 1 ? 's' : ''}) · ${r['nightly_rate']} ${r['currency']} / nuit\n'
              '${reservationStatuses[r['status']]}',
            ),
            isThreeLine: true,
            trailing: actions.isEmpty
                ? null
                : PopupMenuButton<String>(
                    tooltip: 'Actions',
                    onSelected: (a) => act(r, a),
                    itemBuilder: (_) => [
                      for (final (label, a) in actions)
                        PopupMenuItem(value: a, child: Text(label)),
                    ],
                  ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: create,
        icon: const Icon(Icons.add),
        label: const Text('Réservation'),
      ),
    );
  }
}
