import 'package:flutter/material.dart';
import 'screens/capture_screen.dart';

void main() {
  runApp(const ParityApp());
}

class ParityApp extends StatelessWidget {
  const ParityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Parity',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

/// Bundled sample images for "Run Demo Sample" — see pubspec.yaml assets and
/// CaptureScreen.assetOverride. This is the MCB distribution-board scenario
/// (demo_assets/generate_mcb_demo.ps1): position 2 mismatched (20A -> 16A),
/// position 4 missing, position 6 an unauthorised breaker in a spare slot.
/// The electronics-breadboard scenario (demo_spec_A / demo_assembly_B) is
/// still bundled and works the same way — swap these two constants to switch.
const String _demoSpecAsset = 'demo_assets/demo_spec_mcb.png';
const String _demoAssemblyTamperedAsset =
    'demo_assets/demo_assembly_mcb_tampered.png';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _startLiveVerification(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CaptureScreen(mode: CaptureMode.spec),
      ),
    );
  }

  /// Runs the full pipeline against bundled sample images instead of the
  /// camera — a stage-safety fallback (CLAUDE.md section 21: "recorded
  /// backup demo") for when lighting or camera focus can't be trusted live,
  /// and a way to demonstrate a real discrepancy without a physical board.
  void _runDemoSample(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CaptureScreen(
          mode: CaptureMode.spec,
          assetOverride: _demoSpecAsset,
          nextAssetOverride: _demoAssemblyTamperedAsset,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Parity'),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Icon(
                Icons.compare_arrows,
                size: 80,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              const Text(
                'Assembly Verification',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Compare physical assembly to specification',
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),

              ElevatedButton.icon(
                onPressed: () => _startLiveVerification(context),
                icon: const Icon(Icons.camera_alt),
                label: const Text('Start Verification'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  textStyle: const TextStyle(fontSize: 18),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _runDemoSample(context),
                icon: const Icon(Icons.play_circle_outline),
                label: const Text('Run Demo Sample'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 15),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Runs the full pipeline on bundled sample images — a known-good '
                'fallback if venue lighting or the camera can\'t be trusted live.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.offline_bolt, color: Colors.green),
                          SizedBox(width: 8),
                          Text(
                            'Fully Offline',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'All OCR and comparison happens on device. No internet required.',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.speed, color: Colors.blue),
                          SizedBox(width: 8),
                          Text(
                            'Fast Results',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Two photos, instant comparison. Reports what differs only.',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
