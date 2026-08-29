import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:parity/logic/compare.dart';
import 'package:parity/logic/phrase.dart';
import 'package:parity/models/diff_result.dart';
import 'package:parity/models/spec_item.dart';

/// Runs compare() over the named fixture and returns its DiffResult.
DiffResult resultFromFixture(String name) {
  final fixture =
      jsonDecode(File('test/fixtures/$name').readAsStringSync())
          as Map<String, dynamic>;
  List<SpecItem> items(String key) => (fixture[key] as List)
      .map(
        (raw) => SpecItem(
          position: raw['position'] as String,
          component: raw['component'] as String,
        ),
      )
      .toList();
  return compare(items('spec'), items('assembly'));
}

void main() {
  const fixtures = [
    'case_01_missing.json',
    'case_02_mismatched.json',
    'case_03_unexpected.json',
    'case_04_unread.json',
  ];

  group('phraseWithRules() over the fixtures', () {
    for (final name in fixtures) {
      test('$name produces a usable sentence', () {
        final sentence = phraseWithRules(resultFromFixture(name));
        expect(sentence, isNotEmpty);
        expect(sentence, endsWith('.'));
        expect(sentence, startsWith('1 discrepancy:'));
        expect(sentence, contains('P'));
        expect(sentence.toLowerCase(), isNot(contains('null')));
      });
    }

    test('case_01 names the missing component and position', () {
      final sentence = phraseWithRules(
        resultFromFixture('case_01_missing.json'),
      );
      expect(sentence, contains('P2'));
      expect(sentence, contains('7805'));
    });

    test('case_02 names both the found and expected component', () {
      final sentence = phraseWithRules(
        resultFromFixture('case_02_mismatched.json'),
      );
      expect(sentence, contains('LM358'));
      expect(sentence, contains('7805'));
    });

    test('case_03 names the unexpected component', () {
      final sentence = phraseWithRules(
        resultFromFixture('case_03_unexpected.json'),
      );
      expect(sentence, contains('P4'));
      expect(sentence, contains('NE555'));
    });

    test(
      'case_04 says the position could not be read, never that it matched',
      () {
        final sentence = phraseWithRules(
          resultFromFixture('case_04_unread.json'),
        );
        expect(sentence, contains('P3'));
        expect(sentence, contains('could not be read'));
        expect(sentence, isNot(contains('matches')));
      },
    );
  });

  group('phraseWithRules() edge cases', () {
    test('an empty result states success explicitly', () {
      final sentence = phraseWithRules(const DiffResult.empty());
      expect(
        sentence,
        'No discrepancies found — the assembly matches the specification.',
      );
    });

    test(
      'a result with empty lists is treated the same as DiffResult.empty',
      () {
        const sentence = DiffResult(
          missing: [],
          unexpected: [],
          mismatched: [],
          unread: [],
        );
        expect(
          phraseWithRules(sentence),
          phraseWithRules(const DiffResult.empty()),
        );
      },
    );

    test('every discrepancy across all four lists is mentioned', () {
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
      final sentence = phraseWithRules(result);
      expect(sentence, startsWith('4 discrepancies:'));
      for (final position in ['P1', 'P2', 'P3', 'P9']) {
        expect(
          sentence,
          contains(position),
          reason: '$position must be mentioned',
        );
      }
      expect(sentence.split(';'), hasLength(4));
    });

    test('unread on both sides phrases without a null', () {
      final result = compare(
        [const SpecItem(position: 'P1', component: '')],
        [const SpecItem(position: 'P1', component: '')],
      );
      final sentence = phraseWithRules(result);
      expect(sentence, contains('could not be read on either photograph'));
      expect(sentence, isNot(contains('null')));
    });

    test('phrasing is deterministic', () {
      final result = resultFromFixture('case_02_mismatched.json');
      final first = phraseWithRules(result);
      for (var i = 0; i < 10; i++) {
        expect(phraseWithRules(result), first);
      }
    });
  });
}
