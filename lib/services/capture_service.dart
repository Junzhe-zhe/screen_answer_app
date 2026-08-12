import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../utils/constants.dart';
import 'diagnostic_log_service.dart';

/// Platform Channel - 截图服务
class CaptureService {
  static const _channel = MethodChannel(AppConstants.captureChannel);

  /// 请求截图权限（MediaProjection）
  static Future<bool> requestPermission() async {
    try {
      final result = await _channel.invokeMethod('requestPermission');
      return result == true;
    } on PlatformException catch (e, stack) {
      debugPrint('CaptureService.requestPermission error: ${e.message}');
      unawaited(DiagnosticLogService.write('capture-request-permission', e, stack));
      return false;
    } catch (e, stack) {
      debugPrint('CaptureService.requestPermission unexpected: $e');
      unawaited(DiagnosticLogService.write('capture-request-permission', e, stack));
      return false;
    }
  }

  /// 检查截图权限是否已授权
  static Future<bool> isPermissionGranted() async {
    try {
      return await _channel.invokeMethod('isPermissionGranted') == true;
    } on PlatformException catch (e, stack) {
      debugPrint('CaptureService.isPermissionGranted error: ${e.message}');
      unawaited(DiagnosticLogService.write('capture-is-permission-granted', e, stack));
      return false;
    } catch (e, stack) {
      debugPrint('CaptureService.isPermissionGranted unexpected: $e');
      unawaited(DiagnosticLogService.write('capture-is-permission-granted', e, stack));
      return false;
    }
  }
}
