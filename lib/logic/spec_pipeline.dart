import '../models/spec_item.dart';
import 'ocr.dart';
import 'parser.dart';

/// Pipeline for reading the handwritten or printed specification photograph.
class SpecPipeline {
  final OcrReader _ocrReader;

  SpecPipeline(this._ocrReader);

  /// Processes the specification image and returns structured components.
  Future<ParseResult> processSpecification(String imagePath) async {
    final blocks = await _ocrReader.readBlocks(imagePath);
    return parseBlocks(blocks);
  }
}
