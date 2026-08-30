import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
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

  /// Bundled asset path to load instead of opening the camera. Used by the
  /// Home screen's "Run Demo Sample" fallback (CLAUDE.md section 21's
  /// recorded-backup-demo requirement) so a presenter can run the full
  /// pipeline on stage without depending on live camera/lighting, and so the
  /// real on-device OCR path can be exercised without any picker at all.
  /// Null in normal use.
  final String? assetOverride;

  /// The assembly-step asset to chain to when [assetOverride] was used for
  /// the spec step. Ignored in normal use.
  final String? nextAssetOverride;

  const CaptureScreen({
    super.key,
    required this.mode,
    this.previousExpected,
    this.previousExpectedUnparsed = const [],
    this.previousExpectedNoise = const [],
    this.assetOverride,
    this.nextAssetOverride,
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
  int _blocksRead = 0;
  String _error = '';
  bool _loadingAsset = false;

  @override
  void initState() {
    super.initState();
    if (widget.assetOverride != null) {
      // Demo-sample mode: load the bundled asset and run OCR immediately,
      // no camera/gallery/crop step needed — it's already framed correctly.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _loadAsset(widget.assetOverride!),
      );
    }
  }

  @override
  void dispose() {
    _ocrReader.close();
    super.dispose();
  }

  /// Copies a bundled asset to a real file (ML Kit needs a file path, not an
  /// asset bundle key) and runs it straight through OCR.
  Future<void> _loadAsset(String assetPath) async {
    setState(() {
      _loadingAsset = true;
      _error = '';
    });
    try {
      final bytes = await rootBundle.load(assetPath);
      final tempDir = await getTemporaryDirectory();
      final fileName = assetPath.split('/').last;
      final file = File('${tempDir.path}/demo_$fileName');
      await file.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );

      final dims = await readImageDimensions(file.path);
      if (!mounted) return;
      setState(() {
        _imageFile = file;
        _imageWidth = dims.width;
        _imageHeight = dims.height;
        _hInset = 0.0;
        _vInset = 0.0;
        _loadingAsset = false;
      });
      await _runOcr(useFullPhoto: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingAsset = false;
        _stage = _Stage.idle;
        _error = 'Could not load the demo sample: $e';
      });
    }
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
        _blocksRead = blocks.length;
        _stage = _Stage.done;
        _error = _diagnose(blocks.length, parseResult);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.cropping;
        _error = 'OCR failed: $e';
      });
    }
  }

  /// Explains what OCR actually did and what to do next, rather than a
  /// generic "not found" message. Returns '' when the capture is clean.
  String _diagnose(int blocksRead, ParseResult result) {
    if (blocksRead == 0) {
      return 'No text was detected in this photo at all. Check focus and '
          'lighting, make sure the label sheet fills the frame, then retake.';
    }
    if (result.items.isEmpty) {
      final sample = result.unparsedRows.isNotEmpty
          ? ' First line read: "${result.unparsedRows.first}".'
          : '';
      return 'Found $blocksRead block(s) of text, but none started with a '
          'position label like "1" or "P1".$sample You can still tap Next '
          'and add rows by hand on the next screen, or Retake and crop '
          'tighter around just the position and component columns.';
    }
    if (result.unparsedRows.isNotEmpty) {
      return 'Parsed ${result.items.length} row(s). ${result.unparsedRows.length} '
          'more line(s) did not match a position and are listed on the next '
          "screen — add them manually if they're real rows.";
    }
    return '';
  }

  void _retake() {
    setState(() {
      _imageFile = null;
      _stage = _Stage.idle;
      _error = '';
      _parseResult = const ParseResult(items: [], unparsedRows: []);
    });
    // Demo-sample screens have no camera to fall back to — reload the same
    // asset rather than stranding the operator on an unusable idle screen.
    if (widget.assetOverride != null) {
      _loadAsset(widget.assetOverride!);
    }
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
            assetOverride: widget.nextAssetOverride,
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
    final isDemo = widget.assetOverride != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (isDemo)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Chip(
                label: Text('DEMO SAMPLE', style: TextStyle(fontSize: 11)),
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
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
                            ? 'Position labels clearly in frame (e.g. "1  NE555" or "P1: NE555")'
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
              padding: const EdgeInsets.all(12),
              color: Colors.amber.shade100,
              width: double.infinity,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 18, color: Colors.brown),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error,
                      style: const TextStyle(color: Colors.brown, fontSize: 13),
                    ),
                  ),
                ],
              ),
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
    if (_loadingAsset) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading demo sample...'),
          ],
        ),
      );
    }

    if (_stage == _Stage.processing) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Reading text on-device (ML Kit)...'),
          ],
        ),
      );
    }

    if (_imageFile == null) {
      final isDemo = widget.assetOverride != null;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isDemo ? Icons.play_circle_outline : Icons.camera_alt,
              size: 80,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              isDemo
                  ? 'Tap the button below to reload the demo sample'
                  : 'Tap the button below to take a photo',
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
                          '$_blocksRead text block(s) read -> '
                          '${_parseResult.items.length} row(s) parsed'
                          '${_parseResult.ignoredNoise.isEmpty ? '' : ', ${_parseResult.ignoredNoise.length} ignored as noise'}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
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
    if (_loadingAsset) {
      return const SizedBox.shrink();
    }

    if (_stage == _Stage.idle || _imageFile == null) {
      final isDemo = widget.assetOverride != null;
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: isDemo
              ? () => _loadAsset(widget.assetOverride!)
              : _takePhoto,
          icon: Icon(isDemo ? Icons.play_circle_outline : Icons.camera),
          label: Text(isDemo ? 'Reload Demo Sample' : 'Take Photo'),
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
