import 'dart:math';
import '../models/match_result.dart';
import '../utils/text_preprocessor.dart';

class MatchEngine {
  final List<QuestionPair> _pairs;
  /// 与 [_pairs] 平行的预计算预处理文本，避免每次匹配重复预处理全部题目。
  final List<String> _preprocessedQuestions;

  /// 构造时对重复题目去重：相同【原始题目文本】只保留最后插入者。
  ///
  /// 注意：去重键必须用原始文本而非预处理文本——预处理是强过滤管线，
  /// 两道不同的题（如仅数字/选项不同）预处理后可能相同，按预处理去重会误删题目。
  /// 只有完全相同的题目（重复导入/重复录入）才去重，保证
  /// L1 精确匹配 / L1.5 包含匹配 / L2 模糊匹配对重复题目的行为一致。
  factory MatchEngine(List<QuestionPair> pairs) {
    final seen = <String>{};
    final deduped = <QuestionPair>[];
    final preprocessed = <String>[];
    for (final p in pairs.reversed) {
      if (seen.add(p.question)) {
        deduped.add(p);
        preprocessed.add(TextPreprocessor.preprocess(p.question));
      }
    }
    return MatchEngine._(
      deduped.reversed.toList(),
      preprocessed.reversed.toList(),
    );
  }

  MatchEngine._(this._pairs, this._preprocessedQuestions);

  /// 三级匹配流水线
  MatchResult match(String ocrText, {String ocrType = ''}) {
    final preprocessed = TextPreprocessor.preprocess(ocrText);
    if (preprocessed.isEmpty) {
      // 预处理后为空，尝试用原始文本（仅做基本清理）再匹配
      final raw = TextPreprocessor.preprocessRaw(ocrText);
      if (raw.isEmpty) return MatchResult.empty();
      return _fuzzyResult(_scorePairs(raw, ocrType: ocrType));
    }

    return _exactAndContainMatch(preprocessed, ocrType: ocrType) ??
        _fuzzyResult(_scorePairs(preprocessed, ocrType: ocrType));
  }

  /// 带候选列表的匹配：正常匹配 + 失败时返回 Top-3 候选
  /// 与 match() 共享 L1/L1.5/模糊评分逻辑
  MatchResult matchWithCandidates(String ocrText, {String ocrType = ''}) {
    final preprocessed = TextPreprocessor.preprocess(ocrText);
    if (preprocessed.isEmpty) {
      final raw = TextPreprocessor.preprocessRaw(ocrText);
      if (raw.isEmpty) return MatchResult.empty();
      return _fuzzyWithCandidates(_scorePairs(raw, ocrType: ocrType));
    }

    return _exactAndContainMatch(preprocessed, ocrType: ocrType) ??
        _fuzzyWithCandidates(_scorePairs(preprocessed, ocrType: ocrType));
  }

  /// L1: 精确匹配（遍历已去重的题目列表）+ L1.5: 包含匹配，未命中返回 null
  MatchResult? _exactAndContainMatch(String preprocessed,
      {String ocrType = ''}) {
    // L1: 精确匹配。按题型从原始题目列表筛选；倒序遍历使重复题目取最后插入者。
    for (var i = _pairs.length - 1; i >= 0; i--) {
      final pair = _pairs[i];
      if (!_isTypeCompatible(pair, ocrType, allowUnknownOcrType: true)) continue;
      if (_preprocessedQuestions[i] != preprocessed) continue;
      return MatchResult(
        answer: pair.answer,
        matchedQuestion: pair.question,
        confidence: 1.0,
        level: MatchLevel.exact,
        explanation: pair.explanation,
        matchedBankId: pair.bankId,
      );
    }

    // L1.5: 包含匹配 - OCR 文本包含整道题目（OCR 常带题号、选项等噪声）
    // 与 L1 保持一致：倒序遍历 _pairs，重复题目时最后插入者优先。
    var bestContainScore = 0.0;
    QuestionPair? bestContainPair;
    for (var i = _pairs.length - 1; i >= 0; i--) {
      final pair = _pairs[i];
      final bankQ = _preprocessedQuestions[i];
      if (bankQ.isEmpty) continue;
      if (!_isTypeCompatible(pair, ocrType, allowUnknownOcrType: true)) continue;
      if (bankQ.length < 8) continue; // 太短的题目跳过包含匹配
      if (preprocessed.contains(bankQ)) {
        // OCR 包含完整题目 -> 精确匹配
        return MatchResult(
          answer: pair.answer,
          matchedQuestion: pair.question,
          confidence: 0.98,
          level: MatchLevel.exact,
          explanation: pair.explanation,
          matchedBankId: pair.bankId,
        );
      }
      // 题目包含 OCR 核心内容（OCR 只截到了部分题目）
      // 阈值降低：OCR 现在只提取题干（不含选项），短至5字符也可匹配
      if (bankQ.contains(preprocessed) && preprocessed.length >= 5) {
        final score = preprocessed.length / bankQ.length;
        if (score > bestContainScore) {
          bestContainScore = score;
          bestContainPair = pair;
        }
      }
      // 部分包含：OCR 与题库题目有足够长的公共子串
      if (!preprocessed.contains(bankQ) && !bankQ.contains(preprocessed)) {
        final overlap = _longestCommonSubstring(preprocessed, bankQ);
        if (overlap.length >= 8 && overlap.length >= bankQ.length * 0.5) {
          final score = overlap.length / bankQ.length;
          if (score > bestContainScore) {
            bestContainScore = score;
            bestContainPair = pair;
          }
        }
      }
    }
    if (bestContainPair != null && bestContainScore >= 0.4) {
      return MatchResult(
        answer: bestContainPair.answer,
        matchedQuestion: bestContainPair.question,
        confidence: bestContainScore,
        level: MatchLevel.exact,
        explanation: bestContainPair.explanation,
        matchedBankId: bestContainPair.bankId,
      );
    }
    return null;
  }

  /// L2: 对全部题目做模糊评分（一次遍历，同时收集候选）
  _FuzzyOutcome _scorePairs(String preprocessed, {String ocrType = ''}) {
    var bestScore = 0.0;
    QuestionPair? bestPair;
    final scored = <_ScoredPair>[];

    for (var i = 0; i < _pairs.length; i++) {
      final pair = _pairs[i];
      if (!_isTypeCompatible(
        pair,
        ocrType,
        allowUnknownOcrType: ocrType.isEmpty,
      )) {
        continue;
      }
      // 复用构造时预计算的预处理文本，避免每次匹配重新预处理全部题目
      final target = _preprocessedQuestions[i];
      final score = _partialRatio(preprocessed, target);
      if (score > bestScore) {
        bestScore = score;
        bestPair = pair;
      }
      if (score > 0) {
        scored.add(_ScoredPair(pair, score));
      }
      if (bestScore >= 0.95) break;
    }
    return _FuzzyOutcome(bestPair, bestScore, scored);
  }

  /// 模糊评分 -> 普通匹配结果（无候选列表）
  MatchResult _fuzzyResult(_FuzzyOutcome outcome) {
    final bestPair = outcome.bestPair;
    // 阈值 0.55：OCR 常含乱码/错字导致相似度偏低，0.7 过于严格会漏匹配；
    // 候选列表机制（Top-3 + 分数展示）仍能防止低分误匹配。
    if (bestPair != null && outcome.bestScore >= 0.55) {
      return MatchResult(
        answer: bestPair.answer,
        matchedQuestion: bestPair.question,
        confidence: outcome.bestScore,
        level: MatchLevel.fuzzy,
        explanation: bestPair.explanation,
        matchedBankId: bestPair.bankId,
      );
    }
    return MatchResult.empty();
  }

  /// 模糊评分 -> 带候选列表的匹配结果
  MatchResult _fuzzyWithCandidates(_FuzzyOutcome outcome) {
    final bestPair = outcome.bestPair;
    // 阈值 0.55：与 match() 保持一致
    if (bestPair != null && outcome.bestScore >= 0.55) {
      return MatchResult(
        answer: bestPair.answer,
        matchedQuestion: bestPair.question,
        confidence: outcome.bestScore,
        level: MatchLevel.fuzzy,
        explanation: bestPair.explanation,
        matchedBankId: bestPair.bankId,
      );
    }

    // 匹配失败，返回 Top-3 候选
    final scored = outcome.scored..sort((a, b) => b.score.compareTo(a.score));
    final topN = scored.take(3).toList();

    if (topN.isEmpty) return MatchResult.empty();

    return MatchResult(
      answer: '',
      matchedQuestion: '',
      confidence: 0.0,
      level: MatchLevel.none,
      candidates: topN
          .map((s) => CandidateItem(
                question: s.pair.question,
                answer: s.pair.answer,
                explanation: s.pair.explanation,
                score: s.score,
              ))
          .toList(),
    );
  }

  bool _isTypeCompatible(
    QuestionPair pair,
    String ocrType, {
    required bool allowUnknownOcrType,
  }) {
    if (ocrType.isEmpty) {
      // 未识别题型时允许精确/包含匹配保留兼容性；模糊评分由调用方禁止跨题型。
      return allowUnknownOcrType || pair.type.isNotEmpty;
    }
    return pair.type == ocrType;
  }

  /// 最长公共子串
  static String _longestCommonSubstring(String a, String b) {
    if (a.isEmpty || b.isEmpty) return '';
    final m = a.length, n = b.length;
    var maxLen = 0, endIdx = 0;
    final dp = List.generate(m + 1, (_) => List.filled(n + 1, 0));
    for (var i = 1; i <= m; i++) {
      for (var j = 1; j <= n; j++) {
        if (a[i - 1] == b[j - 1]) {
          dp[i][j] = dp[i - 1][j - 1] + 1;
          if (dp[i][j] > maxLen) {
            maxLen = dp[i][j];
            endIdx = i;
          }
        }
      }
    }
    return a.substring(endIdx - maxLen, endIdx);
  }

  /// partial_ratio: 较短文本在较长文本中的滑动窗口最佳匹配
  static double _partialRatio(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0.0;
    if (a == b) return 1.0;

    final short = a.length < b.length ? a : b;
    final long = a.length < b.length ? b : a;

    // 短文本同样做滑动窗口匹配：仅与长文本开头比较会漏掉
    // 匹配内容位于长文本中间的情况（评分严重偏低导致匹配失败）。
    double bestScore = 0.0;
    for (var i = 0; i <= long.length - short.length; i++) {
      final window = long.substring(i, i + short.length);
      final d = _levenshtein(short, window);
      final score = 1.0 - (d / short.length);
      if (score > bestScore) {
        bestScore = score;
        if (bestScore >= 0.95) break;
      }
    }
    return bestScore;
  }

  /// Levenshtein 编辑距离
  static int _levenshtein(String s1, String s2) {
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    var prev = List<int>.generate(s2.length + 1, (i) => i);
    var curr = List<int>.filled(s2.length + 1, 0);

    for (var i = 1; i <= s1.length; i++) {
      curr[0] = i;
      for (var j = 1; j <= s2.length; j++) {
        final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
        curr[j] = min(prev[j] + 1, min(curr[j - 1] + 1, prev[j - 1] + cost));
      }
      final temp = prev;
      prev = curr;
      curr = temp;
    }

    return prev[s2.length];
  }
}

class QuestionPair {
  final String question;
  final String answer;
  final String? explanation;
  final String type; // 'single' | 'multi' | 'judge' | ''
  final String? bankId; // 所属题库（多题库合并匹配时区分来源）

  QuestionPair({
    required this.question,
    required this.answer,
    this.explanation,
    String? type,
    this.bankId,
  }) : type = type ?? QuestionPair.inferType(answer);

  /// 从答案推断题型，兼容导入题库中的"字母 + 选项内容"格式。
  static String inferType(String answer) {
    final value = answer.trim().toUpperCase();
    if (value.isEmpty) return '';

    // 判断题判定（先于选项标记检测）：字母前缀 + 纯判断词（如 "A.正确"、"B、错误"）
    // 此时字母只是题干编号，选项内容本身就是判断词 → 判断题。
    final compactAll = value.replaceAll(RegExp(r'[\s.、．:：()（）/]'), '');
    if (RegExp(r'^[A-H](正确|错误|对|错|是|否)$').hasMatch(compactAll)) {
      return 'judge';
    }

    // 选项字母标记（A. / B、 / C． 等）——先检测，避免选项内容中的
    // "正确/错误"等词（如"D. 正确使用工器具"）误判为判断题。
    final markers = RegExp(r'(?<![A-Z])[A-H](?=\s*[.、．:：)]|$)')
        .allMatches(value)
        .map((m) => m.group(0)!.trim())
        .where((m) => m.isNotEmpty)
        .toSet();

    // 带选项字母标记的答案：按单选/多选处理（选项内容中的"正确/错误"不参与判断）
    if (markers.isNotEmpty) {
      if (markers.length >= 2) return 'multi';
      // 单标记且整体以 "A. xxx" / "A、xxx" / "A: xxx" 形式开头 → 单选
      if (RegExp(r'^\s*[A-H]\s*[.、．:：]').hasMatch(value)) return 'single';
    }

    // 判断题判定：仅在无选项字母标记时，检查是否纯判断词。
    // 支持："正确"、"错误"、"对"、"错"、"是"、"否"、"TRUE"、"FALSE"、"T"、"F"、
    //      "A.正确"（字母+判断词无空格）、"正确 错误"、"对/错" 等组合。
    final compact = value.replaceAll(RegExp(r'[\s.、．:：()（）/]'), '');
    if (RegExp(r'^[A-H]?(正确|错误|对|错|是|否|TRUE|FALSE|T|F)$').hasMatch(compact)) {
      return 'judge';
    }
    // 多判断词组合："正确错误"、"对错"、"正确 错误 正确"（compact 后无分隔）
    if (RegExp(
      r'^(正确|错误|对|错|是|否|TRUE|FALSE|T|F){2,}$',
    ).hasMatch(compact)) {
      return 'judge';
    }

    if (RegExp(r'^[A-H]{2,}$').hasMatch(value.replaceAll(RegExp(r'[\s,，、;；/]'), ''))) {
      return 'multi';
    }
    if (RegExp(r'^[A-H]$').hasMatch(value)) return 'single';
    return '';
  }
}

/// 内部辅助：带分数的题目对
class _ScoredPair {
  final QuestionPair pair;
  final double score;
  _ScoredPair(this.pair, this.score);
}

/// 内部辅助：模糊评分遍历结果
class _FuzzyOutcome {
  final QuestionPair? bestPair;
  final double bestScore;
  final List<_ScoredPair> scored;
  _FuzzyOutcome(this.bestPair, this.bestScore, this.scored);
}
