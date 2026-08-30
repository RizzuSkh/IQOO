import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  void _showJsonDialog(BuildContext context) {
    final encoder = const JsonEncoder.withIndent('  ');
    final jsonMap = {
      'is_match': result.isMatch,
      'discrepancy_count': result.count,
      'expected_spec': expected.map((e) => e.toJson()).toList(),
      'observed_assembly': observed.map((o) => o.toJson()).toList(),
      'discrepancies': {
        'missing': result.missing.map((d) => {'position': d.position, 'expected': d.expected}).toList(),
        'unexpected': result.unexpected.map((d) => {'position': d.position, 'found': d.found}).toList(),
        'mismatched': result.mismatched.map((d) => {'position': d.position, 'expected': d.expected, 'found': d.found}).toList(),
        'unread': result.unread.map((d) => {'position': d.position, 'expected': d.expected}).toList(),
      },
    };
    final jsonString = encoder.convert(jsonMap);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.data_object_rounded, color: Color(0xFF4F46E5)),
            SizedBox(width: 8),
            Text('Verification JSON Data'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              jsonString,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: jsonString));
              Navigator.pop(dialogContext);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Verification JSON copied to clipboard!')),
              );
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copy JSON'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

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

  /// A one-glance key for the colour coding below, so a judge doesn't have to
  /// read every card's "Type:" line to know what red vs. amber vs. orange
  /// means (PRD FR9: missing red, unexpected amber, mismatched orange).
  Widget _legend() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.grey.shade100,
      child: Wrap(
        spacing: 14,
        runSpacing: 4,
        children: [for (final type in DiffType.values) _legendChip(type)],
      ),
    );
  }

  Widget _legendChip(DiffType type) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(_getIcon(type), size: 15, color: _getColor(type)),
        const SizedBox(width: 3),
        Text(
          type.name[0].toUpperCase() + type.name.substring(1),
          style: TextStyle(fontSize: 12, color: _getColor(type)),
        ),
      ],
    );
  }

  Future<void> _exportReport(BuildContext context) async {
    final report = await generateReport(
      expected: expected,
      observed: observed,
      result: result,
    );

    if (!context.mounted) return;

    // Tell the truth about the file write (PRD section 23) instead of
    // always claiming "saved" — the clipboard write happens either way.
    final message = report.fileSaved
        ? 'Report saved to app storage and summary copied to clipboard.'
        : "Couldn't save the report file (${report.fileError ?? 'unknown error'}), "
              'but the summary is on the clipboard.';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: report.fileSaved ? null : Colors.orange.shade800,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verification Results'),
        actions: [
          IconButton(
            icon: const Icon(Icons.data_object_rounded),
            onPressed: () => _showJsonDialog(context),
            tooltip: 'View Extracted JSON',
          ),
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

          if (!result.isMatch) _legend(),

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

          // Bottom actions. SafeArea matters here: without it the buttons sit
          // underneath the system navigation bar on a gesture-nav device and
          // their labels are visibly clipped — the other screens already wrap
          // their action rows the same way.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _exportReport(context),
                      icon: const Icon(Icons.file_download),
                      label: const Text(
                        'Export Report',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.of(
                        context,
                      ).popUntil((route) => route.isFirst),
                      icon: const Icon(Icons.refresh),
                      label: const Text(
                        'New Check',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
