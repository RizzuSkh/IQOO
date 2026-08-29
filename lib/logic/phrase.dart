import '../models/diff_result.dart';

/// Turns an already-computed [DiffResult] into a sentence.
///
/// This is phrasing only. It never decides what differs — `compare()` has
/// already done that, and this function reads its output (CLAUDE.md section 11).
/// The P2 stretch may swap in a model here; the rules path below is the product
/// and must always work on its own.

/// Describes every discrepancy in [result] as one readable sentence.
///
/// Returns an explicit success sentence when there is nothing to report, so the
/// results screen is never blank (PRD section 23).
String phraseWithRules(DiffResult result) {
  if (result.isMatch) {
    return 'No discrepancies found — the assembly matches the specification.';
  }

  final clauses = result.all.map(_describe).toList();
  final count = clauses.length;
  final noun = count == 1 ? 'discrepancy' : 'discrepancies';
  return '$count $noun: ${clauses.join('; ')}.';
}

/// Describes a single discrepancy as one clause, without terminal punctuation.
String _describe(Discrepancy d) {
  final position = d.position;
  switch (d.type) {
    case DiffType.missing:
      return '$position should hold ${d.expected} but nothing was found there';
    case DiffType.unexpected:
      return '$position holds ${d.found}, which the specification does not call for';
    case DiffType.mismatched:
      return '$position holds ${d.found} where the specification calls for ${d.expected}';
    case DiffType.unread:
      final expected = d.expected;
      return expected == null
          ? '$position could not be read on either photograph'
          : '$position could not be read — the specification calls for $expected, '
                'so it needs a retake or manual entry';
  }
}
