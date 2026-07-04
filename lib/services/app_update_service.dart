import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../models/app_update_model.dart';
import '../widgets/update_dialog.dart';
import '../widgets/download_progress_dialog.dart';

class AppUpdateService {
  static bool _checked = false;

  /// Reset the check flag. Call this during development/testing only.
  static void resetForTesting() => _checked = false;

  static const String _apiUrl =
      'http://192.168.110.2/web_develop/landing-page/app_vcm/backend/?c=File&m=listApps&q=OTP';

  /// Call this once after the first frame is rendered.
  /// Shows an update dialog when a new version is available.
  /// On Android: dialog includes a download & install button.
  /// On iOS: dialog shows info only (no update button).
  static Future<void> check(BuildContext context) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    if (_checked) {
      debugPrint('[UPDATE] Already checked, skipping.');
      return;
    }
    _checked = true;

    try {
      // Get current app version
      final pkg = await PackageInfo.fromPlatform();
      final current = pkg.version;
      debugPrint('[UPDATE] Current version: $current');

      // Fetch latest version from API
      final model = await _fetchLatestVersion();
      if (model == null) {
        debugPrint('[UPDATE] No model returned from API.');
        return;
      }

      debugPrint('[UPDATE] Latest version: ${model.version}');

      final hasUpdate = _isNewerVersion(current, model.version);
      debugPrint('[UPDATE] Has update: $hasUpdate');
      if (!hasUpdate) return;

      debugPrint('[UPDATE] context.mounted = ${context.mounted}');
      if (!context.mounted) return;

      debugPrint('[UPDATE] Showing dialog...');
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => UpdateDialog(
          model: model,
          currentVersion: current,
          // iOS: pass null → no update button shown
          // Android: pass callback → shows download button
          onUpdate: Platform.isIOS
              ? null
              : () => _downloadAndInstall(context, model),
        ),
      );
      debugPrint('[UPDATE] showDialog called.');
    } catch (e) {
      debugPrint('[UPDATE] check error: $e');
    }
  }


  /// Fetch the latest app version info from the API.
  static Future<AppUpdateModel?> _fetchLatestVersion() async {
    try {
      final response = await http
          .get(Uri.parse(_apiUrl))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint('[UPDATE] API error: ${response.statusCode}');
        return null;
      }

      final List<dynamic> list = jsonDecode(response.body) as List<dynamic>;
      if (list.isEmpty) return null;

      return AppUpdateModel.fromJson(list.first as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[UPDATE] fetch error: $e');
      return null;
    }
  }

  /// Download the APK and open the installer.
  static Future<void> _downloadAndInstall(
    BuildContext context,
    AppUpdateModel model,
  ) async {
    final dio = Dio();
    final cancelToken = CancelToken();
    final tempDir = await getTemporaryDirectory();
    final savePath = '${tempDir.path}${Platform.pathSeparator}otp_update.apk';

    final progressNotifier = ValueNotifier<double>(0);

    if (!context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => DownloadProgressDialog(
        progress: progressNotifier,
        onCancel: () {
          cancelToken.cancel('user_cancelled');
          Navigator.of(context).pop();
        },
      ),
    );

    try {
      debugPrint('[UPDATE] Download started: ${model.url}');
      await dio.download(
        model.url,
        savePath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final pct = received / total;
            progressNotifier.value = pct;
            debugPrint('[UPDATE] Progress: ${(pct * 100).toStringAsFixed(0)}%');
          }
        },
        cancelToken: cancelToken,
      );

      progressNotifier.value = 1.0;
      debugPrint('[UPDATE] Download complete, launching installer...');

      if (!context.mounted) return;
      Navigator.of(context).pop(); // close progress dialog

      await OpenFilex.open(savePath);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        debugPrint('[UPDATE] Download cancelled by user');
      } else {
        debugPrint('[UPDATE] Download failed: ${e.message}');
        if (context.mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Tải xuống thất bại. Vui lòng thử lại.'),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[UPDATE] Unexpected error: $e');
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã xảy ra lỗi khi tải xuống.')),
        );
      }
    } finally {
      progressNotifier.dispose();
    }
  }

  /// Returns true if [latest] is strictly newer than [current].
  /// Compares version strings by splitting on '.' and comparing each segment.
  static bool _isNewerVersion(String current, String latest) {
    try {
      final cs = current.split('.').map((s) => int.tryParse(s) ?? 0).toList();
      final ls = latest.split('.').map((s) => int.tryParse(s) ?? 0).toList();
      final len = cs.length > ls.length ? cs.length : ls.length;
      for (var i = 0; i < len; i++) {
        final c = i < cs.length ? cs[i] : 0;
        final l = i < ls.length ? ls[i] : 0;
        if (c < l) return true;
        if (c > l) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
