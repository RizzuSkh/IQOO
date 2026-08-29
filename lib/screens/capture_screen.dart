import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/spec_item.dart';
import '../logic/ocr.dart';
import '../logic/parser.dart';
import 'review_extraction_screen.dart';

enum CaptureMode { spec, assembly }

class CaptureScreen extends StatefulWidget {
  final CaptureMode mode;
  final List<SpecItem>? previousExpected;

  const CaptureScreen({
    super.key,
    required this.mode,
    this.previousExpected,
  });

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  final ImagePicker _picker = ImagePicker();
  final OcrReader _ocrReader = OcrReader();
  File? _imageFile;
  bool _processing = false;
  List<SpecItem> _extractedItems = [];
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
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 90,
      );

      if (photo == null) return;

      setState(() {
        _imageFile = File(photo.path);
        _processing = true;
        _error = '';
      });

      // Run OCR using OcrReader
      final blocks = await _ocrReader.readBlocks(photo.path);
      final parseResult = parseBlocks(blocks);

      setState(() {
        _extractedItems = parseResult.items;
        _processing = false;
        if (parseResult.isEmpty) {
          _error = 'No valid labels found (expected P1, P2, etc.)';
        }
      });
    } catch (e) {
      setState(() {
        _processing = false;
        _error = 'Error: $e';
      });
    }
  }

  void _proceed() {
    if (widget.mode == CaptureMode.spec) {
      // After capturing spec, go to assembly capture
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CaptureScreen(
            mode: CaptureMode.assembly,
            previousExpected: _extractedItems,
          ),
        ),
      );
    } else {
      // After capturing assembly, go to review
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ReviewExtractionScreen(
            expected: widget.previousExpected ?? [],
            observed: _extractedItems,
            isEditingExpected: false,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSpec = widget.mode == CaptureMode.spec;
    final title = isSpec ? 'Capture Specification' : 'Capture Assembly';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: Column(
        children: [
          // Instructions
          Container(
            padding: const EdgeInsets.all(16),
            color: isSpec ? Colors.blue.shade50 : Colors.green.shade50,
            width: double.infinity,
            child: Column(
              children: [
                Icon(
                  isSpec ? Icons.description : Icons.memory,
                  size: 48,
                  color: isSpec ? Colors.blue : Colors.green,
                ),
                const SizedBox(height: 8),
                Text(
                  isSpec
                      ? 'Photograph the specification sheet'
                      : 'Photograph the physical assembly',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  isSpec
                      ? 'Position labels clearly in frame (e.g. P1: NE555)'
                      : 'Ensure all components are visible',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          // Image preview
          Expanded(
            child: _processing
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Processing OCR...'),
                      ],
                    ),
                  )
                : _imageFile == null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.camera_alt,
                              size: 80,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Tap the button below to take a photo',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      )
                    : Stack(
                        children: [
                          Image.file(
                            _imageFile!,
                            fit: BoxFit.cover,
                            width: double.infinity,
                          ),
                          if (_extractedItems.isNotEmpty)
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                color: Colors.black.withOpacity(0.7),
                                child: Text(
                                  'Extracted ${_extractedItems.length} items',
                                  style: const TextStyle(color: Colors.white),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                        ],
                      ),
          ),

          if (_error.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.red.shade100,
              width: double.infinity,
              child: Text(_error, style: const TextStyle(color: Colors.red)),
            ),

          // Actions
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (_imageFile == null || _processing)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _processing ? null : _takePhoto,
                      icon: const Icon(Icons.camera),
                      label: const Text('Take Photo'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isSpec ? Colors.blue : Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                if (_imageFile != null && !_processing) ...[
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _takePhoto,
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
                  ),
                  const SizedBox(height: 8),
                  // Show extracted items preview
                  if (_extractedItems.isNotEmpty)
                    Container(
                      height: 100,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.all(8),
                        itemCount: _extractedItems.length,
                        itemBuilder: (context, index) {
                          final item = _extractedItems[index];
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
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
