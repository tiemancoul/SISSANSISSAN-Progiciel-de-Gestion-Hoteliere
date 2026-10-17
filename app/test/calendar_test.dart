import 'package:flutter_test/flutter_test.dart';
import 'package:sissan_hotel/core/roles.dart';
import 'package:sissan_hotel/features/reservations/calendar_screen.dart';

void main() {
  final reservations = [
    {
      'room_id': 'r1',
      'check_in': '2026-10-17',
      'check_out': '2026-10-19',
      'status': 'confirmee',
      'reference': 'A',
    },
    {
      'room_id': 'r1',
      'check_in': '2026-10-18',
      'check_out': '2026-10-20',
      'status': 'en_attente',
      'reference': 'B',
    },
    {
      'room_id': 'r1',
      'check_in': '2026-10-10',
      'check_out': '2026-10-25',
      'status': 'annulee',
      'reference': 'X',
    },
    {
      'room_id': 'r2',
      'check_in': '2026-10-17',
      'check_out': '2026-10-18',
      'status': 'arrivee',
      'reference': 'C',
    },
  ];
  final blocks = [
    {
      'room_id': 'r2',
      'start_date': '2026-10-18',
      'end_date': '2026-10-21',
      'reason': 'Peinture',
    },
  ];

  CellKind kind(String room, String day) =>
      cellFor(room, day, reservations, blocks).$1;

  test('le départ est exclu et la confirmée prime sur l\'attente', () {
    expect(kind('r1', '2026-10-16'), CellKind.libre);
    expect(kind('r1', '2026-10-17'), CellKind.confirmee);
    expect(
      cellFor('r1', '2026-10-18', reservations, blocks).$2!['reference'],
      'A',
    );
    expect(kind('r1', '2026-10-19'), CellKind.attente);
    expect(kind('r1', '2026-10-20'), CellKind.libre); // annulée ignorée
  });

  test('séjour en cours puis blocage', () {
    expect(kind('r2', '2026-10-17'), CellKind.arrivee);
    expect(kind('r2', '2026-10-18'), CellKind.bloquee);
    expect(kind('r2', '2026-10-21'), CellKind.libre);
  });

  test('blocages réservés à la direction et à la maintenance', () {
    expect(AppRole.values.where((r) => r.canManageBlocks), [
      AppRole.superAdmin,
      AppRole.admin,
      AppRole.gerant,
      AppRole.maintenance,
    ]);
  });
}
