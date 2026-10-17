import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'roles.dart';

final supabaseProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(supabaseProvider).auth.onAuthStateChange,
);

/// Profil de l'utilisateur connecté (null si déconnecté).
class Profile {
  const Profile({
    required this.id,
    required this.hotelId,
    required this.fullName,
    required this.role,
  });

  final String id;
  final String? hotelId;
  final String? fullName;
  final AppRole? role;

  bool get hasAccess => role != null && hotelId != null;
}

final profileProvider = FutureProvider<Profile?>((ref) async {
  ref.watch(authStateProvider);
  final db = ref.watch(supabaseProvider);
  final user = db.auth.currentUser;
  if (user == null) return null;
  final row = await db
      .from('profiles')
      .select('id, hotel_id, full_name, role, active')
      .eq('id', user.id)
      .maybeSingle();
  if (row == null || row['active'] != true) {
    return Profile(id: user.id, hotelId: null, fullName: null, role: null);
  }
  return Profile(
    id: user.id,
    hotelId: row['hotel_id'] as String?,
    fullName: row['full_name'] as String?,
    role: AppRole.fromDb(row['role'] as String?),
  );
});

/// Message lisible pour une erreur Supabase.
String errorText(Object e) => switch (e) {
  PostgrestException(code: '42501') => 'Action non autorisée pour votre rôle.',
  PostgrestException(code: '23505') => 'Cette valeur existe déjà.',
  PostgrestException(:final message) => message,
  AuthException(:final message) => message,
  _ => 'Erreur inattendue : $e',
};
