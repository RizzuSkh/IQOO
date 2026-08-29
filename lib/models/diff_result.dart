/// The four ways an assembly can fail to match its specification.
///
/// [unread] is a first-class state, not an error: OCR could not read the
/// component at that position, so the app reports uncertainty rather than
/// assuming a match (PRD section 18).
enum DiffType { missing, unexpected, mismatched, unread }

/// A single difference between the expected and observed lists at one position.
class Discrepancy {
  /// Which kind of difference this is.
  final DiffType type;

  /// The board position the difference was found at, e.g. "P2".
  final String position;

  /// What the specification called for. Null when [type] is [DiffType.unexpected].
  final String? expected;

  /// What was read on the assembly. Null when [type] is [DiffType.missing]
  /// or [DiffType.unread].
  final String? found;

  /// Creates a discrepancy at [position].
  const Discrepancy({
    required this.type,
    required this.position,
    this.expected,
    this.found,
  });

  @override
  String toString() =>
      'Discrepancy(${type.name}, $position, expected: $expected, found: $found)';

  @override
  bool operator ==(Object other) =>
      other is Discrepancy &&
      other.type == type &&
      other.position == position &&
      other.expected == expected &&
      other.found == found;

  @override
  int get hashCode => Object.hash(type, position, expected, found);
}

/// The full outcome of one comparison, grouped by discrepancy type.
///
/// The four lists are disjoint: every discrepancy appears in exactly one.
class DiffResult {
  /// Positions the specification requires that the assembly does not have.
  final List<Discrepancy> missing;

  /// Positions present on the assembly that the specification does not list.
  final List<Discrepancy> unexpected;

  /// Positions where both lists have a component and the two differ.
  final List<Discrepancy> mismatched;

  /// Positions the specification requires where OCR could not read the
  /// assembly. Never treated as a match.
  final List<Discrepancy> unread;

  /// Creates a diff result from four already-grouped lists.
  const DiffResult({
    required this.missing,
    required this.unexpected,
    required this.mismatched,
    required this.unread,
  });

  /// An outcome with no discrepancies of any kind.
  const DiffResult.empty()
    : missing = const [],
      unexpected = const [],
      mismatched = const [],
      unread = const [];

  /// True only when all four lists are empty.
  ///
  /// An unread component keeps this false — uncertainty is not a match.
  bool get isMatch =>
      missing.isEmpty &&
      unexpected.isEmpty &&
      mismatched.isEmpty &&
      unread.isEmpty;

  /// Every discrepancy, in report order: missing, unexpected, mismatched, unread.
  List<Discrepancy> get all => [
    ...missing,
    ...unexpected,
    ...mismatched,
    ...unread,
  ];

  /// Total number of discrepancies across all four lists.
  int get count =>
      missing.length + unexpected.length + mismatched.length + unread.length;

  @override
  String toString() => 'DiffResult(${all.map((d) => d.toString()).join(', ')})';
}
