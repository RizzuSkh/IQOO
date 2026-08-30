import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:parity/logic/compare.dart';
import 'package:parity/logic/parser.dart';
import 'package:parity/logic/ocr.dart';

/// Regression test for demo_assets/overlay_labels_on_mcb_photo.ps1's label
/// panel layout: the real Havells board photo (1200x1200) plus a label panel
/// starting at y=1200, rows at x=90/380, y+=170 from y=1300. Confirms the
/// panel parses cleanly regardless of what ML Kit finds elsewhere on the
/// photo itself (which is not simulated here -- this pins down the panel's
/// own layout, the thing this script controls).
OcrBlock block(
  String text,
  double left,
  double top, {
  double width = 150,
  double height = 80,
}) {
  return OcrBlock(
    text: text,
    boundingBox: Rect.fromLTWH(left, top, width, height),
  );
}

List<OcrBlock> panelBlocks(List<List<String>> rows, {double startY = 1300}) {
  final blocks = <OcrBlock>[];
  var y = startY;
  for (final row in rows) {
    blocks.add(block(row[0], 90, y, width: 80));
    if (row[1].isNotEmpty) blocks.add(block(row[1], 380, y, width: 160));
    y += 170;
  }
  return blocks;
}

void main() {
  test('match panel (6 rows) parses cleanly with no unparsed/noise', () {
    final rows = [
      ['1', 'C32'],
      ['2', 'C32'],
      ['3', 'C32'],
      ['4', 'C32'],
      ['5', 'C32'],
      ['6', 'DP'],
    ];
    final result = parseBlocks(panelBlocks(rows));
    expect(result.unparsedRows, isEmpty);
    expect(result.ignoredNoise, isEmpty);
    expect(result.items.map((i) => '${i.position}:${i.component}').toList(), [
      '1:C32',
      '2:C32',
      '3:C32',
      '4:C32',
      '5:C32',
      '6:DP',
    ]);
  });

  test('spec vs match assembly is a clean MATCH', () {
    final specRows = [
      ['1', 'C32'],
      ['2', 'C32'],
      ['3', 'C32'],
      ['4', 'C32'],
      ['5', 'C32'],
      ['6', 'DP'],
    ];
    final spec = parseBlocks(panelBlocks(specRows, startY: 180)).items;
    final assembly = parseBlocks(panelBlocks(specRows, startY: 1300)).items;
    expect(compare(spec, assembly).isMatch, isTrue);
  });

  test('tampered panel produces exactly the documented 3 discrepancies', () {
    final specRows = [
      ['1', 'C32'],
      ['2', 'C32'],
      ['3', 'C32'],
      ['4', 'C32'],
      ['5', 'C32'],
      ['6', 'DP'],
    ];
    final tamperedRows = [
      ['1', 'C32'],
      ['2', 'C16'],
      ['3', 'C32'],
      ['5', 'C32'],
      ['6', 'DP'],
      ['7', 'C32'],
    ];
    final spec = parseBlocks(panelBlocks(specRows, startY: 180)).items;
    final tampered = parseBlocks(panelBlocks(tamperedRows, startY: 1300)).items;

    final result = compare(spec, tampered);
    expect(result.isMatch, isFalse);
    expect(result.mismatched.single.position, '2');
    expect(result.mismatched.single.expected, 'C32');
    expect(result.mismatched.single.found, 'C16');
    expect(result.missing.single.position, '4');
    expect(result.unexpected.single.position, '7');
    expect(result.count, 3);
  });
}
