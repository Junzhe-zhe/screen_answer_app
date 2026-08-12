import 'package:flutter/services.dart';

/// 将 Flutter 设置页的参数推送到原生 FloatService，实现运行时实时生效。
class FloatSettingsService {
  static const _channel = MethodChannel('com.screenanswer/float');

  /// 同步悬浮球大小、边框粗细、默认锁定面板到原生悬浮窗。
  ///
  /// [ballSize] 悬浮球直径（dp），范围 5-80。
  /// [borderWidth] 选区边框粗细（dp），范围 1-10。
  /// [defaultLock] 是否默认锁定答案面板。
  static Future<bool> applySettings({
    required int ballSize,
    required double borderWidth,
    required bool defaultLock,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('applySettings', {
        'ballSize': ballSize,
        'borderWidth': borderWidth,
        'defaultLock': defaultLock,
      });
      return result ?? false;
    } on MissingPluginException {
      // 原生未注册通道（如 Web 平台），静默返回 false
      return false;
    } catch (e) {
      // 设置应用失败不阻塞 UI，下次启动时自动从 SharedPreferences 加载
      return false;
    }
  }
}
