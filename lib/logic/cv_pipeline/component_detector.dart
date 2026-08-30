class ComponentRegion {
  final String positionLabel; // e.g. "P1"
  final String bounds; // stub for Rect or crop area
  
  const ComponentRegion(this.positionLabel, this.bounds);
}

class ComponentDetector {
  /// Detects components (like ICs) placed on the detected grid.
  /// Returns regions that can be sent to OCR for reading.
  Future<List<ComponentRegion>> detectComponents(String correctedImage, String grid) async {
    // TODO: Detect ICs (black rectangles) resting on the grid
    return [
      const ComponentRegion('P1', 'bounds_stub_1'),
      const ComponentRegion('P2', 'bounds_stub_2'),
    ];
  }
}
