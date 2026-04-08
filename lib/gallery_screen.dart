import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'crypto_engine.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  List<File> _savedImages = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadImages();
  }

  Future<void> _loadImages() async {
    setState(() => _isLoading = true);
    final images = await CryptoEngine.getSavedImages();
    if (mounted) {
      setState(() {
        _savedImages = images;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('TrueLens Secured Images', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadImages,
          ),
        ],
      ),
      backgroundColor: const Color(0xFF0F172A),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
          : _savedImages.isEmpty
              ? _buildEmptyState()
              : _buildImageList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.image, size: 64, color: const Color(0xFF94A3B8).withOpacity(0.5)),
          const SizedBox(height: 16),
          Text(
            'No secured images yet',
            style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Go to Camera tab and capture a verifiable photo',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildImageList() {
    return RefreshIndicator(
      onRefresh: _loadImages,
      color: const Color(0xFF10B981),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _savedImages.length,
        itemBuilder: (context, index) {
          final file = _savedImages[index];
          final fileName = file.path.split('/').last;
          final timestamp = file.lastModifiedSync();

          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF10B981).withOpacity(0.2)),
            ),
            child: Row(
              children: [
                // Real thumbnail from file
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                  ),
                  child: Image.file(
                    file,
                    width: 90,
                    height: 90,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 90,
                      height: 90,
                      color: const Color(0xFF0F172A),
                      child: const Icon(LucideIcons.image, color: Color(0xFF94A3B8)),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(LucideIcons.shieldCheck, color: Color(0xFF10B981), size: 16),
                          const SizedBox(width: 6),
                          Text(
                            'TrueLens Signed',
                            style: GoogleFonts.inter(
                              color: const Color(0xFF10B981),
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}',
                        style: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        fileName,
                        style: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 10),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(LucideIcons.chevronRight, color: Color(0xFF94A3B8)),
                const SizedBox(width: 16),
              ],
            ),
          );
        },
      ),
    );
  }
}
