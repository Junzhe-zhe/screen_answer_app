import 'package:flutter/material.dart';
import '../models/question_bank.dart';
import '../services/database_service.dart';
import 'import_screen.dart';

class BankListScreen extends StatefulWidget {
  const BankListScreen({super.key});

  @override
  State<BankListScreen> createState() => _BankListScreenState();
}

class _BankListScreenState extends State<BankListScreen> {
  List<QuestionBank> _banks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadBanks();
  }

  Future<void> _loadBanks() async {
    if (mounted) setState(() => _loading = true);
    final banks = await DatabaseService.getBanks();
    if (!mounted) return;
    setState(() {
      _banks = banks;
      _loading = false;
    });
  }

  Future<void> _importBank() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ImportScreen()),
    );
    _loadBanks();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('题库管理')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importBank,
        icon: const Icon(Icons.add),
        label: const Text('导入题库'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _banks.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('暂无题库，请先导入', style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _importBank,
                        icon: const Icon(Icons.upload_file),
                        label: const Text('导入题库'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _banks.length,
                  itemBuilder: (context, index) {
                    final bank = _banks[index];
                    return ListTile(
                      leading: Icon(
                        bank.isDefault ? Icons.star : Icons.bookmark_border,
                        color: bank.isDefault ? Colors.amber : Colors.grey,
                      ),
                      title: Text(bank.name),
                      subtitle: Text('${bank.questionCount} 道题'),
                      trailing: PopupMenuButton<String>(
                        onSelected: (action) async {
                          if (action == 'set_default') {
                            await DatabaseService.setDefaultBank(bank.id);
                            _loadBanks();
                          } else if (action == 'delete') {
                            await DatabaseService.deleteBank(bank.id);
                            _loadBanks();
                          }
                        },
                        itemBuilder: (context) => [
                          if (!bank.isDefault)
                            const PopupMenuItem(value: 'set_default', child: Text('设为默认')),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('删除', style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                      onTap: () => Navigator.pop(context, bank),
                    );
                  },
                ),
    );
  }
}
