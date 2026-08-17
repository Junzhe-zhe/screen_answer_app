
import 'package:flutter_test/flutter_test.dart';
import 'package:screen_answer_app/models/match_result.dart';
import 'package:screen_answer_app/services/match_engine.dart';

void main() {
  group('MatchEngine - 长时间连续识别稳定性（上百题场景）', () {
    late MatchEngine engine;
    // 模拟一个较大的题库（50 道混合题型题）
    final questions = List.generate(50, (i) {
      final type = i % 3;
      if (type == 0) {
        return QuestionPair(
          question: '单选题第$i 题：以下关于主题$i 的说法正确的是',
          answer: 'A. 选项甲$i；B. 选项乙$i',
          type: 'single',
        );
      } else if (type == 1) {
        return QuestionPair(
          question: '多选题第$i 题：以下哪些属于主题$i 的内容',
          answer: 'A. 内容一$i；B. 内容二$i；C. 内容三$i',
          type: 'multi',
        );
      } else {
        return QuestionPair(
          question: '判断题第$i 题：主题$i 的说法是',
          answer: '正确',
          type: 'judge',
        );
      }
    });

    setUp(() => engine = MatchEngine(questions));

    test('连续 200 次匹配结果应保持稳定且不退化', () {
      // 模拟上百道题识别：每个题目文本识别 4 次 = 200 次调用
      for (var round = 0; round < 4; round++) {
        for (var i = 0; i < 50; i++) {
          final type = i % 3;
          final text = type == 0
              ? '单选题第$i 题：以下关于主题$i 的说法正确的是 A. 选项甲$i B. 选项乙$i'
              : type == 1
                  ? '多选题第$i 题：以下哪些属于主题$i 的内容 A. 内容一$i B. 内容二$i C. 内容三$i'
                  : '判断题第$i 题：主题$i 的说法是';
          final r = engine.matchWithCandidates(text, ocrType: type == 0 ? 'single' : type == 1 ? 'multi' : 'judge');
          expect(r.level, isNot(MatchLevel.none),
              reason: '第$i 题第$round 轮应匹配成功');
          // 题型严格匹配验证：单选匹配单选，多选匹配多选，判断匹配判断
          expect(r.matchedQuestion, contains('第$i 题'));
        }
      }
    });

    test('同一文本重复匹配结果应完全一致（无状态累积）', () {
      final text = '单选题第7 题：以下关于主题7 的说法正确的是 A. 选项甲7 B. 选项乙7';
      final first = engine.matchWithCandidates(text, ocrType: 'single');
      for (var i = 0; i < 50; i++) {
        final again = engine.matchWithCandidates(text, ocrType: 'single');
        expect(again.answer, first.answer);
        expect(again.matchedQuestion, first.matchedQuestion);
        expect(again.level, first.level);
      }
    });
  });
}
