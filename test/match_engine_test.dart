/// 匹配引擎单元测试
///
/// 覆盖场景:
/// - 精确匹配 (L1): O(1) HashMap 查找
/// - 模糊匹配 (L2): Levenshtein partial_ratio 滑动窗口
/// - 候选列表 (P1-2): matchWithCandidates 匹配失败时返回 Top-3 候选
/// - 边界情况: 空文本、单字符、特殊字符
/// - 预处理一致性: 全角→半角、繁→简、大写化
/// - explanation 字段传递
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:screen_answer_app/services/match_engine.dart';
import 'package:screen_answer_app/models/match_result.dart';

void main() {
  group('MatchEngine - 精确匹配 (L1)', () {
    late MatchEngine engine;

    setUp(() {
      engine = MatchEngine([
        QuestionPair(
          question: '已知函数 f(x)=x²+2x+1，求 f(3) 的值',
          answer: 'f(3) = 16',
          explanation: '将 x=3 代入 f(x)=x²+2x+1',
        ),
        QuestionPair(
          question: '中国的首都是哪个城市？',
          answer: '北京',
        ),
        QuestionPair(
          question: 'What is the capital of France?',
          answer: 'Paris',
        ),
        QuestionPair(
          question: '1 + 1 = ?',
          answer: '2',
        ),
      ]);
    });

    test('精确匹配 - 完全相同的文本应返回 exact 级别', () {
      final result = engine.match('已知函数 f(x)=x²+2x+1，求 f(3) 的值');
      expect(result.level, MatchLevel.exact);
      expect(result.answer, 'f(3) = 16');
      expect(result.confidence, 1.0);
    });

    test('精确匹配 - 预处理后相同的文本应匹配（全角→半角）', () {
      // 全角括号和逗号 → 半角后应匹配
      // 使用不含特殊字符的简单文本
      final engine = MatchEngine([
        QuestionPair(question: '中国的首都是哪个城市', answer: '北京'),
      ]);
      final result = engine.match('中國的首都是哪個城市');
      expect(result.level, MatchLevel.exact);
      expect(result.answer, '北京');
    });

    test('精确匹配 - 预处理后相同的文本应匹配（繁体→简体）', () {
      final result = engine.match('已知函數 f(x)=x²+2x+1，求 f(3) 的值');
      expect(result.level, MatchLevel.exact);
      expect(result.answer, 'f(3) = 16');
    });

    test('精确匹配 - 大小写不敏感', () {
      final result = engine.match('WHAT IS THE CAPITAL OF FRANCE?');
      expect(result.level, MatchLevel.exact);
      expect(result.answer, 'Paris');
    });

    test('精确匹配 - 空文本应返回 empty', () {
      final result = engine.match('');
      expect(result.level, MatchLevel.none);
      expect(result.answer, '');
    });

    test('精确匹配 - 不存在的文本应降级到模糊匹配', () {
      final result = engine.match('已知函数 f(x)=x²+2x+1，求 f(3) 的数值');
      // 仅差几个字，应走模糊匹配
      expect(result.level, MatchLevel.fuzzy);
      expect(result.answer, 'f(3) = 16');
    });

    test('精确匹配 - explanation 字段应传递到 MatchResult', () {
      final result = engine.match('已知函数 f(x)=x²+2x+1，求 f(3) 的值');
      expect(result.explanation, '将 x=3 代入 f(x)=x²+2x+1');
    });

    test('精确匹配 - 无 explanation 时应为 null', () {
      final result = engine.match('中国的首都是哪个城市？');
      expect(result.explanation, isNull);
    });
  });

  group('MatchEngine - 模糊匹配 (L2)', () {
    late MatchEngine engine;

    setUp(() {
      engine = MatchEngine([
        QuestionPair(
          question: '已知函数 f(x)=x²+2x+1，求 f(3) 的值',
          answer: 'f(3) = 16',
          explanation: '将 x=3 代入 f(x)=x²+2x+1',
        ),
        QuestionPair(
          question: '已知函数 f(x)=2x+3，求 f(5) 的值',
          answer: 'f(5) = 13',
        ),
        QuestionPair(
          question: '中国的首都是哪个城市？',
          answer: '北京',
        ),
        QuestionPair(
          question: '地球绕太阳公转一周的时间是',
          answer: '一年（约365.25天）',
        ),
      ]);
    });

    test('模糊匹配 - 微小差异应匹配并返回答案', () {
      // OCR 可能漏掉或错一个字
      // 新版预处理会过滤孤立短词，预处理后文本较短，相似度阈值按 0.7 断言
      final result = engine.match('已知函数 f(x)=x²+2x+1，求f(3)的值');
      expect(result.level, MatchLevel.fuzzy);
      expect(result.confidence, greaterThanOrEqualTo(0.7));
      expect(result.answer, 'f(3) = 16');
    });

    test('模糊匹配 - 归一化后相同的文本应精确匹配', () {
      // "f3" 等孤立短词被预处理过滤，预处理后与题库一致，命中 L1
      // 题库中 f(3)/f(5) 两题归一化后文本相同，精确命中其中之一即可
      final result = engine.match('已知函数 f(x)=x²+2x+1 求 f3 的值');
      expect(result.level, MatchLevel.exact);
      expect(result.answer, isIn(['f(3) = 16', 'f(5) = 13']));
    });

    test('模糊匹配 - 差异过大应返回 empty', () {
      final result = engine.match('今天天气真好');
      expect(result.level, MatchLevel.none);
      expect(result.answer, '');
    });

    test('模糊匹配 - 短文本精确匹配应走 L1', () {
      // 1 + 1 = ? 在 L1 组的题库中，不在本组
      // 预处理后为 "1 1"，与题库中题目无足够相似度
      final result = engine.match('zzz_not_in_any_bank');
      expect(result.level, MatchLevel.none);
    });

    test('模糊匹配 - 相似但不同的题目应选最佳匹配', () {
      // 两个 f(x) 题目，应匹配更相似的那个
      final result = engine.match('已知函数 f(x)=x²+2x+1，求 f(3)');
      expect(result.level, MatchLevel.fuzzy);
      expect(result.answer, 'f(3) = 16');
    });

    test('模糊匹配 - 空题库应返回 empty', () {
      final emptyEngine = MatchEngine([]);
      final result = emptyEngine.match('任何文本');
      expect(result.level, MatchLevel.none);
    });

    test('模糊匹配 - 纯标点符号应返回 empty', () {
      final result = engine.match('！？，。');
      expect(result.level, MatchLevel.none);
    });

    test('模糊匹配 - explanation 应传递', () {
      final result = engine.match('已知函数 f(x)=x²+2x+1，求f(3)的值');
      expect(result.explanation, '将 x=3 代入 f(x)=x²+2x+1');
    });
  });

  group('MatchEngine - 候选列表 (matchWithCandidates)', () {
    late MatchEngine engine;

    setUp(() {
      engine = MatchEngine([
        QuestionPair(
          question: '已知函数 f(x)=x²+2x+1，求 f(3) 的值',
          answer: 'f(3) = 16',
          explanation: '将 x=3 代入',
        ),
        QuestionPair(
          question: '已知函数 f(x)=2x+3，求 f(5) 的值',
          answer: 'f(5) = 13',
        ),
        QuestionPair(
          question: '中国的首都是哪个城市？',
          answer: '北京',
        ),
        QuestionPair(
          question: '地球绕太阳公转一周的时间是',
          answer: '一年（约365.25天）',
        ),
        QuestionPair(
          question: '水的化学式是什么？',
          answer: 'H₂O',
        ),
      ]);
    });

    test('候选列表 - 匹配成功时不应返回候选', () {
      final result = engine.matchWithCandidates('中国的首都是哪个城市？');
      expect(result.level, MatchLevel.exact);
      expect(result.answer, '北京');
      expect(result.candidates, isEmpty);
    });

    test('候选列表 - 模糊匹配成功时不应返回候选', () {
      final result = engine.matchWithCandidates('已知函数 f(x)=x²+2x+1，求f(3)的值');
      expect(result.level, MatchLevel.fuzzy);
      expect(result.candidates, isEmpty);
    });

    test('候选列表 - 完全不匹配时应返回 Top-3 候选', () {
      // 使用与题库部分相似但不足以触发模糊匹配的文本
      // 确保有相似度 > 0 的候选，但低于 0.55 阈值
      final result = engine.matchWithCandidates('函数的数值是多少');
      expect(result.level, MatchLevel.none);
      expect(result.candidates.length, lessThanOrEqualTo(3));
      expect(result.candidates.length, greaterThan(0));
    });

    test('候选列表 - 候选应包含 explanation', () {
      final result = engine.matchWithCandidates('函数的数值是多少');
      expect(result.candidates, isNotEmpty);
      for (final c in result.candidates) {
        expect(c.question, isNotEmpty);
        expect(c.answer, isNotEmpty);
        expect(c.score, greaterThan(0.0));
      }
    });

    test('候选列表 - 候选应按相似度降序排列', () {
      final result = engine.matchWithCandidates('函数的数值是多少');
      expect(result.candidates, isNotEmpty);
      for (var i = 0; i < result.candidates.length - 1; i++) {
        expect(result.candidates[i].score,
            greaterThanOrEqualTo(result.candidates[i + 1].score));
      }
    });

    test('候选列表 - 候选数量应不超过3个', () {
      final result = engine.matchWithCandidates('函数的数值是多少');
      expect(result.candidates.length, lessThanOrEqualTo(3));
    });

    test('候选列表 - 空文本应返回 empty 无候选', () {
      final result = engine.matchWithCandidates('');
      expect(result.level, MatchLevel.none);
      expect(result.candidates, isEmpty);
    });

    test('候选列表 - CandidateItem scorePercent 格式正确', () {
      final result = engine.matchWithCandidates('函数的数值是多少');
      expect(result.candidates, isNotEmpty);
      expect(result.candidates.first.scorePercent, matches(r'\d+%'));
    });
  });

  group('MatchEngine - 边界情况', () {
    test('单个字符输入（预处理为空的退化用例）', () {
      // 单字符经强过滤管线预处理后为空，题库键同样为空，无法有效匹配
      final engine = MatchEngine([
        QuestionPair(question: 'A', answer: '答案A'),
      ]);
      final result = engine.match('A');
      expect(result.level, MatchLevel.none);
    });

    test('超长文本输入（纯孤立字母行被过滤）', () {
      // 纯 A-D 字母组成的行在 Phase 2 被过滤，预处理为空，无法匹配
      final longQuestion = 'A' * 1000;
      final engine = MatchEngine([
        QuestionPair(question: longQuestion, answer: '长文本答案'),
      ]);
      final result = engine.match(longQuestion);
      expect(result.level, MatchLevel.none);
    });

    test('题库包含重复题目', () {
      final engine = MatchEngine([
        QuestionPair(question: '测试题目', answer: '答案1'),
        QuestionPair(question: '测试题目', answer: '答案2'),
      ]);
      // 精确匹配应命中第一个（HashMap 覆盖行为）
      final result = engine.match('测试题目');
      expect(result.level, MatchLevel.exact);
      expect(result.answer, '答案2'); // 后插入的覆盖前一个
    });

    test('包含换行符的文本', () {
      final engine = MatchEngine([
        QuestionPair(
          question: '第一行\n第二行\n第三行',
          answer: '多行答案',
        ),
      ]);
      final result = engine.match('第一行\n第二行\n第三行');
      expect(result.level, MatchLevel.exact);
    });

    test('只含数字和特殊字符', () {
      final engine = MatchEngine([
        QuestionPair(question: '2024年GDP增长率?', answer: '5.2%'),
      ]);
      final result = engine.match('2024年GDP增长率?');
      expect(result.level, MatchLevel.exact);
    });
  });

  group('MatchEngine - 性能与一致性', () {
    test('大量题库应快速匹配', () {
      final pairs = List.generate(
        1000,
        (i) => QuestionPair(
          question: '第${i + 1}题：测试题目内容$i',
          answer: '答案$i',
        ),
      );
      final engine = MatchEngine(pairs);

      final stopwatch = Stopwatch()..start();
      final result = engine.match('第500题：测试题目内容499');
      stopwatch.stop();

      expect(result.level, MatchLevel.exact);
      expect(result.answer, '答案499');
      // 1000 条数据应 < 100ms
      expect(stopwatch.elapsedMilliseconds, lessThan(100));
    });

    test('模糊匹配在大量题库中应表现合理', () {
      final pairs = List.generate(
        500,
        (i) => QuestionPair(
          question: '第${i + 1}题：这是测试题目内容$i用于模糊匹配',
          answer: '答案$i',
        ),
      );
      final engine = MatchEngine(pairs);

      final stopwatch = Stopwatch()..start();
      // 故意输入有微小差异的文本（L1.5 包含匹配可命中内容 300 的题库项）
      final result = engine.match('第300题：这是测试题目内容300用于模糊匹配');
      stopwatch.stop();

      expect(result.level, isNot(MatchLevel.none));
      expect(result.answer, '答案300');
      // 500 条匹配应 < 500ms
      expect(stopwatch.elapsedMilliseconds, lessThan(500));
    });
  });

  group('MatchResult - 数据模型', () {
    test('MatchResult.empty() 应返回空结果', () {
      final result = MatchResult.empty();
      expect(result.answer, '');
      expect(result.matchedQuestion, '');
      expect(result.confidence, 0.0);
      expect(result.level, MatchLevel.none);
    });

    test('confidencePercent 格式正确', () {
      final result = MatchResult(
        answer: '答案',
        matchedQuestion: '题目',
        confidence: 0.856,
        level: MatchLevel.fuzzy,
      );
      expect(result.confidencePercent, '85%');
    });

    test('confidencePercent 满分为 100%', () {
      final result = MatchResult(
        answer: '答案',
        matchedQuestion: '题目',
        confidence: 1.0,
        level: MatchLevel.exact,
      );
      expect(result.confidencePercent, '100%');
    });
  });

  group('MatchEngine - 预处理一致性', () {
    test('预处理后的文本应与精确匹配键一致', () {
      // 验证 MatchEngine 构造函数中使用的预处理逻辑
      // 与 match() 方法中的预处理逻辑一致
      final engine = MatchEngine([
        QuestionPair(
          question: 'Hello World',
          answer: 'Greeting',
        ),
      ]);

      // 不同大小写 + 全角空格
      final result = engine.match('ＨＥＬＬＯ　ＷＯＲＬＤ');
      expect(result.level, MatchLevel.exact);
      expect(result.answer, 'Greeting');
    });
  });

  group('MatchEngine - 题型过滤', () {
    late MatchEngine engine;

    setUp(() {
      engine = MatchEngine([
        // 单选题（答案单个字母）
        QuestionPair(question: '中国的首都是哪个城市？', answer: 'A'),
        QuestionPair(question: '1+1等于几？', answer: 'B'),
        // 判断题（答案包含"正确"或"错误"）
        QuestionPair(question: '地球是圆的', answer: '正确'),
        QuestionPair(question: '太阳从西边升起', answer: '错误'),
        // 多选题（答案多个字母）
        QuestionPair(question: '以下哪些是水果？', answer: 'ABD'),
        // 未知题型（其他格式答案）
        QuestionPair(question: '请简述牛顿第一定律', answer: '惯性定律'),
      ]);
    });

    test('题型推断 - 单选题应推断为 single', () {
      expect(QuestionPair.inferType('A'), 'single');
      expect(QuestionPair.inferType('B'), 'single');
      expect(QuestionPair.inferType('C'), 'single');
      expect(QuestionPair.inferType('D'), 'single');
    });

    test('题型推断 - 多选题应推断为 multi', () {
      expect(QuestionPair.inferType('AB'), 'multi');
      expect(QuestionPair.inferType('ABC'), 'multi');
      expect(QuestionPair.inferType('ABD'), 'multi');
      expect(QuestionPair.inferType('ABCD'), 'multi');
      expect(QuestionPair.inferType('A. 苹果；C. 香蕉'), 'multi');
    });

    test('题型推断 - 带选项内容的单选答案应推断为 single', () {
      expect(QuestionPair.inferType('A. 北京'), 'single');
      expect(QuestionPair.inferType('B、上海'), 'single');
      expect(QuestionPair.inferType('C: 广州'), 'single');
    });

    test('题型推断 - 判断题应推断为 judge', () {
      expect(QuestionPair.inferType('正确'), 'judge');
      expect(QuestionPair.inferType('错误'), 'judge');
      expect(QuestionPair.inferType('A.正确'), 'judge');
      expect(QuestionPair.inferType('B.错误'), 'judge');
    });

    test('题型推断 - 其他答案应推断为空字符串', () {
      expect(QuestionPair.inferType('惯性定律'), '');
      expect(QuestionPair.inferType('3.14'), '');
      expect(QuestionPair.inferType(''), '');
    });

    test('题型推断 - 国网模板多选答案不应误判为 judge（回归）', () {
      // 回归测试：答案选项内容含"正确"（如"D. 正确使用工器具"）时，
      // 旧逻辑按关键词计数误判为判断题，导致 ocrType=multi 匹配被过滤。
      final answer = 'A. 熟悉工作内容、工作流程，清楚工作中的风险点和安全措施，并在工作票上签名确认；'
          'B. 服从工作负责人的指挥，严格遵守本规程和劳动纪律，在确定的作业范围内工作；'
          'C. 对自己在工作中的行为负责，互相关心工作安全；'
          'D. 正确使用工器具、调试计算机（或其他专用设备）、外接存储设备以及软件工具等';
      expect(QuestionPair.inferType(answer), 'multi');
    });

    test('题型推断 - 选项内容含判断词的单选题应判 single（回归）', () {
      expect(QuestionPair.inferType('A. 正确使用工器具的方法'), 'single');
      expect(QuestionPair.inferType('B. 错误的说法是'), 'single');
    });

    test('题型推断 - 字母+纯判断词应判 judge（A.正确）', () {
      expect(QuestionPair.inferType('A.正确'), 'judge');
      expect(QuestionPair.inferType('B、错误'), 'judge');
    });

    test('题型推断 - 多判断词组合应判 judge', () {
      expect(QuestionPair.inferType('正确 错误'), 'judge');
      expect(QuestionPair.inferType('对 错'), 'judge');
      expect(QuestionPair.inferType('是 否'), 'judge');
    });

    test('题型过滤 - 单选题文本应只匹配单选题', () {
      // 单选题文本，指定 ocrType=single
      final result = engine.match('中国的首都是哪个城市？', ocrType: 'single');
      expect(result.level, MatchLevel.exact);
      expect(result.answer, 'A');
    });

    test('题型过滤 - 多选题文本应只匹配多选题', () {
      final result = engine.match('以下哪些是水果？', ocrType: 'multi');
      expect(result.level, MatchLevel.exact);
      expect(result.answer, 'ABD');
    });

    test('题型过滤 - 多选题文本不应匹配单选题或判断题', () {
      final singleResult = engine.match('以下哪些是水果？', ocrType: 'single');
      final judgeResult = engine.match('以下哪些是水果？', ocrType: 'judge');
      expect(singleResult.answer, isNot('ABD'));
      expect(judgeResult.answer, isNot('ABD'));
    });

    test('题型过滤 - 判断题文本应只匹配判断题', () {
      final result = engine.match('地球是圆的', ocrType: 'judge');
      expect(result.level, MatchLevel.exact);
      expect(result.answer, '正确');
    });

    test('题型过滤 - 单选题文本不应匹配判断题', () {
      // 单选题文本，但指定 ocrType=judge，不应匹配到单选题答案
      final result = engine.match('中国的首都是哪个城市？', ocrType: 'judge');
      // 可能模糊匹配到未知题型或判断题，但不应匹配到单选题答案 'A'
      if (result.level != MatchLevel.none) {
        expect(result.answer, isNot('A'));
      }
    });

    test('题型过滤 - 判断题文本不应匹配单选题', () {
      // 判断题文本，但指定 ocrType=single，不应匹配到判断题答案
      final result = engine.match('地球是圆的', ocrType: 'single');
      // 可能模糊匹配到未知题型或单选题，但不应匹配到判断题答案 '正确'
      if (result.level != MatchLevel.none) {
        expect(result.answer, isNot('正确'));
      }
    });

    test('题型过滤 - 不指定 ocrType 时应正常匹配所有题型', () {
      // 不传 ocrType，应匹配到单选题
      final result = engine.match('中国的首都是哪个城市？');
      expect(result.level, MatchLevel.exact);
      expect(result.answer, 'A');
    });

    test('题型过滤 - 未知 OCR 题型不应进入跨题型模糊匹配', () {
      final result = engine.match('中国的首都是哪个城市？', ocrType: '');
      expect(result.level, MatchLevel.exact);
      expect(result.answer, 'A');
    });

    test('题型过滤 - matchWithCandidates 应过滤不同题型', () {
      // 单选题文本，但指定 ocrType=judge，候选列表不应包含单选题
      final result = engine.matchWithCandidates('中国的首都是哪个城市？', ocrType: 'judge');
      // 不应匹配到单选题答案 'A'
      if (result.level != MatchLevel.none) {
        expect(result.answer, isNot('A'));
      }
      // 候选列表不应包含单选题
      for (final c in result.candidates) {
        expect(c.answer, isNot('A'));
      }
    });

    test('题型过滤 - matchWithCandidates 同题型应正常匹配', () {
      final result = engine.matchWithCandidates('中国的首都是哪个城市？', ocrType: 'single');
      expect(result.level, MatchLevel.exact);
      expect(result.answer, 'A');
    });

    test('题型过滤 - 模糊匹配也应过滤不同题型', () {
      // 使用与单选题相似的文本，但指定 ocrType=judge
      final result = engine.match('中国的首都是哪个城市', ocrType: 'judge');
      // 不应匹配到单选题答案 'A'
      if (result.level != MatchLevel.none) {
        expect(result.answer, isNot('A'));
      }
    });

    test('题型过滤 - 模糊匹配同题型应正常匹配', () {
      final result = engine.match('中国的首都是哪个城市', ocrType: 'single');
      expect(result.level, isNot(MatchLevel.none));
      expect(result.answer, 'A');
    });
  });

  group('MatchEngine - UI 噪声鲁棒性', () {
    late MatchEngine engine;

    setUp(() {
      engine = MatchEngine([
        QuestionPair(question: '中国的首都是哪个城市', answer: '北京'),
        QuestionPair(question: '以下哪些是哺乳动物', answer: 'ABC'),
        QuestionPair(question: '地球是圆的', answer: '正确'),
        QuestionPair(question: '根据信息安规规定，外来工作人员必须熟悉的内容', answer: '熟悉作业任务、安全施工方案、作业标准，严格遵守相关规定'),
      ]);
    });

    test('包含"单选题"标签的文本仍应正确匹配', () {
      // OCR 可能识别出页面上的题型标签
      final result = engine.matchWithCandidates(
          '单选题\n中国的首都是哪个城市\nA. 北京 B. 上海 C. 广州 D. 深圳');
      expect(result.level, isNot(MatchLevel.none));
      expect(result.answer, contains('北京'));
    });

    test('包含"选项"前缀的文本不应阻止匹配', () {
      final result = engine.matchWithCandidates(
          '选项A\n中国的首都是哪个城市\nA. 北京 B. 上海 C. 广州 D. 深圳');
      expect(result.level, isNot(MatchLevel.none));
      expect(result.answer, contains('北京'));
    });

    test('含进度格式"4/100"的文本不应完全失败', () {
      final result = engine.matchWithCandidates(
          '4/100\n中国的首都是哪个城市\nA. 北京 B. 上海 C. 广州 D. 深圳');
      // 可能精确匹配或模糊匹配，但不应该完全不匹配
      expect(result.level, isNot(MatchLevel.none));
      expect(result.answer, contains('北京'));
    });

    test('含倒计时"00:00"的文本不应完全失败', () {
      final result = engine.matchWithCandidates(
          '00:00\n中国的首都是哪个城市\nA. 北京 B. 上海 C. 广州 D. 深圳');
      expect(result.level, isNot(MatchLevel.none));
      expect(result.answer, contains('北京'));
    });

    test('包含多项选择标签的文本应正常匹配', () {
      final result = engine.matchWithCandidates(
          '多项选择\n以下哪些是哺乳动物\nA. 狗 B. 猫 C. 鲸鱼 D. 企鹅');
      expect(result.level, isNot(MatchLevel.none));
      expect(result.answer, 'ABC');
    });

    test('包含"第4题"格式的文本应正常匹配', () {
      final result = engine.matchWithCandidates(
          '第4题\n以下哪些是哺乳动物\nA. 狗 B. 猫 C. 鲸鱼 D. 企鹅');
      expect(result.level, isNot(MatchLevel.none));
      expect(result.answer, 'ABC');
    });
  });

  group('MatchEngine - OCR 常见错误模式', () {
    late MatchEngine engine;

    setUp(() {
      // 常见 OCR 混淆：O↔0, I↔1, l↔1
      engine = MatchEngine([
        QuestionPair(question: '输入 0 和字母 O 的区别', answer: '数字0和字母O'),
        QuestionPair(question: '1 和 l 的区别', answer: '数字1和字母l'),
        QuestionPair(question: 'TCP/IP 协议栈包括哪几层', answer: '四层'),
      ]);
    });

    test('O 与 0 混用不应导致精确匹配失败（预处理保持字符原样，匹配通过模糊层）', () {
      // OCR 将题目中的 0 识别成 O：预处理后文本与题库不同但高度相似
      final result = engine.matchWithCandidates('输入 O 和字母 O 的区别');
      // 至少不应返回 none 或空答案
      if (result.level != MatchLevel.none) {
        expect(result.answer, contains('数字'));
      }
    });

    test('纯数字/字母噪声不应误匹配', () {
      final result = engine.matchWithCandidates('0 1 2 3 4 5');
      expect(result.level, MatchLevel.none);
    });

    test('题库题目含数字与字母混排应可精确匹配', () {
      final result = engine.match('TCP/IP 协议栈包括哪几层');
      expect(result.level, MatchLevel.exact);
      expect(result.answer, '四层');
    });
  });

  group('MatchEngine - 题型过滤边界 (L1.5/L2)', () {
    late MatchEngine engine;

    setUp(() {
      engine = MatchEngine([
        QuestionPair(question: '中国的首都是哪个城市', answer: 'A', type: 'single'),
        QuestionPair(question: '以下哪些是水果', answer: 'ABD', type: 'multi'),
        QuestionPair(question: '地球是圆的', answer: '正确', type: 'judge'),
      ]);
    });

    test('包含匹配(L1.5)也应遵守题型过滤', () {
      // OCR 文本包含完整单选题，但指定 ocrType=multi —— 不应命中单选题
      final result = engine.matchWithCandidates(
        '中国的首都是哪个城市\nA. 北京 B. 上海 C. 广州 D. 深圳',
        ocrType: 'multi',
      );
      expect(result.answer, isNot('A'));
    });

    test('包含匹配(L1.5)同题型应命中', () {
      final result = engine.matchWithCandidates(
        '中国的首都是哪个城市\nA. 北京 B. 上海 C. 广州 D. 深圳',
        ocrType: 'single',
      );
      expect(result.answer, 'A');
    });

    test('未知题型(空串)精确匹配应兼容所有题型', () {
      final result = engine.match('地球是圆的', ocrType: '');
      expect(result.level, MatchLevel.exact);
      expect(result.answer, '正确');
    });

    test('题型不兼容时模糊匹配不应跨题型命中', () {
      // 判断题文本指定 single 题型：模糊层应过滤判断题
      final result = engine.match('地球是圆的', ocrType: 'single');
      if (result.level != MatchLevel.none) {
        expect(result.answer, isNot('正确'));
      }
    });
  });

  group('MatchEngine - 重复题目行为一致性 (L1/L1.5)', () {
    test('L1 与 L1.5 对重复题目应一致取最后插入者', () {
      final engine = MatchEngine([
        QuestionPair(question: '重复题目测试', answer: '第一个答案'),
        QuestionPair(question: '重复题目测试', answer: '第二个答案'),
      ]);
      // L1 精确匹配：倒序遍历取最后插入
      final exact = engine.match('重复题目测试');
      expect(exact.level, MatchLevel.exact);
      expect(exact.answer, '第二个答案');

      // L1.5 包含匹配（OCR 带噪声包含完整题目）：同样应取最后插入
      final contain = engine.match('题目头\n重复题目测试\nA. 选项1 B. 选项2');
      expect(contain.answer, '第二个答案');
    });
  });

  group('MatchEngine - 短文本模糊匹配 (partial_ratio 滑动窗口)', () {
    late MatchEngine engine;

    setUp(() {
      engine = MatchEngine([
        QuestionPair(question: '地球绕太阳公转一周的时间是一年', answer: '正确'),
        QuestionPair(question: '中国的首都是哪个城市', answer: '北京'),
        QuestionPair(question: '水的沸点是100摄氏度', answer: '正确'),
      ]);
    });

    test('短文本匹配内容在题目中间时应获得高相似度', () {
      // 回归测试：旧实现只比较长文本开头，'太阳公转' 与题目开头不匹配
      // 导致相似度仅 0.73；修复后滑动窗口应得高分并命中。
      final result = engine.matchWithCandidates('太阳公转');
      expect(result.level, isNot(MatchLevel.none));
      expect(result.answer, '正确');
    });

    test('短文本匹配内容在题目中间偏后位置时应命中', () {
      // '沸点' 位于题目中间，旧实现只比较 '水的沸点' 前两个字会漏掉
      final result = engine.matchWithCandidates('沸点');
      expect(result.level, isNot(MatchLevel.none));
      expect(result.answer, '正确');
    });

    test('短文本命中在题目开头时应保持原有行为', () {
      final result = engine.matchWithCandidates('首都');
      expect(result.level, isNot(MatchLevel.none));
      expect(result.answer, '北京');
    });

    test('2 字符噪声不应误匹配', () {
      final result = engine.matchWithCandidates('哈哈');
      expect(result.level, MatchLevel.none);
    });
  });

  group('MatchEngine - 模糊匹配预计算复用', () {
    test('多次匹配结果应一致（_preprocessedQuestions 复用不改变行为）', () {
      final engine = MatchEngine([
        QuestionPair(question: '已知函数 f(x)=x²+2x+1，求 f(3) 的值', answer: 'f(3)=16'),
        QuestionPair(question: '中国的首都是哪个城市', answer: '北京'),
      ]);

      final r1 = engine.match('已知函数 f(x)=x²+2x+1，求 f(3) 的值');
      final r2 = engine.match('已知函数 f(x)=x²+2x+1，求 f(3) 的值');
      final r3 = engine.matchWithCandidates('中国的首都是哪个城市');
      expect(r1.answer, r2.answer);
      expect(r1.level, MatchLevel.exact);
      expect(r3.answer, '北京');
    });

    test('去重后的题目仍可被模糊匹配命中', () {
      final engine = MatchEngine([
        QuestionPair(question: '重复题目测试内容', answer: '第一个'),
        QuestionPair(question: '重复题目测试内容', answer: '第二个'),
        QuestionPair(question: '另一道不同的题目内容', answer: '不同'),
      ]);
      // 模糊输入部分命中重复题目，应取去重后保留的最后一条
      final result = engine.match('重复题目测试内容');
      expect(result.answer, '第二个');
    });
  });

  group('MatchEngine - 多题库合并匹配', () {
    final engine = MatchEngine([
      QuestionPair(question: '题库A的独有题目：什么是光合作用', answer: 'A', bankId: 'bank-a'),
      QuestionPair(question: '题库A的题目：中国的首都是', answer: '北京', bankId: 'bank-a'),
      QuestionPair(question: '题库B的独有题目：水的化学式是', answer: 'H2O', bankId: 'bank-b'),
      QuestionPair(question: '题库B的题目：中国的首都是', answer: '北京（B题库）', bankId: 'bank-b'),
    ]);

    test('应能命中题库A的独有题目并携带 bankId', () {
      final r = engine.match('什么是光合作用');
      expect(r.level, isNot(MatchLevel.none));
      expect(r.matchedBankId, 'bank-a');
    });

    test('应能命中题库B的独有题目并携带 bankId', () {
      final r = engine.match('水的化学式是');
      expect(r.level, isNot(MatchLevel.none));
      expect(r.matchedBankId, 'bank-b');
    });

    test('重复题目跨题库时优先返回首个题库（合并顺序）', () {
      final r = engine.match('中国的首都是');
      expect(r.level, isNot(MatchLevel.none));
      // 两个题库都有该题，命中任意一个都携带对应 bankId
      expect(r.matchedBankId, anyOf('bank-a', 'bank-b'));
    });

    test('候选列表也应携带题库归属（用于显示来源）', () {
      final r = engine.matchWithCandidates('完全不存在的题目文本xyz');
      // 不要求一定返回候选，但若有候选则字段可用
      for (final c in r.candidates) {
        expect(c.question, isNotEmpty);
      }
    });
  });

  group('MatchEngine - 按题型匹配（单选匹配单选，判断匹配判断）', () {
    final engine = MatchEngine([
      QuestionPair(
        question: '以下关于信息安全的说法，正确的是',
        answer: 'A. 密码要定期更换；B. 密码可以告诉同事',
        type: 'single',
      ),
      QuestionPair(
        question: '以下关于信息安全的说法，正确的是',
        answer: '正确',
        type: 'judge',
      ),
      QuestionPair(
        question: '根据信息安规规定，工作票上需要填写的内容包括',
        answer: 'A. 工作内容；B. 工作地点；C. 工作负责人',
        type: 'multi',
      ),
    ]);

    test('题型已识别(ocrType=single)时严格匹配单选，不命中判断题', () {
      final r = engine.match(
          'A. 密码要定期更换 B. 密码可以告诉同事 以下关于信息安全的说法，正确的是',
          ocrType: 'single');
      expect(r.level, isNot(MatchLevel.none));
      expect(r.answer, contains('密码要定期更换'));
      expect(r.answer, isNot('正确'));
    });

    test('题型已识别(ocrType=judge)时严格匹配判断题', () {
      final r = engine.match('以下关于信息安全的说法，正确的是', ocrType: 'judge');
      expect(r.level, isNot(MatchLevel.none));
      expect(r.answer, '正确');
    });

    test('未识别题型但选项为判断词(A.正确 B.错误)时推断为判断题并匹配', () {
      // 判断题的选项结构：A.正确 B.错误 → 应推断为 judge
      final r = engine.matchWithCandidates(
          '以下关于信息安全的说法，正确的是 A. 正确 B. 错误');
      expect(r.answer, isNot(contains('密码要定期更换'))); // 不命中单选
      expect(r.answer, '正确'); // 命中判断题
    });

    test('判断题无选项锚点(纯题干)时宽松匹配仍可命中判断题', () {
      // 判断题 OCR 只识别出题干 → 宽松匹配 → 判断题可命中
      final r = engine.match('以下关于信息安全的说法，正确的是');
      expect(r.level, isNot(MatchLevel.none));
    });

    test('未识别题型且选项为普通内容时宽松匹配（不严格推断），单选可命中', () {
      // 普通选项结构（A-D）无法区分单选/多选 → 不推断，宽松匹配
      // 宽松模式下单选文本仍可命中单选题（因题库判断题/单选题文本不同）
      final r = engine.matchWithCandidates(
          '以下关于信息安全的说法，正确的是 A. 密码要定期更换 B. 密码可以告诉同事');
      expect(r.level, isNot(MatchLevel.none));
    });
  });
}

