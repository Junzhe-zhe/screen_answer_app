import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/question_bank.dart';
import '../services/capture_service.dart';
import '../services/recognition_service.dart';
import '../utils/constants.dart';
import 'bank_list_screen.dart';
import 'import_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  QuestionBank? _activeBank;

  static const _floatChannel = MethodChannel(AppConstants.floatChannel);

  @override
  void initState() {
    super.initState();
    _loadDefaultBank();
  }

  Future<void> _loadDefaultBank() async {
    await RecognitionService.reloadBank();
    final bank = RecognitionService.activeBank;
    if (bank != null) {
      await _loadMatchEngine(bank);
    }
  }

  Future<void> _loadMatchEngine(QuestionBank bank) async {
    await RecognitionService.loadBank(bank.id);
    if (!mounted) return;
    setState(() => _activeBank = bank);
  }

  Future<void> _startAnswering() async {
    if (_activeBank == null) return;

    // 检查悬浮窗权限
    final hasOverlay = await CaptureService.isPermissionGranted();
    if (!hasOverlay) {
      if (mounted) _showPermissionDialog();
      return;
    }

    // 启动 FloatService
    try {
      await _floatChannel.invokeMethod('showBall');
    } catch (e) {
      if (mounted) _showError('启动失败: $e');
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.orange),
            SizedBox(width: 8),
            Text('需要悬浮窗权限'),
          ],
        ),
        content: const Text(
          '屏幕答题助手需要「在其他应用上层显示」权限。\n\n点击确认后将跳转到设置页面，请开启该权限后返回。',
          style: TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2196F3),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              // 跳转权限设置
              CaptureService.requestPermission();
            },
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F8FA),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          '读屏搜题',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF333333)),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20, color: Color(0xFF666666)),
          onPressed: _showAboutDialog,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 22, color: Color(0xFF666666)),
            tooltip: '设置',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          _buildBankInfo(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              child: Column(
                children: [
                  // 功能卡片：悬浮窗识别
                  _buildFeatureCard(
                    icon: Icons.touch_app,
                    iconColor: const Color(0xFFFF7A45),
                    title: '悬浮窗识别',
                    subtitle: '开启悬浮窗后，框选题目区域即可自动识别并匹配答案',
                    child: Column(
                      children: [
                        const SizedBox(height: 16),
                        _buildStartButton(),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 40,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('模式切换功能即将上线'), duration: Duration(seconds: 1)),
                              );
                            },
                            icon: const Icon(Icons.swap_horiz, size: 16),
                            label: const Text('切换识别模式'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFFF7A45),
                              side: BorderSide(color: const Color(0xFFFF7A45).withValues(alpha:0.4)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              textStyle: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const SizedBox(height: 8),
                  _buildDisclaimer(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 功能卡片组件
  Widget _buildFeatureCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha:0.04), blurRadius: 16, offset: const Offset(0, 4)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF333333),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            child,
          ],
        ),
      ),
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('屏幕答题助手'),
        content: const Text(
          '本软件仅供学习使用，请勿用于正式考试和答题积分。\n\n使用说明：\n1. 导入或选择题库\n2. 点击「开启」启动悬浮窗\n3. 在目标题目界面框选区域\n4. 松手后自动识别并显示答案',
          style: TextStyle(fontSize: 14, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Widget _buildDisclaimer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Text(
        '免责声明：本软件仅供学习使用，请勿用于正式考试和答题积分',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, color: Colors.grey[400]),
      ),
    );
  }

  Widget _buildBankInfo() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha:0.04), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFFF7A45).withValues(alpha:0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.book, color: Color(0xFFFF7A45), size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _activeBank?.name ?? '未选择题库',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF333333)),
                ),
                const SizedBox(height: 2),
                Text(
                  _activeBank != null ? '${_activeBank!.questionCount} 道题目' : '请导入或选择题库',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
          _MiniButton(
            icon: Icons.swap_horiz,
            label: '切换',
            onTap: () async {
              final bank = await Navigator.push<QuestionBank>(
                context, MaterialPageRoute(builder: (_) => const BankListScreen()),
              );
              if (bank != null) _loadMatchEngine(bank);
            },
          ),
          const SizedBox(width: 6),
          _MiniButton(
            icon: Icons.upload_file,
            label: '导入',
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const ImportScreen()));
              // 导入后仅在当前无题库时才加载默认题库，避免覆盖用户已选择的题库
              if (_activeBank == null) {
                _loadDefaultBank();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStartButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            colors: [Color(0xFFFF9F5A), Color(0xFFFF7A45)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          boxShadow: [
            BoxShadow(color: const Color(0xFFFF7A45).withValues(alpha:0.35), blurRadius: 16, offset: const Offset(0, 6)),
          ],
        ),
        child: ElevatedButton(
          onPressed: _activeBank != null ? _startAnswering : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          child: const Text('开启'),
        ),
      ),
    );
  }


}

class _MiniButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MiniButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFFF7A45).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFFF7A45).withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: const Color(0xFFFF7A45)),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Color(0xFFFF7A45)),
            ),
          ],
        ),
      ),
    );
  }
}
