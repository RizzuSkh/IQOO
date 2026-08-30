import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:parity/logic/compare.dart';
import 'package:parity/logic/ocr.dart';
import 'package:parity/logic/parser.dart';

/// Builds a block at a pixel rectangle, the shape ML Kit returns.
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

/// A clean three-row layout: position on the left, component to its right.
/// Deliberately supplied out of reading order to prove the parser sorts.
List<OcrBlock> cleanThreeRowLayout() => [
  block('LM358', 200, 300),
  block('P1', 60, 100),
  block('7805', 200, 200),
  block('P3', 60, 300),
  block('NE555', 200, 100),
  block('P2', 60, 200),
];

void main() {
  group('parseBlocks() on a clean layout', () {
    test('reads three rows in top-to-bottom order', () {
      final result = parseBlocks(cleanThreeRowLayout());

      expect(result.items, hasLength(3));
      expect(result.unparsedRows, isEmpty);
      expect(result.items.map((i) => i.position).toList(), ['P1', 'P2', 'P3']);
      expect(result.items.map((i) => i.component).toList(), [
        'NE555',
        '7805',
        'LM358',
      ]);
    });

    test('feeds compare() a clean match against itself', () {
      final items = parseBlocks(cleanThreeRowLayout()).items;
      expect(compare(items, items).isMatch, isTrue);
    });

    test(
      'pairs the leftmost block as the position regardless of input order',
      () {
        final result = parseBlocks([
          block('NE555', 400, 100),
          block('P1', 60, 100),
        ]);
        expect(result.items.single.position, 'P1');
        expect(result.items.single.component, 'NE555');
      },
    );
  });

  group('row grouping', () {
    test('tolerates a row that is not perfectly level', () {
      // Both blocks are 30 tall, so tolerance is 15. A 10px skew stays one row.
      final result = parseBlocks([
        block('P1', 60, 100),
        block('NE555', 200, 110),
      ]);
      expect(result.items, hasLength(1));
      expect(result.items.single.component, 'NE555');
    });

    test('splits rows once the vertical gap exceeds the tolerance', () {
      final result = parseBlocks([
        block('P1', 60, 100),
        block('NE555', 200, 140),
      ]);
      // Two rows, and the second has no position label of its own, so it is
      // surfaced for correction rather than paired across the gap.
      expect(result.items.single.position, 'P1');
      expect(result.items.single.component, isEmpty);
      expect(result.unparsedRows, ['NE555']);
    });

    test('groupIntoRows returns rows top to bottom', () {
      final rows = groupIntoRows(cleanThreeRowLayout());
      expect(rows, hasLength(3));
      expect(rows.map((r) => r.length).toList(), [2, 2, 2]);
    });

    test('medianHeight averages the middle two on an even count', () {
      final blocks = [
        block('a', 0, 0, height: 10),
        block('b', 0, 100, height: 20),
        block('c', 0, 200, height: 30),
        block('d', 0, 300, height: 40),
      ];
      expect(medianHeight(blocks), 25);
    });
  });

  group('parseBlocks() on imperfect input', () {
    test(
      'a position with no component yields an empty component, never null',
      () {
        final result = parseBlocks([block('P2', 60, 200)]);
        expect(result.items.single.position, 'P2');
        expect(result.items.single.component, '');
        expect(result.items.single.isUnread, isTrue);
      },
    );

    test('a row with no recognisable position is surfaced, not dropped', () {
      final result = parseBlocks([
        block('P1', 60, 100),
        block('NE555', 200, 100),
        block('Bill of Materials', 60, 400),
      ]);
      expect(result.items, hasLength(1));
      expect(result.unparsedRows, ['Bill of Materials']);
      expect(result.needsCorrection, isTrue);
    });

    test('a third block in a row is ignored as noise, not appended', () {
      // A real breadboard puts incidental text (column numbers, colour codes)
      // at the same row height as a real label. It must not corrupt the
      // component field the way appending it used to.
      final result = parseBlocks([
        block('P1', 60, 100),
        block('NE555', 200, 100),
        block('(DIP8)', 340, 100),
      ]);
      expect(result.items.single.component, 'NE555');
      expect(result.ignoredNoise, ['(DIP8)']);
    });

    test('multiple stray blocks in one row are all reported as noise', () {
      final result = parseBlocks([
        block('P1', 60, 100),
        block('NE555', 200, 100),
        block('12', 340, 100),
        block('J7', 420, 100),
      ]);
      expect(result.items.single.component, 'NE555');
      expect(result.ignoredNoise, ['12', 'J7']);
    });

    test('noise on one row does not affect confidence of another row', () {
      final result = parseBlocks([
        block('P1', 60, 100, confidence: 1.0),
        block('NE555', 200, 100, confidence: 1.0),
        block('noise', 340, 100, confidence: 0.1),
      ]);
      expect(result.items.single.confidence, 1.0);
    });

    test('trailing punctuation on a label is tolerated', () {
      final result = parseBlocks([
        block('P1:', 60, 100),
        block('NE555', 200, 100),
      ]);
      expect(result.items.single.position, 'P1');
    });

    test('a lowercase label is normalised to uppercase', () {
      final result = parseBlocks([
        block('p4', 60, 100),
        block('7805', 200, 100),
      ]);
      expect(result.items.single.position, 'P4');
    });

    test('newlines inside a block are flattened to single spaces', () {
      final result = parseBlocks([
        block('P1', 60, 100),
        block('NE\n555', 200, 100),
      ]);
      expect(result.items.single.component, 'NE 555');
    });

    test('no blocks yields an empty result rather than throwing', () {
      final result = parseBlocks([]);
      expect(result.items, isEmpty);
      expect(result.unparsedRows, isEmpty);
      expect(result.isEmpty, isTrue);
    });

    test('blank blocks are ignored', () {
      final result = parseBlocks([
        block('   ', 0, 100),
        block('P1', 60, 100),
        block('NE555', 200, 100),
      ]);
      expect(result.items.single.component, 'NE555');
      expect(result.unparsedRows, isEmpty);
    });

    test('confidence is averaged across the row', () {
      final result = parseBlocks([
        block('P1', 60, 100, confidence: 0.8),
        block('NE555', 200, 100, confidence: 0.6),
      ]);
      expect(result.items.single.confidence, closeTo(0.7, 1e-9));
    });

    test('parsing is deterministic', () {
      final blocks = cleanThreeRowLayout();
      final first = parseBlocks(blocks).items.toString();
      for (var i = 0; i < 10; i++) {
        expect(parseBlocks(blocks).items.toString(), first);
      }
    });
  });

  group('bare-digit positions (the team\'s actual verified BOM format)', () {
    // Breadboard_Bill_of_Materials.pdf's POSITION column reads "1", "2", "3",
    // "4" -- not "P1" style. The parser used to reject every one of these,
    // regardless of photo quality, sending the whole document to
    // unparsedRows. This is that exact document's text, replayed as OCR
    // blocks would deliver it: position, component, then a third
    // DESCRIPTION-column block that must be ignored, not appended.
    test('a bare digit is accepted as a position', () {
      final result = parseBlocks([
        block('1', 60, 100),
        block('NE555', 200, 100),
      ]);
      expect(result.items.single.position, '1');
      expect(result.unparsedRows, isEmpty);
    });

    test(
      'the real BOM table parses correctly, including the DESCRIPTION column as noise',
      () {
        final result = parseBlocks([
          block('1', 60, 100),
          block('NE555', 200, 100),
          block('Timer IC', 400, 100, width: 160),
          block('2', 60, 260),
          block('7805', 200, 260),
          block('Voltage Regulator', 400, 260, width: 260),
          block('3', 60, 420),
          block('LM358', 200, 420),
          block('Dual Op-Amp', 400, 420, width: 200),
        ]);
        expect(result.unparsedRows, isEmpty);
        expect(
          result.items.map((i) => '${i.position}:${i.component}').toList(),
          ['1:NE555', '2:7805', '3:LM358'],
        );
        expect(result.ignoredNoise, [
          'Timer IC',
          'Voltage Regulator',
          'Dual Op-Amp',
        ]);
      },
    );

    test(
      '"P1" style still works -- the fix is additive, not a breaking change',
      () {
        final result = parseBlocks([
          block('P1', 60, 100),
          block('NE555', 200, 100),
        ]);
        expect(result.items.single.position, 'P1');
      },
    );

    test(
      'a bare-digit spec matches a bare-digit assembly reading the same board',
      () {
        final spec = parseBlocks([
          block('1', 60, 100),
          block('NE555', 200, 100),
          block('2', 60, 260),
          block('7805', 200, 260),
        ]).items;
        final assembly = parseBlocks([
          block('1', 60, 100),
          block('NE555', 200, 100),
          block('2', 60, 260),
          block('7805', 200, 260),
        ]).items;
        expect(compare(spec, assembly).isMatch, isTrue);
      },
    );
  });

  group('Circuit breaker, diagram models & JSON conversion', () {
    test('extracts position P1 and ampere value 16A from merged single block', () {
      final result = parseBlocks([
        block('P1 16A', 60, 100),
      ]);
      expect(result.items, hasLength(1));
      expect(result.items.single.position, 'P1');
      expect(result.items.single.component, '16A');
    });

    test('extracts required 16A rating from noisy circuit breaker text', () {
      final result = parseBlocks([
        block('CB1', 60, 100),
        block('16A 240V AC 50Hz IEC/EN 60898-1 Schneider Electric', 200, 100),
      ]);
      expect(result.items, hasLength(1));
      expect(result.items.single.position, 'CB1');
      expect(result.items.single.component, '16A');
    });

    test('extracts C16 curve rating from circuit breaker text', () {
      final result = parseBlocks([
        block('P1: C16 415V 6000A', 60, 100),
      ]);
      expect(result.items, hasLength(1));
      expect(result.items.single.position, 'P1');
      expect(result.items.single.component, 'C16');
    });

    test('supports circuit diagram designation codes (CB1, Q1, F1, SW1)', () {
      final result = parseBlocks([
        block('CB1 16A', 60, 100),
        block('Q1 32A', 60, 200),
        block('F1 10A', 60, 300),
      ]);
      expect(result.items.map((i) => '${i.position}:${i.component}').toList(), [
        'CB1:16A',
        'Q1:32A',
        'F1:10A',
      ]);
    });

    test('converts OCR blocks directly to structured JSON maps', () {
      final blocks = [
        block('P1 16A', 60, 100),
        block('P2 32A', 60, 200),
      ];
      final jsonList = parseBlocksToJson(blocks);
      expect(jsonList, [
        {'position': 'P1', 'component': '16A', 'confidence': 1.0},
        {'position': 'P2', 'component': '32A', 'confidence': 1.0},
      ]);
    });

    test('ParseResult JSON serialization roundtrip', () {
      final original = parseBlocks([
        block('P1 16A', 60, 100),
      ]);
      final jsonMap = original.toJson();
      final reconstructed = ParseResult.fromJson(jsonMap);
      expect(reconstructed.items.single.position, 'P1');
      expect(reconstructed.items.single.component, '16A');
    });
  });
}
