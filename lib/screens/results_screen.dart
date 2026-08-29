import 'package:flutter/material.dart';
import '../models/spec_item.dart';
import '../models/diff_result.dart';
import '../logic/phrase.dart';
import '../io/report.dart';

class ResultsScreen extends StatelessWidget {
  final List<SpecItem> expected;
  final List<SpecItem> observed;
  final DiffResult result;

  const ResultsScreen({
    super.key,
    required this.expected,
    required this.observed,
    required this.result,
  });

  Color _getColor(DiffType type) {
    switch (type) {
      case DiffType.missing:
        return Colors.red;
      case DiffType.unexpected:
        return Colors.amber;
      case DiffType.mismatched:
        return Colors.orange;
      case DiffType.unread:
        return Colors.grey;
    }
  }

  IconData _getIcon(DiffType type) {
    switch (type) {
      case DiffType.missing:
        return Icons.remove_circle;
      case DiffType.unexpected:
        return Icons.add_circle;
      case DiffType.mismatched:
        return Icons.swap_horiz;
      case DiffType.unread:
        return Icons.help_outline;
    }
  }

  Future<void> _exportReport(BuildContext context) async {
    final summary = await generateReport(
      expected: expected,
      observed: observed,
      result: result,
    );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Report saved and copied to clipboard:\n$summary'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verification Results'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => _exportReport(context),
            tooltip: 'Export Report',
          ),
        ],
      ),
      body: Column(
        children: [
          // Summary card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: result.isMatch ? Colors.green.shade100 : Colors.red.shade100,
            child: Column(
              children: [
                Icon(
                  result.isMatch ? Icons.check_circle : Icons.warning,
                  size: 48,
                  color: result.isMatch ? Colors.green : Colors.red,
                ),
                const SizedBox(height: 8),
                Text(
                  result.isMatch ? 'MATCH' : 'DISCREPANCIES FOUND',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: result.isMatch
                        ? Colors.green.shade900
                        : Colors.red.shade900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  phraseWithRules(result),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),

          // Discrepancy list
          Expanded(
            child: result.isMatch
                ? const Center(
                    child: Text(
                      'All components match the specification.',
                      style: TextStyle(fontSize: 18),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: result.all.length,
                    itemBuilder: (context, index) {
                      final d = result.all[index];
                      return Card(
                        color: _getColor(d.type).withValues(alpha: 0.1),
                        child: ListTile(
                          leading: Icon(
                            _getIcon(d.type),
                            color: _getColor(d.type),
                          ),
                          title: Text(
                            d.position,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Type: ${d.type.name.toUpperCase()}'),
                              if (d.expected != null)
                                Text('Expected: ${d.expected}'),
                              if (d.found != null) Text('Found: ${d.found}'),
                            ],
                          ),
                          isThreeLine: true,
                        ),
                      );
                    },
                  ),
          ),

          // Bottom actions
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _exportReport(context),
                    icon: const Icon(Icons.file_download),
                    label: const Text('Export Report'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(
                      context,
                    ).popUntil((route) => route.isFirst),
                    icon: const Icon(Icons.refresh),
                    label: const Text('New Check'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
