import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:parity/logic/compare.dart';
import 'package:parity/models/diff_result.dart';
import 'package:parity/models/spec_item.dart';

/// Loads a fixture from test/fixtures by file name.
Map<String, dynamic> loadFixture(String name) {
  final file = File('test/fixtures/$name');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

/// Builds the SpecItem list held under [key] in a fixture.
List<SpecItem> itemsFrom(Map<String, dynamic> fixture, String key) {
  return (fixture[key] as List)
      .map(
        (raw) => SpecItem(
          position: raw['position'] as String,
          component: raw['component'] as String,
        ),
      )
      .toList();
}

/// Reduces discrepancies to the plain maps a fixture's "expected" block uses.
List<Map<String, dynamic>> asFixtureShape(List<Discrepancy> discrepancies) {
  return discrepancies.map((d) {
    return <String, dynamic>{
      'position': d.position,
      if (d.expected != null) 'expected': d.expected,
      if (d.found != null) 'found': d.found,
    };
  }).toList();
}

/// Asserts compare() reproduces the fixture's expected block exactly.
void expectFixture(String name) {
  final fixture = loadFixture(name);
  final expected = fixture['expected'] as Map<String, dynamic>;
  final result = compare(
    itemsFrom(fixture, 'spec'),
    itemsFrom(fixture, 'assembly'),
  );

  expect(
    asFixtureShape(result.missing),
    expected['missing'],
    reason: '$name missing',
  );
  expect(
    asFixtureShape(result.unexpected),
    expected['unexpected'],
    reason: '$name unexpected',
  );
  expect(
    asFixtureShape(result.mismatched),
    expected['mismatched'],
    reason: '$name mismatched',
  );
  expect(
    asFixtureShape(result.unread),
    expected['unread'],
    reason: '$name unread',
  );

  final total =
      (expected['missing'] as List).length +
      (expected['unexpected'] as List).length +
      (expected['mismatched'] as List).length +
      (expected['unread'] as List).length;
  expect(result.isMatch, total == 0, reason: '$name isMatch');
}

void main() {
  group('compare() against shared fixtures', () {
    test('case_01_missing', () => expectFixture('case_01_missing.json'));
    test('case_02_mismatched', () => expectFixture('case_02_mismatched.json'));
    test('case_03_unexpected', () => expectFixture('case_03_unexpected.json'));
    test('case_04_unread', () => expectFixture('case_04_unread.json'));
  });

  group('compare() invariants', () {
    test('identical lists produce a match', () {
      const items = [
        SpecItem(position: 'P1', component: 'NE555'),
        SpecItem(position: 'P2', component: '7805'),
      ];
      expect(compare(items, items).isMatch, isTrue);
    });

    test('two empty lists produce a match', () {
      expect(compare([], []).isMatch, isTrue);
    });

    test('unread is never reported as a match', () {
      final result = compare(
        [const SpecItem(position: 'P1', component: 'NE555')],
        [const SpecItem(position: 'P1', component: '')],
      );
      expect(result.isMatch, isFalse);
      expect(result.unread.single.type, DiffType.unread);
      expect(result.unread.single.expected, 'NE555');
      expect(result.mismatched, isEmpty);
      expect(result.missing, isEmpty);
    });

    test('whitespace-only component counts as unread', () {
      final result = compare(
        [const SpecItem(position: 'P1', component: 'NE555')],
        [const SpecItem(position: 'P1', component: '   ')],
      );
      expect(result.unread, hasLength(1));
    });

    test('comparison is case-insensitive and trimmed', () {
      final result = compare(
        [const SpecItem(position: 'p1 ', component: ' ne555')],
        [const SpecItem(position: 'P1', component: 'NE555 ')],
      );
      expect(result.isMatch, isTrue);
    });

    test('internal whitespace is a mismatch, not a match', () {
      final result = compare(
        [const SpecItem(position: 'P1', component: 'NE555')],
        [const SpecItem(position: 'P1', component: 'NE 555')],
      );
      expect(result.mismatched.single.found, 'NE 555');
    });

    test('unread on both sides is reported, not dropped', () {
      final result = compare(
        [const SpecItem(position: 'P1', component: '')],
        [const SpecItem(position: 'P1', component: '')],
      );
      expect(result.isMatch, isFalse);
      expect(result.unread.single.expected, isNull);
    });

    test('the four lists are disjoint and total the count', () {
      final result = compare(
        [
          const SpecItem(position: 'P1', component: 'NE555'),
          const SpecItem(position: 'P2', component: '7805'),
          const SpecItem(position: 'P3', component: 'LM358'),
        ],
        [
          const SpecItem(position: 'P2', component: 'LM358'),
          const SpecItem(position: 'P3', component: ''),
          const SpecItem(position: 'P9', component: 'NE555'),
        ],
      );
      expect(result.missing.single.position, 'P1');
      expect(result.mismatched.single.position, 'P2');
      expect(result.unread.single.position, 'P3');
      expect(result.unexpected.single.position, 'P9');
      expect(result.count, 4);
      expect(result.all, hasLength(4));
    });

    test('is deterministic across repeated runs', () {
      final spec = [
        const SpecItem(position: 'P1', component: 'NE555'),
        const SpecItem(position: 'P2', component: '7805'),
      ];
      final assembly = [const SpecItem(position: 'P2', component: 'LM358')];
      final first = compare(spec, assembly).toString();
      for (var i = 0; i < 20; i++) {
        expect(compare(spec, assembly).toString(), first);
      }
    });
  });
}
