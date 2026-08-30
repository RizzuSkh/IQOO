import 'dart:io';
import 'dart:ui' show Rect;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Thin wrapper around ML Kit on-device text recognition.
///
/// This file does perception only: image in, text blocks out. It makes no
/// judgement about what the text means — that is `compare()`'s job.
///
/// Recognition runs entirely on the device. No network call is made here, and
/// no acceleration claim is made: ML Kit chooses its own execution path and
/// does not expose that choice to us.

/// One recognised block of text and where it sat in the image.
///
/// Deliberately a plain value type rather than ML Kit's `TextBlock`, so the
/// parser and its tests do not depend on the ML Kit plugin or a live device.
class OcrBlock {
  /// The recognised text of the block, as ML Kit returned it.
  final String text;

  /// The block's bounding box in image pixel coordinates.
  final Rect boundingBox;

  /// Mean of the per-line confidences ML Kit reported, 0.0 to 1.0.
  ///
  /// Defaults to 1.0 when ML Kit supplies no confidence, which it often does
  /// not. Treat this as "unknown", not as a measured certainty.
  final double confidence;

  /// Creates a recognised block.
  const OcrBlock({
    required this.text,
    required this.boundingBox,
    this.confidence = 1.0,
  });

  /// Vertical centre of the block, used by the parser to group blocks into rows.
  double get centreY => boundingBox.center.dy;

  /// Left edge of the block, used by the parser to order blocks within a row.
  double get left => boundingBox.left;

  /// Height of the block, used to derive the parser's row tolerance.
  double get height => boundingBox.height;

  /// Horizontal centre of the block, used to cluster blocks into columns —
  /// stacked lines on one breaker (rating, voltage, capacity) share an X
  /// position the way a row of labels shares a Y position.
  double get centreX => boundingBox.center.dx;

  /// Width of the block, used to derive the parser's column tolerance.
  double get width => boundingBox.width;

  @override
  String toString() => 'OcrBlock("$text", $boundingBox)';
}

/// Thrown when text recognition cannot be performed at all.
///
/// Recognising zero blocks is not an error — it is an empty result the UI
/// reports as "no labels found" (PRD section 23).
class OcrException implements Exception {
  /// What went wrong, in terms suitable for showing to the operator.
  final String message;

  /// The underlying error, when there was one.
  final Object? cause;

  /// Creates an OCR failure.
  const OcrException(this.message, [this.cause]);

  @override
  String toString() => 'OcrException: $message';
}

/// Reads text from images using the on-device ML Kit Latin recogniser.
///
/// Hold one instance for as long as you need it and call [close] when done;
/// creating a recogniser per image leaks native resources.
class OcrReader {
  final TextRecognizer _recognizer;

  /// Creates a reader for Latin-script text.
  OcrReader()
    : _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  /// Recognises the image at [imagePath] and returns its text blocks.
  ///
  /// Returns an empty list when the image contains no readable text. Throws
  /// [OcrException] if the file is missing or recognition itself fails.
  Future<List<OcrBlock>> readBlocks(String imagePath) async {
    if (!File(imagePath).existsSync()) {
      throw OcrException('Image not found at $imagePath');
    }

    final RecognizedText recognised;
    try {
      recognised = await _recognizer.processImage(
        InputImage.fromFilePath(imagePath),
      );
    } catch (error) {
      throw OcrException('Text recognition failed', error);
    }

    return recognised.blocks
        .map(
          (block) => OcrBlock(
            text: block.text,
            boundingBox: block.boundingBox,
            confidence: _meanLineConfidence(block),
          ),
        )
        .toList();
  }

  /// Mean of the confidences ML Kit reported for [block]'s lines, or 1.0 if none.
  double _meanLineConfidence(TextBlock block) {
    final reported = block.lines
        .map((line) => line.confidence)
        .whereType<double>()
        .toList();
    if (reported.isEmpty) return 1.0;
    return reported.reduce((a, b) => a + b) / reported.length;
  }

  /// Releases the native recogniser. Safe to call more than once.
  Future<void> close() => _recognizer.close();
}
