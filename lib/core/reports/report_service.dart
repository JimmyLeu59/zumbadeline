import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/agenda/domain/class_session.dart';
import '../../features/finances/domain/payment.dart';
import '../../features/members/domain/member.dart';

class ReportService {
  ReportService(this._client);

  final SupabaseClient _client;

  Future<void> shareMembersPdf(List<Member> members) async {
    final document = pw.Document();
    final logo = await _loadLogo();
    final photos = <String, pw.ImageProvider>{};
    for (final member in members) {
      final path = member.photoUrl;
      if (path == null || path.isEmpty || path.startsWith('http')) continue;
      final bytes = await _client.storage.from('member_photos').download(path);
      photos[member.id] = pw.MemoryImage(bytes);
    }
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          _heading('Trombinoscope des adherents', logo),
          pw.SizedBox(height: 12),
          pw.Text('${members.length} adhérent(s)'),
          pw.SizedBox(height: 12),
          pw.Table(
            border: pw.TableBorder.all(
              color: const PdfColor.fromInt(0xFFDDC8D8),
              width: .5,
            ),
            columnWidths: {
              0: const pw.FixedColumnWidth(45),
              1: const pw.FlexColumnWidth(2),
              2: const pw.FlexColumnWidth(1.4),
              3: const pw.FlexColumnWidth(1),
              4: const pw.FlexColumnWidth(1),
            },
            children: [
              _tableRow([
                'Photo',
                'Nom',
                'Cotisation',
                'Passages',
                'Statut',
              ], header: true),
              for (final member in members)
                pw.TableRow(
                  children: [
                    pw.Container(
                      height: 44,
                      alignment: pw.Alignment.center,
                      padding: const pw.EdgeInsets.all(3),
                      child: photos[member.id] == null
                          ? pw.Text('-')
                          : pw.Image(photos[member.id]!, fit: pw.BoxFit.cover),
                    ),
                    _tableCell(member.fullName),
                    _tableCell(
                      member.membershipValidUntil == null
                          ? 'Non renseignee'
                          : _date(member.membershipValidUntil!),
                    ),
                    _tableCell('${member.remainingPasses}'),
                    _tableCell(member.isActive ? 'Actif' : 'Archive'),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
    await Printing.sharePdf(
      bytes: await document.save(),
      filename: 'trombinoscope-adherents.pdf',
    );
  }

  Future<void> shareAttendancePdf({
    required ClassSession session,
    required List<Member> members,
    required List<Map<String, dynamic>> attendances,
  }) async {
    final document = pw.Document();
    final logo = await _loadLogo();
    final attendanceByMember = {
      for (final row in attendances) row['member_id'] as String: row,
    };
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          _heading("Feuille d'emargement", logo),
          pw.SizedBox(height: 12),
          pw.Text(session.title, style: pw.TextStyle(fontSize: 16)),
          pw.Text('${_date(session.startsAt)} · ${_time(session.startsAt)}'),
          if (session.location?.isNotEmpty ?? false)
            pw.Text('Lieu : ${session.location}'),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: const ['#', 'Adhérent', 'Présence', 'Heure', 'Signature'],
            data: [
              for (var index = 0; index < members.length; index++)
                [
                  '${index + 1}',
                  members[index].fullName,
                  attendanceByMember.containsKey(members[index].id)
                      ? 'Present'
                      : 'Absent',
                  attendanceByMember.containsKey(members[index].id)
                      ? _checkedInTime(attendanceByMember[members[index].id]!)
                      : '',
                  '',
                ],
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFFCE4F3),
            ),
            cellPadding: const pw.EdgeInsets.all(7),
            cellHeight: 30,
          ),
        ],
      ),
    );
    await Printing.sharePdf(
      bytes: await document.save(),
      filename: 'emargement-${_filePart(session.title)}.pdf',
    );
  }

  Future<void> shareFinancePdf(List<Payment> payments) async {
    final document = pw.Document();
    final logo = await _loadLogo();
    final total = payments.fold<double>(
      0,
      (sum, payment) => sum + payment.amount,
    );
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          _heading('Bilan financier', logo),
          pw.SizedBox(height: 8),
          pw.Text('Periode : tous les paiements enregistres'),
          pw.Text('${payments.length} paiement(s) · ${_money(total)} EUR'),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: const ['Date', 'Adhérent', 'Type', 'Mode', 'Montant EUR'],
            data: [
              for (final payment in payments)
                [
                  _date(payment.paidAt),
                  payment.memberName,
                  _paymentType(payment.type),
                  _paymentMethod(payment.method),
                  payment.amount.toStringAsFixed(2),
                ],
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFFCE4F3),
            ),
            cellPadding: const pw.EdgeInsets.all(5),
          ),
        ],
      ),
    );
    await Printing.sharePdf(
      bytes: await document.save(),
      filename: 'bilan-financier.pdf',
    );
  }

  Future<void> shareMemberInvoicePdf({
    required Member member,
    required List<Payment> payments,
    required DateTime from,
    required DateTime through,
  }) async {
    if (payments.any((payment) => payment.memberId != member.id)) {
      throw ArgumentError('All invoice payments must belong to the member.');
    }
    if (payments.isEmpty) {
      throw StateError('Aucun paiement enregistré sur cette période.');
    }
    final document = pw.Document();
    final logo = await _loadLogo();
    final total = payments.fold<double>(
      0,
      (sum, payment) => sum + payment.amount,
    );
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          _heading('Facture acquittée', logo),
          pw.SizedBox(height: 8),
          pw.Text(
            'Adhérent : ${member.fullName}',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          if (member.email?.isNotEmpty ?? false) pw.Text(member.email!),
          if (member.phone?.isNotEmpty ?? false) pw.Text(member.phone!),
          pw.SizedBox(height: 8),
          pw.Text('Période : du ${_date(from)} au ${_date(through)}'),
          pw.Text('Émise le ${_date(DateTime.now())} · Paiements acquittés'),
          pw.SizedBox(height: 14),
          pw.TableHelper.fromTextArray(
            headers: const [
              'Date',
              'Désignation',
              'Mode de paiement',
              'Référence reçu',
              'Montant EUR',
            ],
            data: [
              for (final payment in payments)
                [
                  _date(payment.paidAt),
                  _paymentType(payment.type),
                  _paymentMethod(payment.method),
                  payment.receiptNumber ?? '-',
                  payment.amount.toStringAsFixed(2),
                ],
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFFCE4F3),
            ),
            cellPadding: const pw.EdgeInsets.all(6),
          ),
          pw.SizedBox(height: 12),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Total acquitté : ${_money(total)} EUR',
              style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            'Document récapitulatif des paiements enregistrés pour la période. '
            'Les références de reçu d’origine sont conservées.',
            style: const pw.TextStyle(
              fontSize: 9,
              color: PdfColor.fromInt(0xFF6B5B69),
            ),
          ),
        ],
      ),
    );
    await Printing.sharePdf(
      bytes: await document.save(),
      filename:
          'facture-${_filePart(member.fullName)}-'
          '${_filePart(_date(from))}-${_filePart(_date(through))}.pdf',
    );
  }

  Future<void> shareFinanceExcel(List<Payment> payments) async {
    final workbook = Excel.createExcel();
    final sheet = workbook['Sheet1'];
    sheet.appendRow([
      TextCellValue('Date'),
      TextCellValue('Adhérent'),
      TextCellValue('Type'),
      TextCellValue('Moyen de paiement'),
      TextCellValue('Montant EUR'),
      TextCellValue('N° reçu'),
    ]);
    for (final payment in payments) {
      sheet.appendRow([
        TextCellValue(_date(payment.paidAt)),
        TextCellValue(payment.memberName),
        TextCellValue(_paymentType(payment.type)),
        TextCellValue(_paymentMethod(payment.method)),
        DoubleCellValue(payment.amount),
        TextCellValue(payment.receiptNumber ?? ''),
      ]);
    }
    final total = payments.fold<double>(
      0,
      (sum, payment) => sum + payment.amount,
    );
    sheet.appendRow([
      TextCellValue('TOTAL'),
      TextCellValue(''),
      TextCellValue(''),
      TextCellValue(''),
      DoubleCellValue(total),
      TextCellValue(''),
    ]);
    final bytes = workbook.save(fileName: 'bilan-financier.xlsx');
    if (bytes == null || bytes.isEmpty) {
      throw StateError('La génération du fichier Excel a échoué.');
    }
    const filename = 'bilan-financier.xlsx';
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            Uint8List.fromList(bytes),
            mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            name: filename,
          ),
        ],
        fileNameOverrides: const [filename],
        title: 'Bilan financier Excel',
      ),
    );
  }

  Future<pw.ImageProvider> _loadLogo() async {
    final data = await rootBundle.load('assets/images/app_logo.jpg');
    return pw.MemoryImage(data.buffer.asUint8List());
  }

  pw.TableRow _tableRow(List<String> values, {bool header = false}) =>
      pw.TableRow(
        decoration: header
            ? const pw.BoxDecoration(color: PdfColor.fromInt(0xFFFCE4F3))
            : null,
        children: [for (final value in values) _tableCell(value, bold: header)],
      );

  pw.Widget _tableCell(String value, {bool bold = false}) => pw.Padding(
    padding: const pw.EdgeInsets.all(6),
    child: pw.Text(
      value,
      style: bold ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null,
    ),
  );

  pw.Widget _heading(String text, pw.ImageProvider logo) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Row(
        children: [
          pw.Image(logo, width: 40, height: 40),
          pw.SizedBox(width: 10),
          pw.Text(
            'Zumba & Pedagogie',
            style: pw.TextStyle(
              fontSize: 10,
              color: PdfColor.fromInt(0xFF7200C8),
            ),
          ),
        ],
      ),
      pw.SizedBox(height: 4),
      pw.Text(text, style: pw.TextStyle(fontSize: 22)),
      pw.SizedBox(height: 4),
      pw.Text(
        'Genere le ${_date(DateTime.now())}',
        style: const pw.TextStyle(color: PdfColor.fromInt(0xFF6B5B69)),
      ),
      pw.Divider(),
    ],
  );

  String _checkedInTime(Map<String, dynamic> row) {
    final value = row['checked_in_at'];
    if (value is! String) return '';
    return _time(DateTime.parse(value));
  }

  String _date(DateTime value) {
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year}';
  }

  String _time(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  String _filePart(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');

  String _money(double value) => value.toStringAsFixed(2);

  String _paymentType(String value) => switch (value) {
    'membership' => 'Cotisation',
    'single_class' => "Cours a l'unite",
    'class_card' => 'Carte de cours',
    'event' => 'Événement',
    _ => 'Autre',
  };

  String _paymentMethod(String value) => switch (value) {
    'cash' => 'Espèces',
    'cheque' => 'Chèque',
    'bank_transfer' => 'Virement',
    'card' => 'CB',
    _ => value,
  };
}
