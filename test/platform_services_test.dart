/// 平台通道服务 + 数据模型补充测试
///
/// 覆盖场景:
/// - CaptureService 权限请求/查询（成功、PlatformException、异常）
/// - FloatSettingsService.applySettings 参数传递（成功、MissingPluginException）
/// - QuestionBank.fromMap 字段转换边界（is_default int→bool、缺失字段默认值）
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screen_answer_app/models/question_bank.dart';
import 'package:screen_answer_app/services/capture_service.dart';
import 'package:screen_answer_app/services/float_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const captureChannel = MethodChannel('com.screenanswer/capture');
  const floatChannel = MethodChannel('com.screenanswer/float');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  group('CaptureService - 权限请求', () {
    tearDown(() {
      messenger.setMockMethodCallHandler(captureChannel, null);
    });

    test('requestPermission 原生返回 true 时应返回 true', () async {
      messenger.setMockMethodCallHandler(captureChannel, (call) async {
        expect(call.method, 'requestPermission');
        return true;
      });
      expect(await CaptureService.requestPermission(), isTrue);
    });

    test('requestPermission 原生返回 false 时应返回 false', () async {
      messenger.setMockMethodCallHandler(captureChannel, (call) async => false);
      expect(await CaptureService.requestPermission(), isFalse);
    });

    test('requestPermission PlatformException 时应返回 false 不抛异常', () async {
      messenger.setMockMethodCallHandler(
        captureChannel,
        (call) async => throw PlatformException(code: 'PERMISSION_DENIED'),
      );
      expect(await CaptureService.requestPermission(), isFalse);
    });

    test('isPermissionGranted 原生返回 true 时应返回 true', () async {
      messenger.setMockMethodCallHandler(captureChannel, (call) async {
        expect(call.method, 'isPermissionGranted');
        return true;
      });
      expect(await CaptureService.isPermissionGranted(), isTrue);
    });

    test('isPermissionGranted 异常时应返回 false', () async {
      messenger.setMockMethodCallHandler(
        captureChannel,
        (call) async => throw PlatformException(code: 'CHANNEL_ERROR'),
      );
      expect(await CaptureService.isPermissionGranted(), isFalse);
    });
  });

  group('FloatSettingsService - applySettings', () {
    tearDown(() {
      messenger.setMockMethodCallHandler(floatChannel, null);
    });

    test('applySettings 应传递正确参数并返回 true', () async {
      MethodCall? received;
      messenger.setMockMethodCallHandler(floatChannel, (call) async {
        received = call;
        return true;
      });
      final ok = await FloatSettingsService.applySettings(
        ballSize: 40,
        borderWidth: 2.0,
        defaultLock: true,
      );
      expect(ok, isTrue);
      expect(received!.method, 'applySettings');
      expect(received!.arguments['ballSize'], 40);
      expect(received!.arguments['borderWidth'], 2.0);
      expect(received!.arguments['defaultLock'], true);
    });

    test('MissingPluginException 时应静默返回 false', () async {
      messenger.setMockMethodCallHandler(
        floatChannel,
        (call) async => throw MissingPluginException('no impl'),
      );
      expect(
        await FloatSettingsService.applySettings(
          ballSize: 40,
          borderWidth: 2.0,
          defaultLock: false,
        ),
        isFalse,
      );
    });

    test('原生返回 null 时应返回 false', () async {
      messenger.setMockMethodCallHandler(floatChannel, (call) async => null);
      expect(
        await FloatSettingsService.applySettings(
          ballSize: 40,
          borderWidth: 2.0,
          defaultLock: false,
        ),
        isFalse,
      );
    });
  });

  group('QuestionBank.fromMap - 字段转换', () {
    test('is_default int 1 应转为 true', () {
      final bank = QuestionBank.fromMap({
        'id': 'b1',
        'name': '题库',
        'source_file': 'a.xlsx',
        'question_count': 5,
        'is_default': 1,
        'created_at': 1700000000000,
        'updated_at': 1700000000000,
      });
      expect(bank.isDefault, isTrue);
      expect(bank.questionCount, 5);
      expect(bank.sourceFile, 'a.xlsx');
    });

    test('is_default int 0 应转为 false', () {
      final bank = QuestionBank.fromMap({
        'id': 'b1',
        'name': '题库',
        'is_default': 0,
        'created_at': 1700000000000,
        'updated_at': 1700000000000,
      });
      expect(bank.isDefault, isFalse);
    });

    test('缺失字段应使用默认值', () {
      final bank = QuestionBank.fromMap({
        'id': 'b1',
        'name': '题库',
        'created_at': 1700000000000,
        'updated_at': 1700000000000,
      });
      expect(bank.isDefault, isFalse);
      expect(bank.questionCount, 0);
      expect(bank.sourceFile, isNull);
    });

    test('question_count null 应回退为 0', () {
      final bank = QuestionBank.fromMap({
        'id': 'b1',
        'name': '题库',
        'question_count': null,
        'is_default': null,
        'created_at': 1700000000000,
        'updated_at': 1700000000000,
      });
      expect(bank.questionCount, 0);
      expect(bank.isDefault, isFalse);
    });

    test('toMap/fromMap 应往返一致', () {
      final bank = QuestionBank(
        id: 'b1',
        name: '题库',
        sourceFile: 'a.xlsx',
        questionCount: 12,
        isDefault: true,
        createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      final restored = QuestionBank.fromMap(bank.toMap());
      expect(restored.id, bank.id);
      expect(restored.name, bank.name);
      expect(restored.sourceFile, bank.sourceFile);
      expect(restored.questionCount, bank.questionCount);
      expect(restored.isDefault, bank.isDefault);
      expect(restored.createdAt, bank.createdAt);
      expect(restored.updatedAt, bank.updatedAt);
    });
  });
}
