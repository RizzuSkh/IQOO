import 'package:flutter_test/flutter_test.dart';
import 'package:parity/models/spec_item.dart';
import 'package:parity/models/diff_result.dart';
import 'package:parity/logic/compare.dart';

void main() {
  group('compare() tests', () {
    test('Identical lists return match', () {
      final spec = [
        const SpecItem(position: 'P1', component: 'NE555'),
        const SpecItem(position: 'P2', component: 'LM358'),
      ];
      final assembly = [
        const SpecItem(position: 'P1', component: 'NE555'),
        const SpecItem(position: 'P2', component: 'LM358'),
      ];

      final result = compare(spec, assembly);
      expect(result.isMatch, true);
      expect(result.all, isEmpty);
    });

    test('Missing component detected', () {
      final spec = [
        const SpecItem(position: 'P1', component: 'NE555'),
        const SpecItem(position: 'P2', component: 'LM358'),
      ];
      final assembly = [
        const SpecItem(position: 'P1', component: 'NE555'),
      ];

      final result = compare(spec, assembly);
      expect(result.isMatch, false);
      expect(result.missing.length, 1);
      expect(result.missing.first.type, DiffType.missing);
      expect(result.missing.first.position, 'P2');
      expect(result.missing.first.expected, 'LM358');
    });

    test('Unexpected component detected', () {
      final spec = [
        const SpecItem(position: 'P1', component: 'NE555'),
      ];
      final assembly = [
        const SpecItem(position: 'P1', component: 'NE555'),
        const SpecItem(position: 'P2', component: 'LM358'),
      ];

      final result = compare(spec, assembly);
      expect(result.isMatch, false);
      expect(result.unexpected.length, 1);
      expect(result.unexpected.first.type, DiffType.unexpected);
      expect(result.unexpected.first.position, 'P2');
      expect(result.unexpected.first.found, 'LM358');
    });

    test('Mismatched component detected', () {
      final spec = [
        const SpecItem(position: 'P1', component: 'NE555'),
      ];
      final assembly = [
        const SpecItem(position: 'P1', component: 'LM358'),
      ];

      final result = compare(spec, assembly);
      expect(result.isMatch, false);
      expect(result.mismatched.length, 1);
      expect(result.mismatched.first.type, DiffType.mismatched);
      expect(result.mismatched.first.position, 'P1');
      expect(result.mismatched.first.expected, 'NE555');
      expect(result.mismatched.first.found, 'LM358');
    });

    test('Unread component detected', () {
      final spec = [
        const SpecItem(position: 'P1', component: 'NE555'),
      ];
      final assembly = [
        const SpecItem(position: 'P1', component: ''),
      ];

      final result = compare(spec, assembly);
      expect(result.isMatch, false);
      expect(result.unread.length, 1);
      expect(result.unread.first.type, DiffType.unread);
      expect(result.unread.first.position, 'P1');
    });

    test('Case-insensitive matching', () {
      final spec = [
        const SpecItem(position: 'p1', component: 'ne555'),
      ];
      final assembly = [
        const SpecItem(position: 'p1', component: 'NE555'),
      ];

      final result = compare(spec, assembly);
      expect(result.isMatch, true);
    });
  });
}
