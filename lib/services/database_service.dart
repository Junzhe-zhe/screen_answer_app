import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';
import '../models/question_bank.dart';
import '../models/question.dart';
import '../services/match_engine.dart';

class DatabaseService {
  static Database? _database;
  static const _uuid = Uuid();
  static const _dbVersion = 3;

  /// 仅用于单元测试：关闭并清空缓存的数据库实例，同时删除数据库文件，
  /// 保证每个测试用例从全新的数据库开始（避免数据残留导致断言失败）。
  @visibleForTesting
  static Future<void> resetForTest() async {
    final db = _database;
    _database = null;
    await db?.close();
    try {
      final dbPath = await getDatabasesPath();
      final file = File(join(dbPath, 'screen_answer.db'));
      if (await file.exists()) await file.delete();
    } catch (_) {
      // 删除失败不影响测试主体逻辑
    }
  }

  /// 仅用于单元测试：暴露真实的 _onUpgrade 迁移逻辑，供版本迁移测试驱动。
  @visibleForTesting
  static Future<void> onUpgradeForTest(
    Database db,
    int oldVersion,
    int newVersion,
  ) =>
      _onUpgrade(db, oldVersion, newVersion);

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _init();
    return _database!;
  }

  static Future<Database> _init() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'screen_answer.db');
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: _createTables,
      onUpgrade: _onUpgrade,
    );
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // v1→v2: 增加 explanation 列
      try {
        await db.execute('ALTER TABLE questions ADD COLUMN explanation TEXT');
      } catch (_) {
        // 列可能已存在
      }
    }
    if (oldVersion < 3) {
      // v2/v1→v3: 确保 explanation 列存在（修复首次建表遗漏该列的 bug）
      try {
        await db.execute('ALTER TABLE questions ADD COLUMN explanation TEXT');
      } catch (_) {
        // 列可能已存在
      }
    }
  }

  static Future<void> _createTables(Database db, int version) async {
    await db.execute('''
      CREATE TABLE question_banks (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        source_file TEXT,
        question_count INTEGER DEFAULT 0,
        is_default INTEGER DEFAULT 0,
        created_at INTEGER,
        updated_at INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE questions (
        id TEXT PRIMARY KEY,
        bank_id TEXT NOT NULL,
        raw_text TEXT NOT NULL,
        preprocessed_text TEXT NOT NULL,
        answer TEXT NOT NULL,
        explanation TEXT,
        created_at INTEGER,
        FOREIGN KEY (bank_id) REFERENCES question_banks(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE recognition_history (
        id TEXT PRIMARY KEY,
        ocr_text TEXT,
        matched_question TEXT,
        matched_answer TEXT,
        confidence REAL,
        match_level TEXT,
        bank_id TEXT,
        timestamp INTEGER
      )
    ''');

    await db.execute(
        'CREATE INDEX idx_questions_bank ON questions(bank_id)');
    await db.execute(
        'CREATE INDEX idx_history_timestamp ON recognition_history(timestamp DESC)');
  }

  // ==================== 题库 CRUD ====================

  static Future<List<QuestionBank>> getBanks() async {
    final db = await database;
    final maps = await db.query('question_banks', orderBy: 'is_default DESC, updated_at DESC');
    return maps.map((m) => QuestionBank.fromMap(m)).toList();
  }

  static Future<QuestionBank?> getBank(String bankId) async {
    final db = await database;
    final maps = await db.query(
      'question_banks',
      where: 'id = ?',
      whereArgs: [bankId],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return QuestionBank.fromMap(maps.first);
  }

  static Future<QuestionBank?> getDefaultBank() async {
    final db = await database;
    final maps = await db.query(
      'question_banks',
      where: 'is_default = ?',
      whereArgs: [1],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return QuestionBank.fromMap(maps.first);
  }

  static Future<QuestionBank> createBank(String name, String? sourceFile) async {
    final db = await database;
    final now = DateTime.now();
    final bank = QuestionBank(
      id: _uuid.v4(),
      name: name,
      sourceFile: sourceFile,
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('question_banks', bank.toMap());
    return bank;
  }

  static Future<void> deleteBank(String bankId) async {
    final db = await database;
    await db.delete('questions', where: 'bank_id = ?', whereArgs: [bankId]);
    await db.delete('question_banks', where: 'id = ?', whereArgs: [bankId]);
  }

  static Future<void> setDefaultBank(String bankId) async {
    final db = await database;
    // 两步更新必须在同一事务中：防止步骤1成功、步骤2前崩溃导致所有题库都非默认
    await db.transaction((txn) async {
      await txn.update('question_banks', {'is_default': 0});
      await txn.update(
        'question_banks',
        {'is_default': 1},
        where: 'id = ?',
        whereArgs: [bankId],
      );
    });
  }

  // ==================== 题目 CRUD ====================

  static Future<void> insertQuestions(
      String bankId, List<Question> questions) async {
    final db = await database;
    final batch = db.batch();
    for (final q in questions) {
      batch.insert('questions', q.toMap());
    }
    await batch.commit(noResult: true);

    // 更新题目计数
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM questions WHERE bank_id = ?', [bankId]),
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      'question_banks',
      {'question_count': count, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [bankId],
    );
  }

  static Future<int> getQuestionCount(String bankId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as c FROM questions WHERE bank_id = ?',
      [bankId],
    );
    return result.first['c'] as int;
  }

  static Future<List<QuestionPair>> getQuestionPairs(String bankId) async {
    final db = await database;
    final maps = await db.query(
      'questions',
      columns: ['raw_text', 'answer', 'explanation'],
      where: 'bank_id = ?',
      whereArgs: [bankId],
    );
    return maps
        .map((m) => QuestionPair(
              question: m['raw_text'] as String,
              answer: m['answer'] as String,
              explanation: m['explanation'] as String?,
            ))
        .toList();
  }

  // ==================== 历史记录 ====================

  static Future<void> saveHistory(RecognitionHistory history) async {
    final db = await database;
    await db.insert('recognition_history', history.toMap());
  }
}
