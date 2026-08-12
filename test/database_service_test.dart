/// 数据库服务单元测试
///
/// 覆盖场景:
/// - 建表结构（questions 表必须包含 explanation 列）
/// - 版本迁移 onUpgrade（v1→v2→v3 补 explanation 列）
/// - 题库 CRUD（创建/读取/默认/删除/级联删除）
/// - 题目批量插入与计数
/// - setDefaultBank 事务一致性（始终只有一个默认题库）
/// - 识别历史记录保存
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:screen_answer_app/models/question.dart';
import 'package:screen_answer_app/models/question_bank.dart';
import 'package:screen_answer_app/services/database_service.dart';

void main() {
  setUpAll(() {
    // 使用 FFI 版 SQLite（纯 Dart 实现，无需模拟器/真机）
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await DatabaseService.resetForTest();
  });

  group('DatabaseService - 建表结构', () {
    test('questions 表应包含 explanation 列', () async {
      final db = await DatabaseService.database;
      final cols = await db.rawQuery('PRAGMA table_info(questions)');
      final colNames = cols.map((c) => c['name']).toSet();
      expect(colNames, containsAll([
        'id', 'bank_id', 'raw_text', 'preprocessed_text',
        'answer', 'explanation', 'created_at',
      ]));
    });

    test('question_banks 表应包含全部列', () async {
      final db = await DatabaseService.database;
      final cols = await db.rawQuery('PRAGMA table_info(question_banks)');
      final colNames = cols.map((c) => c['name']).toSet();
      expect(colNames, containsAll([
        'id', 'name', 'source_file', 'question_count',
        'is_default', 'created_at', 'updated_at',
      ]));
    });

    test('recognition_history 表应包含全部列', () async {
      final db = await DatabaseService.database;
      final cols = await db.rawQuery('PRAGMA table_info(recognition_history)');
      final colNames = cols.map((c) => c['name']).toSet();
      expect(colNames, containsAll([
        'id', 'ocr_text', 'matched_question', 'matched_answer',
        'confidence', 'match_level', 'bank_id', 'timestamp',
      ]));
    });
  });

  group('DatabaseService - 版本迁移', () {
    test('v1 数据库升级到 v3 应补充 explanation 列', () async {
      // 手工构造 v1 版 questions 表（无 explanation 列）
      final db = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE questions (
                id TEXT PRIMARY KEY,
                bank_id TEXT NOT NULL,
                raw_text TEXT NOT NULL,
                preprocessed_text TEXT NOT NULL,
                answer TEXT NOT NULL,
                created_at INTEGER
              )
            ''');
          },
        ),
      );

      // 确认 v1 表确实没有 explanation 列
      var cols = await db.rawQuery('PRAGMA table_info(questions)');
      expect(cols.map((c) => c['name']), isNot(contains('explanation')));

      // 以 DatabaseService 的真实迁移逻辑驱动升级 v1 -> v3
      await DatabaseService.onUpgradeForTest(db, 1, 3);

      // v3 后应有 explanation 列
      cols = await db.rawQuery('PRAGMA table_info(questions)');
      expect(cols.map((c) => c['name']), contains('explanation'));

      // 重复升级不应报错（幂等）
      await DatabaseService.onUpgradeForTest(db, 2, 3);
      await db.close();
    });
  });

  group('DatabaseService - 题库 CRUD', () {
    test('创建题库后应能读取', () async {
      final bank = await DatabaseService.createBank('测试题库', 'test.xlsx');
      expect(bank.id, isNotEmpty);
      expect(bank.name, '测试题库');
      expect(bank.sourceFile, 'test.xlsx');

      final loaded = await DatabaseService.getBank(bank.id);
      expect(loaded, isNotNull);
      expect(loaded!.name, '测试题库');
    });

    test('题库列表应按 is_default 优先排序', () async {
      await DatabaseService.createBank('题库A', null);
      final bankB = await DatabaseService.createBank('题库B', null);
      await DatabaseService.setDefaultBank(bankB.id);

      final banks = await DatabaseService.getBanks();
      expect(banks.length, 2);
      expect(banks.first.id, bankB.id); // 默认题库排最前
      expect(banks.first.isDefault, isTrue);
    });

    test('getDefaultBank 应返回默认题库', () async {
      final bankA = await DatabaseService.createBank('题库A', null);
      await DatabaseService.setDefaultBank(bankA.id);
      final defaultBank = await DatabaseService.getDefaultBank();
      expect(defaultBank, isNotNull);
      expect(defaultBank!.id, bankA.id);
    });

    test('无默认题库时 getDefaultBank 返回 null', () async {
      await DatabaseService.createBank('题库A', null);
      final defaultBank = await DatabaseService.getDefaultBank();
      expect(defaultBank, isNull);
    });

    test('删除题库应级联删除题目', () async {
      final bank = await DatabaseService.createBank('待删除', null);
      await DatabaseService.insertQuestions(bank.id, [
        Question(
          id: 'q1',
          bankId: bank.id,
          rawText: '题目1',
          preprocessedText: '题目1',
          answer: '答案1',
          createdAt: DateTime.now(),
        ),
      ]);

      await DatabaseService.deleteBank(bank.id);
      expect(await DatabaseService.getBank(bank.id), isNull);
      expect(await DatabaseService.getQuestionCount(bank.id), 0);
    });

    test('删除默认题库后不应残留默认标记', () async {
      final bankA = await DatabaseService.createBank('题库A', null);
      await DatabaseService.createBank('题库B', null);
      await DatabaseService.setDefaultBank(bankA.id);
      await DatabaseService.deleteBank(bankA.id);

      final banks = await DatabaseService.getBanks();
      expect(banks.length, 1);
      expect(banks.first.isDefault, isFalse);
    });
  });

  group('DatabaseService - setDefaultBank 事务一致性', () {
    test('设置默认后始终只有一个默认题库', () async {
      final banks = <QuestionBank>[
        await DatabaseService.createBank('题库1', null),
        await DatabaseService.createBank('题库2', null),
        await DatabaseService.createBank('题库3', null),
      ];

      for (final bank in banks) {
        await DatabaseService.setDefaultBank(bank.id);
        final all = await DatabaseService.getBanks();
        final defaults = all.where((b) => b.isDefault).toList();
        expect(defaults.length, 1, reason: '切换到 \${bank.name} 后应有且仅有一个默认题库');
        expect(defaults.first.id, bank.id);
      }
    });

    test('setDefaultBank 对不存在的 id 不应抛异常', () async {
      await DatabaseService.createBank('题库1', null);
      // 不存在的 id：事务内第二步更新 0 行，不应报错
      await DatabaseService.setDefaultBank('non-existent-id');
      final defaults = (await DatabaseService.getBanks()).where((b) => b.isDefault);
      expect(defaults.length, 0);
    });
  });

  group('DatabaseService - 题目操作', () {
    test('批量插入题目并更新计数', () async {
      final bank = await DatabaseService.createBank('题库', null);
      final questions = List.generate(
        10,
        (i) => Question(
          id: 'q$i',
          bankId: bank.id,
          rawText: '题目$i',
          preprocessedText: '题目$i',
          answer: '答案$i',
          explanation: i.isEven ? '解析$i' : null,
          createdAt: DateTime.now(),
        ),
      );
      await DatabaseService.insertQuestions(bank.id, questions);

      expect(await DatabaseService.getQuestionCount(bank.id), 10);

      final refreshed = await DatabaseService.getBank(bank.id);
      expect(refreshed!.questionCount, 10);
    });

    test('getQuestionPairs 应返回题目/答案/解析', () async {
      final bank = await DatabaseService.createBank('题库', null);
      await DatabaseService.insertQuestions(bank.id, [
        Question(
          id: 'q1',
          bankId: bank.id,
          rawText: '题目1',
          preprocessedText: '题目1',
          answer: '答案1',
          explanation: '解析1',
          createdAt: DateTime.now(),
        ),
      ]);
      final pairs = await DatabaseService.getQuestionPairs(bank.id);
      expect(pairs.length, 1);
      expect(pairs.first.question, '题目1');
      expect(pairs.first.answer, '答案1');
      expect(pairs.first.explanation, '解析1');
    });

    test('重复插入同一主键题目应抛出异常（主键约束）', () async {
      final bank = await DatabaseService.createBank('题库', null);
      final q = Question(
        id: 'dup',
        bankId: bank.id,
        rawText: '题目',
        preprocessedText: '题目',
        answer: '答案',
        createdAt: DateTime.now(),
      );
      await DatabaseService.insertQuestions(bank.id, [q]);
      // 第二次插入同一主键 id 应触发 UNIQUE 约束异常（SQLite 行为）
      await expectLater(
        DatabaseService.insertQuestions(bank.id, [q]),
        throwsA(isA<Exception>()),
      );
      // 数据保持完整：仅 1 行
      expect(await DatabaseService.getQuestionCount(bank.id), 1);
    });
  });

  group('DatabaseService - 历史记录', () {
    test('保存识别历史应成功', () async {
      await DatabaseService.saveHistory(RecognitionHistory(
        id: 'h1',
        ocrText: '题目文本',
        matchedQuestion: '题目文本',
        matchedAnswer: '答案',
        confidence: 0.98,
        matchLevel: 'exact',
        bankId: 'bank-1',
        timestamp: DateTime.now(),
      ));

      final db = await DatabaseService.database;
      final rows = await db.query('recognition_history', where: 'id = ?', whereArgs: ['h1']);
      expect(rows.length, 1);
      expect(rows.first['matched_answer'], '答案');
      expect(rows.first['confidence'], closeTo(0.98, 0.001));
    });

    test('历史记录缺省字段应为 null', () async {
      await DatabaseService.saveHistory(RecognitionHistory(
        id: 'h2',
        ocrText: '仅文本',
        timestamp: DateTime.now(),
      ));
      final db = await DatabaseService.database;
      final rows = await db.query('recognition_history', where: 'id = ?', whereArgs: ['h2']);
      expect(rows.first['matched_question'], isNull);
      expect(rows.first['confidence'], isNull);
    });
  });
}
