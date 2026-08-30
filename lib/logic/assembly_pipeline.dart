import 'dart:math';
import '../models/spec_item.dart';
import 'ocr.dart';
import 'parser.dart';

/// Pipeline for processing the physical breadboard photograph.
class AssemblyPipeline {
  final OcrReader _ocrReader;
  final RegExp _positionPattern = RegExp(r'^(P\d+|\d+(-\d+)?)$');
  final RegExp _trailingPunctuation = RegExp(r'[:.,;–—]+$');

  AssemblyPipeline(this._ocrReader);

  Future<List<SpecItem>> processAssembly(String imagePath) async {
    final List<OcrBlock> blocks;
    try {
      blocks = await _ocrReader.readBlocks(imagePath);
    } on OcrException {
      return [];
    }

    // Clean up blocks
    final usable = blocks
        .map((b) => OcrBlock(
              text: b.text.replaceAll(RegExp(r'\s+'), ' ').trim(),
              boundingBox: b.boundingBox,
              confidence: b.confidence,
            ))
        .where((b) => b.text.isNotEmpty)
        .toList();

    if (usable.isEmpty) return [];

    // Separate blocks into positions and components
    final positions = <OcrBlock>[];
    final components = <OcrBlock>[];

    for (final block in usable) {
      final candidate = block.text
          .toUpperCase()
          .replaceAll(_trailingPunctuation, '')
          .trim();
      if (_positionPattern.hasMatch(candidate)) {
        // Normalise text for the position list
        positions.add(OcrBlock(
          text: candidate,
          boundingBox: block.boundingBox,
          confidence: block.confidence,
        ));
      } else {
        components.add(block);
      }
    }

    final items = <SpecItem>[];

    // For each position, find the nearest component block
    for (final pos in positions) {
      if (components.isEmpty) {
        items.add(SpecItem(
          position: pos.text,
          component: '',
          confidence: pos.confidence,
        ));
        continue;
      }

      OcrBlock? nearest;
      double minDistance = double.infinity;

      final posX = pos.boundingBox.left + pos.boundingBox.width / 2;
      final posY = pos.boundingBox.top + pos.boundingBox.height / 2;

      for (final comp in components) {
        final compX = comp.boundingBox.left + comp.boundingBox.width / 2;
        final compY = comp.boundingBox.top + comp.boundingBox.height / 2;

        final dist = sqrt(pow(posX - compX, 2) + pow(posY - compY, 2));
        if (dist < minDistance) {
          minDistance = dist;
          nearest = comp;
        }
      }

      items.add(SpecItem(
        position: pos.text,
        component: nearest!.text,
        confidence: (pos.confidence + nearest.confidence) / 2,
      ));
    }

    return items;
  }
}
