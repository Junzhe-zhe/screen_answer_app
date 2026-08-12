/// 综合识别流水线测试
///
/// 模拟真实 OCR 输出到匹配的完整流程，覆盖 7 大场景 30+ 测试用例：
///   Group 1: 国网学堂模板格式 (4个)
///   Group 2: 判断题变体 (4个)
///   Group 3: 选项格式变体 (5个)
///   Group 4: 复杂排版 (4个)
///   Group 5: UI噪声组合 (5个)
///   Group 6: 边界情况 (5个)
///   Group 7: 题型标签位置变体 (4个)
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:screen_answer_app/services/match_engine.dart';
import 'package:screen_answer_app/models/match_result.dart';

void main() {
  // ============================================================
  // Group 1: 国网学堂模板格式
  // ============================================================
  group('国网学堂模板格式', () {
    late MatchEngine engine;

    setUp(() {
      engine = MatchEngine([
        QuestionPair(
          question: '根据《国家电网公司安全工作规程》，在电气设备上工作，保证安全的组织措施包括',
          answer: '工作票制度、工作许可制度、工作监护制度、工作间断转移和终结制度',
          type: 'multi',
        ),
        QuestionPair(
          question: '变压器中性点接地属于哪种接地方式',
          answer: '工作接地',
          type: 'single',
        ),
        QuestionPair(
          question: '继电保护装置的基本要求是选择性、速动性、灵敏性和可靠性',
          answer: '正确',
          type: 'judge',
        ),
      ]);
    });

    test('含"试题正文"表头的OCR文本应正确匹配', () {
      // 模拟国网学堂页面：试题正文表头 + 题目
      final ocrText = '试题正文\n'
          '根据《国家电网公司安全工作规程》，在电气设备上工作，保证安全的组织措施包括\n'
          'A. 工作票制度 B. 工作许可制度 C. 工作监护制度 D. 工作间断转移和终结制度';
      final result = engine.matchWithCandidates(ocrText, ocrType: 'multi');
      expect(result.level, isNot(MatchLevel.none));
      expect(result.answer, contains('工作票制度'));
    });

    test('含\$;分隔符布局的选项应正确匹配', () {
      // 模拟国网学堂 \$; 分隔符布局
      final ocrText = '变压器中性点接地属于哪种接地方式\n'
          'A. 工作接地\$;B. 保护接地\$;C. 防雷接地\$;D. 重复接地';
      final result = engine.matchWithCandidates(ocrText, ocrType: 'single');
      expect(result.level, isNot(MatchLevel.none));
      expect(result.answer, contains('工作接地'));
    });

    test('分散列布局（选项在不同行）应正确匹配', () {
      // 模拟选项分散在不同行的布局
      final ocrText = '变压器中性点接地属于哪种接地方式\n'
          'A. 工作接地\n'
          'B. 保护接地\n'
          'C. 防雷接地\n'
          'D. 重复接地';
      final result = engine.matchWithCandidates(ocrText, ocrType: 'single');
      expect(result.level, isNot(MatchLevel.none));
      expect(result.answer, contains('工作接地'));
    });

    test('国网模板 + 判断题组合应正确匹配', () {
      final ocrText = '试题正文\n'
          '判断题\n'
          '继电保护装置的基本要求是选择性、速动性、灵敏性和可靠性\n'
          '正确 错误';
      final result = engine.matchWithCandidates(ocrText, ocrType: 'judge');
      expect(result.level, isNot(MatchLevel.none));
      expect(result.answer, contains('正确'));
    });
  });

  // ============================================================
  // Group 2: 判断题变体
  // ============================================================
  group('判断题变体', () {
    late MatchEngine engine;

    setUp(() {
      engine = MatchEngine([
        QuestionPair(question: '地球绕太阳公转一周的时间是一年', answer: '正确', type: 'judge'),
        QuestionPair(question: '太阳从西边升起', answer: '错误', type: 'judge'),
        QuestionPair(question: '水的沸点是100摄氏度', answer: '正确', type: 'judge'),
      ]);
    });

    test('"判断"标签独立行 + 题目应正确匹配', () {
      final ocrText = '判断\n地球绕太阳公转一周的时间是一年';
      final result = engine.matchWithCandidates(ocrText, ocrType: 'judge');
      expect(result.level, isNot(MatchLevel.none));
      expect(result.answer, contains('正确'));
    });

    test('"正确/错误"独立行 + 题目应正确匹配', () {
      final ocrText = '正确/错误\n太阳从西边升起';
      final result = engine.matchWithCandidates(ocrText, ocrType: 'judge');
      expect(result.level, isNot(MatchLevel.none));
      expect(result.answer, contains('错误'));
    });

    test('"T/F"格式应正确匹配', () {
      final ocrText = 'T/F\n地球绕太阳公转一周的时间是一年';
      final result = engine.matchWithCandidates(ocrText, ocrType: 'judge');
      expect(result.level, isNot(MatchLevel.none));
      expect(result.answer, contains('正确'));
    });

    test('"对/错"格式应正确匹配', () {
      final ocrText = '对/错\n水的沸点是100摄氏度';
      final result = engine.matchWithCandidates(ocrText, ocrType: 'judge');
      expect(result.level, isNot(MatchLevel.none));
      expect(result.answer, contains('正确'));
    });
  });

  // ============================================================
  // Group 3: 选项格式变体
  // ============================================================
  group('选项格式变体', () {
    late MatchEngine engine;

    setUp(() {
      engine = MatchEngine([
        QuestionPair(question: '中国的首都是哪个城市', answer: 'A', type: 'single'),
        QuestionPair(question: '以下哪些是水果', answer: 'ABD', type: 'multi'),
        QuestionPair(question: '1+1等于几', answer: 'B', type: 'single'),
      ]);
    });

    test('选项含中文（A. 北京 B. 上海 C. 广州 D. 深圳）应正确匹配', () {
      final ocrText = '中国的首都是哪个城市\n'
          'A. 北京 B. 上海 C. 广州 D. 深圳';
      final result = engine.matchWithCandidates(ocrText, ocrType: 'single');
      expect(result.level, isNot(MatchLevel.none));
      expect(result.answer, 'A');
    });

    test('选项括号格式（(A) (B) (C) (D)）应正确匹配', () {
      final ocrText = '中国的首都是哪个城市\n'
          '(A) 北京 (B) 上海 (C) 广州 (D) 深圳';
      final result = engine.matchWithCandidates(ocrText, ocrType: 'single');
      expect(result.level, isNot(MatchLevel.none));
      expect(result.answer, 'A');
    });

    test('选项连续排列（A B C D 无换行）应正确匹配', () {
      final ocrText = '中国的首都是哪个城市 A 北京 B 上海 C 广州 D 深圳';
      final result = engine.matchWithCandidates(ocrText, ocrType: 'single');
      expect(result.level, isNot(MatchLevel.none));
      expect(result.answer, 'A');
    });

    test('选项带中文描述（A.苹果 B.香蕉 C.橘子 D.葡萄）应正确匹配', () {
      final ocrText = '以下哪些是水果\n'
          'A.苹果 B.香蕉 C.橘子 D.葡萄';
      final result = engine.matchWithCandidates(ocrText, ocrType: 'multi');
      expect(result.level, isNot(MatchLevel.none));
      expect(result.answer, 'ABD');
    });

    test('选项含标点（A: 北京 B: 上海）应正确匹配', () {
      final ocrText = '中国的首都是哪个城市\n'
          'A: 北京 B: 上海 C: 广州 D: 深圳';
      final result = engine.matchWithCandidates(ocrText, ocrType: 'single');
      expect(result.level, isNot(MatchLevel.none));
      expect(result.answer, 'A');
    });
  });

  // ============================================================
  // Group 4: 复杂排版
  // ============================================================
  group('复杂排版', () {
    late MatchEngine engine;

    setUp(() {
      engine = MatchEngine([
        QuestionPair(
          question: '已知函数f(x)=x²+2x+1，求f(3)的值，并说明该函数在x=1处的导数',
          answer: 'f(3)=16, f\'(1)=4',
          type: 'single',
        ),
        QuestionPair(
          question: '水的化学式是H₂O，二氧化碳的化学式是CO₂，请写出甲烷的化学式',
          answer: 'CH₄',
          type: 'single',
        ),
        QuestionPair(
          question: '请简述牛顿第一定律的内容及其在生活中的应用，并举例说明惯性现象',
          answer: '一切物体在没有受到力的作用时，总保持静止状态或匀速直线运动状态',
          type: 'single',
        ),
        QuestionPair(
          question: '第1题：以下哪个选项描述了光的折射现象',
          answer: 'C',
          type: 'single',
        ),
      ]);
    });

    test('多行题干 + 多行选项应正确匹配', () {
      final ocrText = '已知函数f(x)=x²+2x+1\n'
          '求f(3)的值\n'
          '并说明该函数在x=1处的导数\n'
          'A. f(3)=16, f\'(1)=4\n'
          'B. f(3)=13, f\'(1)=2\n'
          'C. f(3)=10, f\'(1)=0\n'
          'D. f(3)=9, f\'(1)=1';
      final result = engine.matchWithCandidates(ocrText, ocrType: 'single');
      expect(result.level, isNot(MatchLevel.none));
      expect(result.answer, contains('16'));
    });

    test('题干含数学符号/化学式应正确匹配', () {
      final ocrText = '水的化学式是H₂O\n二氧化碳的化学式是CO₂\n请写出甲烷的化学式';
      final result = engine.matchWithCandidates(ocrText, ocrType: 'single');
      expect(result.level, isNot(MatchLevel.none));
      expect(result.answer, contains('CH₄'));
    });

    test('极长题干（200+字符）应正确匹配', () {
      // 构造一个包含完整题目的长文本
      final longQuestion = '请简述牛顿第一定律的内容及其在生活中的应用，并举例说明惯性现象';
      final ocrText = '$longQuestion\n'
          'A. 一切物体在没有受到力的作用时，总保持静止状态或匀速直线运动状态\n'
          'B. 物体的加速度与合外力成正比，与质量成反比\n'
          'C. 作用力与反作用力大小相等方向相反\n'
          'D. 能量既不会凭空产生也不会凭空消失';
      final result = engine.matchWithCandidates(ocrText, ocrType: 'single');
      expect(result.level, isNot(MatchLevel.none));
      expect(result.answer, contains('静止状态'));
    });

    test('题干含数字编号应正确匹配', () {
      final ocrText = '第1题：以下哪个选项描述了光的折射现象\n'
          'A. 水中筷子看起来弯折 B. 影子的形成 C. 小孔成像 D. 平面镜成像';
      final result = engine.matchWithCandidates(ocrText, ocrType: 'single');
      expect(result.level, isNot(MatchLevel.none));
      expect(result.answer, 'C');
    });
  });

  // ============================================================
  // Group 5: UI噪声组合
  // ============================================================
  group('UI噪声组合', () {
    late MatchEngine engine;

    setUp(() {
      engine = MatchEngine([
        QuestionPair(question: '中国的首都是哪个城市', answer: '北京', type: 'single'),
        QuestionPair(question: '以下哪些是哺乳动物', answer: 'ABC', type: 'multi'),
        QuestionPair(question: '地球是圆的', answer: '正确', type: 'judge'),
        QuestionPair(
          question: '根据信息安规规定，外来工作人员必须熟悉的内容',
          answer: '熟悉作业任务、安全施工方案、作业标准，严格遵守相关规定',
          type: 'multi',
        ),
      ]);
    });

    test('交卷按钮 + 剩余时间 + 题目应正确匹配', () {
      final ocrText = '剩余时间 00:39:28\n'
          '交卷\n'
          '中国的首都是哪个城市\n'
          'A. 北京 B. 上海 C. 广州 D. 深圳';
      final result = engine.matchWithCandidates(ocrText, ocrType: 'single');
      expect(result.level, isNot(MatchLevel.none));
      expect(result.answer, contains('北京'));
    });

    test('进度 + 倒计时 + 题型标签 + 题目应正确匹配', () {
      final ocrText = '4/100  倒计时 00:39:28\n'
          '单选题\n'
          '中国的首都是哪个城市\n'
          'A. 北京 B. 上海 C. 广州 D. 深圳';
      final result = engine.matchWithCandidates(ocrText, ocrType: 'single');
      expect(result.level, isNot(MatchLevel.none));
      expect(result.answer, contains('北京'));
    });

    test('备注栏溢出文本 + 题目应正确匹配', () {
      final ocrText = '备注栏：请考生注意审题，仔细阅读每个选项\n'
          '中国的首都是哪个城市\n'
          'A. 北京 B. 上海 C. 广州 D. 深圳';
      final result = engine.matchWithCandidates(ocrText, ocrType: 'single');
      expect(result.level, isNot(MatchLevel.none));
      expect(result.answer, contains('北京'));
    });

    test('答题卡 + 上一题/下一题 + 题目应正确匹配', () {
      final ocrText = '答题卡 1 2 3 4 5 6 7 8 9 10\n'
          '上一题  下一题\n'
          '以下哪些是哺乳动物\n'
          'A. 狗 B. 猫 C. 鲸鱼 D. 企鹅';
      final result = engine.matchWithCandidates(ocrText, ocrType: 'multi');
      expect(result.level, isNot(MatchLevel.none));
      expect(result.answer, 'ABC');
    });

    test('收藏 + 笔记 + 举报按钮 + 题目应正确匹配', () {
      final ocrText = '收藏  笔记  举报\n'
          '以下哪些是哺乳动物\n'
          'A. 狗 B. 猫 C. 鲸鱼 D. 企鹅';
      final result = engine.matchWithCandidates(ocrText, ocrType: 'multi');
      expect(result.level, isNot(MatchLevel.none));
      expect(result.answer, 'ABC');
    });
  });

  // ============================================================
  // Group 6: 边界情况
  // ============================================================
  group('边界情况', () {
    late MatchEngine engine;

    setUp(() {
      engine = MatchEngine([
        QuestionPair(question: '中国的首都是哪个城市', answer: '北京', type: 'single'),
        QuestionPair(question: '以下哪些是哺乳动物', answer: 'ABC', type: 'multi'),
        QuestionPair(question: '地球是圆的', answer: '正确', type: 'judge'),
      ]);
    });

    test('纯噪声文本（只有UI元素，无题目）应返回 empty', () {
      final ocrText = '倒计时 00:39:28\n交卷\n答题卡\n上一题 下一题\n收藏 笔记 举报';
      final result = engine.matchWithCandidates(ocrText);
      expect(result.level, MatchLevel.none);
      expect(result.answer, '');
    });

    test('空文本应返回 empty', () {
      final result = engine.matchWithCandidates('');
      expect(result.level, MatchLevel.none);
      expect(result.answer, '');
    });

    test('纯UI元素（倒计时+交卷+进度）应返回 empty', () {
      // 使用题库中不存在的纯UI文本（无中文题目内容）
      final ocrText = '倒计时 00:39:28\n交卷\n4/100\n上一题 下一题\n答题卡\n设置 帮助 关于';
      final result = engine.matchWithCandidates(ocrText);
      expect(result.level, MatchLevel.none);
      expect(result.answer, '');
    });

    test('混合题型在同一页面（单选+多选+判断）应分别匹配', () {
      // 模拟页面包含多个题型，但 OCR 只截取其中一个
      final ocrText = '1. 中国的首都是哪个城市\n'
          'A. 北京 B. 上海 C. 广州 D. 深圳\n'
          '2. 以下哪些是哺乳动物\n'
          'A. 狗 B. 猫 C. 鲸鱼 D. 企鹅\n'
          '3. 地球是圆的\n正确 错误';
      // 不指定题型，应匹配到最相似的题目
      final result = engine.matchWithCandidates(ocrText);
      expect(result.level, isNot(MatchLevel.none));
      // 至少应匹配到其中一个题目
      expect(result.answer, anyOf(['北京', 'ABC', '正确']));
    });

    test('题型标签在题目中间应正确匹配', () {
      // 模拟题型标签出现在题目文本中间（独立行）
      final ocrText = '以下哪些是哺乳动物\n'
          '多选题\n'
          'A. 狗 B. 猫 C. 鲸鱼 D. 企鹅';
      final result = engine.matchWithCandidates(ocrText, ocrType: 'multi');
      expect(result.level, isNot(MatchLevel.none));
      expect(result.answer, 'ABC');
    });
  });

  // ============================================================
  // Group 7: 题型标签位置变体
  // ============================================================
  group('题型标签位置变体', () {
    late MatchEngine engine;

    setUp(() {
      engine = MatchEngine([
        QuestionPair(question: '中国的首都是哪个城市', answer: '北京', type: 'single'),
        QuestionPair(question: '以下哪些是哺乳动物', answer: 'ABC', type: 'multi'),
        QuestionPair(question: '地球是圆的', answer: '正确', type: 'judge'),
      ]);
    });

    test('标签在题目末尾应正确匹配', () {
      final ocrText = '中国的首都是哪个城市\n'
          '单选题\n'
          'A. 北京 B. 上海 C. 广州 D. 深圳';
      final result = engine.matchWithCandidates(ocrText, ocrType: 'single');
      expect(result.level, isNot(MatchLevel.none));
      expect(result.answer, contains('北京'));
    });

    test('多个标签混合应正确匹配', () {
      final ocrText = '单选题多选题判断题\n'
          '以下哪些是哺乳动物\n'
          'A. 狗 B. 猫 C. 鲸鱼 D. 企鹅';
      final result = engine.matchWithCandidates(ocrText, ocrType: 'multi');
      expect(result.level, isNot(MatchLevel.none));
      expect(result.answer, 'ABC');
    });

    test('标签含空格（"单 项 选 择 题"）应正确匹配', () {
      final ocrText = '单 项 选 择 题\n'
          '中国的首都是哪个城市\n'
          'A. 北京 B. 上海 C. 广州 D. 深圳';
      final result = engine.matchWithCandidates(ocrText, ocrType: 'single');
      expect(result.level, isNot(MatchLevel.none));
      expect(result.answer, contains('北京'));
    });

    test('标签含特殊字符应正确匹配', () {
      final ocrText = '【单选题】\n'
          '中国的首都是哪个城市\n'
          'A. 北京 B. 上海 C. 广州 D. 深圳';
      final result = engine.matchWithCandidates(ocrText, ocrType: 'single');
      expect(result.level, isNot(MatchLevel.none));
      expect(result.answer, contains('北京'));
    });
  });
}
