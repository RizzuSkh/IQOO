import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:parity/logic/image_crop.dart';

/// Writes a synthetic solid-colour PNG of [width]x[height] to a temp file
/// and returns its path, so crop math can be tested without a real photo.
Future<String> _writeSyntheticPng(String path, int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  await File(path).writeAsBytes(byteData!.buffer.asUint8List());
  image.dispose();
  picture.dispose();
  return path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('parity_crop_test');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('readImageDimensions reports the source image size', () async {
    final path = await _writeSyntheticPng(
      '${tempDir.path}/source.png',
      200,
      100,
    );
    final dims = await readImageDimensions(path);
    expect(dims.width, 200);
    expect(dims.height, 100);
  });

  test('cropImageFile trims each edge by its fraction', () async {
    final path = await _writeSyntheticPng(
      '${tempDir.path}/source.png',
      1000,
      500,
    );
    final croppedPath = await cropImageFile(
      sourcePath: path,
      fraction: const CropFraction(
        left: 0.1,
        right: 0.1,
        top: 0.2,
        bottom: 0.2,
      ),
      outputDir: tempDir.path,
    );
    final dims = await readImageDimensions(croppedPath);
    // width: 1000 * (1 - 0.1 - 0.1) = 800; height: 500 * (1 - 0.2 - 0.2) = 300
    expect(dims.width, 800);
    expect(dims.height, 300);
  });

  test('CropFraction.none leaves dimensions unchanged', () async {
    final path = await _writeSyntheticPng(
      '${tempDir.path}/source.png',
      640,
      480,
    );
    final croppedPath = await cropImageFile(
      sourcePath: path,
      fraction: CropFraction.none,
      outputDir: tempDir.path,
    );
    final dims = await readImageDimensions(croppedPath);
    expect(dims.width, 640);
    expect(dims.height, 480);
  });

  test(
    'a degenerate crop fraction throws instead of producing garbage',
    () async {
      final path = await _writeSyntheticPng(
        '${tempDir.path}/source.png',
        100,
        100,
      );
      expect(
        () => cropImageFile(
          sourcePath: path,
          fraction: const CropFraction(left: 0.6, right: 0.6),
          outputDir: tempDir.path,
        ),
        throwsArgumentError,
      );
    },
  );

  test('CropFraction.isDegenerate catches insets that sum to 1 or more', () {
    expect(const CropFraction(left: 0.5, right: 0.5).isDegenerate, isTrue);
    expect(const CropFraction(top: 0.6, bottom: 0.5).isDegenerate, isTrue);
    expect(const CropFraction(left: 0.3, right: 0.3).isDegenerate, isFalse);
  });
}
