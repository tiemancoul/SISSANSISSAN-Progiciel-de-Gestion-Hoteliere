import 'package:flutter_test/flutter_test.dart';
import 'package:sissan_hotel/core/roles.dart';

void main() {
  test('les valeurs correspondent à l\'enum app_role de la base', () {
    expect(AppRole.values.map((r) => r.dbValue), [
      'super_admin',
      'admin',
      'gerant',
      'reception',
      'caissier',
      'comptable',
      'restaurant_bar',
      'magasinier',
      'entretien',
      'maintenance',
      'auditeur',
    ]);
    expect(AppRole.fromDb('gerant'), AppRole.gerant);
    expect(AppRole.fromDb(null), isNull);
    expect(AppRole.fromDb('inconnu'), isNull);
  });

  test('droits alignés sur les décisions D1 à D9', () {
    expect(AppRole.values.where((r) => r.canEditRules), [AppRole.superAdmin]);
    expect(AppRole.values.where((r) => r.canEditCatalog), [
      AppRole.superAdmin,
      AppRole.admin,
    ]);
    expect(AppRole.values.where((r) => r.canEditIdentity), [
      AppRole.superAdmin,
      AppRole.admin,
      AppRole.gerant,
    ]);
  });

  test('un admin ne peut pas attribuer le rôle super admin', () {
    expect(AppRole.admin.assignableRoles, isNot(contains(AppRole.superAdmin)));
    expect(AppRole.superAdmin.assignableRoles, contains(AppRole.superAdmin));
    expect(AppRole.reception.assignableRoles, isEmpty);
  });
}
