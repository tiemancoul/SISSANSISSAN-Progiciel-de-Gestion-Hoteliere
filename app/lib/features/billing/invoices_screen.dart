import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/edit_dialog.dart';
import '../../core/supabase.dart';
import '../../core/table_data.dart';
import '../reservations/guests_screen.dart';
import '../reservations/reservations_screen.dart';

const invoicesQuery = ('invoices', 'created_at');
const balancesQuery = ('invoice_balances', 'invoice_id');

const invoiceStatuses = {
  'brouillon': 'Brouillon',
  'validee': 'Validée',
  'annulee': 'Annulée',
};

/// Liste des factures avec leur solde ; création depuis une réservation
/// ou pour un client de passage.
class InvoicesScreen extends ConsumerWidget {
  const InvoicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guests = {
      for (final g
          in ref.watch(rowsProvider(guestsQuery)).value ?? const <DbRow>[])
        g['id'] as String: guestName(g),
    };
    final balances = {
      for (final b
          in ref.watch(rowsProvider(balancesQuery)).value ?? const <DbRow>[])
        b['invoice_id'] as String: b['balance'],
    };

    Future<void> create() async {
      final reservations =
          ref.read(rowsProvider(reservationsQuery)).value ?? const <DbRow>[];
      final values = await showEditDialog(
        context,
        title: 'Nouvelle facture',
        fields: [
          ChoiceField('reservation_id', 'Réservation (facture du séjour)', {
            for (final r in reservations)
              if (r['status'] != 'annulee')
                r['id'] as String:
                    '${r['reference']} · ${guests[r['guest_id']] ?? ''}',
          }, required: false),
          const TextInput(
            'customer_name',
            'Ou client de passage (nom)',
            required: false,
          ),
        ],
      );
      if (values == null || !context.mounted) return;
      final db = ref.read(supabaseProvider);
      String? error;
      String? id;
      try {
        if (values['reservation_id'] != null) {
          id = await db.rpc<String>(
            'invoice_from_reservation',
            params: {'reservation': values['reservation_id']},
          );
        } else if (values['customer_name'] != null) {
          final row = await db
              .from('invoices')
              .insert({
                'hotel_id': ref.read(profileProvider).value?.hotelId,
                'customer_name': values['customer_name'],
                'currency': await baseCurrency(ref),
              })
              .select('id')
              .single();
          id = row['id'] as String;
        } else {
          error = 'Choisissez une réservation ou saisissez un nom.';
        }
        ref.invalidate(rowsProvider(invoicesQuery));
      } on Object catch (e) {
        error = errorText(e);
      }
      if (!context.mounted) return;
      if (id != null) {
        await context.push('/factures/$id');
      } else {
        showResult(context, error);
      }
    }

    return Scaffold(
      body: RowsView(
        query: invoicesQuery,
        empty: 'Aucune facture.',
        itemBuilder: (i) {
          final balance = balances[i['id']];
          return ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: Text(
              '${i['number'] ?? 'Brouillon'} · '
              '${guests[i['guest_id']] ?? i['customer_name'] ?? ''}',
            ),
            subtitle: Text(
              '${invoiceStatuses[i['status']]}'
              '${i['total'] == null ? '' : ' · ${i['total']} ${i['currency']}'}'
              '${i['status'] == 'validee' && balance != null ? ' · reste dû $balance' : ''}',
            ),
            onTap: () => context.push('/factures/${i['id']}'),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: create,
        icon: const Icon(Icons.add),
        label: const Text('Facture'),
      ),
    );
  }
}

/// Code de la devise principale de l'hôtel.
Future<String> baseCurrency(WidgetRef ref) async {
  final rows = await ref.read(rowsProvider(('currencies', 'code')).future);
  return rows.firstWhere((c) => c['is_base'] == true)['code'] as String;
}
