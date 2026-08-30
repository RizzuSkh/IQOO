import 'dart:convert';
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

  /// Where the text report was written, when [fileSaved] is true.
  final String? filePath;

  /// Where the machine-readable JSON record was written, when it succeeded.
  final String? jsonPath;

  /// What went wrong, when [fileSaved] is false.
  final String? fileError;

  const ReportResult({
    required this.summary,
    required this.fileSaved,
    this.filePath,
    this.jsonPath,
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

/// Builds the same verification result as a structured JSON document.
///
/// Two reasons this exists alongside the text report. First, a machine-
/// readable record is what actually integrates with anything downstream — a
/// maintenance system, a spreadsheet, an audit trail — where the prose
/// report is only good for a human to read. Second, it makes the extraction
/// itself inspectable: an evaluator can see the exact structured data the
/// comparison ran on, rather than taking the verdict on trust.
///
/// Pure, like [buildReportText] — no I/O, unit-testable without mocks.
String buildReportJson({
  required List<SpecItem> expected,
  required List<SpecItem> observed,
  required DiffResult result,
  required DateTime generatedAt,
}) {
  Map<String, dynamic> itemJson(SpecItem item) => {
    'position': item.position,
    'component': item.component,
    'unread': item.component.trim().isEmpty,
    'confidence': double.parse(item.confidence.toStringAsFixed(3)),
  };

  final document = {
    'schema': 'parity.verification.v1',
    'generatedAt': generatedAt.toIso8601String(),
    'summary': phraseWithRules(result),
    'isMatch': result.isMatch,
    'counts': {
      'expected': expected.length,
      'observed': observed.length,
      'missing': result.missing.length,
      'unexpected': result.unexpected.length,
      'mismatched': result.mismatched.length,
      'unread': result.unread.length,
    },
    'expected': expected.map(itemJson).toList(),
    'observed': observed.map(itemJson).toList(),
    'discrepancies': result.all
        .map(
          (d) => {
            'type': d.type.name,
            'position': d.position,
            'expected': d.expected,
            'found': d.found,
          },
        )
        .toList(),
  };

  return const JsonEncoder.withIndent('  ').convert(document);
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
  String? jsonPath;
  String? fileError;
  try {
    final timestamp = now.toIso8601String().replaceAll(':', '-');
    final dir = await getApplicationDocumentsDirectory();

    final file = File('${dir.path}/parity_report_$timestamp.txt');
    await file.writeAsString(reportText);
    savedPath = file.path;

    // Structured record written alongside the prose one, so the result is
    // machine-readable and the extracted data is inspectable.
    final json = File('${dir.path}/parity_report_$timestamp.json');
    await json.writeAsString(
      buildReportJson(
        expected: expected,
        observed: observed,
        result: result,
        generatedAt: now,
      ),
    );
    jsonPath = json.path;
  } catch (e) {
    fileError = e.toString();
  }

  // Clipboard write happens regardless of the file outcome (PRD section 23).
  await Clipboard.setData(ClipboardData(text: summary));

  return ReportResult(
    summary: summary,
    fileSaved: savedPath != null,
    filePath: savedPath,
    jsonPath: jsonPath,
    fileError: fileError,
  );
}
