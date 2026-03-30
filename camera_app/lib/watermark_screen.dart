import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:image_picker/image_picker.dart';

class WatermarkScreen extends StatefulWidget {
  const WatermarkScreen({super.key});

  @override
  State<WatermarkScreen> createState() => _WatermarkScreenState();
}

class _WatermarkScreenState extends State<WatermarkScreen> {
  bool _isRecovering = false;
  Map<String, dynamic>? _recoveryResult;

  Future<void> _pickAndRecoverWatermark() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      setState(() {
        _isRecovering = true;
        _recoveryResult = null;
      });

      // Simulate the invisible watermark extraction process
      await Future.delayed(const Duration(seconds: 3));

      if (!mounted) return;

      setState(() {
        _isRecovering = false;
        // Mocking a successful recovery
        _recoveryResult = {
          'creator': 'TrueLens User 0x7F...9A4B',
          'link': 'https://truelens.network/verify/7f9a4b82',
        };
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
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_recoveryResult == null && !_isRecovering)
                _buildUploadPrompt(),
              if (_isRecovering)
                _buildRecoveringState(),
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
          'Upload a screenshot of a TrueLens image to decode its invisible watermark and find the original creator.',
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
            label: Text('Upload Screenshot', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold)),
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
          'Extracting Watermark...',
          style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 8),
        Text(
          'Analyzing pixel modifications in frequency domain',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF94A3B8)),
        ),
      ],
    );
  }

  Widget _buildResultView(Map<String, dynamic> result) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.5), width: 2),
      ),
      child: Column(
        children: [
          const Icon(
            LucideIcons.zap,
            size: 80,
            color: Color(0xFF3B82F6),
          ),
          const SizedBox(height: 24),
          Text(
            'Recovered Identity',
            style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, color: const Color(0xFF3B82F6)),
          ),
          const SizedBox(height: 16),
          Text(
            'from invisible watermark',
            style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 32),
          _buildResultRow('Original Creator', result['creator'] ?? 'Unknown'),
          const SizedBox(height: 16),
          _buildResultRow('Original Record', 'Tap to view on explorer', isLink: true),
          const SizedBox(height: 48),
          TextButton(
            onPressed: () {
              setState(() {
                _recoveryResult = null;
              });
            },
            child: Text('Scan Another Image', style: GoogleFonts.inter(color: Colors.white)),
          )
        ],
      ),
    );
  }

  Widget _buildResultRow(String label, String value, {bool isLink = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 12)),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.inter(
            color: isLink ? const Color(0xFF3B82F6) : Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 16,
            decoration: isLink ? TextDecoration.underline : TextDecoration.none,
          ),
        ),
      ],
    );
  }
}
