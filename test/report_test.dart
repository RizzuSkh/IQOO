import 'package:flutter_test/flutter_test.dart';
import 'package:parity/io/report.dart';
import 'package:parity/logic/compare.dart';
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
}
