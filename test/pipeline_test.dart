import 'package:flutter_test/flutter_test.dart';
import 'package:parity/logic/assembly_pipeline.dart';
import 'package:parity/logic/ocr.dart';

void main() {
  group('AssemblyPipeline', () {
    test('returns empty list when image path is invalid (OcrException path)', () async {
      // OcrReader.readBlocks throws OcrException for missing files.
      // AssemblyPipeline must catch it and return [] rather than propagate.
      final pipeline = AssemblyPipeline(OcrReader());
      final items = await pipeline.processAssembly('nonexistent_path.png');
      expect(items, isEmpty);
    });
  });
}
