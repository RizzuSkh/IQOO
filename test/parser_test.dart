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

    test('extra blocks in a row are appended, not discarded', () {
      final result = parseBlocks([
        block('P1', 60, 100),
        block('NE555', 200, 100),
        block('(DIP8)', 340, 100),
      ]);
      expect(result.items.single.component, 'NE555 (DIP8)');
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
}
