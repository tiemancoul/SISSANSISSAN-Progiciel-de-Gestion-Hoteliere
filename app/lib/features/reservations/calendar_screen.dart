import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/edit_dialog.dart';
import '../../core/supabase.dart';
import '../../core/table_data.dart';
import '../rooms/rooms_screen.dart' show roomsQuery;
import 'reservations_screen.dart';

const blocksQuery = ('room_blocks', 'start_date');
const _days = 14;

enum CellKind {
  libre('', 'Libre'),
  attente('E', 'En attente'),
  confirmee('C', 'Confirmée'),
  arrivee('A', 'En séjour'),
  bloquee('B', 'Bloquée');

  const CellKind(this.code, this.label);
  final String code;
  final String label;
}

String isoDay(DateTime d) => d.toIso8601String().substring(0, 10);

/// État d'une chambre un jour donné (dates AAAA-MM-JJ, fin exclue).
/// Un blocage l'emporte, puis le séjour en cours, la réservation confirmée,
/// la demande en attente. Renvoie aussi la ligne concernée.
(CellKind, DbRow?) cellFor(
  String roomId,
  String day,
  List<DbRow> reservations,
  List<DbRow> blocks,
) {
  bool covers(DbRow r, String from, String to) =>
      r['room_id'] == roomId &&
      (r[from] as String).compareTo(day) <= 0 &&
      day.compareTo(r[to] as String) < 0;

  for (final b in blocks) {
    if (covers(b, 'start_date', 'end_date')) return (CellKind.bloquee, b);
  }
  DbRow? found;
  var kind = CellKind.libre;
  for (final r in reservations) {
    if (!covers(r, 'check_in', 'check_out')) continue;
    final k = switch (r['status']) {
      'arrivee' => CellKind.arrivee,
      'confirmee' => CellKind.confirmee,
      'en_attente' => CellKind.attente,
      _ => CellKind.libre,
    };
    if (k.index > kind.index) (kind, found) = (k, r);
  }
  return (kind, found);
}

/// Occupation des chambres sur deux semaines et gestion des blocages.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  DateTime _start = DateUtils.dateOnly(DateTime.now());

  Color _color(CellKind k, ColorScheme c) => switch (k) {
    CellKind.libre => c.surface,
    CellKind.attente => c.tertiaryContainer,
    CellKind.confirmee => c.primaryContainer,
    CellKind.arrivee => c.primary,
    CellKind.bloquee => c.errorContainer,
  };

  Color _onColor(CellKind k, ColorScheme c) => switch (k) {
    CellKind.libre => c.onSurface,
    CellKind.attente => c.onTertiaryContainer,
    CellKind.confirmee => c.onPrimaryContainer,
    CellKind.arrivee => c.onPrimary,
    CellKind.bloquee => c.onErrorContainer,
  };

  Future<void> _block(Map<String, String> rooms) async {
    final values = await showEditDialog(
      context,
      title: 'Bloquer une chambre',
      fields: [
        ChoiceField('room_id', 'Chambre', rooms),
        const DateField('start_date', 'Du'),
        const DateField('end_date', 'Au (exclu)'),
        const TextInput('reason', 'Motif (travaux, maintenance…)'),
      ],
    );
    if (values == null || !mounted) return;
    final error = await saveRow(ref, blocksQuery, {
      ...values,
      'hotel_id': ref.read(profileProvider).value?.hotelId,
    });
    if (mounted) showResult(context, error, ok: 'Chambre bloquée.');
  }

  Future<void> _unblock(DbRow b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Lever le blocage ?'),
        content: Text(
          '${b['reason']} : du ${b['start_date']} au ${b['end_date']}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Lever'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    String? error;
    try {
      await ref
          .read(supabaseProvider)
          .from('room_blocks')
          .delete()
          .eq('id', b['id']);
      ref.invalidate(rowsProvider(blocksQuery));
    } on Object catch (e) {
      error = errorText(e);
    }
    if (mounted) showResult(context, error, ok: 'Blocage levé.');
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final canBlock =
        ref.watch(profileProvider).value?.role?.canManageBlocks ?? false;
    final rooms = ref.watch(rowsProvider(roomsQuery));
    final reservations =
        ref.watch(rowsProvider(reservationsQuery)).value ?? const <DbRow>[];
    final blocks =
        ref.watch(rowsProvider(blocksQuery)).value ?? const <DbRow>[];
    final days = [
      for (var i = 0; i < _days; i++) _start.add(Duration(days: i)),
    ];

    Widget header() => Padding(
      padding: const EdgeInsets.all(8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          IconButton(
            tooltip: 'Semaine précédente',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(
              () => _start = _start.subtract(const Duration(days: 7)),
            ),
          ),
          TextButton(
            onPressed: () =>
                setState(() => _start = DateUtils.dateOnly(DateTime.now())),
            child: const Text('Aujourd\'hui'),
          ),
          IconButton(
            tooltip: 'Semaine suivante',
            icon: const Icon(Icons.chevron_right),
            onPressed: () =>
                setState(() => _start = _start.add(const Duration(days: 7))),
          ),
          for (final k in CellKind.values.skip(1))
            Chip(
              avatar: CircleAvatar(
                backgroundColor: _color(k, colors),
                child: Text(
                  k.code,
                  style: TextStyle(color: _onColor(k, colors)),
                ),
              ),
              label: Text(k.label),
            ),
        ],
      ),
    );

    return Scaffold(
      body: rooms.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(errorText(e))),
        data: (rooms) {
          final active = rooms.where((r) => r['active'] == true).toList();
          return ListView(
            children: [
              header(),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 4,
                  horizontalMargin: 8,
                  columns: [
                    const DataColumn(label: Text('Chambre')),
                    for (final d in days)
                      DataColumn(
                        label: Text(
                          '${d.day}/${d.month}',
                          style: d.weekday >= 6
                              ? const TextStyle(fontWeight: FontWeight.bold)
                              : null,
                        ),
                      ),
                  ],
                  rows: [
                    for (final room in active)
                      DataRow(
                        cells: [
                          DataCell(Text('${room['number']}')),
                          for (final d in days)
                            _cell(
                              room,
                              isoDay(d),
                              reservations,
                              blocks,
                              canBlock,
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: canBlock
          ? FloatingActionButton.extended(
              onPressed: () => _block({
                for (final r in rooms.value ?? const <DbRow>[])
                  r['id'] as String: 'Chambre ${r['number']}',
              }),
              icon: const Icon(Icons.block),
              label: const Text('Bloquer'),
            )
          : null,
    );
  }

  DataCell _cell(
    DbRow room,
    String day,
    List<DbRow> reservations,
    List<DbRow> blocks,
    bool canBlock,
  ) {
    final colors = Theme.of(context).colorScheme;
    final (kind, row) = cellFor(
      room['id'] as String,
      day,
      reservations,
      blocks,
    );
    final detail = switch (kind) {
      CellKind.libre => 'Libre',
      CellKind.bloquee => 'Bloquée : ${row!['reason']}',
      _ => '${kind.label} : ${row!['reference']}',
    };
    return DataCell(
      Tooltip(
        message: 'Chambre ${room['number']}, $day. $detail',
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _color(kind, colors),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Text(
            kind.code,
            style: TextStyle(color: _onColor(kind, colors)),
          ),
        ),
      ),
      onTap: kind == CellKind.bloquee && canBlock ? () => _unblock(row!) : null,
    );
  }
}
