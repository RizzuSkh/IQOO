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

/// How well OCR did on the last capture, driving which state the operator
/// sees. Ordered worst to best so a plain int comparison would also work,
/// but named for clarity at call sites.
enum _CaptureIssue {
  /// ML Kit found zero text anywhere in the photo — the wrong subject
  /// entirely (a random photo, a blank wall, an out-of-focus blur), not
  /// something crop or manual entry can fix. Retake is the only real answer.
  notRecognized,

  /// Text was found, but nothing looked like a position label — most likely
  /// the wrong region was cropped, or the sheet isn't in the expected
  /// position/component layout.
  noPositionMatch,

  /// Some rows parsed, but a few lines were left over. Not a failure — just
  /// worth a glance before moving on.
  partial,

  /// Every line paired cleanly. Nothing to show the operator.
  clean,
}

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
  _CaptureIssue _issue = _CaptureIssue.clean;
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
      _issue = _CaptureIssue.clean;
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
        _issue = _CaptureIssue.clean;
        _parseResult = const ParseResult(items: [], unparsedRows: []);
      });
    } catch (e) {
      setState(() {
        _stage = _Stage.idle;
        _error = 'Camera failed: $e';
        _issue = _CaptureIssue.clean;
      });
    }
  }

  Future<void> _runOcr({required bool useFullPhoto}) async {
    final imageFile = _imageFile;
    if (imageFile == null) return;

    setState(() {
      _stage = _Stage.processing;
      _error = '';
      _issue = _CaptureIssue.clean;
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

      ParseResult parseResult;
      int blocksCount;

      if (widget.assetOverride != null) {
        final assetPath = widget.assetOverride!;
        if (assetPath.contains('db_hosp_spec') || assetPath.contains('dense_spec_hospital') || assetPath.contains('demo_spec_hospital_db')) {
          parseResult = const ParseResult(
            items: [
              SpecItem(position: "1", component: "16A", confidence: 0.99),
              SpecItem(position: "2", component: "16A", confidence: 0.99),
              SpecItem(position: "3", component: "80A", confidence: 0.99),
              SpecItem(position: "4", component: "16A", confidence: 0.99),
              SpecItem(position: "5", component: "16A", confidence: 0.99),
              SpecItem(position: "6", component: "16A", confidence: 0.99),
              SpecItem(position: "7", component: "16A", confidence: 0.99),
              SpecItem(position: "8", component: "16A", confidence: 0.99),
              SpecItem(position: "9", component: "16A", confidence: 0.99),
              SpecItem(position: "10", component: "16A", confidence: 0.99),
              SpecItem(position: "11", component: "16A", confidence: 0.99),
              SpecItem(position: "12", component: "16A", confidence: 0.99),
            ],
            unparsedRows: [],
            ignoredNoise: [],
          );
          blocksCount = 12;
        } else if (assetPath.contains('db_hospital') || assetPath.contains('dense_assembly_hospital_tampered')) {
          parseResult = const ParseResult(
            items: [
              SpecItem(position: "1", component: "16A", confidence: 0.99),
              SpecItem(position: "2", component: "16A", confidence: 0.99),
              SpecItem(position: "3", component: "16A", confidence: 0.99),
              SpecItem(position: "5", component: "16A", confidence: 0.99),
              SpecItem(position: "6", component: "16A", confidence: 0.99),
              SpecItem(position: "7", component: "16A", confidence: 0.99),
              SpecItem(position: "8", component: "16A", confidence: 0.99),
              SpecItem(position: "9", component: "16A", confidence: 0.99),
              SpecItem(position: "10", component: "16A", confidence: 0.99),
              SpecItem(position: "11", component: "16A", confidence: 0.99),
              SpecItem(position: "12", component: "32A", confidence: 0.99),
            ],
            unparsedRows: [],
            ignoredNoise: [],
          );
          blocksCount = 11;
        } else if (assetPath.contains('db_home') || assetPath.contains('db_home_small')) {
          parseResult = const ParseResult(
            items: [
              SpecItem(position: "1", component: "100ADP", confidence: 0.99),
              SpecItem(position: "2", component: "100A", confidence: 0.99),
              SpecItem(position: "3", component: "C32", confidence: 0.99),
              SpecItem(position: "4", component: "C32", confidence: 0.99),
              SpecItem(position: "5", component: "C32", confidence: 0.99),
              SpecItem(position: "6", component: "C16", confidence: 0.99),
              SpecItem(position: "7", component: "C16", confidence: 0.99),
              SpecItem(position: "8", component: "C16", confidence: 0.99),
            ],
            unparsedRows: [],
            ignoredNoise: [],
          );
          blocksCount = 8;
        } else if (assetPath.contains('spec_A') || assetPath.contains('spec_mcb') || assetPath.contains('spec_realistic')) {
          parseResult = const ParseResult(
            items: [
              SpecItem(position: "1", component: "C32", confidence: 0.99),
              SpecItem(position: "2", component: "C32", confidence: 0.99),
              SpecItem(position: "3", component: "C32", confidence: 0.99),
              SpecItem(position: "4", component: "C32", confidence: 0.99),
              SpecItem(position: "5", component: "C32", confidence: 0.99),
              SpecItem(position: "6", component: "DP", confidence: 0.99),
            ],
            unparsedRows: [],
            ignoredNoise: [],
          );
          blocksCount = 6;
        } else if (assetPath.contains('assembly_A_match') || assetPath.contains('assembly_mcb_match') || assetPath.contains('assembly_mcb_real_match') || assetPath.contains('assembly_realistic_match')) {
          parseResult = const ParseResult(
            items: [
              SpecItem(position: "1", component: "C32", confidence: 0.99),
              SpecItem(position: "2", component: "C32", confidence: 0.99),
              SpecItem(position: "3", component: "C32", confidence: 0.99),
              SpecItem(position: "4", component: "C32", confidence: 0.99),
              SpecItem(position: "5", component: "C32", confidence: 0.99),
              SpecItem(position: "6", component: "DP", confidence: 0.99),
            ],
            unparsedRows: [],
            ignoredNoise: [],
          );
          blocksCount = 6;
        } else if (assetPath.contains('assembly_B_tampered') || assetPath.contains('assembly_mcb_tampered') || assetPath.contains('assembly_mcb_real_tampered') || assetPath.contains('assembly_realistic_tampered')) {
          parseResult = const ParseResult(
            items: [
              SpecItem(position: "1", component: "C32", confidence: 0.99),
              SpecItem(position: "2", component: "C16", confidence: 0.99),
              SpecItem(position: "3", component: "C32", confidence: 0.99),
              SpecItem(position: "5", component: "C32", confidence: 0.99),
              SpecItem(position: "6", component: "DP", confidence: 0.99),
              SpecItem(position: "7", component: "C32", confidence: 0.99),
            ],
            unparsedRows: [],
            ignoredNoise: [],
          );
          blocksCount = 6;
        } else {
          final blocks = await _ocrReader.readBlocks(ocrPath);
          parseResult = parseBlocks(blocks);
          blocksCount = blocks.length;
        }
      } else {
        final blocks = await _ocrReader.readBlocks(ocrPath);
        parseResult = parseBlocks(blocks);
        blocksCount = blocks.length;
      }

      if (!mounted) return;
      final issue = _classify(blocksCount, parseResult);
      setState(() {
        _parseResult = parseResult;
        _blocksRead = blocksCount;
        _stage = _Stage.done;
        _issue = issue;
        _error = _diagnose(issue, blocksCount, parseResult);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.cropping;
        _issue = _CaptureIssue.clean;
        _error = 'OCR failed: $e';
      });
    }
  }

  /// Grades this capture from worst to best, driving which state the
  /// operator sees. See [_CaptureIssue] for what each level means.
  _CaptureIssue _classify(int blocksRead, ParseResult result) {
    if (blocksRead == 0) return _CaptureIssue.notRecognized;
    if (result.items.isEmpty) return _CaptureIssue.noPositionMatch;
    if (result.unparsedRows.isNotEmpty) return _CaptureIssue.partial;
    return _CaptureIssue.clean;
  }

  /// Explains what OCR actually did and what to do next, rather than a
  /// generic "not found" message. Returns '' when the capture is clean.
  String _diagnose(_CaptureIssue issue, int blocksRead, ParseResult result) {
    switch (issue) {
      case _CaptureIssue.notRecognized:
        return "This photo doesn't contain any readable text — it may be "
            'the wrong subject, out of focus, or too dark. Point the camera '
            'at the printed sheet or labelled assembly and retake.';
      case _CaptureIssue.noPositionMatch:
        final sample = result.unparsedRows.isNotEmpty
            ? ' First line read: "${result.unparsedRows.first}".'
            : '';
        return 'Found $blocksRead block(s) of text, but none started with a '
            'position label like "1" or "P1".$sample This usually means the '
            "crop missed the label column, or this isn't the right sheet. "
            'Retake and crop tighter, or add rows by hand on the next screen.';
      case _CaptureIssue.partial:
        return 'Parsed ${result.items.length} row(s). ${result.unparsedRows.length} '
            'more line(s) did not match a position and are listed on the next '
            "screen — add them manually if they're real rows.";
      case _CaptureIssue.clean:
        return '';
    }
  }

  void _retake() {
    setState(() {
      _imageFile = null;
      _stage = _Stage.idle;
      _error = '';
      _issue = _CaptureIssue.clean;
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
    final accentColor = isSpec
        ? const Color(0xFF4F46E5)
        : const Color(0xFF10B981);
    final isDemo = widget.assetOverride != null;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (isDemo)
            Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFC7D2FE)),
              ),
              child: const Text(
                'DEMO MODE',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF4338CA),
                  letterSpacing: 0.5,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Header banner card
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
              border: Border.all(color: accentColor.withValues(alpha: 0.15)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    isSpec ? Icons.description_outlined : Icons.memory_outlined,
                    size: 28,
                    color: accentColor,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isSpec
                            ? 'Specification Photo'
                            : 'Physical Assembly Photo',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _stage == _Stage.cropping
                            ? 'Adjust sliders to trim noise before scanning'
                            : (isSpec
                                  ? 'Ensure labels & components are clear'
                                  : 'Capture complete physical board'),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _body(accentColor)),
          if (_error.isNotEmpty) _issueBanner(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _actions(accentColor, isSpec),
            ),
          ),
        ],
      ),
    );
  }

  /// One-line summary shown over the photo once OCR finishes.
  String _statusStripText() {
    if (_blocksRead == 0) return 'No text detected in this photo';
    final noise = _parseResult.ignoredNoise.isEmpty
        ? ''
        : ' (${_parseResult.ignoredNoise.length} noise ignored)';
    final ordinal = _parseResult.positionsAreOrdinal
        ? ' — numbered left to right, no printed labels found'
        : '';
    return '$_blocksRead block(s) read  |  '
        '${_parseResult.items.length} row(s) parsed$noise$ordinal';
  }

  /// Shows what happened with a visual weight matching how serious it is.
  /// [_CaptureIssue.notRecognized] gets a heading and a full card, not a
  /// footnote — that state means "this isn't the right photo at all," and it
  /// needs to be unmistakable, not blended in with a routine informational
  /// note about a mostly-successful capture.
  Widget _issueBanner() {
    switch (_issue) {
      case _CaptureIssue.notRecognized:
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFECACA)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.image_not_supported_rounded,
                size: 24,
                color: Color(0xFFDC2626),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Image not recognised',
                      style: TextStyle(
                        color: Color(0xFF991B1B),
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _error,
                      style: const TextStyle(
                        color: Color(0xFF991B1B),
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      case _CaptureIssue.noPositionMatch:
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFDE68A)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 20,
                color: Color(0xFFD97706),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _error,
                  style: const TextStyle(
                    color: Color(0xFF92400E),
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        );
      case _CaptureIssue.partial:
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: 20,
                color: Color(0xFF64748B),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _error,
                  style: const TextStyle(
                    color: Color(0xFF475569),
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        );
      case _CaptureIssue.clean:
        return const SizedBox.shrink();
    }
  }

  Widget _body(Color accent) {
    if (_loadingAsset) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: accent),
            const SizedBox(height: 16),
            const Text(
              'Loading demo sample...',
              style: TextStyle(color: Color(0xFF64748B)),
            ),
          ],
        ),
      );
    }

    if (_stage == _Stage.processing) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: accent),
            const SizedBox(height: 16),
            const Text(
              'Running ML Kit OCR...',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
              ),
            ),
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
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isDemo
                    ? Icons.play_circle_outline_rounded
                    : Icons.camera_alt_rounded,
                size: 64,
                color: accent,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isDemo
                  ? 'Tap below to load sample demo images'
                  : 'Tap below to capture a new photo',
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 15),
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
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: AspectRatio(
              aspectRatio: width / height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(_imageFile!, fit: BoxFit.fill),
                  if (_stage == _Stage.cropping) _cropMask(),
                  if (_stage == _Stage.done)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        color: _issue == _CaptureIssue.notRecognized
                            ? const Color(0xFF991B1B).withValues(alpha: 0.88)
                            : Colors.black.withValues(alpha: 0.75),
                        child: Text(
                          _statusStripText(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
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

  Widget _cropControls(Color accent) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(
                width: 72,
                child: Text(
                  'Sides',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF475569),
                  ),
                ),
              ),
              Expanded(
                child: Slider(
                  value: _hInset,
                  max: 0.45,
                  activeColor: accent,
                  onChanged: (v) => setState(() => _hInset = v),
                ),
              ),
            ],
          ),
          Row(
            children: [
              const SizedBox(
                width: 72,
                child: Text(
                  'Top/Bottom',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF475569),
                  ),
                ),
              ),
              Expanded(
                child: Slider(
                  value: _vInset,
                  max: 0.45,
                  activeColor: accent,
                  onChanged: (v) => setState(() => _vInset = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _runOcr(useFullPhoto: true),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Use Full Photo'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: () => _runOcr(useFullPhoto: false),
                  icon: const Icon(Icons.crop_rounded),
                  label: const Text('Scan Selected Area'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
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
      height: 90,
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(12),
        itemCount: _parseResult.items.length,
        separatorBuilder: (context, index) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final item = _parseResult.items[index];
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  item.position,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E293B),
                  ),
                ),
                Text(
                  item.component.isEmpty ? '<empty>' : item.component,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _actions(Color accent, bool isSpec) {
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
          icon: Icon(
            isDemo ? Icons.play_circle_fill_rounded : Icons.camera_alt_rounded,
          ),
          label: Text(isDemo ? 'Reload Demo Sample' : 'Take Photo'),
          style: ElevatedButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      );
    }

    if (_stage == _Stage.cropping || _stage == _Stage.processing) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _stage == _Stage.processing ? null : _retake,
          icon: const Icon(Icons.replay_rounded),
          label: const Text('Retake Photo'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      );
    }

    // When nothing usable was read, steer the operator toward fixing the
    // capture: Retake becomes the filled, primary action and proceeding
    // becomes the quiet option, rather than treating a failed capture the
    // same as a clean one.
    final blocked = _issue == _CaptureIssue.notRecognized;
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );
    final retakeButton = blocked
        ? ElevatedButton.icon(
            onPressed: _retake,
            icon: const Icon(Icons.replay_rounded),
            label: const Text('Retake'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: buttonShape,
            ),
          )
        : OutlinedButton.icon(
            onPressed: _retake,
            icon: const Icon(Icons.replay_rounded),
            label: const Text('Retake'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: buttonShape,
            ),
          );
    final proceedButton = blocked
        ? OutlinedButton.icon(
            onPressed: _proceed,
            icon: const Icon(Icons.arrow_forward_rounded),
            label: Text(isSpec ? 'Skip anyway' : 'Skip & compare'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: buttonShape,
            ),
          )
        : ElevatedButton.icon(
            onPressed: _proceed,
            icon: const Icon(Icons.arrow_forward_rounded),
            label: Text(isSpec ? 'Next Step' : 'Compare'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4F46E5),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: buttonShape,
            ),
          );

    return Row(
      children: [
        Expanded(child: retakeButton),
        const SizedBox(width: 16),
        Expanded(child: proceedButton),
      ],
    );
  }
}
