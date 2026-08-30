/// One labelled position on the board and the component read at it.
///
/// A [SpecItem] is produced twice per inspection: once from the specification
/// photograph (the expected list) and once from the assembly photograph (the
/// observed list). The two lists are then compared by `compare()`.
class SpecItem {
  /// Board position label, uppercase and trimmed, e.g. "P1".
  final String position;

  /// Component read at [position], e.g. "NE555".
  ///
  /// Empty string when OCR could not read it. Never null — an unread component
  /// is a reportable state, not a missing value (PRD section 18).
  final String component;

  /// OCR confidence for [component], 0.0 to 1.0.
  final double confidence;

  /// Creates a spec item; [position] and [component] are stored as given.
  const SpecItem({
    required this.position,
    required this.component,
    this.confidence = 1.0,
  });

  /// True when OCR produced no readable component for this position.
  bool get isUnread => component.trim().isEmpty;

  /// Returns a copy with the given fields replaced (used by manual correction).
  SpecItem copyWith({String? position, String? component, double? confidence}) {
    return SpecItem(
      position: position ?? this.position,
      component: component ?? this.component,
      confidence: confidence ?? this.confidence,
    );
  }

  /// Converts this [SpecItem] into a JSON map.
  Map<String, dynamic> toJson() => {
        'position': position,
        'component': component,
        'confidence': confidence,
      };

  /// Creates a [SpecItem] from a JSON map.
  factory SpecItem.fromJson(Map<String, dynamic> json) => SpecItem(
        position: json['position'] as String? ?? '',
        component: json['component'] as String? ?? '',
        confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
      );

  @override
  String toString() =>
      'SpecItem($position, "$component", ${confidence.toStringAsFixed(2)})';

  @override
  bool operator ==(Object other) =>
      other is SpecItem &&
      other.position == position &&
      other.component == component &&
      other.confidence == confidence;

  @override
  int get hashCode => Object.hash(position, component, confidence);
}
