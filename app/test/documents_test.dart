import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sissan_hotel/features/billing/documents.dart';

final _invoice = {
  'number': 'F2026-00001',
  'status': 'validee',
  'currency': 'XOF',
  'issued_at': '2026-10-17T10:00:00Z',
  'subtotal': 75000,
  'tax_total': 15000,
  'total': 90000,
  'invoice_items': [
    {
      'description': 'Chambre 101, du 2026-10-17 au 2026-10-20',
      'quantity': 3,
      'unit_price': 25000,
      'amount': 75000,
    },
  ],
  'invoice_taxes': [
    {
      'name': 'TVA',
      'kind': 'pourcentage',
      'rate': 18,
      'base': 75000,
      'amount': 13500,
    },
    {
      'name': 'Taxe de séjour',
      'kind': 'montant_par_nuit',
      'rate': 500,
      'base': 3,
      'amount': 1500,
    },
  ],
};
const _hotel = {
  'name': 'SISSAN SISSAN',
  'address': 'Bamako',
  'tax_id': 'NIF 123',
};
const _cash = {
  'kind': 'paiement',
  'method': 'especes',
  'amount': 40000,
  'currency': 'XOF',
  'amount_invoice': 40000,
  'cash_received': 50000,
  'change_given': 10000,
  'balance_after': 50000,
  'created_at': '2026-10-17T10:05:00Z',
};

void main() {
  test('reçu espèces : à encaisser, reçu, rendu, solde', () {
    expect(receiptLines(_cash, 'XOF'), [
      ('Montant à encaisser', '40000 XOF'),
      ('Espèces reçues', '50000 XOF'),
      ('Monnaie rendue', '10000 XOF'),
      ('Solde après paiement', '50000 XOF'),
    ]);
  });

  test(
    'reçu carte en euros : pas de monnaie rendue, contre-valeur affichée',
    () {
      final lines = receiptLines({
        'kind': 'paiement',
        'method': 'carte',
        'amount': 50,
        'currency': 'EUR',
        'amount_invoice': 32798,
        'reference': 'TPE 123',
        'balance_after': 17202,
      }, 'XOF');
      expect(lines.map((l) => l.$1), isNot(contains('Monnaie rendue')));
      expect(lines, contains(('Contre-valeur', '32798 XOF')));
    },
  );

  test('facture et reçu se génèrent en A4 et A5', () async {
    for (final f in printFormats.values) {
      final inv = await invoicePdf(
        invoice: _invoice,
        hotel: _hotel,
        customer: 'Traoré Awa',
        mentions: 'Mentions légales',
        format: f,
      );
      final rec = await receiptPdf(
        payment: _cash,
        invoice: _invoice,
        hotel: _hotel,
        customer: 'Traoré Awa',
        format: f,
      );
      expect(String.fromCharCodes(inv.take(4)), '%PDF');
      expect(String.fromCharCodes(rec.take(4)), '%PDF');
      final out = Platform.environment['PDF_OUT'];
      if (out != null) {
        File('$out/facture_${f.width.round()}.pdf').writeAsBytesSync(inv);
        File('$out/recu_${f.width.round()}.pdf').writeAsBytesSync(rec);
      }
    }
  });
}
