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
    required String schoolName,
    required String schoolLogo,
    String? shareText,
  }) async {
    if (rows.isEmpty) return false;
    final brandedRows = [
      ['App Name', 'Klassivo', 'App Logo', 'assets/images/logo.png'],
      ['School Name', schoolName, 'School Logo', schoolLogo.isNotEmpty ? schoolLogo : 'N/A'],
      [],
      ...rows,
    ];
    final csv = const ListToCsvConverter().convert(brandedRows);
    final dir = await getTemporaryDirectory();
    final safeName = filename.endsWith('.csv') ? filename : '$filename.csv';
    final file = File('${dir.path}/$safeName');
    await file.writeAsString(csv);
    await Share.shareXFiles([XFile(file.path)], text: shareText);
    return true;
  }

  /// Exports raw text [content] as `[filename]` and opens the share sheet.
  static Future<bool> shareRaw({
    required String filename,
    required String content,
    required String schoolName,
    required String schoolLogo,
    String? shareText,
  }) async {
    final dir = await getTemporaryDirectory();
    final safeName = filename.endsWith('.csv') ? filename : '$filename.csv';
    final file = File('${dir.path}/$safeName');
    final branding = "App Name,Klassivo,App Logo,assets/images/logo.png\n"
        "School Name,\"${schoolName.replaceAll('"', '""')}\",School Logo,${schoolLogo.isNotEmpty ? schoolLogo : 'N/A'}\n\n";
    await file.writeAsString(branding + content);
    await Share.shareXFiles([XFile(file.path)], text: shareText);
    return true;
  }
}
