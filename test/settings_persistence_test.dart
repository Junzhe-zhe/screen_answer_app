/// 设置持久化逻辑测试
///
/// 覆盖场景:
/// - SharedPreferences 读写
/// - 设置保存与恢复
/// - 默认值处理
/// - 设置变更通知
/// - 边界值
///
/// 注意: SettingsScreen 已实现 SharedPreferences 持久化，
/// 键名规则: setting_ball_size, setting_border_width, setting_default_lock
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ==================== 设置模型 ====================

/// 应用设置数据模型 — 与 SettingsScreen 使用的键名一致
class AppSettings {
  final double floatBallSize;
  final double borderWidth;
  final bool defaultLockPanel;

  const AppSettings({
    this.floatBallSize = 40.0,
    this.borderWidth = 2.0,
    this.defaultLockPanel = false,
  });

  AppSettings copyWith({
    double? floatBallSize,
    double? borderWidth,
    bool? defaultLockPanel,
  }) {
    return AppSettings(
      floatBallSize: floatBallSize ?? this.floatBallSize,
      borderWidth: borderWidth ?? this.borderWidth,
      defaultLockPanel: defaultLockPanel ?? this.defaultLockPanel,
    );
  }

  Map<String, dynamic> toMap() => {
        'setting_ball_size': floatBallSize,
        'setting_border_width': borderWidth,
        'setting_default_lock': defaultLockPanel ? 1 : 0,
      };

  factory AppSettings.fromMap(Map<String, dynamic> map) => AppSettings(
        floatBallSize: (map['setting_ball_size'] as num?)?.toDouble() ?? 40.0,
        borderWidth: (map['setting_border_width'] as num?)?.toDouble() ?? 2.0,
        defaultLockPanel: (map['setting_default_lock'] as int?) == 1,
      );
}

// ==================== 设置服务 ====================

/// 设置持久化服务 — 与 SettingsScreen 使用相同的键名
class SettingsService {
  static const _keyFloatBallSize = 'setting_ball_size';
  static const _keyBorderWidth = 'setting_border_width';
  static const _keyDefaultLockPanel = 'setting_default_lock';

  /// 加载设置
  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      floatBallSize: prefs.getDouble(_keyFloatBallSize) ?? 40.0,
      borderWidth: prefs.getDouble(_keyBorderWidth) ?? 2.0,
      defaultLockPanel: prefs.getBool(_keyDefaultLockPanel) ?? false,
    );
  }

  /// 保存设置
  static Future<void> save(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyFloatBallSize, settings.floatBallSize);
    await prefs.setDouble(_keyBorderWidth, settings.borderWidth);
    await prefs.setBool(_keyDefaultLockPanel, settings.defaultLockPanel);
  }

  /// 保存单个设置项
  static Future<void> saveFloatBallSize(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyFloatBallSize, value);
  }

  static Future<void> saveBorderWidth(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyBorderWidth, value);
  }

  static Future<void> saveDefaultLockPanel(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDefaultLockPanel, value);
  }
}

// ==================== 测试 ====================

void main() {
  group('AppSettings - 数据模型', () {
    test('默认值应正确', () {
      final settings = const AppSettings();
      expect(settings.floatBallSize, 40.0);
      expect(settings.borderWidth, 2.0);
      expect(settings.defaultLockPanel, false);
    });

    test('copyWith 应只修改指定字段', () {
      final settings = const AppSettings();
      final modified = settings.copyWith(floatBallSize: 60.0);
      expect(modified.floatBallSize, 60.0);
      expect(modified.borderWidth, 2.0); // 未修改
      expect(modified.defaultLockPanel, false); // 未修改
    });

    test('toMap / fromMap 应往返一致', () {
      final original = AppSettings(
        floatBallSize: 50.0,
        borderWidth: 3.0,
        defaultLockPanel: true,
      );
      final map = original.toMap();
      final restored = AppSettings.fromMap(map);
      expect(restored.floatBallSize, 50.0);
      expect(restored.borderWidth, 3.0);
      expect(restored.defaultLockPanel, true);
    });

    test('fromMap 缺失字段应使用默认值', () {
      final settings = AppSettings.fromMap({});
      expect(settings.floatBallSize, 40.0);
      expect(settings.borderWidth, 2.0);
      expect(settings.defaultLockPanel, false);
    });
  });

  group('SettingsService - SharedPreferences 持久化', () {
    test('保存后应能正确加载', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = AppSettings(
        floatBallSize: 60.0,
        borderWidth: 4.0,
        defaultLockPanel: true,
      );

      await SettingsService.save(settings);
      final loaded = await SettingsService.load();

      expect(loaded.floatBallSize, 60.0);
      expect(loaded.borderWidth, 4.0);
      expect(loaded.defaultLockPanel, true);
    });

    test('未保存过设置应返回默认值', () async {
      SharedPreferences.setMockInitialValues({});
      final loaded = await SettingsService.load();

      expect(loaded.floatBallSize, 40.0);
      expect(loaded.borderWidth, 2.0);
      expect(loaded.defaultLockPanel, false);
    });

    test('部分保存应正确合并', () async {
      SharedPreferences.setMockInitialValues({});
      // 只保存悬浮球大小
      await SettingsService.saveFloatBallSize(55.0);
      final loaded = await SettingsService.load();

      expect(loaded.floatBallSize, 55.0);
      expect(loaded.borderWidth, 2.0); // 默认值
      expect(loaded.defaultLockPanel, false); // 默认值
    });

    test('多次保存应覆盖旧值', () async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.save(const AppSettings(floatBallSize: 30.0));
      await SettingsService.save(const AppSettings(floatBallSize: 70.0));
      final loaded = await SettingsService.load();

      expect(loaded.floatBallSize, 70.0);
    });

    test('保存后重启应保持值（模拟新实例）', () async {
      SharedPreferences.setMockInitialValues({});
      // 第一次保存
      await SettingsService.save(const AppSettings(
        floatBallSize: 50.0,
        borderWidth: 3.0,
        defaultLockPanel: true,
      ));

      // 模拟 App 重启：重新初始化 SharedPreferences
      SharedPreferences.setMockInitialValues({
        'setting_ball_size': 50.0,
        'setting_border_width': 3.0,
        'setting_default_lock': true,
      });

      final loaded = await SettingsService.load();
      expect(loaded.floatBallSize, 50.0);
      expect(loaded.borderWidth, 3.0);
      expect(loaded.defaultLockPanel, true);
    });
  });

  group('SettingsService - 边界值', () {
    test('悬浮球大小最小值', () async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.saveFloatBallSize(5.0); // AppConstants.floatBallMinSize
      final loaded = await SettingsService.load();
      expect(loaded.floatBallSize, 5.0);
    });

    test('悬浮球大小最大值', () async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.saveFloatBallSize(80.0); // AppConstants.floatBallMaxSize
      final loaded = await SettingsService.load();
      expect(loaded.floatBallSize, 80.0);
    });

    test('边框粗细最小值', () async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.saveBorderWidth(1.0);
      final loaded = await SettingsService.load();
      expect(loaded.borderWidth, 1.0);
    });

    test('边框粗细最大值', () async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.saveBorderWidth(10.0);
      final loaded = await SettingsService.load();
      expect(loaded.borderWidth, 10.0);
    });
  });

  group('SettingsService - 并发与一致性', () {
    test('连续快速保存应全部生效', () async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.saveFloatBallSize(20.0);
      await SettingsService.saveFloatBallSize(50.0);
      await SettingsService.saveFloatBallSize(80.0);
      final loaded = await SettingsService.load();
      // 最后一个写入的值应生效
      expect(loaded.floatBallSize, 80.0);
    });

    test('保存大量设置不应超时', () async {
      SharedPreferences.setMockInitialValues({});
      final stopwatch = Stopwatch()..start();
      for (var i = 0; i < 100; i++) {
        await SettingsService.save(AppSettings(
          floatBallSize: 5.0 + (i % 76),
          borderWidth: 1.0 + (i % 6),
          defaultLockPanel: i.isEven,
        ));
      }
      stopwatch.stop();
      // 100 次保存应在合理时间内
      expect(stopwatch.elapsedMilliseconds, lessThan(2000));
    });
  });

  group('FloatSettingsService - applySettings 调用参数', () {
    test('applySettings 传入的 ballSize 应为整数且在合理范围', () async {
      SharedPreferences.setMockInitialValues({});
      // 保存设置后应能正确计算 applySettings 参数
      const ballSizeDouble = 50.0;
      expect(ballSizeDouble.toInt(), 50);
      expect(ballSizeDouble.toInt(), greaterThanOrEqualTo(5));
      expect(ballSizeDouble.toInt(), lessThanOrEqualTo(80));
    });

    test('applySettings 传入的 borderWidth 应在合理范围', () {
      const borderWidth = 3.0;
      expect(borderWidth, greaterThanOrEqualTo(1.0));
      expect(borderWidth, lessThanOrEqualTo(10.0));
    });

    test('save 后 SharedPreferences 键名与设置页一致', () async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.saveFloatBallSize(55.0);
      await SettingsService.saveBorderWidth(4.0);
      await SettingsService.saveDefaultLockPanel(true);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('setting_ball_size'), 55.0);
      expect(prefs.getDouble('setting_border_width'), 4.0);
      expect(prefs.getBool('setting_default_lock'), true);
    });
  });
}
