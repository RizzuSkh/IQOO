import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:parity/logic/compare.dart';
import 'package:parity/logic/ocr.dart';
import 'package:parity/logic/parser.dart';
import 'package:parity/models/spec_item.dart';

/// Verifies the hospital distribution-board blueprint
/// (demo_assets/generate_hospital_db_blueprint.ps1 ->
/// demo_spec_hospital_db.png) parses the way the generator's header comment
/// promises, replaying its actual layout coordinates as synthetic OCR
/// blocks: three columns at x = 110 / 390 / 760, rows starting at y = 330
/// and stepping 165px.
OcrBlock block(
  String text,
  double left,
  double top, {
  double width = 90,
  double height = 80,
}) {
  return OcrBlock(
    text: text,
    boundingBox: Rect.fromLTWH(left, top, width, height),
  );
}

/// The eight schedule rows at the generator's real coordinates.
List<OcrBlock> hospitalBlueprintBlocks() {
  const rows = [
    ['1', 'C63', 'MAIN INCOMER'],
    ['2', 'C32', 'OPERATING THEATRE 1'],
    ['3', 'C32', 'ICU BED BAY 1-4'],
    ['4', 'C20', 'X-RAY IMAGING'],
    ['5', 'C16', 'VENTILATOR SUPPLY'],
    ['6', 'C16', 'NURSE CALL SYSTEM'],
    ['7', 'C10', 'CORRIDOR LIGHTING'],
    ['8', 'C6', 'EMERGENCY LIGHTING'],
  ];

  final blocks = <OcrBlock>[];
  for (var i = 0; i < rows.length; i++) {
    final y = 330.0 + i * 165.0;
    blocks.add(block(rows[i][0], 110, y, width: 40));
    blocks.add(block(rows[i][1], 390, y, width: 140));
    // Description is drawn 14px lower and in a smaller face.
    blocks.add(block(rows[i][2], 760, y + 14, width: 420, height: 58));
  }
  return blocks;
}

void main() {
  group('hospital DB blueprint parses as its generator documents', () {
    test('all eight positions and ratings are read correctly', () {
      final result = parseBlocks(hospitalBlueprintBlocks());

      expect(result.items, hasLength(8));
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
      expect(result.items.map((i) => i.component).toList(), [
        'C63',
        'C32',
        'C32',
        'C20',
        'C16',
        'C16',
        'C10',
        'C6',
      ]);
    });

    test('positions are genuinely read, not auto-numbered', () {
      // This sheet DOES print its positions, so the ordinal fallback that
      // exists for unlabelled breaker panels must not fire here.
      final result = parseBlocks(hospitalBlueprintBlocks());
      expect(result.positionsAreOrdinal, isFalse);
    });

    test(
      'the CIRCUIT DESCRIPTION column lands in ignoredNoise, not the component',
      () {
        final result = parseBlocks(hospitalBlueprintBlocks());

        expect(result.ignoredNoise, contains('MAIN INCOMER'));
        expect(result.ignoredNoise, contains('OPERATING THEATRE 1'));
        expect(result.ignoredNoise, contains('EMERGENCY LIGHTING'));
        expect(result.ignoredNoise, hasLength(8));

        // Crucially, no description text leaked into a rating.
        for (final item in result.items) {
          expect(item.component, matches(RegExp(r'^C\d{1,3}$')));
        }
      },
    );

    test('every row pairs cleanly - nothing unparsed', () {
      final result = parseBlocks(hospitalBlueprintBlocks());
      expect(result.unparsedRows, isEmpty);
    });

    test('compared against itself it is a clean match', () {
      final items = parseBlocks(hospitalBlueprintBlocks()).items;
      expect(compare(items, items).isMatch, isTrue);
    });

    test('a tampered board against this spec produces the expected diff', () {
      final spec = parseBlocks(hospitalBlueprintBlocks()).items;

      // Realistic tamper: theatre breaker downrated, ventilator circuit
      // removed entirely, an unauthorised circuit added at position 9.
      final observed = [
        spec[0],
        spec[1].copyWith(component: 'C16'),
        spec[2],
        spec[3],
        spec[5],
        spec[6],
        spec[7],
        const SpecItem(position: '9', component: 'C20'),
      ];

      final diff = compare(spec, observed);
      expect(diff.mismatched.single.position, '2');
      expect(diff.mismatched.single.expected, 'C32');
      expect(diff.mismatched.single.found, 'C16');
      expect(diff.missing.single.position, '5');
      expect(diff.unexpected.single.position, '9');
    });
  });
}
