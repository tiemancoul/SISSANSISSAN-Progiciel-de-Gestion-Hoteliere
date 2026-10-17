import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/edit_dialog.dart';
import '../../core/roles.dart';
import '../../core/supabase.dart';
import '../../core/table_data.dart';

const _profiles = ('profiles', 'created_at');

/// Attribution des rôles. Les comptes sont créés par inscription ou depuis
/// le tableau de bord Supabase, puis apparaissent ici sans rôle.
class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(profileProvider).value;
    final myRole = me?.role;
    if (me == null || myRole == null) return const SizedBox.shrink();

    return RowsView(
      query: _profiles,
      itemBuilder: (p) {
        final role = AppRole.fromDb(p['role'] as String?);
        final editable =
            p['id'] != me.id &&
            (role == null || myRole.assignableRoles.contains(role));
        return ListTile(
          leading: Icon(
            p['active'] == true
                ? Icons.person_outline
                : Icons.person_off_outlined,
          ),
          title: Text(p['full_name'] as String? ?? 'Sans nom'),
          subtitle: Text(
            '${role?.label ?? 'En attente de rôle'}'
            '${p['active'] == true ? '' : ' · désactivé'}',
          ),
          onTap: editable
              ? () async {
                  final values = await showEditDialog(
                    context,
                    title: 'Utilisateur',
                    initial: p,
                    fields: [
                      const TextInput('full_name', 'Nom complet'),
                      ChoiceField('role', 'Rôle', {
                        for (final r in myRole.assignableRoles)
                          r.dbValue: r.label,
                      }),
                      const BoolField('active', 'Actif'),
                    ],
                  );
                  if (values == null || !context.mounted) return;
                  final error = await saveRow(ref, _profiles, {
                    ...values,
                    'hotel_id': me.hotelId,
                  }, id: p['id']);
                  if (context.mounted) showResult(context, error);
                }
              : null,
        );
      },
    );
  }
}
