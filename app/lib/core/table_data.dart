import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'supabase.dart';

typedef DbRow = Map<String, dynamic>;

/// Lignes d'une table visibles par l'utilisateur (filtrées par RLS), triées.
final rowsProvider = FutureProvider.family<List<DbRow>, (String, String)>((
  ref,
  query,
) async {
  final (table, orderBy) = query;
  ref.watch(profileProvider);
  return ref.watch(supabaseProvider).from(table).select().order(orderBy);
});

/// Insère (sans [id]) ou met à jour une ligne puis rafraîchit la liste.
/// Renvoie un message d'erreur lisible, ou null en cas de succès.
Future<String?> saveRow(
  WidgetRef ref,
  (String, String) query,
  DbRow values, {
  Object? id,
  String idColumn = 'id',
}) async {
  final db = ref.read(supabaseProvider).from(query.$1);
  try {
    if (id == null) {
      await db.insert(values);
    } else {
      await db.update(values).eq(idColumn, id);
    }
    ref.invalidate(rowsProvider(query));
    return null;
  } on Object catch (e) {
    return errorText(e);
  }
}

void showResult(
  BuildContext context,
  String? error, {
  String ok = 'Enregistré.',
}) {
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(error ?? ok)));
}

/// Liste asynchrone standard : chargement, erreur, vide, données.
class RowsView extends ConsumerWidget {
  const RowsView({
    required this.query,
    required this.itemBuilder,
    this.empty = 'Aucun élément.',
    super.key,
  });

  final (String, String) query;
  final Widget Function(DbRow row) itemBuilder;
  final String empty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(rowsProvider(query))
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(errorText(e))),
          data: (rows) => rows.isEmpty
              ? Center(child: Text(empty))
              : ListView(children: [for (final r in rows) itemBuilder(r)]),
        );
  }
}
