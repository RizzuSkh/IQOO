import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'logic/compare.dart';
import 'logic/ocr.dart';
import 'logic/parser.dart';
import 'logic/phrase.dart';
import 'models/spec_item.dart';

/// DEBUG HARNESS — NOT THE PRODUCT UI.
///
/// This screen exists to prove the pipeline is wired end to end:
/// camera -> ocr -> parser -> compare -> phrase -> text.
///
/// The real capture, review, and results screens live in lib/screens/ and are
/// owned by Laptop 2 and Laptop 3. This file is replaced when they land.

void main() => runApp(const ParityDebugApp());

/// Root of the debug harness.
class ParityDebugApp extends StatelessWidget {
  /// Creates the harness app.
  const ParityDebugApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Parity (debug harness)',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const PipelineHarness(),
    );
  }
}

/// Captures two photographs and runs the full pipeline over them.
class PipelineHarness extends StatefulWidget {
  /// Creates the harness screen.
  const PipelineHarness({super.key});

  @override
  State<PipelineHarness> createState() => _PipelineHarnessState();
}

class _PipelineHarnessState extends State<PipelineHarness> {
  final ImagePicker _picker = ImagePicker();
  final OcrReader _ocr = OcrReader();

  ParseResult? _spec;
  ParseResult? _assembly;
  String _status = 'Capture the specification, then the assembly.';
  bool _busy = false;

  @override
  void dispose() {
    _ocr.close();
    super.dispose();
  }

  /// Photographs one side, runs OCR and the parser, and stores the result.
  Future<void> _capture({required bool isSpec}) async {
    final label = isSpec ? 'specification' : 'assembly';
    setState(() {
      _busy = true;
      _status = 'Opening camera for the $label...';
    });

    try {
      final photo = await _picker.pickImage(source: ImageSource.camera);
      if (photo == null) {
        _set('Capture cancelled.');
        return;
      }

      _set('Reading the $label...');
      final blocks = await _ocr.readBlocks(photo.path);
      final parsed = parseBlocks(blocks);

      if (!mounted) return;
      setState(() {
        if (isSpec) {
          _spec = parsed;
        } else {
          _assembly = parsed;
        }
        _busy = false;
        _status =
            '${blocks.length} blocks read, ${parsed.items.length} rows '
            'parsed from the $label.';
      });
    } on OcrException catch (error) {
      _set('OCR failed: ${error.message}');
    } catch (error) {
      _set('Capture failed: $error');
    }
  }

  /// Updates the status line and clears the busy flag.
  void _set(String message) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = message;
    });
  }

  /// Clears both captures (F10 reset, proven here in miniature).
  void _reset() {
    setState(() {
      _spec = null;
      _assembly = null;
      _status = 'Reset. Capture the specification, then the assembly.';
    });
  }

  /// The comparison summary, or null until both sides are captured.
  String? get _summary {
    final spec = _spec;
    final assembly = _assembly;
    if (spec == null || assembly == null) return null;
    return phraseWithRules(compare(spec.items, assembly.items));
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;

    return Scaffold(
      appBar: AppBar(title: const Text('Parity — debug harness')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(
              onPressed: _busy ? null : () => _capture(isSpec: true),
              child: const Text('Capture Spec'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _busy ? null : () => _capture(isSpec: false),
              child: const Text('Capture Assembly'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy ? null : _reset,
              child: const Text('Reset'),
            ),
            const SizedBox(height: 16),
            Text(_status, style: Theme.of(context).textTheme.bodyMedium),
            const Divider(height: 32),
            _extraction('Specification', _spec),
            _extraction('Assembly', _assembly),
            const Divider(height: 32),
            Text(
              summary ?? 'Waiting for both captures.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }

  /// Shows what was extracted from one photograph, including unparsed rows.
  Widget _extraction(String title, ParseResult? parsed) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          if (parsed == null)
            const Text('not captured')
          else ...[
            for (final SpecItem item in parsed.items)
              Text(
                '${item.position}: '
                '${item.component.isEmpty ? "(unread)" : item.component}',
              ),
            for (final row in parsed.unparsedRows) Text('unparsed: $row'),
          ],
        ],
      ),
    );
  }
}
