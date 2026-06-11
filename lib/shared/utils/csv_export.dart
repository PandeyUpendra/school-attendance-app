import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Shared CSV export + share helper (#71 data export).
///
/// Builds a CSV from [rows] (first row is normally the header), writes it to a
/// temporary file, and hands it to the OS share sheet so the user can save it,
/// email it, or open it in a spreadsheet app. Works for any tabular dataset —
/// student rosters, fee ledgers, defaulter lists, attendance registers.
abstract class CsvExport {
  /// Exports [rows] as `[filename]` and opens the share sheet.
  /// Returns false if there is nothing to export.
  static Future<bool> share({
    required String filename,
    required List<List<dynamic>> rows,
    String? shareText,
  }) async {
    if (rows.isEmpty) return false;
    final csv = const ListToCsvConverter().convert(rows);
    final dir = await getTemporaryDirectory();
    final safeName = filename.endsWith('.csv') ? filename : '$filename.csv';
    final file = File('${dir.path}/$safeName');
    await file.writeAsString(csv);
    await Share.shareXFiles([XFile(file.path)], text: shareText);
    return true;
  }
}
