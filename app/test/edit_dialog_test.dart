import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sissan_hotel/core/edit_dialog.dart';

void main() {
  test('validation des nombres décimaux et entiers', () {
    const rate = NumberField('rate', 'Tarif');
    const count = NumberField('n', 'Nombre', integer: true);
    expect(validateField(rate, '25000'), isNull);
    expect(validateField(rate, '655,957'), isNull);
    expect(validateField(rate, '-3'), isNotNull);
    expect(validateField(rate, '1e5'), isNotNull);
    expect(validateField(rate, ''), 'Champ requis');
    expect(validateField(count, '2.5'), isNotNull);
    expect(
      validateField(const TextInput('x', 'X', required: false), ''),
      isNull,
    );
  });

  testWidgets('le formulaire renvoie les montants en texte normalisé', (
    tester,
  ) async {
    Map<String, Object?>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showEditDialog(
              context,
              title: 'Catégorie',
              fields: const [
                TextInput('name', 'Nom'),
                NumberField('base_rate', 'Tarif'),
                TextInput('notes', 'Notes', required: false),
                BoolField('active', 'Active'),
              ],
              initial: const {'active': true},
            ),
            child: const Text('ouvrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Enregistrer'));
    await tester.pump();
    expect(find.text('Champ requis'), findsNWidgets(2));

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nom'),
      ' Suite ',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Tarif'),
      '45000,50',
    );
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();

    expect(result, {
      'name': 'Suite',
      'base_rate': '45000.50',
      'notes': null,
      'active': true,
    });
  });
}
