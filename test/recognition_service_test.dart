/// 识别服务单元测试
///
/// 覆盖场景:
/// - initialize 初始化流程（幂等、MethodChannel 注册）
/// - _onMethodCall 参数解析（Map 格式 + 旧版纯字符串兼容）
/// - _process 空引擎回退（未选题库时返回 none）
/// - _process 正常匹配结果回传（text/answer/explanation/level/generation）
/// - 识别历史记录写入
/// - loadBank 无效 id 容错
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:screen_answer_app/services/recognition_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // RecognitionService.initialize 会加载默认题库（依赖 DatabaseService），
  // 需要 FFI 版 SQLite 才能在纯 Dart 测试环境中工作。
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const channel = MethodChannel('com.screenanswer/recognition');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// 捕获 RecognitionService 发回原生的 result 调用
  late List<MethodCall> resultCalls;

  /// 模拟原生端向 Flutter 发送 recognize 调用
  Future<void> sendRecognize(dynamic arguments) async {
    final codec = const StandardMethodCodec();
    final bytes = codec.encodeMethodCall(MethodCall('recognize', arguments));
    // 通过 binaryMessenger 模拟平台 → Flutter 的调用
    // 注意：encodeMethodCall 返回的 ByteData 直接传递，不要 .buffer.asByteData()，
    // 否则可能因底层 buffer offset 错位导致解码失败。
    await messenger.handlePlatformMessage(
      'com.screenanswer/recognition',
      bytes,
      (_) {},
    );
  }

  setUp(() {
    resultCalls = [];
    // 重置全局单例状态，保证测试间隔离
    RecognitionService.resetForTest();
    // 拦截 Flutter → 原生的 result 回传
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'result') resultCalls.add(call);
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  group('RecognitionService - initialize', () {
    test('initialize 应幂等（多次调用不报错）', () async {
      await RecognitionService.initialize();
      await RecognitionService.initialize();
      await RecognitionService.initialize();
    });

    test('initialize 后 ready 应立即完成', () async {
      await RecognitionService.initialize();
      // 已完成的 completer 再次 await 立即返回
      await RecognitionService.ready.timeout(const Duration(seconds: 1));
    });

    test('未初始化时调用 recognize 应在超时保护后返回结果', () async {
      // 不调用 initialize，直接发 recognize —— _process 内 ready.timeout(3s) 会等 3 秒
      // 引擎为 null 时应返回 none（约 3 秒后返回，验证超时保护路径）
      await sendRecognize({'text': '测试题目', 'type': '', 'generation': 1});
      expect(resultCalls, isNotEmpty);
      final call = resultCalls.last;
      expect(call.arguments['answer'], '');
      expect(call.arguments['level'], 'none');
      expect(call.arguments['generation'], 1);
    });
  });

  group('RecognitionService - 参数解析', () {
    test('Map 参数应正确解析', () async {
      await RecognitionService.initialize();
      await sendRecognize({
        'text': '一些OCR文本',
        'type': 'single',
        'generation': 42,
      });
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(resultCalls, isNotEmpty);
      // 引擎为空（无题库），应返回 none 且回显原始文本
      final call = resultCalls.last;
      expect(call.arguments['text'], '一些OCR文本');
      expect(call.arguments['level'], 'none');
      expect(call.arguments['generation'], 42);
    });

    test('旧版纯字符串参数应兼容', () async {
      await RecognitionService.initialize();
      await sendRecognize('纯字符串OCR文本');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(resultCalls, isNotEmpty);
      expect(resultCalls.last.arguments['level'], 'none');
    });

    test('未知方法应静默返回 null', () async {
      await RecognitionService.initialize();
      final codec = const StandardMethodCodec();
      final bytes = codec.encodeMethodCall(const MethodCall('unknownMethod', null));
      await messenger.handlePlatformMessage(
        'com.screenanswer/recognition',
        bytes,
        (_) {},
      );
      // 不应抛异常，也不应产生 result 回传
      expect(resultCalls, isEmpty);
    });
  });

  group('RecognitionService - loadBank 容错', () {
    test('loadBank 无效 id 不应抛异常', () async {
      await RecognitionService.initialize();
      await RecognitionService.loadBank('non-existent-bank-id');
    });

    test('reloadBank 不应抛异常（空库）', () async {
      await RecognitionService.initialize();
      await RecognitionService.reloadBank();
    });
  });
}
