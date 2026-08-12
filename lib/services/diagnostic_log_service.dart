import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class DiagnosticLogService {
  static File? _file;
  static Future<void>? _initializing;
  static const _maxBytes = 2 * 1024 * 1024;
  static const _nativeChannel = MethodChannel('com.screenanswer/float');

  static Future<void> initialize() {
    return _initializing ??= _initialize();
  }

  static Future<void> _initialize() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      _file = File('${directory.path}/diagnostic.log');
      if (await _file!.exists() && await _file!.length() > _maxBytes) {
        await _file!.writeAsString('');
      }
    } catch (error, stack) {
      debugPrint('[DiagnosticLog] initialize failed: $error\n$stack');
    }
  }

  static Future<void> write(String stage, Object error, [StackTrace? stack]) async {
    final file = _file;
    final line = '${DateTime.now().toIso8601String()} [${Zone.current}] '
        '[$stage] ${error.runtimeType}: $error'
        '${stack == null ? '' : '\n$stack'}\n';
    debugPrint('[DiagnosticLog] $line');
    if (file == null) return;
    try {
      await file.writeAsString(line, mode: FileMode.append, flush: true);
    } catch (writeError, writeStack) {
      debugPrint('[DiagnosticLog] write failed: $writeError\n$writeStack');
    }
  }

  /// 通过 MethodChannel 读取原生端 diagnostic-native.log 内容
  static Future<String> readNativeLog() async {
    try {
      final result = await _nativeChannel.invokeMethod<String>('readNativeLog');
      return result ?? '';
    } catch (error, stack) {
      debugPrint('[DiagnosticLog] readNativeLog failed: $error\n$stack');
      return '';
    }
  }

  static Future<String> read() async {
    await initialize();
    try {
      final flutterLog =
          _file != null && await _file!.exists() ? await _file!.readAsString() : '';
      final nativeLog = await readNativeLog();
      if (nativeLog.isEmpty) return flutterLog;
      if (flutterLog.isEmpty) return nativeLog;
      return '===== 原生日志 (diagnostic-native.log) =====\n$nativeLog\n\n'
          '===== Flutter 日志 (diagnostic.log) =====\n$flutterLog';
    } catch (error, stack) {
      await write('read-log', error, stack);
      return '';
    }
  }

  static Future<String> get path async {
    await initialize();
    return _file?.path ?? '日志路径不可用';
  }
}
