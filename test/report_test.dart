import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:parity/io/report.dart';
import 'package:parity/logic/compare.dart';
import 'package:parity/models/diff_result.dart';
import 'package:parity/models/spec_item.dart';

/// Tests only buildReportText() — the pure formatting function report.dart
/// splits out specifically so this doesn't need path_provider/Clipboard
/// platform mocks. generateReport() itself (the file + clipboard I/O) is
/// exercised on-device, not here.
void main() {
  final generatedAt = DateTime(2026, 8, 30, 12, 0);

  group('buildReportText()', () {
    test('a clean match reports no discrepancies', () {
      const items = [
        SpecItem(position: '1', component: 'NE555'),
        SpecItem(position: '2', component: '7805'),
      ];
      final text = buildReportText(
        expected: items,
        observed: items,
        result: compare(items, items),
        generatedAt: generatedAt,
      );

      expect(text, contains('PARITY VERIFICATION REPORT'));
      expect(text, contains('No discrepancies found'));
      expect(text, contains('None - assembly matches specification.'));
      expect(text, contains('1: NE555'));
      expect(text, contains('2: 7805'));
    });

    test('lists every discrepancy with its type, expected and found', () {
      final expected = [
        const SpecItem(position: '1', component: 'NE555'),
        const SpecItem(position: '2', component: '7805'),
      ];
      final observed = [const SpecItem(position: '2', component: 'LM358')];
      final result = compare(expected, observed);

      final text = buildReportText(
        expected: expected,
        observed: observed,
        result: result,
        generatedAt: generatedAt,
      );

      expect(text, contains('[MISSING] 1: expected="NE555", found="N/A"'));
      expect(text, contains('[MISMATCHED] 2: expected="7805", found="LM358"'));
    });

    test('an unread component is labelled, not shown as blank', () {
      final expected = [const SpecItem(position: '1', component: 'NE555')];
      final observed = [const SpecItem(position: '1', component: '')];
      final text = buildReportText(
        expected: expected,
        observed: observed,
        result: compare(expected, observed),
        generatedAt: generatedAt,
      );
      expect(text, contains('1: (unread)'));
    });

    test('an empty capture is labelled, not rendered as a blank section', () {
      final text = buildReportText(
        expected: const [],
        observed: const [],
        result: compare(const [], const []),
        generatedAt: generatedAt,
      );
      expect(
        text,
        contains('=== EXPECTED (Specification) ===\n(none captured)'),
      );
      expect(text, contains('=== OBSERVED (Assembly) ===\n(none captured)'));
    });

    test('includes the generation timestamp', () {
      final text = buildReportText(
        expected: const [],
        observed: const [],
        result: compare(const [], const []),
        generatedAt: generatedAt,
      );
      expect(text, contains('Generated: $generatedAt'));
    });
  });

  _jsonTests();
}

void _jsonTests() {
  group('buildReportJson()', () {
    final generatedAt = DateTime.utc(2026, 8, 30, 11, 30);

    test('emits a parseable document with the declared schema', () {
      final json = buildReportJson(
        expected: const [SpecItem(position: '1', component: 'C63')],
        observed: const [SpecItem(position: '1', component: 'C63')],
        result: const DiffResult.empty(),
        generatedAt: generatedAt,
      );

      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['schema'], 'parity.verification.v1');
      expect(decoded['isMatch'], isTrue);
      expect(decoded['generatedAt'], generatedAt.toIso8601String());
    });

    test('records every discrepancy with its type, expected and found', () {
      final expected = const [
        SpecItem(position: '1', component: 'C63'),
        SpecItem(position: '2', component: 'C32'),
        SpecItem(position: '3', component: 'C16'),
      ];
      final observed = const [
        SpecItem(position: '1', component: 'C63'),
        SpecItem(position: '2', component: 'C16'),
        SpecItem(position: '9', component: 'C20'),
      ];

      final json = buildReportJson(
        expected: expected,
        observed: observed,
        result: compare(expected, observed),
        generatedAt: generatedAt,
      );
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final discrepancies = (decoded['discrepancies'] as List)
          .cast<Map<String, dynamic>>();

      expect(decoded['isMatch'], isFalse);
      expect(decoded['counts']['missing'], 1);
      expect(decoded['counts']['mismatched'], 1);
      expect(decoded['counts']['unexpected'], 1);

      final mismatch = discrepancies.firstWhere(
        (d) => d['type'] == 'mismatched',
      );
      expect(mismatch['position'], '2');
      expect(mismatch['expected'], 'C32');
      expect(mismatch['found'], 'C16');
    });

    test('flags an unread component explicitly rather than as empty text', () {
      final json = buildReportJson(
        expected: const [SpecItem(position: '1', component: 'C63')],
        observed: const [SpecItem(position: '1', component: '')],
        result: compare(
          const [SpecItem(position: '1', component: 'C63')],
          const [SpecItem(position: '1', component: '')],
        ),
        generatedAt: generatedAt,
      );
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final observed =
          (decoded['observed'] as List).first as Map<String, dynamic>;

      expect(observed['unread'], isTrue);
      expect(decoded['counts']['unread'], 1);
    });

    test('round-trips a dense 20-row schedule without loss', () {
      final expected = [
        for (var i = 1; i <= 20; i++)
          SpecItem(position: '$i', component: 'C${i % 2 == 0 ? 32 : 16}'),
      ];
      final json = buildReportJson(
        expected: expected,
        observed: expected,
        result: compare(expected, expected),
        generatedAt: generatedAt,
      );
      final decoded = jsonDecode(json) as Map<String, dynamic>;

      expect(decoded['counts']['expected'], 20);
      expect((decoded['expected'] as List), hasLength(20));
      expect(decoded['isMatch'], isTrue);
    });
  });
}
