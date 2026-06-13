import 'dart:async';
import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/otp_service.dart';
import '../services/api_service.dart';
import 'scanner_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  String? _uuid;
  String _status = 'Initializing...';
  String? _fullname;

  Timer? _timer;
  int? now;
  String? otpCurr;
  int? secondsLeft;

  @override
  void initState() {
    super.initState();
    _initDeepLink();
  }

  Future<void> _initDeepLink() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUuid = prefs.getString('saved_uuid');
      if (savedUuid != null && savedUuid.isNotEmpty) {
        _setUuidAndStartTimer(savedUuid, 'Loaded UUID from storage: $savedUuid');
      }

      print('🔄 Initializing deep link listener...');
      _sub = _appLinks.uriLinkStream.listen(
        (Uri uri) {
          print('📡 Received stream URI: $uri');
          _handleUri(uri);
        },
        onError: (err) {
          print('❌ Stream error: $err');
          setState(() => _status = 'Stream error: $err');
        },
      );

      final initialUri = await _appLinks.getInitialLink();
      print('🔍 Initial URI: $initialUri');
      if (initialUri != null) {
        await _handleUri(initialUri);
      }
    } catch (e) {
      print('💥 Deep link error: $e');
      setState(() => _status = 'Init error: $e');
    }
  }

  void _setUuidAndStartTimer(String uuid, String statusMsg) {
    setState(() {
      _uuid = uuid;
      _status = statusMsg;
    });
    _startOtpTimer();
    _fetchUserInfo(uuid);
  }

  Future<void> _fetchUserInfo(String uuid) async {
    final name = await ApiService.fetchUserFullName(uuid);
    if (name != null) {
      if (mounted) {
        setState(() {
          _fullname = name;
        });
      }
    }
  }

  Future<void> _handleUri(Uri uri) async {
    print('🔗 Full URI processing: $uri');

    if (uri.host == 'verify') {
      final uuid = uri.queryParameters['uuid'];
      Future.delayed(const Duration(seconds: 5), () async {
        try {
          await launchUrl(
            Uri.parse('myapp://change_password'),
            mode: LaunchMode.externalNonBrowserApplication,
          );
        } catch (e) {
          print('❌ Intent send error: $e');
        }
      });

      if (uuid != null && uuid.isNotEmpty) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('saved_uuid', uuid);
        } catch (e) {
          print('❌ SharedPreferences save error: $e');
        }
        _setUuidAndStartTimer(uuid, 'Processed successfully!');
      } else {
        setState(() => _status = 'UUID missing or empty');
      }
    } else if (uri.host == 'generate') {
      final prefs = await SharedPreferences.getInstance();
      final savedUuid = prefs.getString('saved_uuid');
      if (savedUuid == null || savedUuid.isEmpty) {
        setState(
          () => _status = 'No UUID to generate OTP (run verify first?)',
        );
        return;
      }

      setState(() {
        _status = 'OTP generated: $otpCurr';
        _uuid = savedUuid;
      });

      await Future.delayed(const Duration(seconds: 2));
      final backUri = Uri.parse('myapp://login?otp=$otpCurr');
      try {
        await launchUrl(
          backUri,
          mode: LaunchMode.externalNonBrowserApplication,
        );
      } catch (e) {
        print('❌ Send back error: $e');
        setState(() => _status += ' (OTP send failed: $e)');
      }
    } else {
      setState(() => _status = 'Invalid host: ${uri.host}');
    }
  }

  void _startOtpTimer() {
    _timer?.cancel();
    if (_uuid == null) return;

    _updateOtp();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _updateOtp();
    });
  }

  void _updateOtp() {
    if (_uuid == null) return;

    setState(() {
      now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final counter = now! ~/ OtpService.timeStep;
      final currTs = counter * OtpService.timeStep;

      otpCurr = OtpService.generateOtpFromUuid(_uuid!, currTs);

      final secondsIntoStep = now! % OtpService.timeStep;
      secondsLeft = OtpService.timeStep - secondsIntoStep;
    });
  }

  Future<void> _scanQRCode() async {
    final scannedCode = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const ScannerScreen()),
    );

    if (scannedCode != null && scannedCode.isNotEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('saved_uuid', scannedCode);
      } catch (e) {
        print('SharedPreferences save error: $e');
      }
      _setUuidAndStartTimer(scannedCode, 'UUID scanned successfully');
    }
  }

  void _showAccountInfo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text(
                'Account Information',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 24),
              if (_fullname != null) ...[
                CircleAvatar(
                  radius: 36,
                  backgroundColor: Colors.blueAccent.withOpacity(0.1),
                  child: const Icon(
                    Icons.person,
                    size: 40,
                    color: Colors.blueAccent,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _fullname!,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: QrImageView(
                    data: _fullname!,
                    version: QrVersions.auto,
                    size: 180.0,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Color(0xFF0F172A),
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ),

                const SizedBox(height: 24),
              ] else ...[
                const Padding(
                  padding: EdgeInsets.all(32.0),
                  child: CircularProgressIndicator(),
                ),
                const Text(
                  'Fetching information...',
                  style: TextStyle(color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 24),
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: _uuid != null
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.person, color: Colors.blueAccent),
                    ),
                    onPressed: () => _showAccountInfo(context),
                  ),
                ),
              ],
            )
          : null,
      body: _uuid != null ? _buildOtpScreen() : _buildWelcomeScreen(),
    );
  }

  Widget _buildWelcomeScreen() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.blueAccent.withOpacity(0.15),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Image.asset(
                'assets/images/logo.png',
                height: 80,
                width: 80,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.security,
                  size: 80,
                  color: Colors.blueAccent,
                ),
              ),
            ),
            const SizedBox(height: 40),
            const Text(
              'OTP Authenticator',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Secure your account with a one-time authentication code. Scan the QR code to begin.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: Color(0xFF64748B),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 48),
            ElevatedButton(
              onPressed: _scanQRCode,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.qr_code_scanner, size: 24),
                  SizedBox(width: 12),
                  Text(
                    'Scan QR Code',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOtpScreen() {
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Logo Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blueAccent.withOpacity(0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Image.asset(
                  'assets/images/logo.png',
                  height: 60,
                  width: 60,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.security,
                    size: 60,
                    color: Colors.blueAccent,
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Title
              const Text(
                'OTP Authentication Code',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Use this code to login to the system',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 40),

              // OTP Digits Card
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12.0,
                  vertical: 40.0,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: otpCurr != null
                          ? otpCurr!
                                .split('')
                                .map(
                                  (digit) => Container(
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    width: 38,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: const Color(0xFFE2E8F0),
                                        width: 1,
                                      ),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      digit,
                                      style: const TextStyle(
                                        fontSize: 26,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                  ),
                                )
                                .toList()
                          : List.generate(
                              6,
                              (index) => Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                width: 38,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                alignment: Alignment.center,
                                child: const Text(
                                  '-',
                                  style: TextStyle(
                                    fontSize: 28,
                                    color: Color(0xFF94A3B8),
                                  ),
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(height: 40),

                    // Timer Progress
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 80,
                          height: 80,
                          child: CircularProgressIndicator(
                            value: secondsLeft != null
                                ? secondsLeft! / OtpService.timeStep
                                : 0,
                            strokeWidth: 6,
                            backgroundColor: const Color(0xFFF1F5F9),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              secondsLeft != null && secondsLeft! <= 10
                                  ? const Color(0xFFEF4444)
                                  : Colors.blueAccent,
                            ),
                          ),
                        ),
                        Text(
                          '${secondsLeft ?? 0}s',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: secondsLeft != null && secondsLeft! <= 10
                                ? const Color(0xFFEF4444)
                                : Colors.blueAccent,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
