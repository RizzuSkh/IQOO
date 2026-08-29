import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../models/spec_item.dart';
import '../models/diff_result.dart';
import '../logic/phrase.dart';

/// Generates a report and writes to file + clipboard.
Future<String> generateReport({
  required List<SpecItem> expected,
  required List<SpecItem> observed,
  required DiffResult result,
}) async {
  final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
  final summary = phraseWithRules(result);

  final buffer = StringBuffer();
  buffer.writeln('PARITY VERIFICATION REPORT');
  buffer.writeln('Generated: ${DateTime.now()}');
  buffer.writeln('');
  buffer.writeln('=== SUMMARY ===');
  buffer.writeln(summary);
  buffer.writeln('');

  buffer.writeln('=== EXPECTED (Specification) ===');
  for (final item in expected) {
    buffer.writeln('${item.position}: ${item.component}');
  }
  buffer.writeln('');

  buffer.writeln('=== OBSERVED (Assembly) ===');
  for (final item in observed) {
    buffer.writeln('${item.position}: ${item.component}');
  }
  buffer.writeln('');

  buffer.writeln('=== DISCREPANCIES ===');
  if (result.isMatch) {
    buffer.writeln('None - assembly matches specification.');
  } else {
    for (final d in result.all) {
      final typeStr = d.type.name.toUpperCase();
      buffer.writeln('[$typeStr] ${d.position}: expected="${d.expected ?? "N/A"}", found="${d.found ?? "N/A"}"');
    }
  }

  final reportText = buffer.toString();

  // Write to file
  try {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/parity_report_$timestamp.txt');
    await file.writeAsString(reportText);
  } catch (e) {
    // File write failed - continue with clipboard only
  }

  // Copy to clipboard
  await Clipboard.setData(ClipboardData(text: summary));

  return summary;
}
