import '../models/spec_item.dart';
import 'ocr.dart';

/// Turns loose OCR blocks into the structured list `compare()` consumes.
///
/// The strategy is spatial and is defined in PRD section 19: group blocks into
/// rows by bounding-box Y-centre, order each row left to right, and read the
/// leftmost block as the position and the rest as the component.
///
/// Pure and deterministic — no model, no network, no I/O.

/// A position label the parser accepts, e.g. "P1" or "P12".
final RegExp _positionPattern = RegExp(r'^P\d+$');

/// Trailing punctuation OCR commonly appends to a label, e.g. "P1:" or "P1.".
final RegExp _trailingPunctuation = RegExp(r'[:.,;\-–—]+$');

/// Runs of whitespace, including the newlines ML Kit puts between block lines.
final RegExp _whitespaceRun = RegExp(r'\s+');

/// The outcome of parsing one photograph's blocks.
///
/// Rows the parser could not read as a position are kept in [unparsedRows]
/// rather than dropped, so the correction UI can surface them (PRD section 19).
class ParseResult {
  /// Rows successfully read as position plus component, in top-to-bottom order.
  final List<SpecItem> items;

  /// Raw text of rows whose leftmost block is not a position label.
  final List<String> unparsedRows;

  /// Text ML Kit found sharing a row with a real item, past the component,
  /// that was NOT folded into that item's component text.
  ///
  /// A real breadboard carries incidental text at the same height as a label —
  /// column numbers, resistor colour codes, part date codes — and none of it
  /// belongs in the component field. Surfacing it here (rather than silently
  /// discarding it, and rather than the old behaviour of appending it to the
  /// component) lets the capture screen tell the operator "N extra blocks
  /// ignored" instead of shipping a corrupted component string.
  final List<String> ignoredNoise;

  /// Creates a parse result.
  const ParseResult({
    required this.items,
    required this.unparsedRows,
    this.ignoredNoise = const [],
  });

  /// True when no row could be read as a position.
  bool get isEmpty => items.isEmpty;

  /// True when some text was recognised but no row parsed cleanly.
  bool get needsCorrection => unparsedRows.isNotEmpty;

  @override
  String toString() =>
      'ParseResult(${items.length} items, ${unparsedRows.length} unparsed, '
      '${ignoredNoise.length} noise)';
}

/// Parses OCR [blocks] into spec items by their positions on the page.
///
/// Blocks are grouped into rows using a tolerance of half the median block
/// height, ordered left to right within each row, then read as
/// `position, component`. A row with only a position yields an empty component,
/// which downstream is reported as unread and never as a match.
///
/// A row holding more than two blocks takes only the second as the component;
/// anything past that is incidental text sharing the row's height (a breadboard
/// column number, a resistor colour code, a chip date code) and is reported in
/// [ParseResult.ignoredNoise] rather than appended to the component. Appending
/// it used to silently corrupt the component string — this is why "unwanted
/// things" showed up in extracted components on real photographs.
ParseResult parseBlocks(List<OcrBlock> blocks) {
  final usable = blocks
      .where((block) => _flatten(block.text).isNotEmpty)
      .toList();
  if (usable.isEmpty) {
    return const ParseResult(items: [], unparsedRows: []);
  }

  final items = <SpecItem>[];
  final unparsedRows = <String>[];
  final ignoredNoise = <String>[];

  for (final row in groupIntoRows(usable)) {
    row.sort((a, b) => a.left.compareTo(b.left));

    final label = _asPosition(_flatten(row.first.text));
    if (label == null) {
      unparsedRows.add(row.map((block) => _flatten(block.text)).join(' '));
      continue;
    }

    final component = row.length > 1 ? _flatten(row[1].text) : '';
    if (row.length > 2) {
      ignoredNoise.addAll(row.skip(2).map((block) => _flatten(block.text)));
    }

    items.add(
      SpecItem(
        position: label,
        component: component,
        confidence: _meanConfidence(row.take(2)),
      ),
    );
  }

  return ParseResult(
    items: items,
    unparsedRows: unparsedRows,
    ignoredNoise: ignoredNoise,
  );
}

/// Groups [blocks] into rows by Y-centre, top to bottom.
///
/// The row tolerance is half the median block height, so it adapts to the
/// resolution of the photograph rather than assuming a pixel size. Exposed for
/// testing.
List<List<OcrBlock>> groupIntoRows(List<OcrBlock> blocks) {
  if (blocks.isEmpty) return [];

  final tolerance = medianHeight(blocks) / 2;
  final byHeightOnPage = [...blocks]
    ..sort((a, b) => a.centreY.compareTo(b.centreY));

  final rows = <List<OcrBlock>>[];
  var current = <OcrBlock>[byHeightOnPage.first];
  var currentMean = byHeightOnPage.first.centreY;

  for (final block in byHeightOnPage.skip(1)) {
    if ((block.centreY - currentMean).abs() <= tolerance) {
      current.add(block);
      currentMean =
          current.map((b) => b.centreY).reduce((a, b) => a + b) /
          current.length;
    } else {
      rows.add(current);
      current = <OcrBlock>[block];
      currentMean = block.centreY;
    }
  }
  rows.add(current);

  return rows;
}

/// Median bounding-box height across [blocks]. Exposed for testing.
double medianHeight(List<OcrBlock> blocks) {
  final heights = blocks.map((block) => block.height).toList()..sort();
  final middle = heights.length ~/ 2;
  if (heights.length.isOdd) return heights[middle];
  return (heights[middle - 1] + heights[middle]) / 2;
}

/// Returns [text] as a normalised position label, or null if it is not one.
String? _asPosition(String text) {
  final candidate = text
      .toUpperCase()
      .replaceAll(_trailingPunctuation, '')
      .trim();
  return _positionPattern.hasMatch(candidate) ? candidate : null;
}

/// Collapses newlines and repeated spaces so block text is a single line.
String _flatten(String text) => text.replaceAll(_whitespaceRun, ' ').trim();

/// Mean OCR confidence across [row]. Ignored-noise blocks are excluded by the
/// caller, so this reflects only the position and component that were kept.
double _meanConfidence(Iterable<OcrBlock> row) {
  final confidences = row.map((block) => block.confidence).toList();
  return confidences.reduce((a, b) => a + b) / confidences.length;
}
