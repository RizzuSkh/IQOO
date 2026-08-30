import 'package:flutter/material.dart';
import '../models/spec_item.dart';
import 'results_screen.dart';
import '../logic/compare.dart';

/// F9 manual correction: lets the operator fix, add, or remove any row OCR
/// extracted before comparison runs, and shows what OCR found but discarded
/// (unparsed rows, ignored stray text) so nothing is silently lost.
class ReviewExtractionScreen extends StatefulWidget {
  final List<SpecItem> expected;
  final List<SpecItem> observed;
  final bool isEditingExpected;

  /// Rows the specification photo had text in, but that didn't parse as a
  /// position + component pair.
  final List<String> expectedUnparsed;

  /// Text the specification photo had at a label's row height that was
  /// ignored rather than folded into the component (see parser.dart).
  final List<String> expectedNoise;

  /// Rows the assembly photo had text in, but that didn't parse as a
  /// position + component pair.
  final List<String> observedUnparsed;

  /// Text the assembly photo had at a label's row height that was ignored
  /// rather than folded into the component (see parser.dart).
  final List<String> observedNoise;

  const ReviewExtractionScreen({
    super.key,
    required this.expected,
    required this.observed,
    required this.isEditingExpected,
    this.expectedUnparsed = const [],
    this.expectedNoise = const [],
    this.observedUnparsed = const [],
    this.observedNoise = const [],
  });

  @override
  State<ReviewExtractionScreen> createState() => _ReviewExtractionScreenState();
}

class _ReviewExtractionScreenState extends State<ReviewExtractionScreen> {
  late List<SpecItem> _expected;
  late List<SpecItem> _observed;

  @override
  void initState() {
    super.initState();
    _expected = List.from(widget.expected);
    _observed = List.from(widget.observed);
  }

  void _editItem(int index, bool isExpected) {
    final items = isExpected ? _expected : _observed;
    final item = items[index];
    _openItemDialog(
      title: 'Edit ${isExpected ? "Expected" : "Observed"} Item',
      initialPosition: item.position,
      initialComponent: item.component,
      onSave: (position, component) {
        setState(() {
          final updated = item.copyWith(
            position: position,
            component: component,
          );
          if (isExpected) {
            _expected[index] = updated;
          } else {
            _observed[index] = updated;
          }
        });
      },
    );
  }

  void _deleteItem(int index, bool isExpected) {
    setState(() {
      if (isExpected) {
        _expected.removeAt(index);
      } else {
        _observed.removeAt(index);
      }
    });
  }

  void _addItem(bool isExpected, {String prefillComponent = ''}) {
    final target = isExpected ? _expected : _observed;
    _openItemDialog(
      title: 'Add ${isExpected ? "Expected" : "Observed"} Item',
      initialPosition: '',
      initialComponent: prefillComponent,
      onSave: (position, component) {
        if (target.any((item) => item.position == position)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '$position already exists — edit it instead of adding a duplicate.',
              ),
            ),
          );
          return;
        }
        setState(() {
          target.add(SpecItem(position: position, component: component));
        });
      },
    );
  }

  /// Shared add/edit dialog. [onSave] is only called with a non-empty,
  /// normalised position.
  void _openItemDialog({
    required String title,
    required String initialPosition,
    required String initialComponent,
    required void Function(String position, String component) onSave,
  }) {
    final positionController = TextEditingController(text: initialPosition);
    final componentController = TextEditingController(text: initialComponent);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: positionController,
              decoration: const InputDecoration(
                labelText: 'Position (e.g. P1)',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
              autofocus: initialPosition.isEmpty,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: componentController,
              decoration: const InputDecoration(
                labelText: 'Component (blank = unread)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final position = positionController.text.trim().toUpperCase();
              if (position.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Position cannot be empty.')),
                );
                return;
              }
              onSave(position, componentController.text.trim());
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _proceedToResults() {
    final result = compare(_expected, _observed);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ResultsScreen(
          expected: _expected,
          observed: _observed,
          result: result,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Review Extraction'),
      ),
      body: Column(
        children: [
          Expanded(
            child: _section(
              title: 'EXPECTED (Specification)',
              color: const Color(0xFF4F46E5), // Indigo
              items: _expected,
              unparsed: widget.expectedUnparsed,
              noise: widget.expectedNoise,
              isExpected: true,
            ),
          ),
          Container(height: 2, color: const Color(0xFFE2E8F0)),
          Expanded(
            child: _section(
              title: 'OBSERVED (Assembly)',
              color: const Color(0xFF10B981), // Emerald
              items: _observed,
              unparsed: widget.observedUnparsed,
              noise: widget.observedNoise,
              isExpected: false,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: (_expected.isEmpty || _observed.isEmpty)
                      ? null
                      : _proceedToResults,
                  icon: const Icon(Icons.compare_arrows_rounded),
                  label: const Text('Compare & Show Results'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section({
    required String title,
    required Color color,
    required List<SpecItem> items,
    required List<String> unparsed,
    required List<String> noise,
    required bool isExpected,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            border: Border(bottom: BorderSide(color: color.withValues(alpha: 0.15))),
          ),
          child: Row(
            children: [
              Icon(
                isExpected ? Icons.description_outlined : Icons.memory_outlined,
                color: color,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: color,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.add_circle_outline_rounded, color: color),
                tooltip: 'Add row',
                onPressed: () => _addItem(isExpected),
              ),
            ],
          ),
        ),
        if (unparsed.isNotEmpty || noise.isNotEmpty)
          _diagnostics(
            unparsed: unparsed,
            noise: noise,
            isExpected: isExpected,
          ),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text(
                    'No items detected — tap + to add one',
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  itemCount: items.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final isUnread = item.isUnread;
                    return Container(
                      decoration: BoxDecoration(
                        color: isUnread ? const Color(0xFFFFFBEB) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isUnread ? const Color(0xFFFDE68A) : const Color(0xFFE2E8F0),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ListTile(
                        onTap: () => _editItem(index, isExpected),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: isUnread ? const Color(0xFFFEF3C7) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            item.position,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isUnread ? const Color(0xFFD97706) : const Color(0xFF1E293B),
                            ),
                          ),
                        ),
                        title: Text(
                          isUnread ? 'Unread — needs value' : item.component,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isUnread ? const Color(0xFFB45309) : const Color(0xFF0F172A),
                            fontStyle: isUnread ? FontStyle.italic : FontStyle.normal,
                          ),
                        ),
                        subtitle: Text(
                          isUnread
                              ? 'Tap to enter manually'
                              : 'Confidence: ${(item.confidence * 100).toInt()}%',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              onPressed: () => _editItem(index, isExpected),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Color(0xFFEF4444)),
                              onPressed: () => _deleteItem(index, isExpected),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _diagnostics({
    required List<String> unparsed,
    required List<String> noise,
    required bool isExpected,
  }) {
    final total = unparsed.length + noise.length;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        leading: const Icon(Icons.info_outline_rounded, color: Color(0xFFD97706), size: 20),
        title: Text(
          '$total unused OCR text line${total == 1 ? '' : 's'}',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF92400E)),
        ),
        children: [
          for (final text in unparsed)
            ListTile(
              dense: true,
              leading: const Icon(Icons.help_outline_rounded, size: 18, color: Color(0xFFD97706)),
              title: Text('Unrecognised: "$text"', style: const TextStyle(fontSize: 12)),
              trailing: TextButton(
                child: const Text('Add'),
                onPressed: () => _addItem(isExpected, prefillComponent: text),
              ),
            ),
          for (final text in noise)
            ListTile(
              dense: true,
              leading: const Icon(Icons.block_rounded, size: 18, color: Colors.grey),
              title: Text('Ignored stray: "$text"', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ),
        ],
      ),
    );
  }
}
