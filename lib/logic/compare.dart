import '../models/diff_result.dart';
import '../models/spec_item.dart';

/// PURE DETERMINISTIC COMPARISON — NO MODEL CALLS, NO NETWORK, EVER.
///
/// This file is the judgement step of the product. A language model must never
/// decide what differs; it may only phrase a [DiffResult] this function has
/// already produced (CLAUDE.md section 11).

/// Compares an [assembly] against its [spec] and returns the differences.
///
/// Both lists are indexed by position. Positions are matched case-insensitively
/// after trimming; component text is compared case-insensitively after trimming
/// and is not otherwise normalised, so "NE555" and "NE 555" are a mismatch and
/// that is intended (PRD section 18).
///
/// Per position, following the PRD section 18 table:
///
/// | Specified        | Observed          | Result       |
/// |------------------|-------------------|--------------|
/// | present          | no entry          | `missing`    |
/// | not specified    | present           | `unexpected` |
/// | present          | same component    | no entry     |
/// | present          | other component   | `mismatched` |
/// | present          | entry, unread     | `unread`     |
///
/// A specification entry whose component is empty is treated as "not specified
/// at this position" — that is what fixture `case_03_unexpected.json` pins down.
/// When neither side could be read at a position, the result is `unread` with
/// no expected value: nothing is known there, and an unknown is never a match.
///
/// Output order is deterministic: specification order first, then any
/// assembly-only positions in the order they were observed. Where a position
/// appears more than once in a list, the first occurrence wins.
DiffResult compare(List<SpecItem> spec, List<SpecItem> assembly) {
  final specByPosition = _indexByPosition(spec);
  final assemblyByPosition = _indexByPosition(assembly);

  final missing = <Discrepancy>[];
  final unexpected = <Discrepancy>[];
  final mismatched = <Discrepancy>[];
  final unread = <Discrepancy>[];

  for (final position in _orderedPositions(
    specByPosition,
    assemblyByPosition,
  )) {
    final specItem = specByPosition[position];
    final assemblyItem = assemblyByPosition[position];

    final expected = specItem == null ? '' : specItem.component.trim();
    final isSpecified = expected.isNotEmpty;

    // Position absent from the assembly entirely.
    if (assemblyItem == null) {
      if (isSpecified) {
        missing.add(
          Discrepancy(
            type: DiffType.missing,
            position: position,
            expected: expected,
          ),
        );
      }
      continue;
    }

    final found = assemblyItem.component.trim();

    // The assembly has an entry here but OCR read no component.
    if (found.isEmpty) {
      unread.add(
        Discrepancy(
          type: DiffType.unread,
          position: position,
          expected: isSpecified ? expected : null,
        ),
      );
      continue;
    }

    // Something is fitted where the specification calls for nothing.
    if (!isSpecified) {
      unexpected.add(
        Discrepancy(
          type: DiffType.unexpected,
          position: position,
          found: found,
        ),
      );
      continue;
    }

    if (expected.toLowerCase() != found.toLowerCase()) {
      mismatched.add(
        Discrepancy(
          type: DiffType.mismatched,
          position: position,
          expected: expected,
          found: found,
        ),
      );
    }
  }

  return DiffResult(
    missing: missing,
    unexpected: unexpected,
    mismatched: mismatched,
    unread: unread,
  );
}

/// Indexes [items] by normalised position, keeping the first of any duplicates.
Map<String, SpecItem> _indexByPosition(List<SpecItem> items) {
  final byPosition = <String, SpecItem>{};
  for (final item in items) {
    final position = _normalisePosition(item.position);
    if (position.isEmpty) continue;
    byPosition.putIfAbsent(position, () => item);
  }
  return byPosition;
}

/// Every position in either list: specification order first, then the rest.
List<String> _orderedPositions(
  Map<String, SpecItem> spec,
  Map<String, SpecItem> assembly,
) {
  return [
    ...spec.keys,
    ...assembly.keys.where((position) => !spec.containsKey(position)),
  ];
}

/// Positions are uppercase and trimmed before matching.
String _normalisePosition(String position) => position.trim().toUpperCase();
