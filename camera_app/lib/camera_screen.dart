import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:permission_handler/permission_handler.dart';

import 'crypto_engine.dart';
import 'gallery_screen.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  // Use the specific MethodChannel registered in Android RawCameraView
  final MethodChannel _rawCameraChannel = const MethodChannel('truelens_raw_camera_0');

  // Capture State
  bool _isCapturing = false;
  String _captureStatusMessage = '';
  double _captureProgress = 0.0;
  bool _isNativeViewReady = false;
  bool _hasPermissions = false;

  void _openGallery() {
    // Navigate straight to the History/Gallery screen
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => const GalleryScreen()),
    );
  }

  Future<void> _flipCamera() async {
    if (!_isNativeViewReady || _isCapturing) return;
    try {
      await _rawCameraChannel.invokeMethod('flipCamera');
    } catch (e) {
      debugPrint('Error flipping camera: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    final status = await Permission.camera.request();
    if (mounted) {
      setState(() {
        _hasPermissions = status.isGranted;
      });
    }
  }

  void _onPlatformViewCreated(int id) {
    if (mounted) {
      setState(() {
        _isNativeViewReady = true;
      });
    }
  }

  Future<void> _captureVerifiablePhoto() async {
    if (!_isNativeViewReady || _isCapturing) return;

    setState(() {
      _isCapturing = true;
      _captureStatusMessage = 'Capturing...';
      _captureProgress = 0.2;
    });

    try {
      // Step 1: Request the RAW capture from the Native Kotlin Platform View
      // This bypasses the Flutter framework entirely, taking raw bytes directly via Camera2.
      final Uint8List? rawBytes = await _rawCameraChannel.invokeMethod<Uint8List>('captureRaw');
      
      if (rawBytes == null) throw Exception("Did not receive RAW data from sensor.");

      // Step 2: "Securing Image..."
      setState(() {
        _captureStatusMessage = 'Securing Image...';
        _captureProgress = 0.5;
      });
      await Future.delayed(const Duration(milliseconds: 600));

      // Step 3: "Signing with Device Key..."
      setState(() {
        _captureStatusMessage = 'Signing with Device Key...';
        _captureProgress = 0.8;
      });

      // Pass the RAW bytes to the engine
      final cryptoResult = await CryptoEngine.secureRawImage(rawBytes);

      setState(() {
        _captureStatusMessage = 'Image Secured!';
        _captureProgress = 1.0;
      });
      
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;
      _showSuccessOverlay(context, cryptoResult);

    } catch (e) {
      debugPrint('Capture error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to capture RAW: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      }
    }
  }

  void _showSuccessOverlay(BuildContext context, Map<String, dynamic> metadata) {
    showDialog(
      context: context,
      barrierColor: const Color(0xFF0F172A).withOpacity(0.9),
      barrierDismissible: false,
      builder: (context) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFF10B981).withOpacity(0.5)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(LucideIcons.checkCircle, color: Color(0xFF10B981), size: 64),
                  ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),
                  const SizedBox(height: 24),
                  Text(
                    'Image Secured',
                    style: GoogleFonts.inter(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ).animate().fadeIn(delay: 200.ms),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildMetaRow(LucideIcons.clock, 'Time', metadata['securedAt'].toString().split('T').join(' ').substring(0, 19)),
                        const SizedBox(height: 8),
                        _buildMetaRow(LucideIcons.mapPin, 'Location', 'Unknown Local'),
                        const SizedBox(height: 8),
                        _buildMetaRow(LucideIcons.smartphone, 'Device', 'TrueLens Authenticator'),
                      ],
                    ),
                  ).animate().fadeIn(delay: 400.ms),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      child: Text('Done', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ).animate().fadeIn(delay: 600.ms),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMetaRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF94A3B8)),
        const SizedBox(width: 8),
        Text('$label:', style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 12)),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.inter(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: Center(
          child: Text(
            'Native RAW capture is only supported on Android.',
            style: GoogleFonts.inter(color: Colors.white),
          ),
        ),
      );
    }

    if (!_hasPermissions) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(LucideIcons.cameraOff, color: Colors.white, size: 64),
              const SizedBox(height: 16),
              Text(
                'Camera permission is required.',
                style: GoogleFonts.inter(color: Colors.white),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  openAppSettings();
                },
                child: const Text('Open Settings'),
              )
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Native Android PlatformView
          ClipRRect(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(32),
              bottomRight: Radius.circular(32),
            ),
            child: AndroidView(
              viewType: 'truelens_raw_camera',
              onPlatformViewCreated: _onPlatformViewCreated,
              creationParamsCodec: const StandardMessageCodec(),
            ),
          ),

          // Gradients for text visibility
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 150,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withOpacity(0.6), Colors.transparent],
                ),
              ),
            ),
          ),

          // Top UI: "Verified by TrueLens" Badge
          Positioned(
            top: 60,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A).withOpacity(0.8),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.shieldCheck, color: Color(0xFF10B981), size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Verified by TrueLens',
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Capture Animation State
          if (_isCapturing)
            Positioned.fill(
              child: Container(
                color: const Color(0xFF0F172A).withOpacity(0.85),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 80,
                        height: 80,
                        child: CircularProgressIndicator(
                          value: _captureProgress,
                          strokeWidth: 4,
                          color: const Color(0xFF10B981),
                          backgroundColor: const Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        _captureStatusMessage,
                        style: GoogleFonts.inter(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                      ).animate(key: ValueKey(_captureStatusMessage)).fadeIn().slideY(begin: 0.2, end: 0),
                    ],
                  ),
                ),
              ),
            ),

          // Bottom Controls
          if (!_isCapturing)
            Positioned(
              bottom: 30,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  Text(
                    'Capture Verifiable Photos',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(color: Colors.black.withOpacity(0.5), blurRadius: 4)],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Every image is cryptographically signed',
                    style: GoogleFonts.inter(
                      color: const Color(0xFFD1D5DB),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      shadows: [Shadow(color: Colors.black.withOpacity(0.5), blurRadius: 4)],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: const Icon(LucideIcons.image, color: Colors.white, size: 28),
                        onPressed: _openGallery,
                      ),
                      GestureDetector(
                        onTap: _captureVerifiablePhoto,
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 4),
                            color: const Color(0xFF10B981).withOpacity(0.9),
                          ),
                          child: const Center(
                            child: Icon(LucideIcons.camera, color: Colors.white, size: 36),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.flip_camera_ios, color: Colors.white, size: 28),
                        onPressed: _flipCamera,
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
