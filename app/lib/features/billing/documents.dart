import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/table_data.dart';

/// Formats d'impression retenus (D8 : A4 et A5, ticket 80 mm hors lancement).
const printFormats = {'A4': PdfPageFormat.a4, 'A5': PdfPageFormat.a5};

/// Lignes d'un reçu de paiement. Les mentions espèces (reçu, rendu)
/// n'apparaissent que pour un paiement en espèces : pas de monnaie fictive.
List<(String, String)> receiptLines(DbRow payment, String invoiceCurrency) {
  final cur = payment['currency'];
  return [
    (
      payment['kind'] == 'remboursement'
          ? 'Montant remboursé'
          : 'Montant à encaisser',
      '${payment['amount']} $cur',
    ),
    if (cur != invoiceCurrency)
      ('Contre-valeur', '${payment['amount_invoice']} $invoiceCurrency'),
    if (payment['method'] == 'especes' && payment['cash_received'] != null) ...[
      ('Espèces reçues', '${payment['cash_received']} $cur'),
      ('Monnaie rendue', '${payment['change_given']} $cur'),
    ],
    if (payment['reference'] != null) ('Référence', '${payment['reference']}'),
    ('Solde après paiement', '${payment['balance_after']} $invoiceCurrency'),
  ];
}

pw.Widget _header(DbRow hotel, String title, String subtitle) => pw.Row(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: [
    pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            '${hotel['name']}',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          for (final k in ['legal_name', 'address', 'phone', 'email'])
            if (hotel[k] != null) pw.Text('${hotel[k]}'),
          if (hotel['tax_id'] != null)
            pw.Text('N° fiscal : ${hotel['tax_id']}'),
        ],
      ),
    ),
    pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text(subtitle),
      ],
    ),
  ],
);

pw.Widget _row(String label, String value, {bool bold = false}) => pw.Row(
  children: [
    pw.Expanded(
      child: pw.Text(
        label,
        style: bold ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null,
      ),
    ),
    pw.Text(
      value,
      style: bold ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null,
    ),
  ],
);

/// Facture validée (ou annulée, marquée comme telle) au format demandé.
Future<Uint8List> invoicePdf({
  required DbRow invoice,
  required DbRow hotel,
  required String customer,
  String? mentions,
  PdfPageFormat format = PdfPageFormat.a4,
}) {
  final cur = invoice['currency'];
  final items = (invoice['invoice_items'] as List).cast<DbRow>();
  final taxes = (invoice['invoice_taxes'] as List).cast<DbRow>();
  final doc = pw.Document(title: 'Facture ${invoice['number']}');
  doc.addPage(
    pw.MultiPage(
      pageFormat: format,
      margin: const pw.EdgeInsets.all(28),
      build: (_) => [
        _header(
          hotel,
          invoice['status'] == 'annulee' ? 'FACTURE ANNULÉE' : 'FACTURE',
          'N° ${invoice['number']}\n'
          'Date : ${(invoice['issued_at'] as String).substring(0, 10)}',
        ),
        pw.SizedBox(height: 16),
        pw.Text('Client : $customer'),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headers: ['Désignation', 'Qté', 'Prix unitaire', 'Montant'],
          data: [
            for (final it in items)
              [
                it['description'],
                '${it['quantity']}',
                '${it['unit_price']} $cur',
                '${it['amount']} $cur',
              ],
          ],
          columnWidths: {
            0: const pw.FlexColumnWidth(3),
            1: const pw.IntrinsicColumnWidth(),
            2: const pw.FlexColumnWidth(2),
            3: const pw.FlexColumnWidth(2),
          },
          cellAlignments: {
            1: pw.Alignment.centerRight,
            2: pw.Alignment.centerRight,
            3: pw.Alignment.centerRight,
          },
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 12),
        _row('Sous-total', '${invoice['subtotal']} $cur'),
        for (final t in taxes)
          _row(
            t['kind'] == 'pourcentage'
                ? '${t['name']} ${t['rate']} % sur ${t['base']} $cur'
                : '${t['name']} ${t['rate']} $cur × ${t['base']} nuit(s)',
            '${t['amount']} $cur',
          ),
        _row('TOTAL', '${invoice['total']} $cur', bold: true),
        if (invoice['status'] == 'annulee')
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 8),
            child: pw.Text('Annulée : ${invoice['cancelled_reason']}'),
          ),
        if (mentions != null) ...[
          pw.SizedBox(height: 24),
          pw.Text(mentions, style: const pw.TextStyle(fontSize: 8)),
        ],
      ],
    ),
  );
  return doc.save();
}

/// Reçu d'un paiement ou d'un remboursement.
Future<Uint8List> receiptPdf({
  required DbRow payment,
  required DbRow invoice,
  required DbRow hotel,
  required String customer,
  PdfPageFormat format = PdfPageFormat.a5,
}) {
  final doc = pw.Document(title: 'Reçu');
  doc.addPage(
    pw.Page(
      pageFormat: format,
      margin: const pw.EdgeInsets.all(28),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _header(
            hotel,
            payment['kind'] == 'remboursement'
                ? 'REÇU DE REMBOURSEMENT'
                : 'REÇU',
            'Facture ${invoice['number']}\n'
            '${(payment['created_at'] as String).substring(0, 16).replaceFirst('T', ' ')}',
          ),
          pw.SizedBox(height: 16),
          pw.Text('Client : $customer'),
          pw.Text('Moyen : ${_methods[payment['method']]}'),
          pw.SizedBox(height: 12),
          for (final (label, value) in receiptLines(
            payment,
            invoice['currency'] as String,
          ))
            _row(label, value, bold: label.startsWith('Solde')),
        ],
      ),
    ),
  );
  return doc.save();
}

const _methods = {
  'especes': 'Espèces',
  'carte': 'Carte bancaire',
  'mobile_money': 'Mobile Money',
  'virement': 'Virement',
};
