import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:lucide_icons/lucide_icons.dart';
import 'package:image_picker/image_picker.dart';
import 'crypto_engine.dart';

class WatermarkScreen extends StatefulWidget {
  const WatermarkScreen({super.key});

  @override
  State<WatermarkScreen> createState() => _WatermarkScreenState();
}

class _WatermarkScreenState extends State<WatermarkScreen> {
  bool _isRecovering = false;
  Map<String, dynamic>? _recoveryResult;
  String? _errorMessage;

  Future<void> _pickAndRecoverWatermark() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    setState(() {
      _isRecovering = true;
      _recoveryResult = null;
      _errorMessage = null;
    });

    try {
      final bytes = await File(image.path).readAsBytes();

      // Hit /api/verify — it returns the full embedded manifest
      final uri = Uri.parse('${CryptoEngine.apiBaseUrl}/api/verify');
      final request = http.MultipartRequest('POST', uri)
        ..files.add(http.MultipartFile.fromBytes('image', bytes, filename: 'recover.jpg'));

      final response = await request.send();
      final body = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final json = jsonDecode(body) as Map<String, dynamic>;
        final manifest = json['manifest'] as Map<String, dynamic>?;

        if (manifest == null) {
          setState(() {
            _isRecovering = false;
            _errorMessage = 'No TrueLens watermark found in this image.\nOnly images captured with TrueLens contain an embedded manifest.';
          });
          return;
        }

        final hash = (manifest['image_hash'] ?? '') as String;
        setState(() {
          _isRecovering = false;
          _recoveryResult = {
            'device': manifest['device'] ?? 'TrueLens Authenticator',
            'timestamp': manifest['timestamp'] ?? 'Unknown',
            'algorithm': manifest['algorithm'] ?? 'ES256',
            'hash': hash.length >= 16 ? hash.substring(0, 16) : hash,
            'hashFull': hash,
          };
        });
      } else {
        setState(() {
          _isRecovering = false;
          _errorMessage = 'Server returned an error. Please try again.';
        });
      }
    } catch (e) {
      setState(() {
        _isRecovering = false;
        _errorMessage = 'Could not connect to server.\nMake sure the TrueLens server is running.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: Text('Watermark Recovery', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        centerTitle: true,
        actions: [
          if (_recoveryResult != null || _errorMessage != null)
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: () => setState(() { _recoveryResult = null; _errorMessage = null; }),
            ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_recoveryResult == null && !_isRecovering && _errorMessage == null)
                _buildUploadPrompt(),
              if (_isRecovering)
                _buildRecoveringState(),
              if (_errorMessage != null)
                _buildErrorState(_errorMessage!),
              if (_recoveryResult != null && !_isRecovering)
                _buildResultView(_recoveryResult!),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUploadPrompt() {
    return Column(
      children: [
        Icon(LucideIcons.droplets, size: 80, color: const Color(0xFF3B82F6).withOpacity(0.5)),
        const SizedBox(height: 24),
        Text(
          'Recover Identity',
          style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 12),
        Text(
          'Upload a TrueLens photo to extract its embedded manifest and reveal the original creator info.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF94A3B8)),
        ),
        const SizedBox(height: 48),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E293B),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: const Color(0xFF3B82F6).withOpacity(0.5)),
              ),
            ),
            icon: const Icon(LucideIcons.imagePlus),
            label: Text('Upload TrueLens Image', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold)),
            onPressed: _pickAndRecoverWatermark,
          ),
        ),
      ],
    );
  }

  Widget _buildRecoveringState() {
    return Column(
      children: [
        const CircularProgressIndicator(color: Color(0xFF3B82F6)),
        const SizedBox(height: 24),
        Text(
          'Extracting Manifest...',
          style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 8),
        Text(
          'Contacting verification server',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF94A3B8)),
        ),
      ],
    );
  }

  Widget _buildErrorState(String message) {
    return Column(
      children: [
        const Icon(LucideIcons.alertTriangle, size: 64, color: Color(0xFFF59E0B)),
        const SizedBox(height: 24),
        Text(
          message,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 15, color: const Color(0xFF94A3B8)),
        ),
        const SizedBox(height: 32),
        TextButton(
          onPressed: () => setState(() => _errorMessage = null),
          child: Text('Try Again', style: GoogleFonts.inter(color: const Color(0xFF3B82F6))),
        ),
      ],
    );
  }

  Widget _buildResultView(Map<String, dynamic> result) {
    final ts = result['timestamp'].toString();
    final displayTime = ts.length >= 16 ? ts.substring(0, 16).replaceFirst('T', ' ') : ts;

    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.5), width: 2),
      ),
      child: Column(
        children: [
          const Icon(LucideIcons.zap, size: 64, color: Color(0xFF3B82F6)),
          const SizedBox(height: 16),
          Text(
            'Identity Recovered',
            style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.bold, color: const Color(0xFF3B82F6)),
          ),
          const SizedBox(height: 6),
          Text(
            'from embedded TrueLens manifest',
            style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 28),
          _buildRow(LucideIcons.smartphone, 'Original Device', result['device'] as String),
          const Divider(color: Color(0xFF2D3F55), height: 28),
          _buildRow(LucideIcons.clock, 'Signed At', displayTime),
          const Divider(color: Color(0xFF2D3F55), height: 28),
          _buildRow(LucideIcons.key, 'Algorithm', result['algorithm'] as String),
          const Divider(color: Color(0xFF2D3F55), height: 28),
          _buildRow(LucideIcons.hash, 'Image Fingerprint', '${result['hash']}…'),
          const SizedBox(height: 32),
          TextButton(
            onPressed: () => setState(() => _recoveryResult = null),
            child: Text('Scan Another Image', style: GoogleFonts.inter(color: Colors.white60)),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF3B82F6)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 11)),
              const SizedBox(height: 2),
              Text(
                value,
                style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
