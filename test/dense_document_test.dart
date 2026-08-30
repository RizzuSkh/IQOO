import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:parity/logic/compare.dart';
import 'package:parity/logic/ocr.dart';
import 'package:parity/logic/parser.dart';
import 'package:parity/models/spec_item.dart';

/// The failure a mentor reproduced live: small sheets parsed fine, but a
/// large hospital/school schedule failed with "didn't find... didn't find".
///
/// Root cause was NOT character recognition. ML Kit returns a three-level
/// tree (blocks -> lines -> elements) and `ocr.dart` was emitting only
/// BLOCK-level text. On a dense table ML Kit groups the whole table into a
/// couple of blocks whose `.text` is every row joined by newlines, which
/// `parser.dart` then flattened into one run-on string. Twenty rows became
/// two unparseable rows. Sparse sheets happened to work because each row
/// became its own block.
///
/// The fix is two-part and both halves are needed:
///   1. ocr.dart emits one OcrBlock per recognised LINE, so real rows survive.
///   2. parser.dart can split a single merged run ("1 C63 MAIN INCOMER"),
///      because at line granularity a table row IS one line.
///
/// These tests pin both halves against realistically dense documents.
OcrBlock block(
  String text,
  double left,
  double top, {
  double width = 600,
  double height = 60,
}) {
  return OcrBlock(
    text: text,
    boundingBox: Rect.fromLTWH(left, top, width, height),
  );
}

/// A 20-circuit hospital distribution-board schedule as OCR at LINE
/// granularity actually delivers it: one line per row, each line containing
/// position + rating + description together.
List<OcrBlock> denseHospitalSchedule() {
  const rows = [
    '1 C63 MAIN INCOMER',
    '2 C32 OPERATING THEATRE 1',
    '3 C32 OPERATING THEATRE 2',
    '4 C32 ICU BED BAY 1-4',
    '5 C32 ICU BED BAY 5-8',
    '6 C20 X-RAY IMAGING',
    '7 C20 CT SCANNER ANTEROOM',
    '8 C20 DIALYSIS UNIT',
    '9 C16 VENTILATOR SUPPLY A',
    '10 C16 VENTILATOR SUPPLY B',
    '11 C16 NURSE CALL SYSTEM',
    '12 C16 PHARMACY REFRIGERATION',
    '13 C16 PATHOLOGY LAB SOCKETS',
    '14 C10 CORRIDOR LIGHTING EAST',
    '15 C10 CORRIDOR LIGHTING WEST',
    '16 C10 WARD LIGHTING LEVEL 2',
    '17 C10 STAFF ROOM SOCKETS',
    '18 C6 EMERGENCY LIGHTING',
    '19 C6 FIRE ALARM PANEL',
    '20 C6 EXIT SIGN CIRCUIT',
  ];
  final blocks = <OcrBlock>[];
  for (var i = 0; i < rows.length; i++) {
    blocks.add(block(rows[i], 110, 300.0 + i * 90.0));
  }
  return blocks;
}

/// A school equipment list — different domain, different component format
/// (no breaker-rating codes at all), same dense single-line-per-row shape.
List<OcrBlock> denseSchoolInventory() {
  const rows = [
    '1 PROJECTOR-EPSON EB-S41 LAB A',
    '2 SWITCH-CISCO-2960 SERVER RACK',
    '3 UPS-APC-1500VA SERVER RACK',
    '4 PRINTER-HP-M404 STAFF ROOM',
    '5 ROUTER-TPLINK-AX55 LAB B',
    '6 MONITOR-DELL-P2422H LAB B',
    '7 AP-UBIQUITI-U6LR CORRIDOR',
    '8 NAS-SYNOLOGY-DS220 SERVER RACK',
    '9 SCANNER-CANON-DR2010 LIBRARY',
    '10 SPEAKER-JBL-CONTROL1 HALL',
    '11 CAMERA-HIKVISION-2CD ENTRANCE',
    '12 LAPTOP-LENOVO-T14 STAFF ROOM',
  ];
  final blocks = <OcrBlock>[];
  for (var i = 0; i < rows.length; i++) {
    blocks.add(block(rows[i], 90, 260.0 + i * 95.0));
  }
  return blocks;
}

void main() {
  group('dense hospital schedule (20 circuits, merged rows)', () {
    test('every one of the 20 rows parses — none lost to unparsedRows', () {
      final result = parseBlocks(denseHospitalSchedule());

      expect(result.items, hasLength(20));
      expect(result.unparsedRows, isEmpty);
    });

    test('positions read 1 through 20 in order, including two-digit ones', () {
      final result = parseBlocks(denseHospitalSchedule());
      expect(result.items.map((i) => i.position).toList(), [
        for (var i = 1; i <= 20; i++) '$i',
      ]);
    });

    test('ratings are extracted cleanly, descriptions never leak in', () {
      final result = parseBlocks(denseHospitalSchedule());

      expect(result.items.first.component, 'C63');
      expect(result.items[8].component, 'C16'); // position 9
      expect(result.items.last.component, 'C6'); // position 20

      // The critical assertion: no component ever contains description text.
      for (final item in result.items) {
        expect(
          item.component,
          matches(RegExp(r'^C\d{1,3}$')),
          reason: 'position ${item.position} leaked description into rating',
        );
      }
    });

    test('description text is reported as noise, not silently dropped', () {
      final result = parseBlocks(denseHospitalSchedule());
      expect(result.ignoredNoise, contains('MAIN INCOMER'));
      expect(result.ignoredNoise, contains('VENTILATOR SUPPLY A'));
      expect(result.ignoredNoise, contains('EXIT SIGN CIRCUIT'));
      expect(result.ignoredNoise, hasLength(20));
    });

    test('positions are genuinely read, not ordinal-numbered', () {
      final result = parseBlocks(denseHospitalSchedule());
      expect(result.positionsAreOrdinal, isFalse);
    });

    test('a tampered dense board produces exactly the right diff', () {
      final spec = parseBlocks(denseHospitalSchedule()).items;

      // Downrate the second theatre, remove the dialysis circuit, add an
      // unauthorised circuit at 21.
      final observed = [
        for (final item in spec)
          if (item.position != '8')
            item.position == '3' ? item.copyWith(component: 'C16') : item,
        const SpecItem(position: '21', component: 'C32'),
      ];

      final diff = compare(spec, observed);
      expect(diff.mismatched.single.position, '3');
      expect(diff.mismatched.single.expected, 'C32');
      expect(diff.mismatched.single.found, 'C16');
      expect(diff.missing.single.position, '8');
      expect(diff.unexpected.single.position, '21');
    });
  });

  group('dense school inventory (non-breaker components)', () {
    test('all 12 rows parse with hyphenated part codes intact', () {
      final result = parseBlocks(denseSchoolInventory());

      expect(result.items, hasLength(12));
      expect(result.unparsedRows, isEmpty);
      expect(result.items.first.component, 'PROJECTOR-EPSON');
      expect(result.items[4].component, 'ROUTER-TPLINK-AX55');
      expect(result.items.last.component, 'LAPTOP-LENOVO-T14');
    });

    test('location column is separated as noise, not merged into the part', () {
      final result = parseBlocks(denseSchoolInventory());
      expect(result.ignoredNoise, contains('SERVER RACK'));
      expect(result.ignoredNoise, contains('STAFF ROOM'));
      // No component carries a trailing location.
      for (final item in result.items) {
        expect(item.component, isNot(contains(' ')));
      }
    });

    test('an identical school inventory compares as a clean match', () {
      final items = parseBlocks(denseSchoolInventory()).items;
      expect(compare(items, items).isMatch, isTrue);
    });
  });

  group('splitMergedRow() unit behaviour', () {
    test('splits position, rating and description', () {
      final row = splitMergedRow('7 C10 CORRIDOR LIGHTING EAST')!;
      expect(row.position, '7');
      expect(row.component, 'C10');
      expect(row.noise, ['CORRIDOR LIGHTING EAST']);
    });

    test('keeps a spaced rating whole rather than splitting it', () {
      final row = splitMergedRow('2 C 32 OPERATING THEATRE')!;
      expect(row.component, 'C32');
      expect(row.noise, ['OPERATING THEATRE']);
    });

    test('tolerates separators OCR introduces after the position', () {
      expect(splitMergedRow('3: C16 LAB')!.component, 'C16');
      expect(splitMergedRow('4) C16 LAB')!.component, 'C16');
      expect(splitMergedRow('5. C16 LAB')!.component, 'C16');
      expect(splitMergedRow('6 - C16 LAB')!.component, 'C16');
    });

    test('a position with only a component and no description', () {
      final row = splitMergedRow('P4 NE555')!;
      expect(row.position, 'P4');
      expect(row.component, 'NE555');
      expect(row.noise, isEmpty);
    });

    test('returns null when the run does not start with a position', () {
      expect(splitMergedRow('DISTRIBUTION BOARD SCHEDULE'), isNull);
      expect(splitMergedRow('HAVELLS I-ON'), isNull);
      expect(splitMergedRow(''), isNull);
    });

    test('does not treat an electrical spec number as a position', () {
      // "6000 3" is breaking capacity + pole count, not position 6000.
      expect(splitMergedRow('6000 3'), isNull);
    });
  });
}
