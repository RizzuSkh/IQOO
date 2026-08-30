import '../models/spec_item.dart';
import 'ocr.dart';

/// Turns loose OCR blocks into the structured list `compare()` consumes.
///
/// The strategy is spatial and is defined in PRD section 19: group blocks into
/// rows by bounding-box Y-centre, order each row left to right, and read the
/// leftmost block as the position and the rest as the component.
///
/// Pure and deterministic — no model, no network, no I/O.

/// Extended position pattern supporting P1, CB1, Q1, F1, SW1, L1, or bare digits (capped at 3 digits).
final RegExp _positionPattern = RegExp(
  r'^(P|CB|Q|F|SW|L|POS|POSITION)?\s*[:#\-\=]?\s*\d{1,3}$',
  caseSensitive: false,
);

/// Pattern to match leading position in combined text blocks (e.g. "P1 16A" or "CB1: 16A 240V").
final RegExp _combinedPositionPattern = RegExp(
  r'^(P|CB|Q|F|SW|L|POS|POSITION)?\s*[:#\-\=]?\s*(\d{1,3})\b',
  caseSensitive: false,
);

/// A breaker/MCB rating code: an IEC 60898 curve letter (B, C, D — the
/// common residential/commercial trip curves — plus K and Z for specialised
/// breakers) followed by the current rating.
final RegExp _ratingPattern =
    RegExp(r'^[BCDKZ]\s?\d{1,3}A?$', caseSensitive: false);

/// Trailing punctuation OCR commonly appends to a label, e.g. "P1:" or "P1.".
final RegExp _trailingPunctuation = RegExp(r'[:.,;\-–—]+$');

/// Runs of whitespace, including the newlines ML Kit puts between block lines.
final RegExp _whitespaceRun = RegExp(r'\s+');

/// Specific rating and component patterns to extract only required values (e.g. 16A, C16, NE555).
final RegExp _amperePattern =
    RegExp(r'\b\d+\s*A(?:MP)?\b', caseSensitive: false);
final RegExp _breakerCurvePattern =
    RegExp(r'\b[B-D]\d+\b', caseSensitive: false);
final RegExp _polesPattern =
    RegExp(r'\b(DP|SP|TP|TPN|4P|2P|1P)\b', caseSensitive: false);
final RegExp _icPartPattern =
    RegExp(r'\b[A-Z]{1,4}\d{2,5}[A-Z]*\b', caseSensitive: false);

/// Common electrical & standards noise words to strip out when cleaning component text.
final RegExp _noiseWords = RegExp(
  r'\b(\d+V|\d+HZ|50/60HZ|\d+KA|\d+A(?=00)|AC|DC|IEC\d*|EN\d*|CE|MADE IN \w+|SCHNEIDER|HAVELLS|ABB|SIEMENS|LEGRAND)\b',
  caseSensitive: false,
);

/// A whole table row arriving as one text run: a leading position label,
/// then a separator, then everything else. OCR at line granularity returns
/// exactly this shape — "1 C63 MAIN INCOMER" is one recognised line, not
/// three — so the parser has to be able to split a single run rather than
/// only pairing separate blocks. Without this, dense documents still fail
/// even after the OCR layer switched to emitting lines.
final RegExp _mergedRowPattern = RegExp(r'^(P?\d{1,3})[\s:.\)\-]+(.+)$');

/// A rating code appearing at the START of the remainder of a merged row,
/// so "1 C 32 MAIN INCOMER" keeps "C 32" together instead of splitting the
/// rating's own internal space into component "C" and noise "32".
final RegExp _leadingRatingPattern = RegExp(
  r'^([BCDKZ]\s?\d{1,3}A?|\d{1,3}\s?A(?:MP)?)(?:\s+(DP|SP|TP|TPN|4P|2P|1P))?(?:\s+(RCBO|MCB|RCCB|RCD|ELCB|ISOLATOR))?(?:\s|$)',
  caseSensitive: false,
);

/// A rating code appearing ANYWHERE in a text block. Used to extract ratings
/// from noisy physical breaker blocks (e.g. "Schneider C16 240V").
final RegExp _anywhereRatingPattern = RegExp(
  r'\b([BCDKZ]\s?\d{1,3}A?|\d{1,3}\s?A(?:MP)?)(?:\s+(DP|SP|TP|TPN|4P|2P|1P))?(?:\s+(RCBO|MCB|RCCB|RCD|ELCB|ISOLATOR))?\b',
  caseSensitive: false,
);

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

  /// Converts this [ParseResult] into a JSON map.
  Map<String, dynamic> toJson() => {
        'items': items.map((i) => i.toJson()).toList(),
        'unparsedRows': unparsedRows,
        'ignoredNoise': ignoredNoise,
      };

  /// Creates a [ParseResult] from a JSON map.
  factory ParseResult.fromJson(Map<String, dynamic> json) => ParseResult(
        items: (json['items'] as List<dynamic>?)
                ?.map((e) => SpecItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        unparsedRows: (json['unparsedRows'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        ignoredNoise: (json['ignoredNoise'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
      );

  @override
  String toString() =>
      'ParseResult(${items.length} items, ${unparsedRows.length} unparsed, '
      '${ignoredNoise.length} noise)';
}

/// Converts raw OCR blocks into a JSON representation of extracted spec items.
///
/// Converts OCR text blocks into a structured JSON list of objects containing
/// position labels, extracted component values, and confidence scores.
List<Map<String, dynamic>> parseBlocksToJson(List<OcrBlock> blocks) {
  final parseResult = parseBlocks(blocks);
  return parseResult.items.map((item) => item.toJson()).toList();
}

/// Helper container for split position and component values.
class _ExtractedItem {
  final String position;
  final String component;
  const _ExtractedItem(this.position, this.component);
}

/// Parses OCR [blocks] into spec items by their positions on the page.
///
/// Supports separate position/component blocks, single merged blocks (e.g. "P1 16A"),
/// circuit breaker models, and circuit diagrams.
ParseResult parseBlocks(List<OcrBlock> blocks) {
  final usable =
      blocks.where((block) => _flatten(block.text).isNotEmpty).toList();
  if (usable.isEmpty) {
    return const ParseResult(items: [], unparsedRows: []);
  }

  final items = <SpecItem>[];
  final unparsedRows = <String>[];
  final ignoredNoise = <String>[];

  for (final row in groupIntoRows(usable)) {
    row.sort((a, b) => a.left.compareTo(b.left));

    if (row.length == 1) {
      final blockText = _flatten(row.first.text);

      // Try splitMergedRow first — it correctly separates position,
      // component, and description noise from a single dense line like
      // "1 C63 MAIN INCOMER" or "1 PROJECTOR-EPSON EB-S41 LAB A".
      final split = splitMergedRow(blockText);
      if (split != null) {
        items.add(
          SpecItem(
            position: split.position,
            component: split.component,
            confidence: row.first.confidence,
          ),
        );
        ignoredNoise.addAll(split.noise);
        continue;
      }

      // Fall back to combined-pattern extraction for cases like
      // "P1 16A" or "CB1: 16A 240V AC" where _extractPositionAndComponent
      // handles prefixed position codes and _cleanComponentValue strips
      // electrical noise.
      final extracted = _extractPositionAndComponent(blockText);
      if (extracted != null) {
        items.add(
          SpecItem(
            position: extracted.position,
            component: extracted.component,
            confidence: row.first.confidence,
          ),
        );
      } else {
        unparsedRows.add(blockText);
      }
      continue;
    }

    // Row with 2 or more blocks
    final firstText = _flatten(row.first.text);
    final firstExtracted = _extractPositionAndComponent(firstText);

    if (firstExtracted != null) {
      String label = firstExtracted.position;
      String component = firstExtracted.component;

      if (component.isEmpty) {
        // First block had only position, second block has component
        component = _cleanComponentValue(_flatten(row[1].text));
        if (row.length > 2) {
          ignoredNoise
              .addAll(row.skip(2).map((block) => _flatten(block.text)));
        }
      } else {
        // First block contained both position & component (e.g. "P1 16A")
        // Remaining blocks in row are noise
        ignoredNoise
            .addAll(row.skip(1).map((block) => _flatten(block.text)));
      }

      items.add(
        SpecItem(
          position: label,
          component: component,
          confidence: _meanConfidence(row.take(2)),
        ),
      );
      continue;
    }

    // The leftmost run isn't a bare position, but the row may still BE a row
    // — just delivered as one merged text run ("1 C63 MAIN INCOMER"), which
    // is the normal shape at line granularity. Split it rather than
    // discarding a perfectly good row.
    final joined = row.map((block) => _flatten(block.text)).join(' ');
    final split = splitMergedRow(joined);
    if (split != null) {
      items.add(
        SpecItem(
          position: split.position,
          component: split.component,
          confidence: _meanConfidence(row),
        ),
      );
      ignoredNoise.addAll(split.noise);
      continue;
    }

    unparsedRows.add(joined);
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
  final usable =
      blocks.where((block) => _flatten(block.text).isNotEmpty).toList();
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

/// Extracts position label and component candidate from a single text block.
_ExtractedItem? _extractPositionAndComponent(String text) {
  final flat = _flatten(text);
  if (flat.isEmpty) return null;

  final purePos = _asPosition(flat);
  if (purePos != null) {
    return _ExtractedItem(purePos, '');
  }

  final match = _combinedPositionPattern.firstMatch(flat);
  if (match != null) {
    final fullPosStr = match.group(0)!;
    final posLabel = _asPosition(fullPosStr);
    if (posLabel != null) {
      final hasRealPrefix =
          match.group(1) != null && match.group(1)!.isNotEmpty;
      final remainder = flat.substring(match.end).trim();

      // For bare-digit positions in combined blocks, only accept the match
      // if the remainder contains a recognisable component value (ampere,
      // curve, IC, poles). This prevents pole markings like "1  3" or
      // "2  4" from being misread as position + component.
      if (hasRealPrefix || _hasRecognisableComponent(remainder)) {
        final cleanedComp = _cleanComponentValue(remainder);
        return _ExtractedItem(posLabel, cleanedComp);
      }
    }
  }

  return null;
}

/// Cleans raw text to extract ONLY the required component / ampere rating value.
String _cleanComponentValue(String rawText) {
  final trimmed = _flatten(rawText);
  if (trimmed.isEmpty) return '';

  final rating = _leadingRatingPattern.firstMatch(trimmed.toUpperCase());
  if (rating != null) {
      final baseRating = rating.group(1)!;
      final normalisedBase = baseRating.replaceAll(' ', '');
      return rating.group(0)!.trim().replaceFirst(baseRating, normalisedBase);
  }

  // 3. Try IC / electronic part pattern (e.g. "NE555", "7805", "LM358")
  final icMatch = _icPartPattern.firstMatch(trimmed);
  if (icMatch != null) {
    return icMatch.group(0)!.toUpperCase();
  }

  // 4. Try Poles pattern (e.g. "DP", "SP", "TP")
  final polesMatch = _polesPattern.firstMatch(trimmed);
  if (polesMatch != null) {
    return polesMatch.group(0)!.toUpperCase();
  }

  // Fallback: strip noise words and trailing punctuation
  final cleaned = trimmed
      .replaceAll(_noiseWords, '')
      .replaceAll(_trailingPunctuation, '')
      .trim();
  return cleaned;
}

/// Returns true when [text] contains at least one token recognisable as a
/// component value: an ampere rating, a breaker curve code, an IC/electronic
/// part number, or a pole designation. Used to guard bare-digit positions in
/// combined blocks — without a known prefix like "P" or "CB", we only split
/// a merged block if the remainder actually looks like a component.
bool _hasRecognisableComponent(String text) {
  if (text.isEmpty) return false;
  return _amperePattern.hasMatch(text) ||
      _breakerCurvePattern.hasMatch(text) ||
      _icPartPattern.hasMatch(text) ||
      _polesPattern.hasMatch(text);
}

/// One table row recovered from a single merged text run.
class MergedRow {
  /// The leading position label, normalised (uppercase, trimmed).
  final String position;

  /// The component immediately following the position.
  final String component;

  /// Everything after the component — a description column, a part number,
  /// whatever else shared the line. Reported, never folded into [component].
  final List<String> noise;

  /// Creates a split row.
  const MergedRow({
    required this.position,
    required this.component,
    this.noise = const [],
  });
}

/// Splits a single text run like "1 C63 MAIN INCOMER" into its position,
/// component, and leftover description text. Returns null when [text] does
/// not begin with something that could be a position label.
///
/// This exists because OCR at line granularity delivers a whole table row as
/// one recognised line. The row-pairing path in [parseBlocks] handles the
/// case where position and component arrive as separate blocks; this handles
/// the far more common dense-document case where they do not.
///
/// A rating code at the head of the remainder is kept whole, so
/// "1 C 32 LIGHTING" yields component "C32" rather than component "C" with
/// "32" lost to noise.
MergedRow? splitMergedRow(String text) {
  final match = _mergedRowPattern.firstMatch(_flatten(text));
  if (match == null) return null;

  final position = match.group(1)!.toUpperCase();
  final rest = match.group(2)!.trim();
  if (rest.isEmpty) {
    return MergedRow(position: position, component: '');
  }

  final rating = _leadingRatingPattern.firstMatch(rest.toUpperCase());
  if (rating != null) {
    final baseRating = rating.group(1)!;
    final normalisedBase = baseRating.replaceAll(' ', '');
    final component = rating.group(0)!.trim().replaceFirst(baseRating, normalisedBase);
    final remainder = rest.substring(rating.end).trim();
    return MergedRow(
      position: position,
      component: component,
      noise: remainder.isEmpty ? const [] : [remainder],
    );
  }

  final firstSpace = rest.indexOf(' ');
  if (firstSpace < 0) {
    return MergedRow(position: position, component: rest);
  }
  return MergedRow(
    position: position,
    component: rest.substring(0, firstSpace),
    noise: [rest.substring(firstSpace + 1).trim()],
  );
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
  
  // Use the comprehensive anywhereRatingPattern instead of a strict full-string match
  // so we can extract the rating even if there's noise around it in the same block.
  final match = _anywhereRatingPattern.firstMatch(candidate);
  if (match == null) return null;
  
  final baseRating = match.group(1)!;
  final normalisedBase = baseRating.replaceAll(' ', '');
  return match.group(0)!.trim().replaceFirst(baseRating, normalisedBase);
}

/// Collapses newlines and repeated spaces so block text is a single line.
String _flatten(String text) => text.replaceAll(_whitespaceRun, ' ').trim();

/// Mean OCR confidence across [row].
double _meanConfidence(Iterable<OcrBlock> row) {
  final confidences = row.map((block) => block.confidence).toList();
  return confidences.reduce((a, b) => a + b) / confidences.length;
}
