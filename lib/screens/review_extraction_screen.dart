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
                labelText: 'Position (e.g. 1 or P1)',
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
      appBar: AppBar(title: const Text('Review Extraction')),
      body: Column(
        children: [
          Expanded(
            child: _section(
              title: 'EXPECTED (Specification)',
              color: Colors.blue,
              items: _expected,
              unparsed: widget.expectedUnparsed,
              noise: widget.expectedNoise,
              isExpected: true,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _section(
              title: 'OBSERVED (Assembly)',
              color: Colors.green,
              items: _observed,
              unparsed: widget.observedUnparsed,
              noise: widget.observedNoise,
              isExpected: false,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (_expected.isEmpty || _observed.isEmpty)
                    ? null
                    : _proceedToResults,
                icon: const Icon(Icons.compare_arrows),
                label: const Text('Compare & Show Results'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
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
    required MaterialColor color,
    required List<SpecItem> items,
    required List<String> unparsed,
    required List<String> noise,
    required bool isExpected,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: color.shade100,
          width: double.infinity,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
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
              ? const Center(child: Text('No items — tap + to add one'))
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final isUnread = item.isUnread;
                    // PRD section 23: an unread component must be visibly
                    // flagged, never treated as though it matched.
                    return Container(
                      color: isUnread ? Colors.amber.shade50 : null,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isUnread
                              ? Colors.amber.shade200
                              : null,
                          child: Text(item.position),
                        ),
                        title: Text(
                          isUnread ? 'Unread — needs a value' : item.component,
                          style: isUnread
                              ? TextStyle(
                                  color: Colors.amber.shade900,
                                  fontStyle: FontStyle.italic,
                                )
                              : null,
                        ),
                        subtitle: Text(
                          isUnread
                              ? 'OCR could not read this — tap to enter it manually'
                              : 'Confidence: ${(item.confidence * 100).toInt()}%',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () => _editItem(index, isExpected),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.red,
                              ),
                              onPressed: () => _deleteItem(index, isExpected),
                            ),
                          ],
                        ),
                        onTap: () => _editItem(index, isExpected),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// Shows what OCR found but didn't turn into a row, so the operator knows
  /// to look closer rather than assuming the photo was read completely.
  Widget _diagnostics({
    required List<String> unparsed,
    required List<String> noise,
    required bool isExpected,
  }) {
    final total = unparsed.length + noise.length;
    return Container(
      color: Colors.amber.shade50,
      child: ExpansionTile(
        leading: const Icon(Icons.info_outline, color: Colors.amber),
        title: Text(
          '$total item${total == 1 ? '' : 's'} from the photo were not used — tap to check',
        ),
        childrenPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
        children: [
          for (final text in unparsed)
            ListTile(
              dense: true,
              leading: const Icon(Icons.help_outline, size: 20),
              title: Text('Unrecognised row: "$text"'),
              subtitle: const Text(
                "Didn't start with a position like P1 — add it manually if it's real.",
              ),
              trailing: TextButton(
                child: const Text('Add'),
                onPressed: () => _addItem(isExpected, prefillComponent: text),
              ),
            ),
          for (final text in noise)
            ListTile(
              dense: true,
              leading: const Icon(Icons.block, size: 20),
              title: Text('Ignored near a row: "$text"'),
              subtitle: const Text(
                'Treated as stray text, not part of any component.',
              ),
            ),
        ],
      ),
    );
  }
}
