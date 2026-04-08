import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:image_picker/image_picker.dart';
import 'crypto_engine.dart';

class VerificationScreen extends StatefulWidget {
  final File? preloadedFile; // optional: auto-load a just-captured image
  const VerificationScreen({super.key, this.preloadedFile});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  bool _isVerifying = false;
  Map<String, dynamic>? _verificationResult;

  @override
  void initState() {
    super.initState();
    // If a pre-captured file was passed in, auto-verify it immediately
    if (widget.preloadedFile != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _verifyFile(widget.preloadedFile!);
      });
    }
  }

  Future<void> _verifyFile(File file) async {
    setState(() { _isVerifying = true; _verificationResult = null; });
    try {
      final bytes = await file.readAsBytes();
      final result = await CryptoEngine.verifyImage(bytes);
      if (mounted) setState(() { _verificationResult = result; _isVerifying = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _isVerifying = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Verification Failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _pickAndVerifyImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) await _verifyFile(File(image.path));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: Text('Proof Engine', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_verificationResult == null && !_isVerifying)
                _buildUploadPrompt(),
              if (_isVerifying)
                _buildVerifyingState(),
              if (_verificationResult != null && !_isVerifying)
                _buildResultView(_verificationResult!),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUploadPrompt() {
    return Column(
      children: [
        Icon(LucideIcons.shieldCheck, size: 80, color: const Color(0xFF10B981).withOpacity(0.5)),
        const SizedBox(height: 24),
        Text(
          'Independent Verification',
          style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 12),
        Text(
          'Upload any TrueLens photo to verify its authenticity and see origin proofs.',
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
                side: BorderSide(color: const Color(0xFF10B981).withOpacity(0.5)),
              ),
            ),
            icon: const Icon(LucideIcons.uploadCloud),
            label: Text('Upload Image', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold)),
            onPressed: _pickAndVerifyImage,
          ),
        ),
      ],
    );
  }


  Widget _buildVerifyingState() {
    return Column(
      children: [
        const CircularProgressIndicator(color: Color(0xFF10B981)),
        const SizedBox(height: 24),
        Text(
          'Verifying Authenticity...',
          style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 8),
        Text(
          'Checking hardware signatures on-chain',
          style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF94A3B8)),
        ),
      ],
    );
  }

  Widget _buildResultView(Map<String, dynamic> result) {
    final bool isAuthentic = result['isAuthentic'] ?? false;
    final color = isAuthentic ? const Color(0xFF10B981) : const Color(0xFFEF4444);

    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withOpacity(0.5), width: 2),
      ),
      child: Column(
        children: [
          Icon(
            isAuthentic ? LucideIcons.checkCircle : LucideIcons.alertOctagon,
            size: 80,
            color: color,
          ),
          const SizedBox(height: 24),
          Text(
            isAuthentic ? 'Authentic Image' : 'Image Modified',
            style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(height: 32),
          if (isAuthentic) ...[
            _buildResultRow('Creator', result['creator'] ?? 'Unknown'),
            const SizedBox(height: 16),
            _buildResultRow('Time', result['timestamp'].toString().substring(0, 16).replaceFirst('T', ' ')),
            const SizedBox(height: 16),
            _buildResultRow('Source App', result['sourceApp'] ?? 'Unknown App'),
          ] else ...[
            Text(
              'Original signature invalid. Hash mismatch detected.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 16, color: const Color(0xFF94A3B8)),
            ),
          ],
          const SizedBox(height: 48),
          TextButton(
            onPressed: () {
              setState(() {
                _verificationResult = null;
              });
            },
            child: Text('Verify Another Image', style: GoogleFonts.inter(color: Colors.white)),
          )
        ],
      ),
    );
  }

  Widget _buildResultRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.inter(color: const Color(0xFF94A3B8))),
        Text(value, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
