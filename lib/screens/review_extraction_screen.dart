import 'package:flutter/material.dart';
import '../models/spec_item.dart';
import 'results_screen.dart';
import '../logic/compare.dart';

class ReviewExtractionScreen extends StatefulWidget {
  final List<SpecItem> expected;
  final List<SpecItem> observed;
  final bool isEditingExpected;

  const ReviewExtractionScreen({
    super.key,
    required this.expected,
    required this.observed,
    required this.isEditingExpected,
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

    final positionController = TextEditingController(text: item.position);
    final componentController = TextEditingController(text: item.component);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit ${isExpected ? "Expected" : "Observed"} Item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: positionController,
              decoration: const InputDecoration(
                labelText: 'Position',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: componentController,
              decoration: const InputDecoration(
                labelText: 'Component',
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
              setState(() {
                if (isExpected) {
                  _expected[index] = item.copyWith(
                    position: positionController.text.toUpperCase(),
                    component: componentController.text,
                  );
                } else {
                  _observed[index] = item.copyWith(
                    position: positionController.text.toUpperCase(),
                    component: componentController.text,
                  );
                }
              });
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
      appBar: AppBar(
        title: const Text('Review Extraction'),
      ),
      body: Column(
        children: [
          // Expected list
          Expanded(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  color: Colors.blue.shade100,
                  width: double.infinity,
                  child: const Text(
                    'EXPECTED (Specification)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                Expanded(
                  child: _expected.isEmpty
                      ? const Center(child: Text('No items detected'))
                      : ListView.builder(
                          itemCount: _expected.length,
                          itemBuilder: (context, index) {
                            final item = _expected[index];
                            return ListTile(
                              leading: CircleAvatar(child: Text(item.position)),
                              title: Text(item.component.isEmpty ? '<empty>' : item.component),
                              subtitle: Text('Confidence: ${(item.confidence * 100).toInt()}%'),
                              trailing: IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: () => _editItem(index, true),
                              ),
                              onTap: () => _editItem(index, true),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Observed list
          Expanded(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  color: Colors.green.shade100,
                  width: double.infinity,
                  child: const Text(
                    'OBSERVED (Assembly)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                Expanded(
                  child: _observed.isEmpty
                      ? const Center(child: Text('No items detected'))
                      : ListView.builder(
                          itemCount: _observed.length,
                          itemBuilder: (context, index) {
                            final item = _observed[index];
                            return ListTile(
                              leading: CircleAvatar(child: Text(item.position)),
                              title: Text(item.component.isEmpty ? '<empty>' : item.component),
                              subtitle: Text('Confidence: ${(item.confidence * 100).toInt()}%'),
                              trailing: IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: () => _editItem(index, false),
                              ),
                              onTap: () => _editItem(index, false),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),

          // Proceed button
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _proceedToResults,
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
}
