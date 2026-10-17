import 'package:flutter_test/flutter_test.dart';
import 'package:sissan_hotel/core/roles.dart';
import 'package:sissan_hotel/features/reservations/reservations_screen.dart';

void main() {
  test('nuits : date de départ exclue', () {
    expect(nights('2026-10-17', '2026-10-18'), 1);
    expect(nights('2026-10-30', '2026-11-02'), 3);
    expect(nights('2028-02-28', '2028-03-01'), 2); // année bissextile
  });

  test('arrivée et départ passent par les fonctions serveur', () {
    expect(actionsFor('confirmee').map((a) => a.$2), contains('rpc:check_in'));
    expect(actionsFor('arrivee'), [('Enregistrer le départ', 'rpc:check_out')]);
    expect(actionsFor('partie'), isEmpty);
    expect(actionsFor('annulee'), isEmpty);
  });

  test('accès clients limité à l\'accueil et à la direction', () {
    expect(AppRole.values.where((r) => r.canManageGuests), [
      AppRole.superAdmin,
      AppRole.admin,
      AppRole.gerant,
      AppRole.reception,
    ]);
  });
}
