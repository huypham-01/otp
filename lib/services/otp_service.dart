import 'dart:typed_data';
import 'package:crypto/crypto.dart';

class OtpService {
  static const int timeStep = 30;
  static const int digits = 6;
  static const String algo = 'sha1';

  static Uint8List uuidToKey(String uuid) {
    try {
      final hex = uuid.replaceAll('-', '');
      final bytes = <int>[];
      for (int i = 0; i < hex.length; i += 2) {
        bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
      }
      return Uint8List.fromList(bytes);
    } catch (e) {
      print('⚠️ UUID parse error: $e');
      return Uint8List.fromList(List.filled(16, 0));
    }
  }

  static Uint8List packCounterBE(int counter) {
    final data = ByteData(8);
    data.setUint32(0, (counter >> 32) & 0xFFFFFFFF);
    data.setUint32(4, counter & 0xFFFFFFFF);
    return data.buffer.asUint8List();
  }

  static String generateOtpFromUuid(
    String uuid,
    int timestamp, {
    int step = timeStep,
    int codeDigits = digits,
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

      final otp = (binary % _pow10(codeDigits)).toString().padLeft(codeDigits, '0');
      return otp;
    } catch (e) {
      print('❌ OTP generation error: $e');
      return '000000'.padLeft(codeDigits, '0');
    }
  }

  static int _pow10(int n) => List.generate(n, (_) => 10).reduce((a, b) => a * b);
}
