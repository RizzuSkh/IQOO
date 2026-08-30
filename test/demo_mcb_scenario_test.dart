import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:parity/logic/compare.dart';
import 'package:parity/logic/parser.dart';
import 'package:parity/logic/ocr.dart';

/// Regression test for demo_assets/generate_mcb_demo.ps1: pins down that the
/// MCB blueprint + illustrated-panel layout parses into position+rating
/// pairs correctly, using synthetic OCR blocks at the generator's actual
/// coordinates and font scale (same technique as
/// demo_realistic_scenario_test.dart for the breadboard set).
OcrBlock block(
  String text,
  double left,
  double top, {
  double width = 140,
  double height = 80,
}) {
  return OcrBlock(
    text: text,
    boundingBox: Rect.fromLTWH(left, top, width, height),
  );
}

/// The five spec rows at the generator's actual x=90/420, y=700+190*n coords.
List<OcrBlock> _specBlocks() => [
  block('1', 90, 700),
  block('32A', 420, 700, width: 160),
  block('2', 90, 890),
  block('20A', 420, 890, width: 160),
  block('3', 90, 1080),
  block('16A', 420, 1080, width: 160),
  block('4', 90, 1270),
  block('6A', 420, 1270, width: 120),
  block('5', 90, 1460),
  block('32A', 420, 1460, width: 160),
];

void main() {
  group('demo_spec_mcb.png layout', () {
    test('parses as five clean position/rating rows', () {
      final result = parseBlocks(_specBlocks());
      expect(result.unparsedRows, isEmpty);
      expect(result.items.map((i) => '${i.position}:${i.component}').toList(), [
        '1:32A',
        '2:20A',
        '3:16A',
        '4:6A',
        '5:32A',
      ]);
    });
  });

  group(
    'demo_assembly_mcb_*.png label panel (below the illustrated board, y=700+)',
    () {
      test('match scenario is identical to the spec', () {
        final spec = parseBlocks(_specBlocks()).items;
        final assembly = parseBlocks(
          _specBlocks(),
        ).items; // same layout in the match asset
        expect(compare(spec, assembly).isMatch, isTrue);
      });

      test(
        'tampered scenario (2 mismatched, 4 missing, 6 unexpected) matches the documented diff',
        () {
          final tamperedBlocks = [
            block('1', 90, 700),
            block('32A', 420, 700, width: 160),
            block('2', 90, 890),
            block('16A', 420, 890, width: 160),
            block('3', 90, 1080),
            block('16A', 420, 1080, width: 160),
            block('5', 90, 1270),
            block('32A', 420, 1270, width: 160),
            block('6', 90, 1460),
            block('20A', 420, 1460, width: 160),
          ];
          final spec = parseBlocks(_specBlocks()).items;
          final tampered = parseBlocks(tamperedBlocks).items;

          final result = compare(spec, tampered);
          expect(result.isMatch, isFalse);
          expect(result.mismatched.single.position, '2');
          expect(result.mismatched.single.expected, '20A');
          expect(result.mismatched.single.found, '16A');
          expect(result.missing.single.position, '4');
          expect(result.missing.single.expected, '6A');
          expect(result.unexpected.single.position, '6');
          expect(result.unexpected.single.found, '20A');
        },
      );
    },
  );
}
