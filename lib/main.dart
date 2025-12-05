import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';
import 'package:app_links/app_links.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(
    const MaterialApp(debugShowCheckedModeBanner: false, home: OtpLiveWidget()),
  );
}

class OtpLiveWidget extends StatefulWidget {
  const OtpLiveWidget({super.key});

  @override
  State<OtpLiveWidget> createState() => _OtpLiveWidgetState();
}

class _OtpLiveWidgetState extends State<OtpLiveWidget> {
  static const int timeStep = 30;
  static const int digits = 6;
  static const String algo = 'sha1';

  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  String? _uuid;
  String _status = 'Đang khởi tạo...';

  Timer? _timer;
  int? now;
  String? otpPrev, otpCurr, otpNext;
  int? secondsLeft;

  @override
  void initState() {
    super.initState();
    _initDeepLink();

    // ✅ Dòng này cho phép test nếu chưa có deep link
    // _uuid = '123e4567-e89b-12d3-a456-426614174000';
    // _startOtpTimer();
  }

  Future<void> _initDeepLink() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUuid = prefs.getString('saved_uuid');
      if (savedUuid != null && savedUuid.isNotEmpty) {
        setState(() {
          _uuid = savedUuid;
          _status = 'Đã load UUID từ lưu trữ: $savedUuid';
        });
        print('📂 Loaded saved UUID: $savedUuid');
        _startOtpTimer();
      }

      print('🔄 Khởi tạo deep link listener...');
      _sub = _appLinks.uriLinkStream.listen(
        (Uri uri) {
          print('📡 Nhận stream URI: $uri');
          _handleUri(uri);
        },
        onError: (err) {
          print('❌ Stream error: $err');
          setState(() => _status = 'Lỗi stream: $err');
        },
      );

      final initialUri = await _appLinks.getInitialLink();
      print('🔍 Initial URI: $initialUri');
      if (initialUri != null) {
        await _handleUri(initialUri);
      } else {
        print('ℹ️ Không có initial link');
      }
    } catch (e) {
      print('💥 Deep link error: $e');
      setState(() => _status = 'Lỗi init: $e');
    }
  }

  Future<void> _handleUri(Uri uri) async {
    print('🔗 Xử lý URI đầy đủ: $uri');
    print('📍 Path: ${uri.path}');
    print('🏠 Host: ${uri.host}');
    print('🔑 Query params: ${uri.queryParameters}');

    // Xử lý theo host cụ thể
    if (uri.host == 'verify') {
      // Code xử lý verify như cũ: Lấy UUID, lưu prefs, start timer, delay 5s rồi launch back
      final uuid = uri.queryParameters['uuid'];
      print('✅ UUID extract: $uuid');
      print('🕐 Chuẩn bị quay lại app chính sau 5s...');
      Future.delayed(const Duration(seconds: 5), () async {
        try {
          print('🚀 Gửi intent myapp://change_password');
          await launchUrl(
            Uri.parse('myapp://change_password'),
            mode: LaunchMode.externalNonBrowserApplication,
          );
          print('✅ Đã gửi intent');
        } catch (e) {
          print('❌ Lỗi khi gửi intent: $e');
        }
      });

      if (uuid != null && uuid.isNotEmpty) {
        setState(() {
          _uuid = uuid;
          _status = 'Đã xử lý thành công!';
        });
        print('🎉 Set state UUID: $uuid');

        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('saved_uuid', uuid);
          print('💾 Đã lưu UUID vào SharedPreferences: $uuid');
          setState(() => _status += ' (Đã lưu vào bộ nhớ)');
        } catch (e) {
          print('❌ Lỗi lưu SharedPreferences: $e');
          setState(() => _status += ' (Lưu thất bại: $e)');
        }

        _startOtpTimer();
      } else {
        print('❌ UUID không hợp lệ trong URI: $uri');
        setState(() => _status = 'UUID thiếu hoặc rỗng');
      }
    } else if (uri.host == 'generate') {
      // Xử lý generate: Lấy UUID từ prefs, sinh OTP hiện tại, gửi back app chính
      final prefs = await SharedPreferences.getInstance();
      final savedUuid = prefs.getString('saved_uuid');
      if (savedUuid == null || savedUuid.isEmpty) {
        print('❌ Không có UUID lưu sẵn cho generate');
        setState(
          () => _status = 'Chưa có UUID để generate OTP (chạy verify trước?)',
        );
        return;
      }

      setState(() {
        _status = 'Đã generate OTP: $otpCurr';
        _uuid = savedUuid; // Đảm bảo _uuid set để UI update nếu cần
      });

      print('✅ OTP generated: $otpCurr từ UUID: $savedUuid');

      // Delay 1s rồi gửi back app chính kèm OTP
      await Future.delayed(const Duration(seconds: 2));
      final backUri = Uri.parse('myapp://login?otp=$otpCurr');
      try {
        await launchUrl(
          backUri,
          mode: LaunchMode.externalNonBrowserApplication,
        );
        print('🚀 Đã gửi OTP quay lại app chính: $otpCurr');
      } catch (e) {
        print('❌ Lỗi gửi back: $e');
        setState(() => _status += ' (Gửi OTP thất bại: $e)');
      }
    } else {
      // Host không hỗ trợ
      print('⚠️ Host không hỗ trợ: ${uri.host}');
      setState(() => _status = 'Host sai: ${uri.host}');
    }
  }

  void _startOtpTimer() {
    _timer?.cancel(); // ✅ An toàn
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
      final counter = now! ~/ timeStep;

      final prevTs = (counter - 1) * timeStep;
      final currTs = counter * timeStep;
      final nextTs = (counter + 1) * timeStep;

      otpPrev = generateOtpFromUuid(_uuid!, prevTs);
      otpCurr = generateOtpFromUuid(_uuid!, currTs);
      otpNext = generateOtpFromUuid(_uuid!, nextTs);

      final secondsIntoStep = now! % timeStep;
      secondsLeft = timeStep - secondsIntoStep;
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel(); // ✅ An toàn
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(
        0xFFF5F5F5,
      ), // Light background for modern feel
      body: _uuid != null
          ? Padding(
              padding: const EdgeInsets.all(15.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 40), // Space from top
                  // Logo and title centered at the top
                  Column(
                    children: [
                      Image.asset(
                        'assets/images/logo.png', // Replace with your logo asset path
                        height: 120,
                        width: 120,
                      ),
                      const SizedBox(height: 40),
                      const Text(
                        'OTP',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                  ),

                  // Main OTP display - large and prominent
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(32.0),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // OTP code with separated digits for better UX
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
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(
                                              0xFF2196F3,
                                            ).withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Text(
                                            digit,
                                            style: const TextStyle(
                                              fontSize: 26,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF2196F3),
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList()
                                : [
                                    Container(
                                      width: 200,
                                      height: 50,
                                      decoration: BoxDecoration(
                                        color: Colors.grey[300],
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Center(
                                        child: Text(
                                          '000000',
                                          style: TextStyle(
                                            fontSize: 36,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                          ),
                          const SizedBox(height: 16),
                          // Countdown timer
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4CAF50).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.access_time,
                                  size: 16,
                                  color: Color(0xFF4CAF50),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Remaining: $secondsLeft seconds',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF4CAF50),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                'A new code will be generated after 30 seconds',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            )
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/images/logo.png',
                      height: 80,
                      width: 80,
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'OTP Internal App',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'This application only works when it is opened from the main app via a deep link.\n\n'
                      'Please use the test deep link to perform the verification.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    // const SizedBox(height: 30),
                    // ElevatedButton(
                    //   onPressed: () {
                    //     _handleUri(
                    //       Uri.parse(
                    //         'myotp://verify?uuid=123e4567-e89b-12d3-a456-426614174000',
                    //       ),
                    //     );
                    //   },
                    //   child: const Text('Test OTP for Apple'),
                    // ),
                  ],
                ),
              ),
            ),
    );
  }

  // ========================
  // === OTP FUNCTIONS ===
  // ========================

  Uint8List uuidToKey(String uuid) {
    try {
      final hex = uuid.replaceAll('-', '');
      final bytes = <int>[];
      for (int i = 0; i < hex.length; i += 2) {
        bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
      }
      return Uint8List.fromList(bytes);
    } catch (e) {
      print('⚠️ Lỗi khi parse UUID: $e');
      return Uint8List.fromList(List.filled(16, 0));
    }
  }

  Uint8List packCounterBE(int counter) {
    final data = ByteData(8);
    data.setUint32(0, (counter >> 32) & 0xFFFFFFFF);
    data.setUint32(4, counter & 0xFFFFFFFF);
    return data.buffer.asUint8List();
  }

  String generateOtpFromUuid(
    String uuid,
    int timestamp, {
    int step = timeStep,
    int digits = digits,
    String algorithm = algo,
  }) {
    try {
      final key = uuidToKey(uuid);
      final counter = timestamp ~/ step;
      final counterBytes = packCounterBE(counter);

      Hmac hmac;
      switch (algorithm.toLowerCase()) {
        case 'sha256':
          hmac = Hmac(sha256, key);
          break;
        case 'sha512':
          hmac = Hmac(sha512, key);
          break;
        default:
          hmac = Hmac(sha1, key);
      }

      final digest = hmac.convert(counterBytes).bytes;
      final offset = digest.last & 0x0f;

      final binary =
          ((digest[offset] & 0x7f) << 24) |
          ((digest[offset + 1] & 0xff) << 16) |
          ((digest[offset + 2] & 0xff) << 8) |
          (digest[offset + 3] & 0xff);

      final otp = (binary % pow10(digits)).toString().padLeft(digits, '0');
      return otp;
    } catch (e) {
      print('❌ Lỗi sinh OTP: $e');
      return '000000';
    }
  }

  int pow10(int n) => List.generate(n, (_) => 10).reduce((a, b) => a * b);
}
