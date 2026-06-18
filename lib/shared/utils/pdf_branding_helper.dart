import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'pdf_theme.dart';

class PdfBrandingData {
  final String schoolName;
  final pw.MemoryImage? schoolLogo;
  final String appName = 'Klassivo';
  final pw.MemoryImage? appLogo;

  PdfBrandingData({
    required this.schoolName,
    this.schoolLogo,
    this.appLogo,
  });
}

class PdfBrandingHelper {
  static Future<PdfBrandingData> load({
    required String schoolName,
    required String schoolLogoUrl,
  }) async {
    pw.MemoryImage? appLogo;
    pw.MemoryImage? schoolLogo;

    // Load App Logo
    try {
      final appLogoData = await rootBundle.load('assets/images/logo.png');
      appLogo = pw.MemoryImage(appLogoData.buffer.asUint8List());
    } catch (e) {
      // Fallback or ignore
    }

    // Load School Logo from URL
    if (schoolLogoUrl.isNotEmpty) {
      try {
        final res = await http.get(Uri.parse(schoolLogoUrl)).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          schoolLogo = pw.MemoryImage(res.bodyBytes);
        }
      } catch (e) {
        // Fallback or ignore
      }
    }

    return PdfBrandingData(
      schoolName: schoolName,
      schoolLogo: schoolLogo,
      appLogo: appLogo,
    );
  }

  static pw.Widget buildHeader(PdfBrandingData data) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 12),
      child: pw.Column(
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // School branding
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  if (data.schoolLogo != null)
                    pw.Container(
                      width: 28,
                      height: 28,
                      margin: const pw.EdgeInsets.only(right: 6),
                      child: pw.Image(data.schoolLogo!),
                    ),
                  pw.Text(
                    data.schoolName,
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfTheme.primary,
                    ),
                  ),
                ],
              ),
              // App branding
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  if (data.appLogo != null)
                    pw.Container(
                      width: 18,
                      height: 18,
                      margin: const pw.EdgeInsets.only(right: 4),
                      child: pw.Image(data.appLogo!),
                    ),
                  pw.Text(
                    data.appName,
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfTheme.textLight,
                    ),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Container(
            height: 0.8,
            color: PdfTheme.primaryLight,
          ),
        ],
      ),
    );
  }
}
