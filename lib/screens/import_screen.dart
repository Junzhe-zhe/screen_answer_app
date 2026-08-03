import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/file_import_service.dart';
import '../services/database_service.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  bool _importing = false;
  String? _error;
  int? _importedCount;
  String? _bankName;

  Future<void> _pickFile() async {
    setState(() {
      _error = null;
      _importedCount = null;
      _bankName = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'csv', 'xlsx'],
        allowMultiple: false,
        withData: true, // 读取字节数据
      );

      if (result == null || result.files.isEmpty) {
        // 用户取消
        return;
      }

      final file = result.files.first;
      final bytes = file.bytes;
      final fileName = file.name;

      if (bytes == null) {
        setState(() => _error = '无法读取文件内容');
        return;
      }

      setState(() => _importing = true);

      // 解析文件
      final parseResult = await FileImportService.importFile(bytes, fileName);

      if (parseResult.error != null) {
        setState(() {
          _error = parseResult.error;
          _importing = false;
        });
        return;
      }

      if (parseResult.questions.isEmpty) {
        setState(() {
          _error = '文件中没有找到有效的题目数据';
          _importing = false;
        });
        return;
      }

      // 创建题库
      final bankName = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
      final bank = await DatabaseService.createBank(bankName, fileName);

      // 插入题目
      final questions = FileImportService.toDbQuestions(
        parseResult.questions,
        bank.id,
      );
      await DatabaseService.insertQuestions(bank.id, questions);

      // 设为默认题库（首个题库自动设默认）
      final banks = await DatabaseService.getBanks();
      if (banks.length == 1) {
        await DatabaseService.setDefaultBank(bank.id);
      }

      setState(() {
        _importedCount = questions.length;
        _bankName = bankName;
        _importing = false;
      });
    } catch (e) {
      setState(() {
        _error = '导入失败: $e';
        _importing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('导入题库')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 状态显示
              if (_importing) ...[
                const _ImportingView(),
              ] else if (_importedCount != null) ...[
                _SuccessView(
                  bankName: _bankName ?? '',
                  count: _importedCount!,
                  onDone: () => Navigator.pop(context, true),
                  onImportMore: _pickFile,
                ),
              ] else ...[
                // 初始状态：选择文件
                Icon(
                  Icons.upload_file,
                  size: 80,
                  color: Colors.grey[600],
                ),
                const SizedBox(height: 24),
                const Text(
                  '导入题库',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  '支持 JSON / CSV / Excel(.xlsx) 格式\n包括国网学堂考试模板',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[500], fontSize: 14),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: 220,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _pickFile,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('选择文件', style: TextStyle(fontSize: 16)),
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 20),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Colors.red, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ImportingView extends StatelessWidget {
  const _ImportingView();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 48,
          height: 48,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
        const SizedBox(height: 24),
        const Text(
          '正在解析文件中...',
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      ],
    );
  }
}

class _SuccessView extends StatelessWidget {
  final String bankName;
  final int count;
  final VoidCallback onDone;
  final VoidCallback onImportMore;

  const _SuccessView({
    required this.bankName,
    required this.count,
    required this.onDone,
    required this.onImportMore,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle, size: 64, color: Colors.green),
        const SizedBox(height: 16),
        const Text(
          '导入成功',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Text(
                bankName,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
              Text(
                '共 $count 道题目',
                style: TextStyle(fontSize: 14, color: Colors.grey[400]),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: onImportMore,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('继续导入'),
            ),
            const SizedBox(width: 16),
            ElevatedButton.icon(
              onPressed: onDone,
              icon: const Icon(Icons.check, size: 18),
              label: const Text('完成'),
            ),
          ],
        ),
      ],
    );
  }
}
