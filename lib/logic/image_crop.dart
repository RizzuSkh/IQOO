import 'dart:io';
import 'dart:ui' as ui;

/// Crops a captured photo to the region the operator selected before OCR runs.
///
/// This exists because whole-frame OCR on a real assembly photo also reads
/// everything else in the shot — a breadboard's own column numbers, resistor
/// colour codes, part date codes — which then shows up as unwanted text in
/// the extracted component list. Restricting OCR to a chosen region is the
/// fix; this file does the actual pixel crop.
///
/// Uses only `dart:ui`, already part of the Flutter SDK — no new dependency.

/// A crop expressed as insets, each a fraction of the full image's width or
/// height (0.0 to under 0.5), so it is resolution-independent.
class CropFraction {
  /// Fraction to trim from the left edge.
  final double left;

  /// Fraction to trim from the top edge.
  final double top;

  /// Fraction to trim from the right edge.
  final double right;

  /// Fraction to trim from the bottom edge.
  final double bottom;

  /// Creates a crop. All four default to 0 (no crop).
  const CropFraction({
    this.left = 0,
    this.top = 0,
    this.right = 0,
    this.bottom = 0,
  });

  /// No crop at all — the full image.
  static const none = CropFraction();

  /// True when this crop would leave no image area.
  bool get isDegenerate => left + right >= 1.0 || top + bottom >= 1.0;
}

/// Decodes the image at [path] and returns its pixel dimensions.
///
/// Callers use this to size the crop-selection UI to the photo's own aspect
/// ratio before the operator picks a region.
Future<({int width, int height})> readImageDimensions(String path) async {
  final bytes = await File(path).readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final dimensions = (width: frame.image.width, height: frame.image.height);
  frame.image.dispose();
  codec.dispose();
  return dimensions;
}

/// Crops the image at [sourcePath] by [fraction] and writes a PNG into
/// [outputDir], returning the new file's path.
///
/// Throws [ArgumentError] if [fraction] is degenerate.
Future<String> cropImageFile({
  required String sourcePath,
  required CropFraction fraction,
  required String outputDir,
}) async {
  if (fraction.isDegenerate) {
    throw ArgumentError('Crop fraction leaves no image area: $fraction');
  }

  final bytes = await File(sourcePath).readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;

  try {
    final width = image.width.toDouble();
    final height = image.height.toDouble();

    final cropLeft = width * fraction.left;
    final cropTop = height * fraction.top;
    final cropWidth = (width * (1 - fraction.left - fraction.right))
        .roundToDouble();
    final cropHeight = (height * (1 - fraction.top - fraction.bottom))
        .roundToDouble();

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final srcRect = ui.Rect.fromLTWH(cropLeft, cropTop, cropWidth, cropHeight);
    final dstRect = ui.Rect.fromLTWH(0, 0, cropWidth, cropHeight);
    canvas.drawImageRect(image, srcRect, dstRect, ui.Paint());

    final picture = recorder.endRecording();
    final croppedImage = await picture.toImage(
      cropWidth.round(),
      cropHeight.round(),
    );
    try {
      final byteData = await croppedImage.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData == null) {
        throw StateError('Failed to encode cropped image as PNG');
      }
      final outPath =
          '$outputDir/parity_crop_${DateTime.now().microsecondsSinceEpoch}.png';
      final outFile = File(outPath);
      await outFile.writeAsBytes(byteData.buffer.asUint8List());
      return outPath;
    } finally {
      croppedImage.dispose();
      picture.dispose();
    }
  } finally {
    image.dispose();
    codec.dispose();
  }
}
