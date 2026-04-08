import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:device_info_plus/device_info_plus.dart';

class CryptoEngine {
  // Note: For physical devices, change this to your computer's IP address
  static const String apiBaseUrl = 'http://10.97.123.247:3000';

  // Hits /api/embed on the Node processor to secure an image
  static Future<Map<String, dynamic>> secureRawImage(Uint8List rawBytes) async {
    try {
      // 1. Locally compute hash
      final digest = sha256.convert(rawBytes);
      final hashHex = digest.toString();

      // 2. Mock a local signature
      final fakeSignature = base64Encode(utf8.encode('mock_signature_$hashHex'));
      const fakePublicKey = '-----BEGIN PUBLIC KEY-----\nMOCK\n-----END PUBLIC KEY-----';

      // 3. Fetch real device info
      String deviceName = 'Unknown TrueLens Device';
      try {
        final deviceInfo = DeviceInfoPlugin();
        if (Platform.isAndroid) {
          final androidInfo = await deviceInfo.androidInfo;
          // E.g. "motorola moto g64 5g"
          deviceName = '${androidInfo.manufacturer} ${androidInfo.model}';
        } else if (Platform.isIOS) {
          final iosInfo = await deviceInfo.iosInfo;
          deviceName = iosInfo.utsname.machine;
        }
      } catch (e) {
        debugPrint('Failed to get device info: $e');
      }

      // 4. Post to Node Backend
      var uri = Uri.parse('$apiBaseUrl/api/embed');
      var request = http.MultipartRequest('POST', uri)
        ..fields['image_hash'] = hashHex
        ..fields['signature'] = fakeSignature
        ..fields['public_key'] = fakePublicKey
        ..fields['timestamp'] = DateTime.now().toIso8601String()
        ..fields['device'] = deviceName
        ..files.add(http.MultipartFile.fromBytes('image', rawBytes, filename: 'capture.jpg'));

      var response = await request.send();

      if (response.statusCode == 200) {
        // Server returns the signed JPEG bytes
        final signedBytes = await response.stream.toBytes();
        final fileName = 'truelens_${DateTime.now().millisecondsSinceEpoch}.jpg';

        // 1. Save to internal app folder (for in-app picker)
        final savedPath = await _saveToAppDocuments(signedBytes, fileName);
        debugPrint('TrueLens: Saved internally to: $savedPath');

        // 2. Also save to public Gallery using gal (MediaStore) so it's editable
        try {
          await Gal.putImageBytes(signedBytes, name: fileName, album: 'TrueLens');
          debugPrint('TrueLens: Saved to public Gallery/TrueLens album');
        } catch (galErr) {
          debugPrint('TrueLens: Gallery save skipped: $galErr');
        }

        return {
          'hash': hashHex,
          'signature': '${fakeSignature.substring(0, 30)}...',
          'certificate': 'device-attestation-cert-v2',
          'isAuthentic': true,
          'securedAt': DateTime.now().toIso8601String(),
          'savedAs': fileName,
          'savedPath': savedPath,
        };
      } else {
        throw Exception('Server failed to embed manifest. Code: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('secureRawImage error: $e');
      throw Exception('Network or Server Error: $e');
    }
  }

  // Save image to the public Pictures/TrueLens folder (visible in Gallery app)
  static Future<String> _saveToAppDocuments(Uint8List bytes, String fileName) async {
    // getExternalStorageDirectories gives us the public Pictures folder on Android
    final dirs = await getExternalStorageDirectories(type: StorageDirectory.pictures);
    final Directory baseDir;
    if (dirs != null && dirs.isNotEmpty) {
      baseDir = dirs.first;
    } else {
      // Fallback: app documents directory
      baseDir = await getApplicationDocumentsDirectory();
    }

    final trueLensDir = Directory('${baseDir.path}/TrueLens');
    if (!trueLensDir.existsSync()) {
      trueLensDir.createSync(recursive: true);
    }
    final file = File('${trueLensDir.path}/$fileName');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  // Hits /api/verify to check the signed JPEG
  static Future<Map<String, dynamic>> verifyImage(Uint8List imageBytes) async {
    try {
      var uri = Uri.parse('$apiBaseUrl/api/verify');
      var request = http.MultipartRequest('POST', uri)
        ..files.add(http.MultipartFile.fromBytes('image', imageBytes, filename: 'verify.jpg'));

      var response = await request.send();
      var responseBody = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        var json = jsonDecode(responseBody);

        // Map backend STATUS string to our UI's boolean expectation
        bool authentic = json['status'] == 'AUTHENTIC';

        return {
          'isAuthentic': authentic,
          'creator': json['manifest']?['device'] ?? 'Unknown Source',
          'timestamp': json['manifest']?['timestamp'] ?? DateTime.now().toIso8601String(),
          'sourceApp': 'TrueLens ${json['manifest']?['algorithm'] ?? ''}',
        };
      } else {
        throw Exception('Verification endpoint failed.');
      }
    } catch (e) {
      debugPrint('verifyImage error: $e');
      throw Exception('Verification failed due to error: $e');
    }
  }

  // Returns list of all saved TrueLens signed images
  static Future<List<File>> getSavedImages() async {
    try {
      // Must use the SAME base dir as _saveToAppDocuments
      final dirs = await getExternalStorageDirectories(type: StorageDirectory.pictures);
      final Directory baseDir;
      if (dirs != null && dirs.isNotEmpty) {
        baseDir = dirs.first;
      } else {
        baseDir = await getApplicationDocumentsDirectory();
      }
      final trueLensDir = Directory('${baseDir.path}/TrueLens');
      if (!trueLensDir.existsSync()) return [];

      return trueLensDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.jpg'))
          .toList()
          ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    } catch (e) {
      debugPrint('getSavedImages error: $e');
      return [];
    }
  }
}
