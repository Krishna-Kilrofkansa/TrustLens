import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'camera_screen.dart';
import 'gallery_screen.dart';
import 'verify_screen.dart';
import 'watermark_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TrueLensApp());
}

class TrueLensApp extends StatelessWidget {
  const TrueLensApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TrueLens',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF10B981), // Green for verified
          secondary: Color(0xFF1E293B),
          surface: Color(0xFF1E293B),
          error: Color(0xFFEF4444),
        ),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
        useMaterial3: true,
      ),
      home: const MainNavigation(),
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const CameraScreen(),
    const VerificationScreen(),
    const WatermarkScreen(),
    const GalleryScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        backgroundColor: const Color(0xFF0F172A),
        indicatorColor: const Color(0xFF10B981).withOpacity(0.2),
        destinations: const [
          NavigationDestination(
            icon: Icon(LucideIcons.camera),
            label: 'Capture',
          ),
          NavigationDestination(
            icon: Icon(LucideIcons.checkSquare),
            label: 'Verify',
          ),
          NavigationDestination(
            icon: Icon(LucideIcons.droplets),
            label: 'Recover',
          ),
          NavigationDestination(
            icon: Icon(LucideIcons.image),
            label: 'History',
          ),
        ],
      ),
    );
  }
}
