import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/edit_dialog.dart';
import '../../core/supabase.dart';
import '../../core/table_data.dart';

const sessionsQuery = ('cash_sessions', 'opened_at');

/// Ouverture et clôture de la caisse ; historique des sessions visibles.
class CashScreen extends ConsumerWidget {
  const CashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(profileProvider).value;
    final db = ref.read(supabaseProvider);
    final sessions =
        ref.watch(rowsProvider(sessionsQuery)).value ?? const <DbRow>[];
    final open = sessions
        .where((s) => s['opened_by'] == me?.id && s['closed_at'] == null)
        .firstOrNull;

    Future<void> run(Future<Object?> Function() action, String ok) async {
      String? error;
      try {
        await action();
        ref.invalidate(rowsProvider(sessionsQuery));
      } on Object catch (e) {
        error = errorText(e);
      }
      if (context.mounted) showResult(context, error, ok: ok);
    }

    Future<void> openSession() async {
      final v = await showEditDialog(
        context,
        title: 'Ouvrir la caisse',
        fields: const [NumberField('opening_float', 'Fonds de caisse')],
      );
      if (v == null) return;
      await run(
        () => db.rpc<String>('open_cash_session', params: v),
        'Caisse ouverte.',
      );
    }

    Future<void> closeSession() async {
      final v = await showEditDialog(
        context,
        title: 'Clôturer la caisse',
        fields: const [NumberField('counted', 'Espèces comptées')],
      );
      if (v == null) return;
      await run(() async {
        final diff = await db.rpc<num>(
          'close_cash_session',
          params: {'session': open!['id'], 'counted': v['counted']},
        );
        if (context.mounted) {
          await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Caisse clôturée'),
              content: Text(
                diff == 0
                    ? 'Aucun écart.'
                    : 'Écart : ${diff > 0 ? '+' : ''}$diff',
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
        return diff;
      }, 'Caisse clôturée.');
    }

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            margin: const EdgeInsets.all(12),
            child: ListTile(
              leading: Icon(
                open == null ? Icons.lock_outline : Icons.lock_open,
              ),
              title: Text(
                open == null
                    ? 'Votre caisse est fermée'
                    : 'Votre caisse est ouverte',
              ),
              subtitle: open == null
                  ? const Text('Ouvrez-la avant tout encaissement en espèces.')
                  : Text(
                      'Depuis ${_time(open['opened_at'])} · fonds ${open['opening_float']} ${open['currency']}',
                    ),
              trailing: FilledButton(
                onPressed: open == null ? openSession : closeSession,
                child: Text(open == null ? 'Ouvrir' : 'Clôturer'),
              ),
            ),
          ),
          Expanded(
            child: RowsView(
              query: sessionsQuery,
              empty: 'Aucune session.',
              itemBuilder: (s) => s['closed_at'] == null
                  ? const SizedBox.shrink()
                  : ListTile(
                      leading: const Icon(Icons.point_of_sale_outlined),
                      title: Text(
                        '${_time(s['opened_at'])} → ${_time(s['closed_at'])}',
                      ),
                      subtitle: Text(
                        'Théorique ${s['expected_amount']} · compté ${s['counted_amount']} · '
                        'écart ${s['difference']} ${s['currency']}',
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

String _time(Object? iso) =>
    DateTime.parse(iso! as String).toLocal().toString().substring(0, 16);
