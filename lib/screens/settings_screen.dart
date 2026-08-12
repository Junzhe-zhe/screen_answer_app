import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/diagnostic_log_service.dart';
import '../services/float_settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // 设置键名
  static const _keyBallSize = 'setting_ball_size';
  static const _keyBorderWidth = 'setting_border_width';
  static const _keyDefaultLock = 'setting_default_lock';

  double _ballSize = 40;
  double _borderWidth = 2;
  bool _defaultLock = false;
  bool _isLoaded = false;

  /// Slider 拖动防抖：拖动停止 [debounceDelay] 后才真正写盘并推送原生端。
  /// 避免每次刻度变化都触发 SharedPreferences 写入导致 UI 卡顿。
  static const debounceDelay = Duration(milliseconds: 300);
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _ballSize = prefs.getDouble(_keyBallSize) ?? 40.0;
      _borderWidth = prefs.getDouble(_keyBorderWidth) ?? 2.0;
      _defaultLock = prefs.getBool(_keyDefaultLock) ?? false;
      _isLoaded = true;
    });
  }

  Future<void> _saveDouble(
      String key, double value, ValueChanged<double> apply) async {
    setState(() => apply(value));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(key, value);
  }

  Future<void> _saveBallSize(double value) async {
    await _saveDouble(_keyBallSize, value, (v) => _ballSize = v);
    _scheduleApplyToNative();
  }

  Future<void> _saveBorderWidth(double value) async {
    await _saveDouble(_keyBorderWidth, value, (v) => _borderWidth = v);
    _scheduleApplyToNative();
  }

  Future<void> _saveDefaultLock(bool value) async {
    setState(() => _defaultLock = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDefaultLock, value);
    _scheduleApplyToNative();
  }

  /// 防抖推送原生端：拖动过程中多次触发只保留最后一次。
  void _scheduleApplyToNative() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounceDelay, _applyToNative);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  /// 将当前设置参数推送到原生 FloatService，运行时立即生效。
  void _applyToNative() {
    FloatSettingsService.applySettings(
      ballSize: _ballSize.toInt(),
      borderWidth: _borderWidth,
      defaultLock: _defaultLock,
    );
  }

  Future<void> _showDiagnosticLog() async {
    final content = await DiagnosticLogService.read();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('异常诊断日志'),
        content: SizedBox(
          width: double.maxFinite,
          height: 420,
          child: SingleChildScrollView(
            child: SelectableText(content.isEmpty ? '暂无日志' : content),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded) {
      return Scaffold(
        appBar: AppBar(title: const Text('设置')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 悬浮球设置
          const _SectionHeader(title: '悬浮球设置'),
          ListTile(
            title: const Text('悬浮球大小'),
            subtitle: Text('${_ballSize.toInt()} dp'),
            trailing: SizedBox(
              width: 200,
              child: Slider(
                value: _ballSize,
                min: 5,
                max: 80,
                divisions: 75,
                label: '${_ballSize.toInt()} dp',
                onChanged: _saveBallSize,
              ),
            ),
          ),
          ListTile(
            title: const Text('边框粗细'),
            subtitle: Text('${_borderWidth.toInt()} dp'),
            trailing: SizedBox(
              width: 200,
              child: Slider(
                value: _borderWidth,
                min: 1,
                max: 10,
                divisions: 9,
                label: '${_borderWidth.toInt()} dp',
                onChanged: _saveBorderWidth,
              ),
            ),
          ),
          const Divider(),

          // 答案面板设置
          const _SectionHeader(title: '答案面板设置'),
          SwitchListTile(
            title: const Text('默认锁定面板'),
            subtitle: const Text('开启后答案面板不会自动消失'),
            value: _defaultLock,
            onChanged: _saveDefaultLock,
          ),
          const Divider(),

          // 关于
          const _SectionHeader(title: '关于'),
          const ListTile(
            title: Text('版本'),
            subtitle: Text('1.0.0'),
          ),
          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('查看异常诊断日志'),
            subtitle: const Text('卡顿或闪退后可复制日志内容反馈'),
            onTap: _showDiagnosticLog,
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    );
  }
}
