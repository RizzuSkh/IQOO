import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:parity/logic/compare.dart';
import 'package:parity/logic/ocr.dart';
import 'package:parity/logic/parser.dart';

/// Regression tests for the second parsing strategy this fixes: a real
/// breaker panel photograph has NO printed position numbers at all -- only
/// each breaker's own rating code mixed with other spec text (breaking
/// capacity, voltage, pole count). The user reported this exact failure
/// against their real Havells board ("found 25 blocks but none started
/// with... it reads havells havells") and a second real DIN-rail panel
/// (C63/C32/C16.../6A, with visible "6000" and "240/415V" noise) -- both
/// replayed here at approximate real coordinates.
OcrBlock block(
  String text,
  double left,
  double top, {
  double width = 90,
  double height = 30,
  double confidence = 1.0,
}) {
  return OcrBlock(
    text: text,
    boundingBox: Rect.fromLTWH(left, top, width, height),
    confidence: confidence,
  );
}

/// Six Havells breakers side by side, each contributing its own
/// HAVELLS / I-ON / rating / model column, matching the real photo's actual
/// text and approximate layout (five C32 single-pole breakers, then a DP
/// isolator with no rating printed on it at all).
List<OcrBlock> havellsBoardBlocks() {
  final blocks = <OcrBlock>[];
  const columnLefts = [100.0, 260.0, 420.0, 580.0, 740.0, 900.0];
  const ratings = ['C 32', 'C 32', 'C 32', 'C 32', 'C 32', null];
  for (var i = 0; i < columnLefts.length; i++) {
    final x = columnLefts[i];
    blocks.add(block('HAVELLS', x, 100, width: 120));
    blocks.add(block('I-ON', x, 160, width: 60));
    final rating = ratings[i];
    if (rating != null) blocks.add(block(rating, x, 220, width: 80));
    blocks.add(block('DHMGCSPF032', x, 260, width: 140));
    if (rating != null) blocks.add(block('10000', x, 300, width: 70));
    if (rating != null) blocks.add(block('3', x + 75, 300, width: 20));
  }
  return blocks;
}

/// Nine breakers on a DIN rail: C63 (2-pole main), a blank 2-pole switch,
/// then C32/C16/C16/C16/C10/C10/C6, each with a voltage line and a breaking
/// capacity line -- matching the second real photo.
List<OcrBlock> dinRailBoardBlocks() {
  final ratings = ['C63', null, 'C32', 'C16', 'C16', 'C16', 'C10', 'C10', 'C6'];
  final blocks = <OcrBlock>[];
  for (var i = 0; i < ratings.length; i++) {
    final x = 80.0 + i * 130.0;
    final rating = ratings[i];
    if (rating != null) {
      blocks.add(block(rating, x, 400, width: 80));
      blocks.add(block('230/400V~', x, 440, width: 110));
      blocks.add(block('6000', x, 480, width: 60));
      blocks.add(block('3', x + 65, 480, width: 20));
    } else {
      blocks.add(block('1  3', x, 400, width: 60));
      blocks.add(block('2  4', x, 440, width: 60));
    }
  }
  return blocks;
}

void main() {
  group('the real problem: a raw board photo has zero position labels', () {
    test(
      'the primary row-based parser alone finds nothing on the raw Havells photo',
      () {
        // Reproduces the exact failure reported ("found 25 blocks but none
        // started with... it reads havells havells") before asserting the
        // fix below: the row-based strategy alone, without the fallback,
        // must not manufacture items from this photo. "3" (a genuine pole
        // count) is a valid short number and is expected to end up folded
        // into the same unparsed row as "10000" rather than read alone --
        // that pairing is exactly why groupIntoRows exists.
        final unparsedOnly = <String>[];
        for (final row in groupIntoRows(havellsBoardBlocks())) {
          row.sort((a, b) => a.left.compareTo(b.left));
          unparsedOnly.add(row.first.text);
        }
        // None of the real leftmost-per-row text is a clean position label.
        expect(unparsedOnly, isNot(contains('1')));
        expect(unparsedOnly, isNot(contains('2')));
      },
    );
  });

  group('parseBreakerRow() reads a real, unlabelled breaker panel', () {
    test(
      'Havells board: 5 breakers rated, positions auto-numbered 1-5, DP skipped',
      () {
        final result = parseBlocks(havellsBoardBlocks());
        expect(result.positionsAreOrdinal, isTrue);
        expect(
          result.items.map((i) => '${i.position}:${i.component}').toList(),
          ['1:C32', '2:C32', '3:C32', '4:C32', '5:C32'],
        );
        expect(result.ignoredNoise, contains('HAVELLS'));
        expect(result.ignoredNoise, contains('DHMGCSPF032'));
        expect(result.ignoredNoise, contains('10000'));
        expect(result.ignoredNoise, contains('3'));
        expect(result.ignoredNoise, contains('I-ON'));
      },
    );

    test(
      'DIN rail board: 7 rated breakers correctly extracted in order, main isolator skipped',
      () {
        final result = parseBlocks(dinRailBoardBlocks());
        expect(result.positionsAreOrdinal, isTrue);
        expect(result.items.map((i) => i.component).toList(), [
          'C63',
          'C32',
          'C16',
          'C16',
          'C16',
          'C10',
          'C10',
          'C6',
        ]);
        expect(result.items.map((i) => i.position).toList(), [
          '1',
          '2',
          '3',
          '4',
          '5',
          '6',
          '7',
          '8',
        ]);
        expect(result.ignoredNoise, contains('230/400V~'));
        expect(result.ignoredNoise, contains('6000'));
      },
    );

    test(
      'a photo with no rating-like text anywhere yields nothing, not fabricated positions',
      () {
        final result = parseBreakerRow([
          block('Bill of Materials', 100, 100, width: 200),
          block('Warning: switch off before opening', 100, 200, width: 300),
        ]);
        expect(result.items, isEmpty);
        expect(result.positionsAreOrdinal, isFalse);
        expect(result.unparsedRows, isNotEmpty);
      },
    );

    test(
      '"C 32" and "C32" (with and without the OCR space) read as the same rating',
      () {
        final spaced = parseBreakerRow([block('C 32', 100, 100)]);
        final tight = parseBreakerRow([block('C32', 400, 100)]);
        expect(spaced.items.single.component, 'C32');
        expect(tight.items.single.component, 'C32');
      },
    );

    test('lowercase rating text is normalised', () {
      final result = parseBreakerRow([block('c16', 100, 100)]);
      expect(result.items.single.component, 'C16');
    });
  });

  group(
    '_positionPattern no longer accepts electrical spec numbers as positions',
    () {
      test(
        'a bare "6000" (breaking capacity) is not read as a position label',
        () {
          // Regression: the pattern used to be unbounded (^P?\d+$), so a
          // real board's own "6000"/"10000" breaking-capacity print could
          // be mistaken for "position 6000". A lone "6000" block must not
          // produce an item.
          final result = parseBlocks([block('6000', 100, 100)]);
          expect(result.items, isEmpty);
        },
      );

      test('a normal 1-3 digit position still works exactly as before', () {
        final result = parseBlocks([
          block('7', 100, 100),
          block('C16', 300, 100),
        ]);
        expect(result.items.single.position, '7');
        expect(result.items.single.component, 'C16');
      });
    },
  );

  group('end to end: the fallback feeds compare() correctly', () {
    test(
      'a real-shaped tampered assembly against a hand-typed spec produces the right diff',
      () {
        final assembly = parseBlocks(havellsBoardBlocks()).items;
        final spec = [
          for (final position in ['1', '2', '3', '4', '5'])
            assembly.firstWhere((i) => i.position == position),
        ];
        // Tamper: physically swap position 2's rating in the spec only, so
        // a real mismatch is detected against the auto-numbered real photo.
        final tamperedSpec = [
          spec[0],
          spec[1].copyWith(component: 'C16'),
          spec[2],
          spec[3],
          spec[4],
        ];
        final diff = compare(tamperedSpec, assembly);
        expect(diff.mismatched.single.position, '2');
        expect(diff.mismatched.single.found, 'C32');
      },
    );
  });
}
