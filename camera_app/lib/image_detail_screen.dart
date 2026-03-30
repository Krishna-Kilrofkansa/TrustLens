import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

class ImageDetailScreen extends StatelessWidget {
  final Map<String, dynamic> data;

  const ImageDetailScreen({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final bool isAuthentic = data['isAuthentic'] ?? false;
    final colorContext = isAuthentic ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final statusText = isAuthentic ? 'Verified Authentic' : 'Tampered';

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: Text('Image Detail', style: GoogleFonts.inter()),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Image Preview (Placeholder for real images)
            Container(
              width: double.infinity,
              height: 300,
              color: const Color(0xFF1E293B),
              child: const Center(
                child: Icon(LucideIcons.image, size: 64, color: Color(0xFF94A3B8)),
              ),
            ),
            
            // Details Section
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: colorContext.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colorContext.withOpacity(0.5)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(isAuthentic ? LucideIcons.checkCircle : LucideIcons.alertCircle, color: colorContext),
                        const SizedBox(width: 8),
                        Text(
                          statusText,
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: colorContext,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Metadata Section
                  _buildDataRow('Captured by:', 'TrueLens Authenticator Device #9214'),
                  const SizedBox(height: 12),
                  _buildDataRow('Time:', data['securedAt'] ?? 'Unknown'),
                  const SizedBox(height: 12),
                  _buildDataRow('Location:', '37.7749° N, 122.4194° W'),

                  const SizedBox(height: 32),
                  const Divider(color: Color(0xFF1E293B)),
                  const SizedBox(height: 24),

                  // Integrity Status
                  Text(
                    'Integrity Status',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: const Color(0xFF94A3B8),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isAuthentic ? 'No modifications detected' : 'Warning: Signature mismatch/Tampered data',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Expandable Crypto Details
                  Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      iconColor: const Color(0xFF10B981),
                      collapsedIconColor: const Color(0xFF94A3B8),
                      title: Text(
                        'View Cryptographic Details',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF10B981),
                        ),
                      ),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildCryptoRow('Hash (SHA-256)', data['hash'] ?? 'N/A'),
                              const SizedBox(height: 16),
                              _buildCryptoRow('Signature', '304402206bf23ab65db988fb1c6204cbf92bdc2e... (RSA-4096)'),
                              const SizedBox(height: 16),
                              _buildCryptoRow('Certificate', 'device-attestation-cert-v2 (Hardware Backed)'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 14,
            color: const Color(0xFF94A3B8),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 16,
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildCryptoRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            color: const Color(0xFF94A3B8),
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            value,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 12,
              color: const Color(0xFF10B981),
            ),
            softWrap: true,
          ),
        ),
      ],
    );
  }
}
