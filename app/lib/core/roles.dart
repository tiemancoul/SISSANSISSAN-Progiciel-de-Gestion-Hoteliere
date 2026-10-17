/// Rôles du personnel, identiques à l'enum `app_role` de la base.
///
/// Ces droits ne servent qu'à adapter l'interface : la base les applique
/// elle-même via RLS (supabase/migrations).
enum AppRole {
  superAdmin('super_admin', 'Super administrateur'),
  admin('admin', 'Administrateur'),
  gerant('gerant', 'Gérant'),
  reception('reception', 'Réceptionniste'),
  caissier('caissier', 'Caissier'),
  comptable('comptable', 'Comptable'),
  restaurantBar('restaurant_bar', 'Restaurant / bar'),
  magasinier('magasinier', 'Magasinier'),
  entretien('entretien', 'Entretien'),
  maintenance('maintenance', 'Maintenance'),
  auditeur('auditeur', 'Auditeur');

  const AppRole(this.dbValue, this.label);

  final String dbValue;
  final String label;

  static AppRole? fromDb(String? value) {
    for (final r in values) {
      if (r.dbValue == value) return r;
    }
    return null;
  }

  /// Devises, taxes et règles de séjour (décisions D2 à D4).
  bool get canEditRules => this == superAdmin;

  /// Chambres, catégories, tarifs, équipements, salles (D9).
  bool get canEditCatalog => this == superAdmin || this == admin;

  /// Identité de l'hôtel et logo (D1).
  bool get canEditIdentity => canEditCatalog || this == gerant;

  bool get canManageUsers => canEditCatalog;

  /// Blocage de chambres par période (travaux, maintenance).
  bool get canManageBlocks =>
      canEditCatalog || this == gerant || this == maintenance;

  /// Clients, réservations, arrivées et départs.
  bool get canManageGuests =>
      canEditCatalog || this == gerant || this == reception;

  /// Rôles qu'un utilisateur de ce rôle peut attribuer.
  List<AppRole> get assignableRoles => switch (this) {
    superAdmin => AppRole.values,
    admin => AppRole.values.where((r) => r != superAdmin).toList(),
    _ => const [],
  };
}
