# Parity — Modern Offline Equipment & Assembly Verification

**Parity** is a modern, high-performance Flutter mobile application designed for deterministic, 100% offline verification of physical board assemblies (MCBs, ICs, breadboards, electrical panels) against specification sheets.

Built with Google ML Kit's on-device OCR, Parity operates completely air-gapped with zero network calls, guaranteeing zero data leakage and instantaneous analysis.

---

## Key Features

- 🎨 **Modern Material 3 Aesthetic**: Sleek Indigo/Slate/Emerald design system with rounded glassmorphic cards, subtle drop shadows, fluid entrance animations, and micro-interactions.
- ⚡ **100% Offline & Private**: All image processing and OCR text recognition occur strictly on-device using native Google ML Kit.
- 🎯 **Proximity-Based Label Matching**: Uses Euclidean geometric distance matching (`AssemblyPipeline`) to accurately pair labels with components despite physical offsets and rotational variations.
- 🔍 **Interactive Noise & Cropping Control**: Built-in visual slider controls allow operators to trim unnecessary noise, inspect unparsed text lines, and preview parsed items in real time.
- 🧪 **Bundled Real-Photo Demo Mode**: Includes pre-loaded real-world MCB distribution board sample images for instant stage demonstration without needing a live hardware panel.
- 📊 **Deterministic Discrepancy Engine**: Classifies component differences into four precise states (`missing`, `unexpected`, `mismatched`, `unread`) and generates human-readable diagnostic summaries.
- 📄 **Exportable Reports**: Generates structured summary reports ready for sharing or record-keeping.

---

## App Workflow

```mermaid
graph TD
    A[Home Screen / Demo Launch] --> B[Capture Specification Photo]
    B --> C[Crop & Scan Spec OCR]
    C --> D[Capture Assembly Photo]
    D --> E[Crop & Scan Assembly OCR]
    E --> F[Review & Manual Extraction Correction]
    F --> G[Deterministic Comparison Engine]
    G --> H[High-Fidelity Results Screen]
    H --> I[Export / Share Report]
```

1. **Home Screen**: Launch live camera verification or select "Run Demo Sample".
2. **Capture Specification**: Capture or select specification sheet photo with interactive crop sliders.
3. **Capture Assembly**: Capture physical assembly panel/board photo.
4. **Review Extraction**: Verify detected items, manually adjust unread components, or include ignored OCR text lines.
5. **Results Screen**: View color-coded discrepancy breakdown, confidence scores, and natural-language summary.

---

## Directory Structure

```
lib/
├── logic/
│   ├── assembly_pipeline.dart    # Assembly OCR & geometric proximity matching
│   ├── spec_pipeline.dart        # Spec sheet scanning & row parsing
│   ├── compare.dart              # Core 4-state discrepancy comparison engine
│   ├── parser.dart               # Text block & position regex parsing
│   ├── phrase.dart               # Deterministic natural-language summary builder
│   └── ocr.dart                  # On-device ML Kit OCR runner
├── models/
│   ├── diff_result.dart          # Discrepancy data contracts
│   └── spec_item.dart            # Spec item model with confidence tracking
├── screens/
│   ├── capture_screen.dart       # Interactive camera & crop viewport
│   ├── review_extraction_screen.dart # Expected vs. observed manual correction list
│   └── results_screen.dart       # High-fidelity result summary & discrepancy card view
└── main.dart                     # App entry point with Material 3 theme & animations
```

---

## Getting Started

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (v3.27.0 or newer)
- Android Studio / VS Code with Flutter extension
- Physical Android device (Android 8.0 / SDK 26+) connected via USB

### Installation & Run

1. **Clone the repository:**
   ```bash
   git clone https://github.com/RizzuSkh/IQOO.git
   cd IQOO
   ```

2. **Fetch dependencies:**
   ```bash
   flutter pub get
   ```

3. **Run unit & widget tests:**
   ```bash
   flutter test
   ```

4. **Deploy to connected Android device:**
   ```bash
   flutter devices
   flutter run -d <your-device-id>
   ```

---

## Verification & Testing

The verification logic is covered by 63 unit and widget tests covering:
- Deterministic 4-state comparison logic (`missing`, `unexpected`, `mismatched`, `unread`).
- Spatial proximity label matching for offset text blocks.
- Report text generation formatting and unread component handling.

Run all tests with:
```bash
flutter test
```

---

## License

Internal Development — All Rights Reserved.