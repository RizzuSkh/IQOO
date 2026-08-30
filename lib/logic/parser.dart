import '../models/spec_item.dart';
import 'ocr.dart';

/// Turns loose OCR blocks into the structured list `compare()` consumes.
///
/// The strategy is spatial and is defined in PRD section 19: group blocks into
/// rows by bounding-box Y-centre, order each row left to right, and read the
/// leftmost block as the position and the rest as the component.
///
/// Pure and deterministic — no model, no network, no I/O.

/// A position label the parser accepts: an optional "P" prefix, then 1-3
/// digits. Matches both "P1" (PRD section 17's example) and a bare "1" — the
/// team's actual verified Bill of Materials (Breadboard_Bill_of_Materials.pdf)
/// uses bare numbers in its POSITION column, not "P1" style, and the parser
/// used to reject every one of them, sending the whole document to
/// unparsedRows regardless of photo quality or crop.
///
/// Capped at 3 digits on purpose: a real distribution board prints its own
/// electrical ratings as bare numbers too — "6000" (breaking capacity in
/// amps), "10000" — and an uncapped pattern happily accepted those as
/// "position 6000", a real board's own spec text quietly becoming wrong
/// data instead of being rejected. No assembly in this project's scope has
/// anywhere near 1000 positions, so this loses nothing real.
final RegExp _positionPattern = RegExp(r'^P?\d{1,3}$');

/// A breaker/MCB rating code: an IEC 60898 curve letter (B, C, D — the
/// common residential/commercial trip curves — plus K and Z for specialised
/// breakers) followed by the current rating, with or without the space OCR
/// sometimes keeps ("C32" and "C 32" both occur on real printed labels), and
/// an optional trailing "A" for amps.
///
/// This is what [parseBreakerRow] looks for when a photograph has no printed
/// position numbers at all — which is the normal case for a real breaker
/// panel. Manufacturers print the rating on the breaker; they do not print
/// "position 1, position 2..." anywhere. That numbering only exists in the
/// specification document, so on the assembly side it has to come from
/// left-to-right reading order instead.
final RegExp _ratingPattern = RegExp(r'^[BCDKZ]\s?\d{1,3}A?$');

/// Text that looks numeric or spec-like but is not a rating: the rest of
/// what's actually printed on a breaker alongside its curve/current code —
/// breaking capacity ("6000", "10000"), voltage ("230/400V~", "240/415V~"),
/// pole markings ("1 3", "2 4"), bare pole counts ("3"). None of this is
/// wrong to read — it just is not the field the comparison cares about, and
/// folding it into the component text is exactly the "unwanted things"
/// problem the project already fixed once for incidental row noise.

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

  /// True when [items]' positions were not read from the photo at all, but
  /// assigned left-to-right because nothing in the image looked like a
  /// printed position label. See [parseBreakerRow] — the normal case for a
  /// real, unlabelled breaker panel. The UI should say so explicitly rather
  /// than presenting invented numbering as if it had been read.
  final bool positionsAreOrdinal;

  /// Creates a parse result.
  const ParseResult({
    required this.items,
    required this.unparsedRows,
    this.ignoredNoise = const [],
    this.positionsAreOrdinal = false,
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

  if (items.isNotEmpty) {
    return ParseResult(
      items: items,
      unparsedRows: unparsedRows,
      ignoredNoise: ignoredNoise,
    );
  }

  // No printed position label anywhere — the normal case for a real,
  // unmodified breaker panel (PRD section 19's small-print problem, but
  // worse: there is no position number to read even at a readable size,
  // because manufacturers print ratings, not positions). Try reading it as
  // a row of breakers instead, numbered by reading order.
  final fallback = parseBreakerRow(usable);
  if (fallback.items.isNotEmpty) return fallback;

  return ParseResult(
    items: items,
    unparsedRows: unparsedRows,
    ignoredNoise: ignoredNoise,
  );
}

/// Reads [blocks] as a row of breakers with no printed position numbers,
/// the shape a real MCB/distribution panel actually is: each breaker prints
/// its own rating code (PRD section 19's small print, e.g. "C32") stacked
/// with other spec text (breaking capacity, voltage, pole count) that is not
/// the rating. There is no field anywhere labelled "position" — a technician
/// reading the panel would count breakers left to right, so that is what
/// this does: cluster blocks into columns by X-proximity, take the rating
/// code out of each column, and number the columns that actually produced
/// one, left to right, starting at 1.
///
/// Returns an empty [ParseResult] (not a partial one) if nothing in [blocks]
/// looks like a rating code at all — that means this isn't a breaker panel,
/// and inventing positions over unrelated text would be worse than admitting
/// nothing was found.
ParseResult parseBreakerRow(List<OcrBlock> blocks) {
  final usable = blocks
      .where((block) => _flatten(block.text).isNotEmpty)
      .toList();
  if (usable.isEmpty) {
    return const ParseResult(items: [], unparsedRows: []);
  }

  final items = <SpecItem>[];
  final ignoredNoise = <String>[];
  var position = 0;

  for (final column in _clusterByX(usable)) {
    column.sort((a, b) => a.centreY.compareTo(b.centreY));

    OcrBlock? rating;
    for (final block in column) {
      if (_asRating(_flatten(block.text)) != null) {
        rating = block;
        break;
      }
    }

    if (rating == null) {
      ignoredNoise.addAll(column.map((block) => _flatten(block.text)));
      continue;
    }

    position += 1;
    ignoredNoise.addAll(
      column
          .where((block) => block != rating)
          .map((block) => _flatten(block.text)),
    );

    items.add(
      SpecItem(
        position: '$position',
        component: _asRating(_flatten(rating.text))!,
        confidence: rating.confidence,
      ),
    );
  }

  if (items.isEmpty) {
    return ParseResult(
      items: const [],
      unparsedRows: usable.map((block) => _flatten(block.text)).toList(),
    );
  }

  return ParseResult(
    items: items,
    unparsedRows: const [],
    ignoredNoise: ignoredNoise,
    positionsAreOrdinal: true,
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

/// Groups [blocks] into columns by X-centre, left to right — the same idea
/// as [groupIntoRows] turned 90 degrees, for a row of breakers where each
/// breaker's stacked text (rating, voltage, capacity) shares an X position
/// instead of a Y position. Exposed for testing.
List<List<OcrBlock>> _clusterByX(List<OcrBlock> blocks) {
  if (blocks.isEmpty) return [];

  final tolerance = medianWidth(blocks) * 0.75;
  final byX = [...blocks]..sort((a, b) => a.centreX.compareTo(b.centreX));

  final columns = <List<OcrBlock>>[];
  var current = <OcrBlock>[byX.first];
  var currentMean = byX.first.centreX;

  for (final block in byX.skip(1)) {
    if ((block.centreX - currentMean).abs() <= tolerance) {
      current.add(block);
      currentMean =
          current.map((b) => b.centreX).reduce((a, b) => a + b) /
          current.length;
    } else {
      columns.add(current);
      current = <OcrBlock>[block];
      currentMean = block.centreX;
    }
  }
  columns.add(current);

  return columns;
}

/// Median bounding-box width across [blocks]. Exposed for testing.
double medianWidth(List<OcrBlock> blocks) {
  final widths = blocks.map((block) => block.width).toList()..sort();
  final middle = widths.length ~/ 2;
  if (widths.length.isOdd) return widths[middle];
  return (widths[middle - 1] + widths[middle]) / 2;
}

/// Returns [text] as a normalised position label, or null if it is not one.
String? _asPosition(String text) {
  final candidate = text
      .toUpperCase()
      .replaceAll(_trailingPunctuation, '')
      .trim();
  return _positionPattern.hasMatch(candidate) ? candidate : null;
}

/// Returns [text] as a normalised breaker rating, or null if it is not one.
/// Normalises away the optional internal space ("C 32" -> "C32") so the
/// same true rating reads identically regardless of how OCR spaced it.
String? _asRating(String text) {
  final candidate = text
      .toUpperCase()
      .replaceAll(_trailingPunctuation, '')
      .trim();
  if (!_ratingPattern.hasMatch(candidate)) return null;
  return candidate.replaceAll(' ', '');
}

/// Collapses newlines and repeated spaces so block text is a single line.
String _flatten(String text) => text.replaceAll(_whitespaceRun, ' ').trim();

/// Mean OCR confidence across [row]. Ignored-noise blocks are excluded by the
/// caller, so this reflects only the position and component that were kept.
double _meanConfidence(Iterable<OcrBlock> row) {
  final confidences = row.map((block) => block.confidence).toList();
  return confidences.reduce((a, b) => a + b) / confidences.length;
}
