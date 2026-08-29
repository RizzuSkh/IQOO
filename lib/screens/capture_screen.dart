import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/spec_item.dart';
import '../logic/ocr.dart';
import '../logic/parser.dart';
import '../logic/image_crop.dart';
import 'review_extraction_screen.dart';

enum CaptureMode { spec, assembly }

/// F1/F3: photograph the specification or the assembly, let the operator
/// crop out everything but the label region, then run OCR + the parser.
///
/// Cropping exists because whole-frame OCR on a real assembly photo also
/// reads the board's own silkscreen — column numbers, resistor colour codes —
/// which used to show up as unwanted text in extracted components. Trimming
/// the frame down to just the labels before OCR runs removes most of it at
/// the source, and the parser's own ignored-noise handling catches the rest.
class CaptureScreen extends StatefulWidget {
  final CaptureMode mode;
  final List<SpecItem>? previousExpected;
  final List<String> previousExpectedUnparsed;
  final List<String> previousExpectedNoise;

  const CaptureScreen({
    super.key,
    required this.mode,
    this.previousExpected,
    this.previousExpectedUnparsed = const [],
    this.previousExpectedNoise = const [],
  });

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

enum _Stage { idle, cropping, processing, done }

class _CaptureScreenState extends State<CaptureScreen> {
  final ImagePicker _picker = ImagePicker();
  final OcrReader _ocrReader = OcrReader();

  File? _imageFile;
  int? _imageWidth;
  int? _imageHeight;

  _Stage _stage = _Stage.idle;
  double _hInset = 0.0; // fraction trimmed from left AND right
  double _vInset = 0.0; // fraction trimmed from top AND bottom

  ParseResult _parseResult = const ParseResult(items: [], unparsedRows: []);
  String _status = '';
  String _error = '';

  @override
  void dispose() {
    _ocrReader.close();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 2400,
        maxHeight: 2400,
        imageQuality: 95,
      );
      if (photo == null) return;

      final dims = await readImageDimensions(photo.path);

      setState(() {
        _imageFile = File(photo.path);
        _imageWidth = dims.width;
        _imageHeight = dims.height;
        _hInset = 0.0;
        _vInset = 0.0;
        _stage = _Stage.cropping;
        _error = '';
        _status = '';
        _parseResult = const ParseResult(items: [], unparsedRows: []);
      });
    } catch (e) {
      setState(() {
        _stage = _Stage.idle;
        _error = 'Camera failed: $e';
      });
    }
  }

  Future<void> _runOcr({required bool useFullPhoto}) async {
    final imageFile = _imageFile;
    if (imageFile == null) return;

    setState(() {
      _stage = _Stage.processing;
      _error = '';
    });

    try {
      String ocrPath = imageFile.path;

      if (!useFullPhoto && (_hInset > 0 || _vInset > 0)) {
        ocrPath = await cropImageFile(
          sourcePath: imageFile.path,
          fraction: CropFraction(
            left: _hInset,
            right: _hInset,
            top: _vInset,
            bottom: _vInset,
          ),
          outputDir: imageFile.parent.path,
        );
      }

      final blocks = await _ocrReader.readBlocks(ocrPath);
      final parseResult = parseBlocks(blocks);

      if (!mounted) return;
      setState(() {
        _parseResult = parseResult;
        _stage = _Stage.done;
        final noiseNote = parseResult.ignoredNoise.isEmpty
            ? ''
            : ', ${parseResult.ignoredNoise.length} stray text block(s) ignored';
        _status =
            '${blocks.length} text blocks read, '
            '${parseResult.items.length} row(s) parsed$noiseNote.';
        if (parseResult.isEmpty) {
          _error =
              'No valid labels found (expected P1, P2, etc.). '
              'Retake with the label sheet filling more of the frame, or crop tighter.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.cropping;
        _error = 'OCR failed: $e';
      });
    }
  }

  void _retake() {
    setState(() {
      _imageFile = null;
      _stage = _Stage.idle;
      _error = '';
      _status = '';
      _parseResult = const ParseResult(items: [], unparsedRows: []);
    });
  }

  void _proceed() {
    if (widget.mode == CaptureMode.spec) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CaptureScreen(
            mode: CaptureMode.assembly,
            previousExpected: _parseResult.items,
            previousExpectedUnparsed: _parseResult.unparsedRows,
            previousExpectedNoise: _parseResult.ignoredNoise,
          ),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ReviewExtractionScreen(
            expected: widget.previousExpected ?? [],
            observed: _parseResult.items,
            isEditingExpected: false,
            expectedUnparsed: widget.previousExpectedUnparsed,
            expectedNoise: widget.previousExpectedNoise,
            observedUnparsed: _parseResult.unparsedRows,
            observedNoise: _parseResult.ignoredNoise,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSpec = widget.mode == CaptureMode.spec;
    final title = isSpec ? 'Capture Specification' : 'Capture Assembly';
    final accent = isSpec ? Colors.blue : Colors.green;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: accent.shade50,
            width: double.infinity,
            child: Column(
              children: [
                Icon(
                  isSpec ? Icons.description : Icons.memory,
                  size: 48,
                  color: accent,
                ),
                const SizedBox(height: 8),
                Text(
                  isSpec
                      ? 'Photograph the specification sheet'
                      : 'Photograph the physical assembly',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  _stage == _Stage.cropping
                      ? 'Trim the frame to just the labels, then scan'
                      : (isSpec
                            ? 'Position labels clearly in frame (e.g. P1: NE555)'
                            : 'Ensure all components are visible'),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          Expanded(child: _body(accent)),
          if (_error.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.red.shade100,
              width: double.infinity,
              child: Text(_error, style: const TextStyle(color: Colors.red)),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: _actions(accent, isSpec),
          ),
        ],
      ),
    );
  }

  Widget _body(MaterialColor accent) {
    if (_stage == _Stage.processing) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Processing OCR...'),
          ],
        ),
      );
    }

    if (_imageFile == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.camera_alt, size: 80, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'Tap the button below to take a photo',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    final width = _imageWidth ?? 1;
    final height = _imageHeight ?? 1;

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: AspectRatio(
              aspectRatio: width / height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(_imageFile!, fit: BoxFit.fill),
                  if (_stage == _Stage.cropping) _cropMask(),
                  if (_stage == _Stage.done && _parseResult.items.isNotEmpty)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        color: Colors.black.withValues(alpha: 0.7),
                        child: Text(
                          'Extracted ${_parseResult.items.length} item(s)',
                          style: const TextStyle(color: Colors.white),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (_stage == _Stage.cropping) _cropControls(accent),
        if (_stage == _Stage.done && _status.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(_status, style: Theme.of(context).textTheme.bodySmall),
          ),
        if (_stage == _Stage.done && _parseResult.items.isNotEmpty)
          _itemsPreview(),
      ],
    );
  }

  /// Darkens the trimmed-away edges so the operator can see exactly what OCR
  /// will and won't look at.
  Widget _cropMask() {
    return IgnorePointer(
      child: Stack(
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: FractionallySizedBox(
              heightFactor: _vInset,
              widthFactor: 1,
              child: Container(color: Colors.black.withValues(alpha: 0.55)),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: _vInset,
              widthFactor: 1,
              child: Container(color: Colors.black.withValues(alpha: 0.55)),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: _hInset,
              heightFactor: 1 - (2 * _vInset).clamp(0.0, 1.0),
              child: Container(color: Colors.black.withValues(alpha: 0.55)),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: _hInset,
              heightFactor: 1 - (2 * _vInset).clamp(0.0, 1.0),
              child: Container(color: Colors.black.withValues(alpha: 0.55)),
            ),
          ),
          Positioned.fill(
            child: FractionalTranslation(
              translation: Offset.zero,
              child: Align(
                child: FractionallySizedBox(
                  widthFactor: (1 - 2 * _hInset).clamp(0.0, 1.0),
                  heightFactor: (1 - 2 * _vInset).clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.amberAccent, width: 2),
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

  Widget _cropControls(MaterialColor accent) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(
                width: 72,
                child: Text('Sides', style: TextStyle(fontSize: 12)),
              ),
              Expanded(
                child: Slider(
                  value: _hInset,
                  max: 0.45,
                  activeColor: accent,
                  label: '${(_hInset * 100).round()}%',
                  onChanged: (v) => setState(() => _hInset = v),
                ),
              ),
            ],
          ),
          Row(
            children: [
              const SizedBox(
                width: 72,
                child: Text('Top/Bottom', style: TextStyle(fontSize: 12)),
              ),
              Expanded(
                child: Slider(
                  value: _vInset,
                  max: 0.45,
                  activeColor: accent,
                  label: '${(_vInset * 100).round()}%',
                  onChanged: (v) => setState(() => _vInset = v),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _runOcr(useFullPhoto: true),
                  child: const Text('Use Full Photo'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: () => _runOcr(useFullPhoto: false),
                  icon: const Icon(Icons.crop),
                  label: const Text('Scan Selected Area'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _itemsPreview() {
    return Container(
      height: 100,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(8),
        itemCount: _parseResult.items.length,
        itemBuilder: (context, index) {
          final item = _parseResult.items[index];
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.position,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(item.component.isEmpty ? '<empty>' : item.component),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _actions(MaterialColor accent, bool isSpec) {
    if (_stage == _Stage.idle || _imageFile == null) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _takePhoto,
          icon: const Icon(Icons.camera),
          label: const Text('Take Photo'),
          style: ElevatedButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      );
    }

    if (_stage == _Stage.cropping || _stage == _Stage.processing) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _stage == _Stage.processing ? null : _retake,
          icon: const Icon(Icons.replay),
          label: const Text('Retake'),
        ),
      );
    }

    // _Stage.done
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _retake,
            icon: const Icon(Icons.replay),
            label: const Text('Retake'),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _proceed,
            icon: const Icon(Icons.arrow_forward),
            label: Text(isSpec ? 'Next' : 'Compare'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
              foregroundColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}
