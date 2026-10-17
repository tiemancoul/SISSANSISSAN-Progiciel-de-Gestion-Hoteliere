import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:uuid/uuid.dart';

import '../../core/edit_dialog.dart';
import '../../core/supabase.dart';
import '../../core/table_data.dart';
import '../reservations/guests_screen.dart';
import 'documents.dart';
import 'invoices_screen.dart';

const paymentMethods = {
  'especes': 'Espèces',
  'carte': 'Carte bancaire',
  'mobile_money': 'Mobile Money',
  'virement': 'Virement',
};

const itemCategories = {
  'hebergement': 'Hébergement',
  'restauration': 'Restaurant / bar',
  'prestations': 'Prestations',
};

/// Une facture, ses lignes, ses taxes et ses paiements, chargés ensemble.
final invoiceDetailProvider = FutureProvider.family<DbRow, String>((
  ref,
  id,
) async {
  ref.watch(profileProvider);
  return ref
      .watch(supabaseProvider)
      .from('invoices')
      .select('*, invoice_items(*), invoice_taxes(*), payments(*)')
      .eq('id', id)
      .single();
});

class InvoiceScreen extends ConsumerWidget {
  const InvoiceScreen({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(profileProvider).value?.role;
    final detail = ref.watch(invoiceDetailProvider(id));
    final balance = (ref.watch(rowsProvider(balancesQuery)).value ?? const [])
        .where((b) => b['invoice_id'] == id)
        .map((b) => b['balance'])
        .firstOrNull;

    void refresh() => ref
      ..invalidate(invoiceDetailProvider(id))
      ..invalidate(rowsProvider(invoicesQuery))
      ..invalidate(rowsProvider(balancesQuery));

    Future<void> run(Future<Object?> Function() action, String ok) async {
      String? error;
      try {
        await action();
        refresh();
      } on Object catch (e) {
        error = errorText(e);
      }
      if (context.mounted) showResult(context, error, ok: ok);
    }

    final db = ref.read(supabaseProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Facture')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(errorText(e))),
        data: (inv) {
          final draft = inv['status'] == 'brouillon';
          final cur = inv['currency'] as String;
          final items = (inv['invoice_items'] as List).cast<DbRow>();
          final taxes = (inv['invoice_taxes'] as List).cast<DbRow>();
          final payments = (inv['payments'] as List).cast<DbRow>()
            ..sort(
              (a, b) => (a['created_at'] as String).compareTo(
                b['created_at'] as String,
              ),
            );

          Future<void> addItem() async {
            final v = await showEditDialog(
              context,
              title: 'Nouvelle ligne',
              initial: const {'category': 'prestations', 'quantity': 1},
              fields: const [
                TextInput('description', 'Désignation'),
                ChoiceField('category', 'Catégorie', itemCategories),
                NumberField('quantity', 'Quantité'),
                NumberField('unit_price', 'Prix unitaire'),
              ],
            );
            if (v == null) return;
            await run(
              () => db.from('invoice_items').insert({...v, 'invoice_id': id}),
              'Ligne ajoutée.',
            );
          }

          Future<void> pay({bool refund = false}) async {
            final currencies =
                ref.read(rowsProvider(('currencies', 'code'))).value ??
                const [];
            // Une clé par saisie : un double clic ou une nouvelle tentative
            // réseau ne crée pas un second paiement.
            final key = const Uuid().v4();
            final v = await showEditDialog(
              context,
              title: refund
                  ? 'Rembourser'
                  : 'Encaisser (reste dû : $balance $cur)',
              initial: {
                'currency': cur,
                'method': 'especes',
                if (!refund) 'amount': balance,
              },
              fields: [
                const NumberField('amount', 'Montant'),
                ChoiceField('currency', 'Devise', {
                  for (final c in currencies)
                    if (c['active'] == true)
                      c['code'] as String: c['code'] as String,
                }),
                const ChoiceField(
                  'method',
                  'Moyen de paiement',
                  paymentMethods,
                ),
                if (!refund)
                  const NumberField(
                    'cash_received',
                    'Espèces reçues (espèces uniquement)',
                    required: false,
                  ),
                const TextInput(
                  'reference',
                  'Référence (TPE, transaction…)',
                  required: false,
                ),
              ],
            );
            if (v == null) return;
            await run(() async {
              final paymentId = await db.rpc<String>(
                'record_payment',
                params: {
                  'invoice': id,
                  'amount': v['amount'],
                  'currency': v['currency'],
                  'method': v['method'],
                  'idempotency_key': key,
                  'cash_received': v['method'] == 'especes'
                      ? v['cash_received']
                      : null,
                  'reference': v['reference'],
                  'kind': refund ? 'remboursement' : 'paiement',
                },
              );
              final p = await db
                  .from('payments')
                  .select('change_given, currency')
                  .eq('id', paymentId)
                  .single();
              if (p['change_given'] != null && context.mounted) {
                await showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Monnaie à rendre'),
                    content: Text(
                      '${p['change_given']} ${p['currency']}',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    actions: [
                      FilledButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                );
              }
              return paymentId;
            }, refund ? 'Remboursement enregistré.' : 'Paiement enregistré.');
          }

          Future<void> cancel() async {
            final v = await showEditDialog(
              context,
              title: 'Annuler la facture',
              fields: const [TextInput('cancelled_reason', 'Motif')],
            );
            if (v == null) return;
            await run(
              () => db
                  .from('invoices')
                  .update({'status': 'annulee', ...v})
                  .eq('id', id),
              'Facture annulée.',
            );
          }

          Future<void> printDoc({DbRow? payment}) async {
            final format = await showEditDialog(
              context,
              title: payment == null
                  ? 'Imprimer la facture'
                  : 'Imprimer le reçu',
              initial: {'format': payment == null ? 'A4' : 'A5'},
              fields: const [
                ChoiceField('format', 'Format', {'A4': 'A4', 'A5': 'A5'}),
              ],
            );
            if (format == null) return;
            await run(() async {
              final hotel = (await ref.read(
                rowsProvider(('hotels', 'name')).future,
              )).first;
              final settings = await ref.read(
                rowsProvider(('hotel_settings', 'hotel_id')).future,
              );
              final guest = inv['guest_id'] == null
                  ? null
                  : (await ref.read(rowsProvider(guestsQuery).future))
                        .where((g) => g['id'] == inv['guest_id'])
                        .firstOrNull;
              final customer = guest == null
                  ? '${inv['customer_name'] ?? ''}'
                  : guestName(guest);
              final pageFormat = printFormats[format['format']]!;
              final bytes = payment == null
                  ? await invoicePdf(
                      invoice: inv,
                      hotel: hotel,
                      customer: customer,
                      mentions:
                          settings.firstOrNull?['invoice_mentions'] as String?,
                      format: pageFormat,
                    )
                  : await receiptPdf(
                      payment: payment,
                      invoice: inv,
                      hotel: hotel,
                      customer: customer,
                      format: pageFormat,
                    );
              return Printing.layoutPdf(
                format: pageFormat,
                name: payment == null
                    ? 'Facture ${inv['number']}'
                    : 'Reçu ${inv['number']}',
                onLayout: (_) async => bytes,
              );
            }, 'Document envoyé à l\'impression.');
          }

          final manager = role?.canEditIdentity ?? false;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '${inv['number'] ?? 'Brouillon'} · ${invoiceStatuses[inv['status']]}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (inv['cancelled_reason'] != null)
                Text('Motif d\'annulation : ${inv['cancelled_reason']}'),
              const Divider(),
              for (final it in items)
                ListTile(
                  title: Text(it['description'] as String),
                  subtitle: Text(
                    '${itemCategories[it['category']]} · '
                    '${it['quantity']} × ${it['unit_price']} $cur',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${it['amount']} $cur'),
                      if (draft)
                        IconButton(
                          tooltip: 'Supprimer la ligne',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => run(
                            () => db
                                .from('invoice_items')
                                .delete()
                                .eq('id', it['id']),
                            'Ligne supprimée.',
                          ),
                        ),
                    ],
                  ),
                ),
              if (!draft) ...[
                const Divider(),
                _line('Sous-total', '${inv['subtotal']} $cur'),
                for (final t in taxes)
                  _line(
                    '${t['name']} (${t['kind'] == 'pourcentage' ? '${t['rate']} %' : '${t['rate']} × ${t['base']} nuit(s)'})',
                    '${t['amount']} $cur',
                  ),
                _line('Total', '${inv['total']} $cur', bold: true),
                if (inv['status'] == 'validee')
                  _line('Reste dû', '${balance ?? '…'} $cur', bold: true),
              ],
              if (payments.isNotEmpty) ...[
                const Divider(),
                Text(
                  'Paiements',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final p in payments)
                  ListTile(
                    dense: true,
                    trailing: IconButton(
                      tooltip: 'Imprimer le reçu',
                      icon: const Icon(Icons.print_outlined),
                      onPressed: () => printDoc(payment: p),
                    ),
                    title: Text(
                      '${p['kind'] == 'remboursement' ? 'Remboursement' : 'Paiement'} · '
                      '${paymentMethods[p['method']]} · ${p['amount']} ${p['currency']}',
                    ),
                    subtitle: Text(
                      [
                        (p['created_at'] as String)
                            .substring(0, 16)
                            .replaceFirst('T', ' '),
                        if (p['currency'] != cur)
                          '= ${p['amount_invoice']} $cur',
                        if (p['cash_received'] != null)
                          'reçu ${p['cash_received']}, rendu ${p['change_given']}',
                        if (p['reference'] != null) p['reference'],
                      ].join(' · '),
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (draft) ...[
                    OutlinedButton.icon(
                      onPressed: addItem,
                      icon: const Icon(Icons.add),
                      label: const Text('Ajouter une ligne'),
                    ),
                    FilledButton.icon(
                      onPressed: () => run(
                        () => db.rpc<String>(
                          'finalize_invoice',
                          params: {'invoice': id},
                        ),
                        'Facture validée.',
                      ),
                      icon: const Icon(Icons.check),
                      label: const Text('Valider la facture'),
                    ),
                  ],
                  if (!draft)
                    OutlinedButton.icon(
                      onPressed: printDoc,
                      icon: const Icon(Icons.print_outlined),
                      label: const Text('Imprimer la facture'),
                    ),
                  if (inv['status'] == 'validee') ...[
                    FilledButton.icon(
                      onPressed: pay,
                      icon: const Icon(Icons.payments_outlined),
                      label: const Text('Encaisser'),
                    ),
                    if (manager)
                      OutlinedButton(
                        onPressed: () => pay(refund: true),
                        child: const Text('Rembourser'),
                      ),
                    if (manager)
                      OutlinedButton(
                        onPressed: cancel,
                        child: const Text('Annuler la facture'),
                      ),
                  ],
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _line(String label, String value, {bool bold = false}) {
    final style = bold ? const TextStyle(fontWeight: FontWeight.bold) : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}
