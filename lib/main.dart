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

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Parity'),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Logo/Icon
            Icon(
              Icons.compare_arrows,
              size: 80,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),

            // Title
            const Text(
              'Assembly Verification',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),

            // Subtitle
            Text(
              'Compare physical assembly to specification',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 48),

            // Start button
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CaptureScreen(mode: CaptureMode.spec),
                  ),
                );
              },
              icon: const Icon(Icons.camera_alt),
              label: const Text('Start Verification'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 20),
                textStyle: const TextStyle(fontSize: 18),
              ),
            ),
            const SizedBox(height: 24),

            // Info cards
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.offline_bolt, color: Colors.green),
                        SizedBox(width: 8),
                        Text('Fully Offline', style: TextStyle(fontWeight: FontWeight.bold)),
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
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.speed, color: Colors.blue),
                        SizedBox(width: 8),
                        Text('Fast Results', style: TextStyle(fontWeight: FontWeight.bold)),
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
    );
  }
}
