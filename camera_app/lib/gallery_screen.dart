import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'image_detail_screen.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  // Mock data to make the app feel real
  final List<Map<String, dynamic>> _historyData = [
    {
      'id': '1',
      'imageUrl': 'assets/mock1.jpg',
      'isAuthentic': true,
      'securedAt': DateTime.now().subtract(const Duration(hours: 2)).toIso8601String(),
      'hash': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    },
    {
      'id': '2',
      'imageUrl': 'assets/mock2.jpg',
      'isAuthentic': true,
      'securedAt': DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
      'hash': '8f434346648f6b96df89dda901c5176b10a6d83961dd3c1ac88b59b2dc327aa4',
    },
    {
      'id': '3',
      'imageUrl': 'assets/mock3.jpg',
      'isAuthentic': false,
      'securedAt': DateTime.now().subtract(const Duration(days: 3)).toIso8601String(),
      'hash': 'tampered_hash_signature_mismatch',
    }
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'History',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
      ),
      backgroundColor: const Color(0xFF0F172A),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _historyData.length,
        itemBuilder: (context, index) {
          final item = _historyData[index];
          final bool isAuthentic = item['isAuthentic'];
          
          return GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ImageDetailScreen(data: item),
                ),
              );
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isAuthentic 
                      ? const Color(0xFF10B981).withOpacity(0.2)
                      : const Color(0xFFEF4444).withOpacity(0.2),
                ),
              ),
              child: Row(
                children: [
                  // Thumbnail (Mocked with colored box since we have no assets)
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        bottomLeft: Radius.circular(16),
                      ),
                    ),
                    child: Icon(
                      LucideIcons.image,
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                  const SizedBox(width: 16),
                  
                  // Details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isAuthentic ? LucideIcons.shieldCheck : LucideIcons.alertTriangle,
                              color: isAuthentic ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isAuthentic ? 'Verified' : 'Tampered',
                              style: GoogleFonts.inter(
                                color: isAuthentic ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          item['securedAt'].toString().split('T').join(' ').substring(0, 16),
                          style: GoogleFonts.inter(
                            color: const Color(0xFF94A3B8),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    LucideIcons.chevronRight,
                    color: Color(0xFF94A3B8),
                  ),
                  const SizedBox(width: 16),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
