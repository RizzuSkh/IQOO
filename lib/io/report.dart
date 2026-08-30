import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../models/spec_item.dart';
import '../models/diff_result.dart';
import '../logic/phrase.dart';

/// F8: writes the verification report to the app documents directory and
/// copies the one-sentence summary to the system clipboard (PRD section 22 —
/// Office Kit bridges the rest by hand, this app makes no Office Kit call).

/// Outcome of [generateReport], carrying enough detail for the UI to tell the
/// operator the truth (PRD section 23: a file-write failure must not be
/// reported as a save — the summary is still on the clipboard either way).
class ReportResult {
  /// The one-sentence summary that was copied to the clipboard.
  final String summary;

  /// True when the full report was written to disk.
  final bool fileSaved;

  /// Where the file was written, when [fileSaved] is true.
  final String? filePath;

  /// What went wrong, when [fileSaved] is false.
  final String? fileError;

  const ReportResult({
    required this.summary,
    required this.fileSaved,
    this.filePath,
    this.fileError,
  });
}

/// Builds the full report text. Pure — no file or clipboard I/O — so this is
/// unit-testable without platform mocks; [generateReport] wraps it with the
/// actual side effects.
String buildReportText({
  required List<SpecItem> expected,
  required List<SpecItem> observed,
  required DiffResult result,
  required DateTime generatedAt,
}) {
  final summary = phraseWithRules(result);
  final buffer = StringBuffer();

  buffer.writeln('PARITY VERIFICATION REPORT');
  buffer.writeln('Generated: $generatedAt');
  buffer.writeln('');
  buffer.writeln('=== SUMMARY ===');
  buffer.writeln(summary);
  buffer.writeln('');

  buffer.writeln('=== EXPECTED (Specification) ===');
  if (expected.isEmpty) {
    buffer.writeln('(none captured)');
  }
  for (final item in expected) {
    buffer.writeln(
      '${item.position}: ${item.component.isEmpty ? "(unread)" : item.component}',
    );
  }
  buffer.writeln('');

  buffer.writeln('=== OBSERVED (Assembly) ===');
  if (observed.isEmpty) {
    buffer.writeln('(none captured)');
  }
  for (final item in observed) {
    buffer.writeln(
      '${item.position}: ${item.component.isEmpty ? "(unread)" : item.component}',
    );
  }
  buffer.writeln('');

  buffer.writeln('=== DISCREPANCIES ===');
  if (result.isMatch) {
    buffer.writeln('None - assembly matches specification.');
  } else {
    for (final d in result.all) {
      final typeStr = d.type.name.toUpperCase();
      buffer.writeln(
        '[$typeStr] ${d.position}: expected="${d.expected ?? "N/A"}", found="${d.found ?? "N/A"}"',
      );
    }
  }

  return buffer.toString();
}

/// Writes the report to the app documents directory and the summary to the
/// clipboard. The clipboard write always happens; the file write's actual
/// success is reported truthfully in the result rather than assumed.
Future<ReportResult> generateReport({
  required List<SpecItem> expected,
  required List<SpecItem> observed,
  required DiffResult result,
}) async {
  final now = DateTime.now();
  final summary = phraseWithRules(result);
  final reportText = buildReportText(
    expected: expected,
    observed: observed,
    result: result,
    generatedAt: now,
  );

  String? savedPath;
  String? fileError;
  try {
    final timestamp = now.toIso8601String().replaceAll(':', '-');
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/parity_report_$timestamp.txt');
    await file.writeAsString(reportText);
    savedPath = file.path;
  } catch (e) {
    fileError = e.toString();
  }

  // Clipboard write happens regardless of the file outcome (PRD section 23).
  await Clipboard.setData(ClipboardData(text: summary));

  return ReportResult(
    summary: summary,
    fileSaved: savedPath != null,
    filePath: savedPath,
    fileError: fileError,
  );
}
